-- Shared helpers for fuzz.lua and the focused fuzzers (fuzz-grid,
-- fuzz-recursion, fuzz-invalidation, fuzz-input).  Anything that's
-- the same regardless of which bug class is being targeted belongs
-- here: PRNG, byte-stream encoding, random text generators,
-- win/buf/tab picking, teardown of tracked state, the state struct
-- itself.
--
-- Focused fuzzers do not have to share anything beyond this.  AUTOCMD
-- event lists, vim-command strings, option names, and dispatch
-- tables all live in the per-fuzzer file because they're shaped by
-- the bug class.
--
-- Usage from a fuzzer:
--
--   package.path = './lib/?.lua;./lib/?/init.lua;' .. package.path
--   local C = require('fuzz-common')
--   local api = vim.api
--   local R = C.make_prng(C.resolve_bytes(arg and arg[1] or '42'),
--                         'file:' .. tostring(arg and arg[1] or '42'))
--   local S = C.new_state()
--   ...
--   for round = 1, ROUNDS do
--     ...
--     local b = C.pick_buf(api, R)
--     ...
--     C.teardown_bufs(api, S.scratch_bufs)
--   end

local M = {}

------------------------------------------------------------
-- PRNG plumbing
--
-- The byte-stream driven PRNG is documented in detail in fuzz.lua.
-- These three functions are the entire surface area; everything else
-- (pick, num, chance, ...) is hung off the closure that make_prng
-- returns.
------------------------------------------------------------

function M.read_bytes(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local data = f:read('*a')
  f:close()
  if not data or #data == 0 then return nil end
  return data
end

function M.encode_seed_to_bytes(seed_input)
  if type(seed_input) == 'number' then
    local lo = bit.band(seed_input, 0xFFFFFFFF)
    local hi = bit.band(bit.rshift(seed_input, 32), 0xFFFFFFFF)
    local salt = 0x9E3779B9
    return string.char(
      bit.band(lo, 0xFF), bit.band(bit.rshift(lo, 8), 0xFF),
      bit.band(bit.rshift(lo, 16), 0xFF), bit.band(bit.rshift(lo, 24), 0xFF),
      bit.band(hi, 0xFF), bit.band(bit.rshift(hi, 8), 0xFF),
      bit.band(bit.rshift(hi, 16), 0xFF), bit.band(bit.rshift(hi, 24), 0xFF),
      bit.band(salt, 0xFF), bit.band(bit.rshift(salt, 8), 0xFF),
      bit.band(bit.rshift(salt, 16), 0xFF), bit.band(bit.rshift(salt, 24), 0xFF),
      0x42, 0x13, 0x37, 0x91)
  end
  local s = tostring(seed_input or '42')
  local h = 0xCBF29CE484222325
  for i = 1, #s do
    h = bit.bxor(h, s:byte(i))
    h = (h * 0x100000001B3) % 0x10000000000000000
  end
  local bytes = {}
  for shift = 0, 56, 8 do
    bytes[#bytes + 1] = string.char(bit.band(bit.rshift(h, shift), 0xFF))
  end
  for i = 1, 8 do bytes[#bytes + 1] = string.char(0xA5 + i) end
  return table.concat(bytes)
end

function M.resolve_bytes(seed_input)
  if type(seed_input) == 'string' then
    -- Try the path as-given first (handles absolute paths).
    local b = M.read_bytes(seed_input)
    if b then return b, 'file:' .. seed_input end
    -- Then try it as relative to vim.loop.cwd(). AFL child invocations
    -- receive absolute paths so this fallback is for human-driven
    -- reproduce (e.g., ./fuzz-crashhunter.lua ./afl-findings/crashes/id:*).
    -- Without this, a relative path gets hashed AS A STRING and the
    -- fuzzer dispatches entirely different ops, missing the bug.
    local cwd = vim.loop and vim.loop.cwd() or nil
    if cwd and not seed_input:match('^/') then
      local abs = cwd .. '/' .. seed_input
      local b2 = M.read_bytes(abs)
      if b2 then return b2, 'file:' .. abs end
    end
  end
  return M.encode_seed_to_bytes(seed_input), 'encoded:' .. tostring(seed_input)
end

function M.make_prng(bytes, source_label)
  local st = {bytes = bytes, n = #bytes, pos = 0}
  local function b()
    st.pos = (st.pos % st.n) + 1
    return st.bytes:byte(st.pos)
  end
  local function u16() return bit.bor(b(), bit.lshift(b(), 8)) end
  local function u32()
    return bit.bor(b(),
           bit.lshift(b(), 8),
           bit.lshift(b(), 16),
           bit.lshift(b(), 24))
  end
  return {
    source = source_label .. ' (' .. st.n .. ' bytes)',
    u8     = b,
    u16    = u16,
    u32    = u32,
    num    = function(lo, hi)
      if hi < lo then return lo end
      return lo + (u32() % (hi - lo + 1))
    end,
    pick   = function(arr) return arr[1 + (u32() % #arr)] end,
    one_of_n = function(k) return u32() % k end,
    chance = function(p, q) return (u32() % q) < p end,
  }
end

------------------------------------------------------------
-- Misc helpers
------------------------------------------------------------

function M.cap(t, max)
  if #t > max then
    local drop = {}
    for _ = 1, max do drop[#drop + 1] = table.remove(t, 1) end
    return drop
  end
  return nil
end

function M.safe(fn, ...)
  return pcall(fn, ...)
end

local PRINTABLE = ' !"#$%&\'()*+,-./0123456789:;<=>?@' ..
                  'ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`' ..
                  'abcdefghijklmnopqrstuvwxyz{|}~'

function M.rand_printable(R, n)
  local t = {}
  for _ = 1, n do t[#t + 1] = PRINTABLE:sub(R.u8() % #PRINTABLE + 1, -1) end
  return table.concat(t)
end

function M.rand_buf(R, n)
  local t = {}
  for _ = 1, n do t[#t + 1] = string.char(R.u8()) end
  return table.concat(t)
end

function M.rand_word(R, n)
  local t = {}
  for _ = 1, n do
    local idx = R.num(1, 26)
    t[#t + 1] = string.char(96 + idx)
  end
  return table.concat(t)
end

------------------------------------------------------------
-- Win/buf/tab enumeration and picking
------------------------------------------------------------

function M.list_wins(api) return api.nvim_list_wins() end
function M.list_bufs(api) return api.nvim_list_bufs() end
function M.list_tabs(api) return api.nvim_list_tabpages() end

function M.pick_win(api, R)
  local ws = M.list_wins(api)
  if #ws == 0 then return nil end
  return ws[R.one_of_n(#ws)]
end

function M.pick_buf(api, R)
  local bs = M.list_bufs(api)
  if #bs == 0 then return nil end
  return bs[R.one_of_n(#bs)]
end

function M.pick_tab(api, R)
  local ts = M.list_tabs(api)
  if #ts == 0 then return nil end
  return ts[R.one_of_n(#ts)]
end

------------------------------------------------------------
-- State
--
-- Fuzzers track three kinds of resources that they themselves
-- create: scratch buffers, floating windows, autocmd registrations.
-- A focused fuzzer might only use one or two of these; that's
-- fine, the unused lists just stay empty.
------------------------------------------------------------

function M.new_state()
  return {
    floats = {},       -- win ids of floating windows we created
    scratch_bufs = {}, -- scratch buffer ids
    augroups = {},     -- augroup ids we created (so we can clear)
    auids = {},        -- autocmd ids we created (so we can del)
    namespaces = {},   -- extmark namespaces
    user_cmds = {},    -- user command names
    timers = {},       -- timer ids
    highlight_ns = nil,
    HASH_NS_PREFIX = 'fz',
  }
end

------------------------------------------------------------
-- Teardown
--
-- These iterate the lists in S and close/del each entry. They
-- ignore failures because by the time we call teardown the entry
-- may already be invalid (a prior op deleted it). pcall catches
-- the error and we move on.
------------------------------------------------------------

function M.teardown_floats(api, floats)
  for i = #floats, 1, -1 do
    pcall(api.nvim_win_close, floats[i], true)
    floats[i] = nil
  end
end

function M.teardown_bufs(api, scratch_bufs)
  for i = #scratch_bufs, 1, -1 do
    local b = scratch_bufs[i]
    if api.nvim_buf_is_valid(b) then
      pcall(api.nvim_buf_delete, b, { force = true })
    end
    scratch_bufs[i] = nil
  end
end

function M.teardown_autocmds(api, auids, augroups)
  for i = #auids, 1, -1 do
    pcall(api.nvim_del_autocmd, auids[i])
    auids[i] = nil
  end
  for i = #augroups, 1, -1 do
    pcall(api.nvim_del_augroup_by_id, augroups[i])
    augroups[i] = nil
  end
end

------------------------------------------------------------
-- Weighted dispatch
--
-- t is a list of {w=number, name=string, fn=function} records
-- (or {w=..., name=..., fn=...} for traps). pick_weighted returns
-- one element with probability proportional to w. R is the
-- fuzz-common PRNG. Total weight is computed on the fly; we
-- cache it in the table for repeated calls on the same t.
------------------------------------------------------------

function M.total_weight(t)
  if not t._total then
    local s = 0
    for i = 1, #t do s = s + t[i].w end
    t._total = s
  end
  return t._total
end

function M.pick_weighted(t, R, mix)
  local total = M.total_weight(t)
  -- mix is an optional integer (typically the round counter).
  -- Without it, R.u32() % total gives at most (#bytes/4) distinct
  -- values per seed; AFL iterates over many seeds so coverage
  -- improves across runs, but a single 200-round standalone
  -- execution only hits 3-4 ops. XORing the round counter into
  -- the u32 breaks the cycle, giving each round a fresh pick.
  local r
  if mix then
    r = bit.bxor(R.u32(), mix * 0x9E3779B9) % total
  else
    r = R.u32() % total
  end
  for i = 1, #t do
    r = r - t[i].w
    if r < 0 then return t[i] end
  end
  return t[#t]
end

function M.reset_weight_cache(t) t._total = nil end

------------------------------------------------------------
-- Varied-callback factory
--
-- An autocmd callback that does the same thing every firing
-- collapses fuzzer coverage to one branch per scenario.  This
-- returns a thin dispatcher that round-robins through a pool
-- of behaviors, keyed by an invocation counter.  Variants
-- receive (args, n) where n is the 1-based counter, so a
-- variant can adapt its parameters (e.g. float width =
-- 5 + (n % 20)) to widen the parameter space each time the
-- event re-fires.
--
-- counter * 31 (a prime) modulo N spreads the dispatch so two
-- consecutive firings never pick the same variant twice.
------------------------------------------------------------

function M.make_varied_cb(behaviors)
  local counter = 0
  return function(args)
    counter = counter + 1
    local idx = ((counter * 31) % #behaviors) + 1
    local fn = behaviors[idx]
    if fn then fn(args, counter) end
  end
end

------------------------------------------------------------
-- Standard behavior pools
--
-- Each pool is a list of `function(args, n)` closures that
-- mutate nvim state in different ways.  Pools are defined
-- here (not at module load) so they can capture per-fuzzer
-- helpers (api/cmd/R/...) at install time.  Pass the fuzzer's
-- context in; the returned pools close over it.
--
-- Pools follow a single shape: an array of behavior fns.
-- Scenarios choose the pool that fits the event semantics.
-- Behaviors that may target already-freed state rely on pcall
-- at the call site.
------------------------------------------------------------

function M.behavior_pools(ctx)
  local api, cmd, R, pick_buf, rand_printable, rand_word = ctx.api, ctx.cmd, ctx.R,
    ctx.pick_buf, ctx.rand_printable, ctx.rand_word

  local CB_WINLEAVE = {
    function(_args, n)  -- open float with parameters scaled by n
      local b = api.nvim_create_buf(false, true)
      pcall(api.nvim_open_win, b, false, {
        relative = 'editor',
        row = ((n % 5) - 2), col = ((n % 7) - 3),
        width = ((n % 10) + 5), height = ((n % 4) + 3),
      })
    end,
    function() pcall(api.nvim_win_close, 0, true) end,
    function()
      local bs = api.nvim_list_bufs()
      if #bs > 1 then
        pcall(api.nvim_buf_delete, bs[#bs], { force = true })
      end
    end,
    function(_args, n)
      pcall(api.nvim_buf_set_lines, 0, 0, 0, true, { 'fzwl' .. tostring(n) })
    end,
    function() end,  -- explicit no-op, lets us exercise the event path
    function() pcall(cmd, 'tabnew') end,
    function() pcall(api.nvim_exec_autocmds, 'User FzStub', {}) end,
  }

  local CB_WINCLOSED = {
    function() pcall(api.nvim_win_close, 0, true) end,
    function(_args, n)
      local ws = api.nvim_list_wins()
      if #ws > 1 then
        pcall(api.nvim_win_close, ws[1 + (n % #ws)], true)
      end
    end,
    function()  -- delete an unloaded buffer (the original bug)
      for _, b in ipairs(api.nvim_list_bufs()) do
        if api.nvim_buf_is_valid(b) and not api.nvim_buf_is_loaded(b) then
          pcall(api.nvim_buf_delete, b, { force = true, unload = true })
          return
        end
      end
    end,
    function() end,
    function(_args, n)
      pcall(api.nvim_buf_set_lines, 0, 0, 0, true, { 'fzwc' .. tostring(n) })
    end,
    function() pcall(cmd, 'tabnew') end,
  }

  local CB_BUFUNLOAD = {
    function()  -- delete the last (oldest) buffer (original bug)
      local bs = api.nvim_list_bufs()
      if #bs >= 2 then
        pcall(api.nvim_buf_delete, bs[#bs], { force = true })
      end
    end,
    function() pcall(api.nvim_win_close, 0, true) end,
    function()  -- delete a specific other buffer
      local bs = api.nvim_list_bufs()
      if #bs >= 3 then
        pcall(api.nvim_buf_delete, bs[#bs - 1], { force = true })
      end
    end,
    function() end,
    function(_args, n)
      pcall(api.nvim_buf_set_lines, 0, 0, 0, true, { 'fzbu' .. tostring(n) })
    end,
    function() pcall(cmd, 'tabnext') end,
  }

  local CB_ON_LINES = {
    function() pcall(api.nvim_win_close, 0, true) end,
    function()  -- open float (different shape from CB_WINLEAVE)
      local b = api.nvim_create_buf(false, true)
      pcall(api.nvim_open_win, b, false, {
        relative = 'editor', row = 0, col = 0, width = 12, height = 4,
      })
    end,
    function(_args, n)  -- recursive set_lines (counted externally)
      pcall(api.nvim_buf_set_lines, 0, 0, 0, true, { 'fzol' .. tostring(n) })
    end,
    function() end,
    function()
      local bs = api.nvim_list_bufs()
      if #bs > 1 then
        pcall(api.nvim_buf_delete, bs[#bs], { force = true })
      end
    end,
    function() pcall(cmd, 'tabnew') end,
  }

  local CB_TABNEW = {
    function()  -- nested nvim_open_tabpage (the original bug class)
      local b = api.nvim_create_buf(false, true)
      pcall(api.nvim_open_tabpage, b, false, {})
    end,
    function()  -- close current tab
      if #api.nvim_list_tabpages() > 1 then
        pcall(api.nvim_command, 'tabclose')
      end
    end,
    function()  -- open a small float
      local b = api.nvim_create_buf(false, true)
      pcall(api.nvim_open_win, b, false, {
        relative = 'editor', row = 0, col = 0, width = 8, height = 4,
      })
    end,
    function() end,
    function(_args, n)
      pcall(api.nvim_buf_set_lines, 0, 0, 0, true, { 'fztn' .. tostring(n) })
    end,
    function()
      pcall(api.nvim_exec_autocmds, 'User FzStub', {})
    end,
  }

  return {
    WINLEAVE = CB_WINLEAVE,
    WINCLOSED = CB_WINCLOSED,
    BUFUNLOAD = CB_BUFUNLOAD,
    ON_LINES = CB_ON_LINES,
    TABNEW = CB_TABNEW,
  }
end

------------------------------------------------------------
-- Argument serializer (for log= and replay= modes)
--
-- Serialize a Lua value as a Lua literal string that load() can
-- re-evaluate.  Used by make_api_logger / make_cmd_logger to
-- embed per-call args in a captured dispatch log.  The shape
-- is a tuple table (so the consumer can reconstruct each arg
-- via load() and dispatch on type).  Cycles are not allowed
-- in nvim API args so we don't defend against them; opaque
-- userdata/function/thread values get a string sentinel.
------------------------------------------------------------

function M.make_arg_serializer()
  local function ser_arg(v)
    local t = type(v)
    if t == 'nil' then
      return 'nil'
    elseif t == 'boolean' then
      return tostring(v)
    elseif t == 'number' then
      if v ~= v or v == math.huge or v == -math.huge then
        return 'nil'
      end
      return tostring(v)
    elseif t == 'string' then
      return string.format('%q', v)
    elseif t == 'table' then
      local parts = {}
      for k, vv in pairs(v) do
        local ks
        if type(k) == 'string' then
          ks = '[' .. string.format('%q', k) .. ']'
        elseif type(k) == 'number' then
          ks = '[' .. tostring(k) .. ']'
        else
          ks = 'nil'
        end
        parts[#parts + 1] = ks .. '=' .. ser_arg(vv)
      end
      return '{' .. table.concat(parts, ',') .. '}'
    else
      return string.format('"<%s: not serializable>"', t)
    end
  end

  local function ser_args(args)
    local parts = {}
    for i, a in ipairs(args) do
      parts[i] = ser_arg(a)
    end
    return '{' .. table.concat(parts, ',') .. '}'
  end

  return ser_arg, ser_args
end

------------------------------------------------------------
-- API / cmd proxies for log= mode
--
-- When a log file is being written, replace the caller's
-- `api` and `cmd` with these proxies: every call is forwarded
-- to vim.api / vim.cmd, but also emitted as one log line of
-- the form `log.ops[#log.ops+1] = {...}` so bin/from-log.lua
-- can translate the log into a standalone repro.lua.
--
-- round_idx_fn is a closure that returns the current 1-based
-- round index (the fuzzer bumps it once per round).  round_ops
-- is a {count=int} table shared with cmd_proxy; the cap is
-- FUZZ_ROUND_OPS_CAP (0 = disabled).  Both are mutated in
-- place so the proxies and the fuzzer see the same counter.
--
-- Stamping CURRENT_ROUND on each log line lets from-log.lua
-- group ops by round and emit per-round teardown, matching
-- the fuzzer's per-round state reset.
------------------------------------------------------------

function M.make_api_logger(opts)
  local orig = opts.api
  local ser_arg, ser_args = opts.ser_arg, opts.ser_args
  local round_idx_fn = opts.round_idx_fn
  local round_ops = opts.round_ops
  local cap = opts.round_ops_cap
  local log_fh = opts.log_fh
  return setmetatable({}, { __index = function(_, k)
    local v = rawget(orig, k) or orig[k]
    if type(v) == 'function' then
      return function(...)
        if cap > 0 then
          round_ops[1] = round_ops[1] + 1
          if round_ops[1] > cap then return nil end
        end
        if log_fh then
          local n = select('#', ...)
          local args = { ... }
          log_fh:write(string.format(
            'log.ops[#log.ops+1] = {kind="api",name=%q,nargs=%d,'
              .. 'sargs=%s,args=%s,round=%s}\n',
            'vim.api.' .. k, n, string.format('%q', ser_args(args)),
            ser_args(args), tostring(round_idx_fn() or 0)))
          log_fh:flush()
        end
        return v(...)
      end
    end
    return v
  end })
end

function M.make_cmd_logger(opts)
  local orig = opts.cmd
  local ser_arg, ser_args = opts.ser_arg, opts.ser_args
  local round_idx_fn = opts.round_idx_fn
  local round_ops = opts.round_ops
  local cap = opts.round_ops_cap
  local log_fh = opts.log_fh
  return setmetatable({}, { __index = function(_, k)
    local v = rawget(orig, k) or orig[k]
    if type(v) == 'function' then
      return function(...)
        if cap > 0 then
          round_ops[1] = round_ops[1] + 1
          if round_ops[1] > cap then return nil end
        end
        if log_fh then
          local args = { ... }
          log_fh:write(string.format(
            'log.ops[#log.ops+1] = {kind="api",name=%q,nargs=%d,'
              .. 'sargs=%s,args=%s,round=%s}\n',
            'vim.cmd.' .. k, #args, string.format('%q', ser_args(args)),
            ser_args(args), tostring(round_idx_fn() or 0)))
          log_fh:flush()
        end
        return v(...)
      end
    end
    return v
  end, __call = function(_, ...)
    if cap > 0 then
      round_ops[1] = round_ops[1] + 1
      if round_ops[1] > cap then return nil end
    end
    if log_fh then
      local args = { ... }
      log_fh:write(string.format(
        'log.ops[#log.ops+1] = {kind="cmd_invocation",nargs=%d,'
          .. 'sargs=%s,args=%s,round=%s}\n',
        #args, string.format('%q', ser_args(args)), ser_args(args),
        tostring(round_idx_fn() or 0)))
      log_fh:flush()
    end
    return orig(...)
  end })
end

return M
