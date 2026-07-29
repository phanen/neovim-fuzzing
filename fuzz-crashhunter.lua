-- Focused fuzzer for the crash patterns documented in doc/crashes/.
-- Smaller and more targeted than fuzz.lua: every op here maps to a
-- known upstream crash family.
--
-- Usage:
--   out/nvim -l fuzz-crashhunter.lua [SEED_OR_FILE] [ROUNDS]
--
-- SEED_OR_FILE is a positive integer or a path to an existing file
-- (AFL "@@" mode).  Defaults: SEED=42, ROUNDS=500.
--
-- Coverage targets (ordered by crash-density, per doc/crashes/):
--   1. autocmd re-entrancy on window/buffer close  (#31236, #37211,
--      #13265, #13231, #33603, #19608)
--   2. last-non-float window in last tabpage       (#30425, #17796)
--   3. extmark + signcolumn + statuscolumn sync   (#27127, #32849,
--      #33067, #27209)
--   4. undolevels=-1 + extmark                    (#24894)
--   5. libvterm VLA stack-overflow                 (#16040, #19075)

vim.o.swapfile = false
vim.o.shadafile = 'NONE'
vim.o.more = false
vim.o.shortmess = 'aoOstTWAIcCFqs'

local QUIET = os.getenv('FUZZ_QUIET') == '1'
local ROUNDS = tonumber(os.getenv('ROUNDS'))
                 or tonumber(arg and arg[2])
                 or 500

-- Mode dispatch: nil = normal fuzz, "log=path" = record ops to file,
-- "replay=path" = replay recorded ops instead of fuzzing. Same semantics
-- as fuzz.lua so bin/from-log.lua can convert a captured log into a
-- standalone repro.lua. The fuzzer used by AFL already writes the
-- log incrementally so an ASAN abort mid-run still leaves a parseable
-- file behind (from-log.lua auto-appends a trailing `return log` if
-- missing).
local MODE = arg and arg[3] or nil
local MODE_ARG = nil
if MODE then
  local k, v = MODE:match('^([^=]+)=(.*)$')
  if k then MODE, MODE_ARG = k, v end
end

local api = vim.api
local cmd = vim.cmd

------------------------------------------------------------
-- Per-op args capture (must be declared BEFORE ops so closures can see
-- them as upvalues; Lua treats `local function` as a local at the
-- enclosing scope, so referring to it before its declaration makes it
-- look like a global that doesn't exist).
------------------------------------------------------------
local op_args = nil
local function record_args(t)
  op_args = t
end
local function consume_args()
  local a = op_args
  op_args = nil
  return a
end

------------------------------------------------------------
-- Dispatch log (used when MODE='log=path'; same shape as fuzz.lua so
-- bin/from-log.lua can convert a captured log into a standalone
-- repro.lua that calls vim.api.* explicitly with the recorded args).
------------------------------------------------------------
local LOG_TARGET = nil

-- Stamped onto every captured log op by the api/cmd proxy. Set at
-- the top of each round iteration. Standalone replay reads this to
-- group ops per round and emit teardown between rounds.
--
-- IMPORTANT: declared BEFORE make_api_logger() / make_cmd_logger()
-- run, so the proxy closures bind CURRENT_ROUND as an upvalue that
-- picks up later assignments to the chunk-local. If you declare this
-- AFTER the proxies, their upvalues will stay nil forever (round=0
-- for every captured op).
local CURRENT_ROUND = 0

local function log_dispatch(entry)
  if LOG_TARGET then
    LOG_TARGET.ops[#LOG_TARGET.ops + 1] = entry
    local parts = {
      'kind=' .. string.format('%q', entry.kind),
      'round=' .. tostring(entry.round or -1),
      'name=' .. string.format('%q', entry.name or ''),
    }
    LOG_TARGET.fh:write('log.ops[#log.ops+1] = {'
      .. table.concat(parts, ',') .. '}\n')
    LOG_TARGET.fh:flush()
  end
end

if MODE == 'log' then
  assert(MODE_ARG, 'log mode requires a path argument: log=/path/to/log.lua')
  -- LOG_TARGET is created with `fh` opened eagerly; `source` and
  -- `rounds` are filled in after R is constructed further down.
  LOG_TARGET = {
    ops = {}, fh = assert(io.open(MODE_ARG, 'w')),
  }
  LOG_TARGET.fh:write('-- generated incrementally by fuzz-crashhunter.lua; '
    .. 'replay parses via fuzz.lua\n')
  LOG_TARGET.fh:flush()
end

local REPLAY_LOG = nil
if MODE == 'replay' then
  assert(MODE_ARG, 'replay mode requires a path argument: replay=/path/to/log')
  REPLAY_LOG = dofile(MODE_ARG)
  ROUNDS = REPLAY_LOG.rounds
end

-- Transparent API tracing: when LOG_TARGET is set, replace the local
-- `api` and `cmd` bindings used by every scenario with metatable
-- proxies that forward to vim.api/vim.cmd but also emit a per-call
-- entry (kind='api', name='vim.api.foo', args={...}) into the log.
-- bin/from-log.lua translates those entries into safe() calls so the
-- generated repro.lua replays the exact sequence with no PRNG.
--
-- Args are serialized as a single Lua literal string via ser_arg(),
-- so the resulting log line is a self-contained Lua expression that
-- can be eval'd in a fresh state to reconstruct the call. Tables
-- serialize key by key (numeric keys via [N], string keys via
-- ['x']); cycles are not allowed in nvim API args so we don't
-- defend against them.
local function ser_arg(v)
  local t = type(v)
  if t == 'nil' then
    return 'nil'
  elseif t == 'boolean' then
    return tostring(v)
  elseif t == 'number' then
    if v ~= v or v == math.huge or v == -math.huge then
      return 'nil'  -- NaN/inf -> emit nil so the literal stays valid
    end
    return tostring(v)
  elseif t == 'string' then
    return string.format('%q', v)
  elseif t == 'table' then
    -- serialize as a Lua table ctor
    local parts = {}
    for k, vv in pairs(v) do
      local ks
      if type(k) == 'string' then
        ks = '[' .. string.format('%q', k) .. ']'
      elseif type(k) == 'number' then
        ks = '[' .. tostring(k) .. ']'
      else
        ks = 'nil'  -- unsupported key type, drop
      end
      parts[#parts + 1] = ks .. '=' .. ser_arg(vv)
    end
    return '{' .. table.concat(parts, ',') .. '}'
  elseif t == 'userdata' or t == 'function' or t == 'thread' then
    -- Vim API args are typically primitives / tables; opaque userdata
    -- can't be replayed from a captured log, so emit a placeholder.
    -- The standalone repro's flow will diverge from the original only
    -- where such an arg was actually used; the caller decides whether
    -- to refine the script.
    -- Use a string sentinel (not a comment, since nested /* ... */
    -- inside a table ctor breaks Lua 5.1's parser).
    return string.format('"<%s: not serializable>"', t)
  end
  return 'nil'
end

-- Serialize all args as a tuple-table Lua literal: {ser_arg(arg1),
-- ser_arg(arg2), ...}. Picking this shape over `table.concat(args,
-- '\1')` lets the consumer (bin/from-log.lua) reconstruct each arg
-- via load() and dispatch on its type.
local function ser_args(args)
  local parts = {}
  for i, a in ipairs(args) do
    parts[i] = ser_arg(a)
  end
  return '{' .. table.concat(parts, ',') .. '}'
end

local function make_api_logger()
  local orig_api = vim.api
  local proxy = setmetatable({}, { __index = function(_, k)
    local v = rawget(orig_api, k) or orig_api[k]
    if type(v) == 'function' then
      return function(...)
        if LOG_TARGET then
          local n = select('#', ...)
          local args = { ... }
          -- `sargs` (string-args) is the canonical storage: a
          -- loadstring()-able Lua expression that reconstructs the
          -- exact tuple. `args` is left as the post-eval table for
          -- back-compat; consumers should prefer `sargs`. `round`
          -- tags each op with its source round so `bin/from-log.lua`
          -- can group ops by round and emit per-round blocks (with
          -- teardown between rounds), reproducing the fuzzer's
          -- per-round state reset on standalone replay.
          LOG_TARGET.fh:write(string.format(
            'log.ops[#log.ops+1] = {kind="api",name=%q,nargs=%d,'
              .. 'sargs=%s,args=%s,round=%s}\n',
            'vim.api.' .. k, n, string.format('%q', ser_args(args)),
            ser_args(args), tostring(CURRENT_ROUND or 0)))
          LOG_TARGET.fh:flush()
        end
        return v(...)
      end
    end
    return v
  end })
  return proxy
end

local function make_cmd_logger()
  -- vim.cmd is a Lua callable table, not a userdata. Wrap it via
  -- __call: invoking vim.cmd(...) falls into __call, which we forward.
  local orig_cmd = vim.cmd
  local proxy = setmetatable({}, { __index = function(_, k)
    local v = rawget(orig_cmd, k) or orig_cmd[k]
    if type(v) == 'function' then
      return function(...)
        if LOG_TARGET then
          local args = { ... }
          LOG_TARGET.fh:write(string.format(
            'log.ops[#log.ops+1] = {kind="api",name=%q,nargs=%d,'
              .. 'sargs=%s,args=%s,round=%s}\n',
            'vim.cmd.' .. k, #args, string.format('%q', ser_args(args)),
            ser_args(args), tostring(CURRENT_ROUND or 0)))
          LOG_TARGET.fh:flush()
        end
        return v(...)
      end
    end
    return v
  end, __call = function(_, ...)
    -- vim.cmd(...) with no method name: command string invocation
    if LOG_TARGET then
      local args = { ... }
      LOG_TARGET.fh:write(string.format(
        'log.ops[#log.ops+1] = {kind="cmd_invocation",nargs=%d,'
          .. 'sargs=%s,args=%s,round=%s}\n',
        #args, string.format('%q', ser_args(args)), ser_args(args), tostring(CURRENT_ROUND or 0)))
      LOG_TARGET.fh:flush()
    end
    return orig_cmd(...)
  end })
  return proxy
end

if LOG_TARGET then
  api = make_api_logger()
  cmd = make_cmd_logger()
end

package.path = './lib/?.lua;./lib/?/init.lua;' .. package.path
local C = require('fuzz-common')

local R_bytes, R_label = C.resolve_bytes(arg and arg[1] or '42')
local R = C.make_prng(R_bytes, 'crashhunter:' .. R_label)

-- Late-init LOG_TARGET fields that depend on R (created earlier when
-- MODE was parsed, so the file handle is open).
if LOG_TARGET then
  LOG_TARGET.source = R.source
  LOG_TARGET.rounds = ROUNDS
  LOG_TARGET.fh:write('local log = { source = '
    .. string.format('%q', LOG_TARGET.source)
    .. ', rounds = ' .. LOG_TARGET.rounds .. ', ops = {}, ops_per_round = {} }\n')
  LOG_TARGET.fh:flush()
end

do
  local seed_lo = 0
  for i = 1, 4 do
    seed_lo = bit.bor(seed_lo, bit.lshift(R_bytes:byte(((i - 1) % #R_bytes) + 1), (i - 1) * 8))
  end
  math.randomseed(seed_lo)
end

io.write('fuzz-crashhunter: source=' .. R.source .. ' rounds=' .. ROUNDS .. '\n')

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local rand_printable = function(n) return C.rand_printable(R, n) end
local rand_buf = function(n) return C.rand_buf(R, n) end
local rand_word = function(n) return C.rand_word(R, n) end

local safe = C.safe
local cap = C.cap

local function list_wins() return C.list_wins(api) end
local function list_bufs() return C.list_bufs(api) end
local function list_tabs() return C.list_tabs(api) end
local function pick_win() return C.pick_win(api, R) end
local function pick_buf() return C.pick_buf(api, R) end
local function pick_tab() return C.pick_tab(api, R) end

------------------------------------------------------------
-- Varied callback factory
--
-- A scenario's autocmd callback fires whenever the event triggers;
-- if the callback does the same thing every time, fuzz coverage
-- collapses to one branch per scenario.  make_varied_cb() returns a
-- thin dispatcher that round-robins through a behavior pool keyed
-- by an invocation counter. Variants receive (args, n) where n is
-- the 1-based counter, so a variant can adapt its parameters (e.g.
-- float width = 5 + (n % 20)) to widen the parameter space each
-- time the event re-fires.
--
-- counter * 31 (a prime) modulo N spreads the dispatch so two
-- consecutive firings never pick the same variant twice.
local function make_varied_cb(behaviors)
  local counter = 0
  return function(args)
    counter = counter + 1
    local idx = ((counter * 31) % #behaviors) + 1
    local fn = behaviors[idx]
    if fn then fn(args, counter) end
  end
end

-- Shared behavior pools. Each pool is a list of `function(args, n)`
-- closures captured over api / cmd / R / helpers. Scenarios choose
-- which pool fits the event semantics; behaviors that try to mutate
-- a window after WinClosed etc. rely on pcall at the call site.

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
    pcall(api.nvim_buf_set_lines, 0, 0, 0, true,
      { 'fzwl' .. tostring(n) })
  end,
  function() end,  -- explicit no-op, lets us exercise the event
                   -- path without forced state churn
  function() pcall(cmd, 'tabnew') end,
  function()
    pcall(api.nvim_exec_autocmds, 'User FzStub', {})
  end,
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
    pcall(api.nvim_buf_set_lines, 0, 0, 0, true,
      { 'fzwc' .. tostring(n) })
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
    pcall(api.nvim_buf_set_lines, 0, 0, 0, true,
      { 'fzbu' .. tostring(n) })
  end,
  function() pcall(cmd, 'tabnext') end,
}

local CB_ON_LINES = {
  function() pcall(api.nvim_win_close, 0, true) end,
  function()  -- open float (different shape from CB_WINLEAVE)
    local b = api.nvim_create_buf(false, true)
    pcall(api.nvim_open_win, b, false, {
      relative = 'editor', row = 0, col = 0,
      width = 12, height = 4,
    })
  end,
  function(_args, n)  -- recursive set_lines (counted externally)
    pcall(api.nvim_buf_set_lines, 0, 0, 0, true,
      { 'fzol' .. tostring(n) })
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

------------------------------------------------------------
-- State (tracked across rounds)
------------------------------------------------------------

local S = C.new_state()

------------------------------------------------------------
-- Op bodies
------------------------------------------------------------

-- Window ops ----------------------------------------------------------

local function op_open_float()
  local rel = R.pick({ 'editor', 'win', 'cursor' })
  local cfg = {
    relative = rel,
    width    = R.num(1, 200),
    height   = R.num(1, 50),
    row      = R.num(-50, 50),
    col      = R.num(-50, 50),
    focusable = R.chance(1, 2),
    style    = R.chance(1, 4) and 'minimal' or nil,
    border   = R.chance(1, 3) and R.pick({ 'single', 'double', 'rounded', 'solid', 'shadow' }) or nil,
    zindex   = R.chance(1, 5) and R.num(-100, 1000) or R.num(50, 200),
    noautocmd = R.chance(1, 5),
  }
  if rel ~= 'cursor' and R.chance(1, 3) then
    cfg.anchor = R.pick({ 'NW', 'NE', 'SW', 'SE' })
  end
  if R.chance(1, 8) then
    cfg.bufpos = { pick_buf() or 0, R.num(-5, 50), R.num(-1, 50) }
  end
  if R.chance(1, 8) then cfg.hide = true end
  if R.chance(1, 8) then cfg.external = true end
  if R.chance(1, 4) then
    cfg.title = rand_printable(R.num(0, 12))
    cfg.title_pos = R.pick({ 'left', 'center', 'right' })
  end
  local enter = R.chance(1, 4)
  local buf = api.nvim_create_buf(false, true)
  local ok, win = pcall(api.nvim_open_win, buf, enter, cfg)
  if ok and type(win) == 'number' then
    S.floats[#S.floats + 1] = win
    cap(S.floats, 32)
  else
    pcall(api.nvim_buf_delete, buf, { force = true })
  end
end

local function op_close_random_win()
  local ws = list_wins()
  if #ws <= 1 then return end
  local w = ws[R.one_of_n(#ws)]
  pcall(api.nvim_win_close, w, true)
end

local function op_win_set_buf()
  local w = pick_win()
  local b = pick_buf()
  if not w or not b then return end
  pcall(api.nvim_win_set_buf, w, b)
end

local function op_win_set_cursor()
  local w = pick_win()
  if not w then return end
  local row = R.chance(1, 5) and R.num(-100, 100000) or R.num(1, 1000)
  local col = R.chance(1, 5) and R.num(-10, 10000) or R.num(0, 500)
  pcall(api.nvim_win_set_cursor, w, { row, col })
end

-- Buffer ops ----------------------------------------------------------

local function op_create_buf()
  local listed = R.chance(1, 4)
  local scratch = R.chance(1, 2)
  local ok, buf = pcall(api.nvim_create_buf, listed, scratch)
  if ok and buf then
    S.scratch_bufs[#S.scratch_bufs + 1] = buf
    cap(S.scratch_bufs, 32)
    pcall(api.nvim_buf_set_name, buf, '/tmp/fzc_' .. rand_word(8) .. '.txt')
  end
end

local function op_delete_buf()
  local bs = list_bufs()
  if #bs <= 1 then return end
  local b = bs[R.one_of_n(#bs)]
  pcall(api.nvim_buf_delete, b, { force = true, unload = R.chance(1, 2) })
end

local function op_buf_set_lines()
  local b = pick_buf()
  if not b then return end
  local lines = {}
  for _ = 1, R.num(0, 6) do
    lines[#lines + 1] = R.chance(1, 8) and rand_buf(R.num(0, 8)) or rand_printable(R.num(0, 30))
  end
  local start, finish
  if R.chance(1, 5) then
    start, finish = R.num(-100, 10000), R.num(-100, 10000)
  else
    start, finish = R.num(-1, 100), R.num(-1, 100)
  end
  pcall(api.nvim_buf_set_lines, b, start, finish, R.chance(1, 2), lines)
end

local function op_buf_set_extmark()
  local b = pick_buf()
  if not b then return end
  local ns
  if #S.namespaces == 0 or R.chance(1, 4) then
    ns = api.nvim_create_namespace('fzc' .. rand_word(6))
    S.namespaces[#S.namespaces + 1] = ns
    cap(S.namespaces, 16)
  else
    ns = R.pick(S.namespaces)
  end
  local opts = {}
  if R.chance(1, 2) then opts.virt_text = { { rand_printable(R.num(1, 30)), 'Comment' } } end
  if R.chance(1, 3) then opts.virt_text_pos = R.pick({ 'eol', 'overlay', 'right_align' }) end
  if R.chance(1, 4) then opts.hl_group = 'Error' end
  if R.chance(1, 3) then opts.sign_text = rand_word(1) end
  if R.chance(1, 5) then opts.ui_watched = true end
  if R.chance(1, 5) then opts.invalidate = true end
  if R.chance(1, 6) then opts.end_row = R.num(-10, 1000) end
  if R.chance(1, 4) then opts.priority = R.num(-10, 8192) end
  local row = R.chance(1, 5) and R.num(-100, 100000) or R.num(-2, 100)
  local col = R.chance(1, 5) and R.num(-10, 10000) or R.num(-2, 100)
  pcall(api.nvim_buf_set_extmark, b, ns, row, col, opts)
end

local function op_buf_clear_extmark()
  local b = pick_buf()
  if not b or #S.namespaces == 0 then return end
  local ns = R.pick(S.namespaces)
  pcall(api.nvim_buf_clear_namespace, b, ns, R.num(-10, 100), R.num(-10, 100))
end

-- Tabpage ops ---------------------------------------------------------

local function op_tabnew() pcall(cmd, 'tabnew') end
local function op_tabclose()
  if #list_tabs() <= 1 then return end
  pcall(cmd, 'tabclose')
end
local function op_tabnext() pcall(cmd, R.pick({ 'tabnext', 'tabprev', 'tabfirst', 'tablast' })) end

------------------------------------------------------------
-- Pattern 1: autocmd re-entrancy scenarios
------------------------------------------------------------
-- These install an autocmd first, then fire the triggering op.
-- They bypass the heuristic search that a randomized fuzzer
-- would otherwise need to discover the multi-step interaction.

local function scenario_winleave_open_float()
  -- #31236: WinLeave callback opens a float; then a tab split
  -- closes the tab and frees the float. Callback now uses the
  -- shared WINLEAVE behavior pool so each replay fires a
  -- different variant (open-float, close-win, delete-buf, ...).
  pcall(api.nvim_create_autocmd, 'WinLeave', {
    callback = make_varied_cb(CB_WINLEAVE),
  })
  local ts = list_tabs()
  if #ts >= 2 then
    pcall(cmd, 'tabnext')
    pcall(cmd, 'tabclose')
  else
    pcall(cmd, 'tabnew')
  end
  safe(cmd, 'redrawstatus')
end

local function scenario_winclosed_reentrant_close()
  -- #37211 / #13265: WinClosed callback closes another window.
  -- Pick a target window up front; the callback closes the current
  -- one (or a different one) after the WinClosed fires.
  local target = pick_win()
  if not target then return end
  pcall(api.nvim_create_autocmd, 'WinClosed', {
    nested = true,
    callback = make_varied_cb(CB_WINCLOSED),
  })
  pcall(api.nvim_win_close, target, true)
  safe(cmd, 'redrawstatus')
end

local function scenario_winclosed_reentrant_buf_delete()
  -- #37211 / #33603: WinClosed callback deletes a buffer.
  local target_buf = pick_buf()
  if not target_buf then return end
  local target_win = pick_win()
  if not target_win then return end
  pcall(api.nvim_create_autocmd, 'WinClosed', {
    nested = true,
    callback = make_varied_cb(CB_WINCLOSED),
  })
  pcall(api.nvim_win_close, target_win, true)
  safe(cmd, 'redrawstatus')
end

local function scenario_bufunload_reentrant_bufdelete()
  -- #33603: BufUnload callback deletes another buffer in the same
  -- tabpage.
  local target_a = pick_buf()
  local target_b = pick_buf()
  if not target_a or not target_b or target_a == target_b then return end
  pcall(api.nvim_create_autocmd, 'BufUnload', {
    nested = true,
    callback = make_varied_cb(CB_BUFUNLOAD),
  })
  pcall(api.nvim_buf_delete, target_a, { force = true })
  safe(cmd, 'redrawstatus')
end

local function scenario_on_lines_closes_win()
  -- #13231: nvim_buf_attach callback closes the window.
  local target = pick_buf()
  if not target then return end
  local ok = pcall(api.nvim_buf_attach, target, false, {
    on_lines = make_varied_cb(CB_ON_LINES),
  })
  if not ok then return end
  pcall(api.nvim_buf_set_lines, target, 0, 0, true, { 'x' })
  safe(cmd, 'redrawstatus')
end

------------------------------------------------------------
-- Pattern 1.5: new scenarios borrowed from neovim test/functional/api
--
-- Sources (file:line):
--   window_spec.lua:1949-1955  -- WinNewPre delete target buf UAF
--   extmark_spec.lua:1883-1948 + vim_spec:nvim_set_decoration_provider
--                                -- provider on_buf/on_line chain
--   buffer_updates_spec.lua:127-232 -- on_lines recursive set_lines
--   vim_spec.lua:4502-4746  -- statuscolumn eval string side-effects
--   vim_spec.lua:4294-4500  -- nvim_open_term on_input callback
------------------------------------------------------------

local function scenario_winnew_delete_target_buf()
  -- WinNewPre callback deletes the would-be buffer before the new
  -- window finishes initializing. Mirrors window_spec.lua:1949-1955
  -- "no heap-use-after-free if target buffer deleted by autocommands".
  local target_buf = pick_buf()
  if not target_buf then return end
  pcall(api.nvim_create_autocmd, 'WinNew', {
    callback = function()
      pcall(api.nvim_buf_delete, target_buf, { force = true })
    end,
  })
  -- Trigger by opening a new split; WinNew fires inside nvim's
  -- window initialization, which is the same call path the original
  -- crash lived on.
  pcall(cmd, R.chance(1, 2) and 'split' or 'vsplit')
  safe(cmd, 'redrawstatus')
end

local function scenario_decoration_provider_chain()
  -- nvim_set_decoration_provider with on_buf and on_line callbacks
  -- that re-enter the API to mutate extmarks. The provider runs
  -- deep inside neovim's redraw pipeline; calling set_extmark from
  -- there has been a recurring UAF source.
  local ns = api.nvim_create_namespace('fzc' .. rand_word(6))
  S.namespaces[#S.namespaces + 1] = ns
  cap(S.namespaces, 16)
  pcall(api.nvim_set_decoration_provider, ns, {
    on_buf = function(_, b, tick)
      pcall(api.nvim_buf_set_extmark, b, ns, 0, 0, {
        ephemeral = true,
        virt_text = { { rand_printable(R.num(0, 6)), 'Comment' } },
      })
      return tick
    end,
    on_line = function(_, _w, b, row)
      pcall(api.nvim_buf_set_extmark, b, ns, row, 0, {
        ephemeral = true, sign_text = rand_word(1),
      })
    end,
  })
  -- Force the provider to run by editing the buffer
  local tb = pick_buf()
  if tb then
    pcall(api.nvim_buf_set_lines, tb,
      R.num(-1, 30), R.num(-1, 30), false,
      { rand_printable(R.num(0, 6)) })
  end
  safe(cmd, 'redrawstatus')
end

local function scenario_buf_attach_recursive_lines()
  -- nvim_buf_attach on_lines callback that recursively mutates the
  -- buffer. The on_lines callback runs during text-change commit; a
  -- callback that calls nvim_buf_set_lines back into the same buffer
  -- has historically been a state-machine crash site
  -- (buffer_updates_spec.lua:127-232).
  local target = pick_buf()
  if not target then return end
  local fired = 0
  local ok = pcall(api.nvim_buf_attach, target, false, {
    on_lines = function(_, b, _changedtick, _first, _last, _ll, _bc)
      fired = fired + 1
      if fired > 4 then return end
      pcall(api.nvim_buf_set_lines, b, fired, fired, false,
        { rand_printable(R.num(0, 4)) })
    end,
    on_detach = function() end,
  })
  if not ok then return end
  -- Initial mutation: the outer on_lines fires for this set_lines.
  pcall(api.nvim_buf_set_lines, target, 0, 0, true,
    { rand_printable(R.num(0, 6)) })
  safe(cmd, 'redrawstatus')
end

local function scenario_statuscolumn_eval_complex()
  -- statuscolumn set to an expression containing %{} that re-evaluates
  -- per redraw, combined with sign_text + ui_watched extmark to force
  -- re-evaluation. statuscolumn eval historically called user-supplied
  -- Vim expressions during redraw; bad inputs have crashed the redraw
  -- path (vim_spec.lua:4502-4746 eval_statusline).
  local b = pick_buf()
  if not b then return end
  pcall(api.nvim_set_option_value, 'statuscolumn', R.pick({
    '%{""}',
    '%{%}',
    '%c%v',
    '%{mode()}',
    '%{"" .. ""}',
    '%{%{%{""}%}%}',
    '%{toupper("fz")}',
  }), {})
  local ns = api.nvim_create_namespace('fzc' .. rand_word(6))
  pcall(api.nvim_buf_set_extmark, b, ns, 0, 0, {
    sign_text = rand_word(1),
    ui_watched = true,
  })
  safe(cmd, 'redrawstatus')
end

local function scenario_open_term_on_input()
  -- nvim_open_term with on_input callback that re-enters the API to
  -- mutate the buffer. on_input fires from inside the terminal input
  -- path; set_lines from there has triggered stack/ordering issues
  -- historically (vim_spec.lua:4294-4500).
  local bs = list_bufs()
  if #bs == 0 then return end
  local b = R.pick(bs)
  local ok, ch = pcall(api.nvim_open_term, b, {
    on_input = function(_, _term, _buf, _data)
      pcall(api.nvim_buf_set_lines, _buf, 0, -1, false, { 'fzot' })
    end,
  })
  if not ok or not ch then return end
  -- Send mixed payload: raw bytes, ANSI, control chars, printable.
  local payload = {}
  for _ = 1, R.num(4, 64) do
    local k = R.one_of_n(4)
    if k == 0 then
      payload[#payload + 1] = string.char(R.u8() % 128)
    elseif k == 1 then
      payload[#payload + 1] = string.char(R.num(1, 31))
    elseif k == 2 then
      payload[#payload + 1] = '\27[' .. R.num(0, 999) .. 'm'
    else
      payload[#payload + 1] = rand_printable(R.num(0, 8))
    end
  end
  pcall(api.nvim_chan_send, ch, table.concat(payload))
end

------------------------------------------------------------
-- Pattern 1.6: second wave, sources from neovim test/functional/api
--
-- Sources (file:line):
--   tabpage_spec.lua:319-334   -- nested nvim_open_tabpage inside TabNew
--   autocmd_spec.lua:1577-1605 -- 4 callbacks on same event, ordering
--   buffer_updates_spec.lua:488-511 -- attach/detach cycling on one buf
--   extmark_spec.lua + vim_spec:nvim_set_decoration_provider
--                                -- all 6 hooks installed at once
------------------------------------------------------------

-- Behavior pool for TabNew-family events (re-entry from inside the
-- tabpage-creation lifecycle). Uses varied_cb in scenario so each
-- replay cycles through different side-effects.
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
    pcall(api.nvim_buf_set_lines, 0, 0, 0, true,
      { 'fztn' .. tostring(n) })
  end,
  function()
    pcall(api.nvim_exec_autocmds, 'User FzStub', {})
  end,
}

local function scenario_tabnew_nested_open_tabpage()
  -- TabNew callback that opens another tabpage. The nested
  -- nvim_open_tabpage fires its own TabNew while the outer one
  -- is mid-callback, exercising the re-entry guard and tabpage
  -- lifecycle ordering (tabpage_spec.lua:319-334 "handles nasty
  -- autocmds").
  pcall(api.nvim_create_autocmd, 'TabNew', {
    callback = make_varied_cb(CB_TABNEW),
  })
  pcall(cmd, 'tabnew')
  safe(cmd, 'redrawstatus')
end

local function scenario_multi_callback_same_event()
  -- Install multiple distinct callbacks on the same User event
  -- and fire them all at once. Each callback mutates a different
  -- resource (buf lines, cursor, new float, delete buf), forcing
  -- the autocmd dispatcher to chain state changes that re-enter
  -- the API in interleaved order
  -- (autocmd_spec.lua:1577-1605 "calls multiple lua callbacks").
  local function cb_set_lines()
    pcall(api.nvim_buf_set_lines, 0, 0, 0, true, { 'mcb1' })
  end
  local function cb_set_cursor()
    pcall(api.nvim_win_set_cursor, 0, { 1, 0 })
  end
  local function cb_open_float()
    local b = api.nvim_create_buf(false, true)
    pcall(api.nvim_open_win, b, false, {
      relative = 'editor', row = 0, col = 0, width = 5, height = 3,
    })
  end
  local function cb_delete_buf()
    local bs = api.nvim_list_bufs()
    if #bs > 1 then
      pcall(api.nvim_buf_delete, bs[#bs], { force = true })
    end
  end
  local pool = { cb_set_lines, cb_set_cursor, cb_open_float, cb_delete_buf }
  -- Randomize subset count and ordering so each replay covers a
  -- different fan-out width.
  local n = R.num(2, #pool)
  for _ = 1, n do
    local idx = R.one_of_n(#pool) + 1
    pcall(api.nvim_create_autocmd, 'User FzMcb',
      { callback = pool[idx] })
    table.remove(pool, idx)
  end
  -- Fire all installed callbacks via a single synthetic event.
  pcall(api.nvim_exec_autocmds, 'User FzMcb', {})
  safe(cmd, 'redrawstatus')
end

local function scenario_attach_detach_cycle()
  -- Attach and detach rapidly on the same buffer. on_lines
  -- notifications depend on per-channel state inside nvim;
  -- repeated cycles reveal race-style state-machine bugs
  -- (buffer_updates_spec.lua:488-511 "does not get confused if
  -- enabled/disabled many times").
  local target = pick_buf()
  if not target then return end
  local cycles = R.num(2, 6)
  for _ = 1, cycles do
    local ok = pcall(api.nvim_buf_attach, target, false, {
      on_lines = function() end,
      on_detach = function() end,
    })
    if not ok then break end
    pcall(api.nvim_buf_detach, target)
  end
  -- A final attach + mutate; the on_lines should fire exactly
  -- once if the cycling cleared internal state correctly.
  local ok = pcall(api.nvim_buf_attach, target, false, {
    on_lines = function(_, b)
      -- Recursive-but-bounded: only mutate once.
      pcall(api.nvim_buf_set_lines, b, -1, -1, false,
        { rand_printable(R.num(0, 4)) })
    end,
  })
  if ok then
    pcall(api.nvim_buf_set_lines, target, 0, 0, true,
      { rand_printable(R.num(0, 6)) })
  end
  safe(cmd, 'redrawstatus')
end

local function scenario_decoration_provider_full_hooks()
  -- nvim_set_decoration_provider with ALL six hooks installed at
  -- once (on_start, on_buf, on_win, on_line, on_range, on_end).
  -- Each hook re-enters the API to mutate extmarks from inside
  -- the redraw pipeline, the broadest reentrancy shape covered
  -- by neovim's extmark tests.
  local ns = api.nvim_create_namespace('fzc' .. rand_word(6))
  S.namespaces[#S.namespaces + 1] = ns
  cap(S.namespaces, 16)
  pcall(api.nvim_set_decoration_provider, ns, {
    on_start = function() return true end,
    on_buf = function(_, b, tick)
      pcall(api.nvim_buf_set_extmark, b, ns, 0, 0, {
        ephemeral = true,
        virt_text = { { rand_printable(R.num(0, 4)), 'Normal' } },
      })
      return tick
    end,
    on_win = function() return true end,
    on_line = function(_, _w, b, row)
      pcall(api.nvim_buf_set_extmark, b, ns, row, 0, {
        ephemeral = true, sign_text = rand_word(1),
      })
    end,
    on_range = function(_, _w, b, br, bc, er, ec)
      pcall(api.nvim_buf_set_extmark, b, ns, br, bc, {
        ephemeral = true,
        end_row = er, end_col = ec,
        hl_group = R.pick({ 'Error', 'Comment', 'Search' }),
      })
    end,
    on_end = function() end,
  })
  local b = pick_buf()
  if b then
    pcall(api.nvim_buf_set_lines, b, 0, 0, true,
      { rand_printable(R.num(0, 6)) })
  end
  safe(cmd, 'redrawstatus')
end

------------------------------------------------------------
-- Pattern 2: last-tab + float boundary
------------------------------------------------------------

local function scenario_last_tab_float_close()
  -- #30425 / #17796 / #31236: float in tab A, close the only
  -- non-current window in tab B.
  pcall(op_open_float)
  local ts = list_tabs()
  if #ts <= 1 then
    pcall(cmd, 'tabnew')
  end
  for _ = 1, 4 do
    pcall(cmd, 'only')
  end
  pcall(cmd, 'tabnext')
  pcall(cmd, 'only')
  local ws = list_wins()
  if #ws > 1 then
    local w = ws[R.one_of_n(#ws)]
    pcall(api.nvim_win_close, w, true)
  end
  if #list_tabs() > 1 then
    pcall(cmd, 'tabclose')
  end
  pcall(api.nvim_buf_delete, list_bufs()[1] or 0, { force = true })
  safe(cmd, 'redrawstatus')
end

local function scenario_bdelete_with_float_in_other_tab()
  -- #30425: bdelete on a non-float buffer when a float is in
  -- another tab anchored to that buffer (or to a buffer being
  -- wiped).
  local extra_bufs = {}
  for _ = 1, 4 do
    local b = api.nvim_create_buf(false, true)
    extra_bufs[#extra_bufs + 1] = b
  end
  pcall(op_open_float)
  pcall(cmd, 'tabnew')
  pcall(cmd, 'only')
  for _, b in ipairs(extra_bufs) do
    pcall(api.nvim_buf_delete, b, { force = true })
  end
  pcall(cmd, 'bdelete')
  safe(cmd, 'redrawstatus')
end

------------------------------------------------------------
-- Pattern 3: extmark + signcolumn / statuscolumn
------------------------------------------------------------

local function scenario_extmark_set_then_buf_set_lines()
  -- #27127: extmark with sign_text + signcolumn=auto + window
  -- buffer swap + bufdelete + set_lines.
  pcall(api.nvim_set_option_value, 'signcolumn', 'auto:3', {})
  local b = pick_buf()
  if not b then return end
  local ns = api.nvim_create_namespace('fzc' .. rand_word(6))
  pcall(api.nvim_buf_set_extmark, b, ns, 0, 0, { sign_text = 'h' })
  pcall(api.nvim_win_set_buf, 0, api.nvim_create_buf(false, true))
  pcall(api.nvim_buf_delete, b, { unload = true, force = true })
  pcall(api.nvim_buf_set_lines, b, 0, -1, false, { '' })
  safe(cmd, 'redrawstatus')
end

local function scenario_statuscolumn_with_extmark()
  -- #32849: statuscolumn set to %s%l + extmark + visual-block input.
  pcall(api.nvim_set_option_value, 'statuscolumn', '%s%l', {})
  local b = pick_buf()
  if not b then return end
  local ns = api.nvim_create_namespace('fzc' .. rand_word(6))
  pcall(api.nvim_buf_set_extmark, b, ns, 0, 0, {
    sign_text = rand_word(1),
    virt_text = { { rand_printable(R.num(0, 30)), 'Error' } },
  })
  pcall(api.nvim_input, '<C-v>jj<Esc>')
  safe(cmd, 'redrawstatus')
end

local function scenario_extmark_invalidate_then_undo()
  -- #27209 / #24894: invalidate=true extmark, then undo.
  local b = pick_buf()
  if not b then return end
  pcall(api.nvim_buf_set_option, b, 'undolevels', -1)
  local ns = api.nvim_create_namespace('fzc' .. rand_word(6))
  pcall(api.nvim_buf_set_lines, b, 0, -1, false, { 'a', 'b', 'c' })
  pcall(api.nvim_buf_set_extmark, b, ns, 0, 0, { invalidate = true })
  pcall(cmd, 'undo')
  pcall(cmd, 'redo')
  pcall(cmd, 'undo')
  safe(cmd, 'redrawstatus')
end

local function scenario_undo_set_lines()
  -- #19608: set_lines + :delete + :undo.
  local b = pick_buf()
  if not b then return end
  pcall(api.nvim_buf_set_lines, b, 0, -1, false, { 'aa' })
  pcall(cmd, 'delete')
  pcall(cmd, 'undo')
  safe(cmd, 'redrawstatus')
end

------------------------------------------------------------
-- Pattern 4 / 5: explicit signcol / statuscol + term chan-send
------------------------------------------------------------

local function op_set_statuscolumn()
  local opts = {}
  if R.chance(1, 3) then opts.win = pick_win() end
  pcall(api.nvim_set_option_value, 'statuscolumn', R.pick({
    '', '%s', '%l', '%s%l', '%f', '%{&fileformat}', '%.30v:%.30h',
    '%{""}', '%{%}', '%c%v', '%{mode()}', '%{"" .. ""}',
  }), opts)
end

local function op_set_signcolumn()
  local v
  local t = R.one_of_n(4)
  if t == 0 then v = 'auto'
  elseif t == 1 then v = 'auto:' .. R.num(1, 9)
  elseif t == 2 then v = 'auto:1-9'
  else v = R.pick({ 'no', 'yes', 'number' })
  end
  pcall(api.nvim_set_option_value, 'signcolumn', v, {})
end

local function op_redraw()
  safe(cmd, R.chance(1, 4) and 'redraw' or 'redrawstatus')
end

local function scenario_chan_send_huge_term_paste()
  -- #16040 / #19075: chansend a huge payload into an open_term
  -- channel; produces a VLA stack-overflow in libvterm on_text.
  local bufs = list_bufs()
  if #bufs == 0 then return end
  local b = R.pick(bufs)
  local ok, ch = pcall(api.nvim_open_term, b, {})
  if not ok or not ch then return end
  local nlines = R.num(2000, 8000)
  local payload = {}
  for _ = 1, nlines do
    payload[#payload + 1] = string.rep('x', 187) .. '\r'
  end
  pcall(api.nvim_chan_send, ch, table.concat(payload))
end

local function scenario_chan_send_ansi_burst()
  -- Escapes / control bytes into an open_term channel.
  local bufs = list_bufs()
  if #bufs == 0 then return end
  local b = R.pick(bufs)
  local ok, ch = pcall(api.nvim_open_term, b, {})
  if not ok or not ch then return end
  local pieces = {}
  for _ = 1, R.num(50, 500) do
    pieces[#pieces + 1] = string.char(R.num(1, 31))
  end
  pcall(api.nvim_chan_send, ch, table.concat(pieces))
end

------------------------------------------------------------
-- Traps
------------------------------------------------------------

local function trap_huge_input()
  pcall(api.nvim_input, ('\12'):rep(R.num(5000, 20000)))
end

local function trap_paste_weird()
  local text = string.char(0)
              .. string.char(2, 3, 6, 0x15, 0x16, 0x17, 0x18, 0x1b, 0x7f)
              .. rand_printable(R.num(0, 8))
  pcall(api.nvim_paste, text, R.chance(1, 2), R.num(-1, 3))
end

local function trap_recursive_exec2()
  pcall(api.nvim_exec_lua, [[
    pcall(vim.api.nvim_create_user_command, '__FzcRec', function()
      pcall(vim.api.nvim_exec2, 'echo "x"', {})
    end, {})
    pcall(vim.api.nvim_cmd, { cmd = '__FzcRec' }, {})
  ]], {})
end

------------------------------------------------------------
-- Dispatch table -- weights bias toward high-density patterns
------------------------------------------------------------

local OPS = {
  { w = 10, name = 'open_float',                    fn = op_open_float },
  { w = 10, name = 'close_random_win',              fn = op_close_random_win },
  { w =  4, name = 'win_set_buf',                   fn = op_win_set_buf },
  { w =  4, name = 'win_set_cursor',                fn = op_win_set_cursor },
  { w =  4, name = 'create_buf',                    fn = op_create_buf },
  { w =  4, name = 'delete_buf',                    fn = op_delete_buf },
  { w =  6, name = 'buf_set_lines',                 fn = op_buf_set_lines },
  { w = 10, name = 'buf_set_extmark',               fn = op_buf_set_extmark },
  { w =  4, name = 'buf_clear_extmark',             fn = op_buf_clear_extmark },
  { w =  3, name = 'tabnew',                        fn = op_tabnew },
  { w =  3, name = 'tabclose',                      fn = op_tabclose },
  { w =  3, name = 'tabnext',                       fn = op_tabnext },
  { w =  5, name = 'set_statuscolumn',              fn = op_set_statuscolumn },
  { w =  4, name = 'set_signcolumn',                fn = op_set_signcolumn },
  { w =  3, name = 'redraw',                        fn = op_redraw },
  -- Pattern 1: autocmd reentrancy
  { w = 10, name = 'scn_winleave_open_float',       fn = scenario_winleave_open_float },
  { w = 10, name = 'scn_winclosed_reentrant_close', fn = scenario_winclosed_reentrant_close },
  { w =  8, name = 'scn_winclosed_reentrant_bufdel',fn = scenario_winclosed_reentrant_buf_delete },
  { w = 10, name = 'scn_bufunload_reentrant_del',   fn = scenario_bufunload_reentrant_bufdelete },
  { w =  8, name = 'scn_on_lines_closes_win',       fn = scenario_on_lines_closes_win },
  -- Pattern 1.5: borrowed from neovim test/functional/api
  { w =  7, name = 'scn_winnew_delete_target',       fn = scenario_winnew_delete_target_buf },
  { w =  6, name = 'scn_deco_provider_chain',        fn = scenario_decoration_provider_chain },
  { w =  6, name = 'scn_buf_attach_recursive',       fn = scenario_buf_attach_recursive_lines },
  { w =  6, name = 'scn_statuscol_eval_complex',     fn = scenario_statuscolumn_eval_complex },
  { w =  6, name = 'scn_open_term_on_input',         fn = scenario_open_term_on_input },
  -- Pattern 1.6: second wave (nested tab, multi-cb, attach/detach cycle,
  -- full decoration provider hooks)
  { w =  6, name = 'scn_tabnew_nested',              fn = scenario_tabnew_nested_open_tabpage },
  { w =  5, name = 'scn_multi_cb_same_event',        fn = scenario_multi_callback_same_event },
  { w =  5, name = 'scn_attach_detach_cycle',        fn = scenario_attach_detach_cycle },
  { w =  5, name = 'scn_deco_provider_full',         fn = scenario_decoration_provider_full_hooks },
  -- Pattern 2: last-tab + float
  { w =  9, name = 'scn_last_tab_float_close',      fn = scenario_last_tab_float_close },
  { w =  8, name = 'scn_bdelete_float_other_tab',   fn = scenario_bdelete_with_float_in_other_tab },
  -- Pattern 3: extmark + signcol/statuscol
  { w = 10, name = 'scn_extmark_buf_set_lines',     fn = scenario_extmark_set_then_buf_set_lines },
  { w = 10, name = 'scn_statuscol_extmark_visual',  fn = scenario_statuscolumn_with_extmark },
  { w =  8, name = 'scn_extmark_invalidate_undo',   fn = scenario_extmark_invalidate_then_undo },
  { w =  6, name = 'scn_undo_set_lines',            fn = scenario_undo_set_lines },
  -- Pattern 5: term chan-send
  { w =  6, name = 'scn_chan_send_huge_term',       fn = scenario_chan_send_huge_term_paste },
  { w =  4, name = 'scn_chan_send_ansi_burst',      fn = scenario_chan_send_ansi_burst },
}

local TRAPS = {
  { w = 4, name = 'huge_input',         fn = trap_huge_input },
  { w = 3, name = 'paste_weird',        fn = trap_paste_weird },
  { w = 3, name = 'recursive_exec2',    fn = trap_recursive_exec2 },
}

local TOTAL = 0
for _, op in ipairs(OPS) do TOTAL = TOTAL + op.w end
local TRAP_TOTAL = 0
for _, t in ipairs(TRAPS) do TRAP_TOTAL = TRAP_TOTAL + t.w end

local OPS_BY_NAME = {}
for _, op in ipairs(OPS) do OPS_BY_NAME[op.name] = op end
for _, t in ipairs(TRAPS) do OPS_BY_NAME[t.name] = t end

local function pick_op()
  local r = R.u32() % TOTAL
  for _, op in ipairs(OPS) do
    r = r - op.w
    if r < 0 then return op end
  end
  return OPS[#OPS]
end

local function pick_trap()
  local r = R.u32() % TRAP_TOTAL
  for _, t in ipairs(TRAPS) do
    r = r - t.w
    if r < 0 then return t end
  end
  return TRAPS[#TRAPS]
end

------------------------------------------------------------
-- Main loop
------------------------------------------------------------

local function teardown_floats()
  C.teardown_floats(api, S.floats)
end
local function teardown_bufs()
  C.teardown_bufs(api, S.scratch_bufs)
end
local function teardown_autocmds()
  C.teardown_autocmds(api, S.auids, S.augroups)
end

for round = 1, ROUNDS do
  CURRENT_ROUND = round
  -- High-level scenario plays first so autocmd / state is set up
  -- before individual ops mutate it.
  if R.chance(2, 5) then
    local op = pick_op()
    safe(op.fn)
    if LOG_TARGET then log_dispatch({ kind = 'op', round = round, name = op.name }) end
  else
    -- 40% of rounds: weighted dispatch across the high-density bug
    -- patterns. Each candidate gets its own chance roll so a
    -- single seed's PRNG can't starve half of them. New patterns
    -- (Pattern 1.5/1.6) get the same chance as the original 3 so
    -- they actually fire over a session of any length.
    if R.chance(1, 5) then
      safe(scenario_winleave_open_float)
      if LOG_TARGET then log_dispatch({ kind = 'scenario', round = round, name = 'scn_winleave_open_float' }) end
    elseif R.chance(1, 5) then
      safe(scenario_last_tab_float_close)
      if LOG_TARGET then log_dispatch({ kind = 'scenario', round = round, name = 'scn_last_tab_float_close' }) end
    elseif R.chance(1, 5) then
      safe(scenario_extmark_set_then_buf_set_lines)
      if LOG_TARGET then log_dispatch({ kind = 'scenario', round = round, name = 'scn_extmark_buf_set_lines' }) end
    elseif R.chance(1, 5) then
      safe(scenario_winnew_delete_target_buf)
      if LOG_TARGET then log_dispatch({ kind = 'scenario', round = round, name = 'scn_winnew_delete_target' }) end
    elseif R.chance(1, 5) then
      safe(scenario_decoration_provider_chain)
      if LOG_TARGET then log_dispatch({ kind = 'scenario', round = round, name = 'scn_deco_provider_chain' }) end
    elseif R.chance(1, 5) then
      safe(scenario_buf_attach_recursive_lines)
      if LOG_TARGET then log_dispatch({ kind = 'scenario', round = round, name = 'scn_buf_attach_recursive' }) end
    elseif R.chance(1, 5) then
      safe(scenario_tabnew_nested_open_tabpage)
      if LOG_TARGET then log_dispatch({ kind = 'scenario', round = round, name = 'scn_tabnew_nested' }) end
    end
  end
  if R.chance(1, 6) then
    local trap = pick_trap()
    safe(trap.fn)
    if LOG_TARGET then log_dispatch({ kind = 'trap', round = round, name = trap.name }) end
  end
  if round % 50 == 0 then
    teardown_floats(); teardown_bufs(); teardown_autocmds()
    if LOG_TARGET then log_dispatch({ kind = 'teardown', round = round, name = 'floats+bufs+autocmds' }) end
  end
  if round % 5 == 0 then
    safe(cmd, 'redrawstatus')
    if LOG_TARGET then log_dispatch({ kind = 'redraw', round = round, name = 'redrawstatus' }) end
  end
  if round % 50 == 0 and not QUIET then
    io.write(string.format('round=%d/%d  wins=%d  bufs=%d  tabs=%d\n',
      round, ROUNDS,
      #api.nvim_list_wins(), #api.nvim_list_bufs(),
      #api.nvim_list_tabpages()))
    io.flush()
  end
end

teardown_floats()
teardown_bufs()
teardown_autocmds()
safe(cmd, 'redrawstatus')
print('done seed=' .. tostring(arg and arg[1] or '42'))
