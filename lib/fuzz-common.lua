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

return M
