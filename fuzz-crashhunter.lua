-- Focused fuzzer for the crash patterns documented in doc/crashes/.
-- Smaller and more targeted than fuzz.lua: every op / scenario here
-- maps to a known upstream crash family or to a regression class
-- pulled from neovim's functional API tests.
--
-- Usage:
--   out/nvim -l fuzz-crashhunter.lua [SEED_OR_FILE] [ROUNDS]
--
-- SEED_OR_FILE is a positive integer or a path to an existing file
-- (AFL "@@" mode). Defaults: SEED=42, ROUNDS=500.
--
-- Coverage targets (ordered by crash-density):
--
--  * Old top-5 (doc/crashes/00-summary.md):
--    1. autocmd re-entrancy on window/buffer close (WinLeave /
--       WinClosed / BufUnload / on_lines / TabNew nested open_tabpage
--       / multi-cb same event / attach-detach cycle / QuickFixCmdPost
--       nested cclose / WinLeave nested win_close / DirChanged
--       nested)
--    2. last-non-float window in last tabpage
--    3. extmark + signcolumn / statuscolumn sync
--    4. undolevels=-1 + extmark
--    5. libvterm VLA stack-overflow (chansend huge payload)
--
--  * Newer patterns pulled from neovim's functional tests:
--    6. nvim_echo + custom kind + guicursor change + nvim__redraw
--       {flush=true} + :messages  (#38289, vim_spec.lua:4280-4295)
--    7. nvim__redraw variants (range / valid / cursor / statusline /
--       statuscolumn / winbar / tabline / flush)  (#38289, vim_spec
--       .lua:6133-6430)
--    8. 80k-byte pattern in nvim_create_autocmd (fast_spec.lua:97)
--    9. popmenu / wildmenu closed without selection  (ui/popupmenu
--       _spec, vim/wildmenu_spec)
--   10. timer callback in fast-event window  (lua/timer_spec)
--   11. nvim_buf_attach in fast-event with on_lines reentry
--
-- Architecture: this file is a thin layer over lib/fuzz-ops.lua and
-- lib/fuzz-common.lua.  The basic 50-ish op functions and the trap
-- set live in fuzz-ops.lua and are installed via F.install(ctx);
-- the scenarios live here because they are the bug-class shaped glue
-- that pulls behavior pools from common.behavior_pools(ctx).  OPS
-- and TRAPS tables are merged into a single weighted dispatch so
-- every op / scenario fires proportionally to its weight -- there
-- is no hardcoded chance cascade that could starve new patterns.

vim.o.swapfile = false
vim.o.shadafile = 'NONE'
vim.o.more = false
vim.o.shortmess = 'aoOstTWAIcCFqs'

local QUIET = os.getenv('FUZZ_QUIET') == '1'
local ROUNDS = tonumber(os.getenv('ROUNDS'))
                 or tonumber(arg and arg[2])
                 or 500

local MODE = arg and arg[3] or nil
local MODE_ARG = nil
if MODE then
  local k, v = MODE:match('^([^=]+)=(.*)$')
  if k then MODE, MODE_ARG = k, v end
end

local api = vim.api
local cmd = vim.cmd

------------------------------------------------------------
-- Round / per-round-ops state
--
-- Declared before proxies run so the proxy closures bind them
-- as upvalues. CURRENT_ROUND is set once per round by the
-- main loop; _round_ops is reset at the start of every round
-- and incremented by the api/cmd proxy whenever an op / cmd
-- fires. FUZZ_ROUND_OPS_CAP=0 disables the cap entirely.
------------------------------------------------------------
local CURRENT_ROUND = 0
local _round_ops = { 0 }
local FUZZ_ROUND_OPS_CAP = tonumber(os.getenv('FUZZ_ROUND_OPS_CAP')) or 0

------------------------------------------------------------
-- Dispatch log (used when MODE='log=path'; same shape as
-- fuzz.lua so bin/from-log.lua can convert a captured log into
-- a standalone repro.lua that calls vim.api.* explicitly with
-- the recorded args).
------------------------------------------------------------
local LOG_TARGET = nil
local LOG_PATH = nil
if MODE == 'log' then
  assert(MODE_ARG, 'log mode requires a path argument: log=/path/to/log.lua')
  LOG_PATH = MODE_ARG
  LOG_TARGET = { ops = {}, fh = assert(io.open(LOG_PATH, 'w')) }
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

------------------------------------------------------------
-- Pull common helpers; install api/cmd proxies for log mode.
------------------------------------------------------------
package.path = './lib/?.lua;./lib/?/init.lua;' .. package.path
local C = require('fuzz-common')

local ser_arg, ser_args = C.make_arg_serializer()
local function round_idx() return CURRENT_ROUND end

if LOG_TARGET then
  api = C.make_api_logger({
    api = vim.api, ser_arg = ser_arg, ser_args = ser_args,
    round_idx_fn = round_idx, round_ops = _round_ops,
    round_ops_cap = FUZZ_ROUND_OPS_CAP, log_fh = LOG_TARGET.fh,
  })
  cmd = C.make_cmd_logger({
    cmd = vim.cmd, ser_arg = ser_arg, ser_args = ser_args,
    round_idx_fn = round_idx, round_ops = _round_ops,
    round_ops_cap = FUZZ_ROUND_OPS_CAP, log_fh = LOG_TARGET.fh,
  })
end

------------------------------------------------------------
-- PRNG / state / shared libs
------------------------------------------------------------
local R_bytes, R_label = C.resolve_bytes(arg and arg[1] or '42')
local R = C.make_prng(R_bytes, 'crashhunter:' .. R_label)

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

local S = C.new_state()

local rand_printable = function(n) return C.rand_printable(R, n) end
local rand_buf = function(n) return C.rand_buf(R, n) end
local rand_word = function(n) return C.rand_word(R, n) end

local list_wins = function() return C.list_wins(api) end
local list_bufs = function() return C.list_bufs(api) end
local list_tabs = function() return C.list_tabs(api) end
local pick_win = function() return C.pick_win(api, R) end
local pick_buf = function() return C.pick_buf(api, R) end
local pick_tab = function() return C.pick_tab(api, R) end

local safe = C.safe
local cap = C.cap
local varied_cb = C.make_varied_cb

------------------------------------------------------------
-- Behavior pools for autocmd callbacks.
------------------------------------------------------------
local POOLS = C.behavior_pools({
  api = api, cmd = cmd, R = R,
  pick_buf = pick_buf, rand_printable = rand_printable, rand_word = rand_word,
})

------------------------------------------------------------
-- Install op + trap library. ops.OPS / ops.TRAPS drive the
-- single weighted dispatch in the main loop. Anything op-shaped
-- that fuzz-ops.lua does not already cover (signcolumn / status
-- column sets, redraw) is appended to the dispatch here.
------------------------------------------------------------
local F = require('fuzz-ops')
local ops = F.install({
  api = api, cmd = cmd, R = R, S = S,
  list_wins = list_wins, list_bufs = list_bufs, list_tabs = list_tabs,
  pick_win = pick_win, pick_buf = pick_buf, pick_tab = pick_tab,
  rand_printable = rand_printable, rand_buf = rand_buf, rand_word = rand_word,
  cap = cap, safe = safe,
  record_args = function(_) end,  -- crashes are not arg-replay targets
  consume_args = function() return nil end,
})

------------------------------------------------------------
-- Helper ops that are NOT in fuzz-ops.lua (signcolumn / status
-- column / redraw).  Same pattern: take no args, use the
-- captured api/R.
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

------------------------------------------------------------
-- Pattern 1: autocmd re-entrancy scenarios.
--
-- Each installs a varied callback on the event and then fires
-- the triggering op. By using the shared CB pools, every replay
-- of the same seed explores a different behavior path even for
-- the same scenario.
------------------------------------------------------------

local function scn_winleave_open_float()
  -- #31236: WinLeave callback opens a float; tab split then
  -- closes the only non-current tab and frees the float.
  pcall(api.nvim_create_autocmd, 'WinLeave',
    { callback = varied_cb(POOLS.WINLEAVE) })
  local ts = list_tabs()
  if #ts >= 2 then
    pcall(cmd, 'tabnext'); pcall(cmd, 'tabclose')
  else
    pcall(cmd, 'tabnew')
  end
  safe(cmd, 'redrawstatus')
end

local function scn_winclosed_reentrant_close()
  -- #37211 / #13265: WinClosed callback closes another window.
  local target = pick_win()
  if not target then return end
  pcall(api.nvim_create_autocmd, 'WinClosed',
    { nested = true, callback = varied_cb(POOLS.WINCLOSED) })
  pcall(api.nvim_win_close, target, true)
  safe(cmd, 'redrawstatus')
end

local function scn_winclosed_reentrant_buf_delete()
  -- #37211 / #33603: WinClosed callback deletes a buffer.
  local tb = pick_buf(); local tw = pick_win()
  if not tb or not tw then return end
  pcall(api.nvim_create_autocmd, 'WinClosed',
    { nested = true, callback = varied_cb(POOLS.WINCLOSED) })
  pcall(api.nvim_win_close, tw, true)
  safe(cmd, 'redrawstatus')
end

local function scn_bufunload_reentrant_bufdelete()
  -- #33603: BufUnload callback deletes another buffer.
  local ta, tb = pick_buf(), pick_buf()
  if not ta or not tb or ta == tb then return end
  pcall(api.nvim_create_autocmd, 'BufUnload',
    { nested = true, callback = varied_cb(POOLS.BUFUNLOAD) })
  pcall(api.nvim_buf_delete, ta, { force = true })
  safe(cmd, 'redrawstatus')
end

local function scn_on_lines_closes_win()
  -- #13231: nvim_buf_attach callback closes the window.
  local target = pick_buf()
  if not target then return end
  local ok = pcall(api.nvim_buf_attach, target, false,
    { on_lines = varied_cb(POOLS.ON_LINES) })
  if not ok then return end
  pcall(api.nvim_buf_set_lines, target, 0, 0, true, { 'x' })
  safe(cmd, 'redrawstatus')
end

local function scn_winnew_delete_target_buf()
  -- window_spec.lua:1949-1955 -- WinNew callback deletes the
  -- would-be buffer before the new window finishes initializing.
  local target_buf = pick_buf()
  if not target_buf then return end
  pcall(api.nvim_create_autocmd, 'WinNew', {
    callback = function()
      pcall(api.nvim_buf_delete, target_buf, { force = true })
    end,
  })
  pcall(cmd, R.chance(1, 2) and 'split' or 'vsplit')
  safe(cmd, 'redrawstatus')
end

local function scn_deco_provider_chain()
  -- nvim_set_decoration_provider with on_buf + on_line that
  -- re-enter the API to mutate extmarks from inside the
  -- redraw pipeline.
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
  local tb = pick_buf()
  if tb then
    pcall(api.nvim_buf_set_lines, tb,
      R.num(-1, 30), R.num(-1, 30), false,
      { rand_printable(R.num(0, 6)) })
  end
  safe(cmd, 'redrawstatus')
end

local function scn_buf_attach_recursive_lines()
  -- nvim_buf_attach on_lines that recursively mutates the same
  -- buffer, bounded to a small depth.
  local target = pick_buf()
  if not target then return end
  local fired = 0
  local ok = pcall(api.nvim_buf_attach, target, false, {
    on_lines = function(_, b, _ct, _f, _l, _ll, _bc)
      fired = fired + 1
      if fired > 4 then return end
      pcall(api.nvim_buf_set_lines, b, fired, fired, false,
        { rand_printable(R.num(0, 4)) })
    end,
    on_detach = function() end,
  })
  if not ok then return end
  pcall(api.nvim_buf_set_lines, target, 0, 0, true,
    { rand_printable(R.num(0, 6)) })
  safe(cmd, 'redrawstatus')
end

local function scn_statuscolumn_eval_complex()
  -- statuscolumn set to an expression containing %{} that
  -- re-evaluates per redraw, with sign_text + ui_watched
  -- extmark forcing re-evaluation (vim_spec.lua:4502-4746).
  local b = pick_buf(); if not b then return end
  pcall(api.nvim_set_option_value, 'statuscolumn', R.pick({
    '%{""}', '%{%}', '%c%v', '%{mode()}',
    '%{"" .. ""}', '%{%{%{""}%}%}', '%{toupper("fz")}',
  }), {})
  local ns = api.nvim_create_namespace('fzc' .. rand_word(6))
  pcall(api.nvim_buf_set_extmark, b, ns, 0, 0, {
    sign_text = rand_word(1), ui_watched = true,
  })
  safe(cmd, 'redrawstatus')
end

local function scn_open_term_on_input()
  -- nvim_open_term with on_input callback that re-enters the
  -- API to mutate the buffer (vim_spec.lua:4294-4500).
  local bs = list_bufs(); if #bs == 0 then return end
  local b = R.pick(bs)
  local ok, ch = pcall(api.nvim_open_term, b, {
    on_input = function(_, _t, _b, _d)
      pcall(api.nvim_buf_set_lines, _b, 0, -1, false, { 'fzot' })
    end,
  })
  if not ok or not ch then return end
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

local function scn_tabnew_nested_open_tabpage()
  -- tabpage_spec.lua:319-334 -- nested nvim_open_tabpage inside
  -- a TabNew callback. Re-entry through tabpage creation.
  pcall(api.nvim_create_autocmd, 'TabNew',
    { callback = varied_cb(POOLS.TABNEW) })
  pcall(cmd, 'tabnew'); safe(cmd, 'redrawstatus')
end

local function scn_multi_callback_same_event()
  -- autocmd_spec.lua:1577-1605 -- multiple distinct callbacks
  -- on the same User event, each mutating a different resource.
  local pool = {
    function() pcall(api.nvim_buf_set_lines, 0, 0, 0, true, { 'mcb1' }) end,
    function() pcall(api.nvim_win_set_cursor, 0, { 1, 0 }) end,
    function()
      local b = api.nvim_create_buf(false, true)
      pcall(api.nvim_open_win, b, false,
        { relative = 'editor', row = 0, col = 0, width = 5, height = 3 })
    end,
    function()
      local bs = api.nvim_list_bufs()
      if #bs > 1 then pcall(api.nvim_buf_delete, bs[#bs], { force = true }) end
    end,
  }
  local n = R.num(2, #pool)
  for _ = 1, n do
    local idx = R.one_of_n(#pool) + 1
    pcall(api.nvim_create_autocmd, 'User FzMcb', { callback = pool[idx] })
    table.remove(pool, idx)
  end
  pcall(api.nvim_exec_autocmds, 'User FzMcb', {})
  safe(cmd, 'redrawstatus')
end

local function scn_attach_detach_cycle()
  -- buffer_updates_spec.lua:488-511 -- rapid attach/detach
  -- cycling reveals race-style state-machine bugs.
  local target = pick_buf(); if not target then return end
  for _ = 1, R.num(2, 6) do
    local ok = pcall(api.nvim_buf_attach, target, false,
      { on_lines = function() end, on_detach = function() end })
    if not ok then break end
    pcall(api.nvim_buf_detach, target)
  end
  local ok = pcall(api.nvim_buf_attach, target, false, {
    on_lines = function(_, b)
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

local function scn_deco_provider_full_hooks()
  -- extmark_spec.lua -- all six hooks installed at once; each
  -- re-enters the API to mutate extmarks from inside the
  -- redraw pipeline (broadest reentrancy shape).
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
      pcall(api.nvim_buf_set_extmark, b, ns, row, 0,
        { ephemeral = true, sign_text = rand_word(1) })
    end,
    on_range = function(_, _w, b, br, bc, er, ec)
      pcall(api.nvim_buf_set_extmark, b, ns, br, bc, {
        ephemeral = true, end_row = er, end_col = ec,
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

local function scn_buf_attach_ondetach_chain()
  -- buffer_updates_spec.lua:1776-1892 -- nvim_buf_attach
  -- + on_detach that re-attaches the same buffer, exercising
  -- the free_buffer_stuff -> on_detach cycle.
  local target = pick_buf(); if not target then return end
  local depth = 0
  local ok = pcall(api.nvim_buf_attach, target, false, {
    on_lines = function() end,
    on_detach = function()
      depth = depth + 1
      if depth > 2 then return end
      pcall(api.nvim_buf_attach, target, false,
        { on_lines = function() end, on_detach = function() end })
    end,
  })
  if not ok then return end
  pcall(api.nvim_buf_set_name, target,
    '/tmp/fz_detach_' .. rand_word(4) .. '.txt')
  pcall(cmd, 'edit'); safe(cmd, 'redrawstatus')
end

local function scn_termclose_bwipe_chanclose()
  -- channel_spec.lua:209-230 -- TermClose callback bwipes the
  -- buffer and writes to the channel in the same event.
  local b = pick_buf(); if not b then return end
  local ok, ch = pcall(api.nvim_open_term, b, {})
  if not ok or not ch then return end
  pcall(api.nvim_create_autocmd, 'TermClose', {
    nested = true,
    callback = function()
      pcall(api.nvim_buf_delete, b, { force = true })
      pcall(api.nvim_chan_send, ch, '\x03')
    end,
  })
  pcall(api.nvim_chan_send, ch, 'exit\r')
  safe(cmd, 'redrawstatus')
end

local function scn_quickfix_nested_autocmd()
  -- quickfix_commands_spec.lua:196 -- QuickFixCmdPost nested
  -- cclose | cwindow under ++nested.
  pcall(api.nvim_create_autocmd, 'QuickFixCmdPost', {
    nested = true,
    callback = function()
      pcall(cmd, 'cclose'); pcall(cmd, 'cwindow')
    end,
  })
  pcall(api.nvim_buf_set_lines, 0, 0, -1, false,
    { 'foo bar', 'baz foo', 'qux bar', 'extra line' })
  pcall(cmd, 'vimgrep /foo/ %'); safe(cmd, 'redrawstatus')
end

local function scn_winleave_nested_win_close()
  -- errorlist_spec.lua:77-82 -- WinLeave autocmd closes the
  -- current window inside the callback.
  local target = pick_win(); if not target then return end
  pcall(api.nvim_create_autocmd, 'WinLeave', {
    nested = true,
    callback = function() pcall(api.nvim_win_close, 0, true) end,
  })
  pcall(api.nvim_win_close, target, true); safe(cmd, 'redrawstatus')
end

local function scn_dirchange_nested()
  -- dirchanged_spec.lua:93 -- DirChanged autocmd attempts
  -- another :cd inside the callback.
  pcall(api.nvim_create_autocmd, 'DirChanged', {
    nested = true,
    callback = function() pcall(cmd, 'cd /tmp') end,
  })
  pcall(cmd, 'cd /'); safe(cmd, 'redrawstatus')
end

local function scn_langmap_with_input_chain()
  -- langmap_spec.lua:64-201 -- langmap set + insert-mode
  -- mapping that calls a nvim API to mutate the buffer.
  pcall(cmd, 'set langmap=xX,Xx,yY,Yy')
  local rhs = ':lua vim.api.nvim_buf_set_lines(0, 0, 0, true, {"fzlm"})<CR>'
  local opts = { noremap = true, silent = true }
  local ok = pcall(api.nvim_buf_set_keymap, 0, 'i', '<F2>', rhs, opts)
  if not ok then pcall(api.nvim_set_keymap, 'i', '<F2>', rhs, opts) end
  pcall(api.nvim_input, '<F2>'); safe(cmd, 'redrawstatus')
end

------------------------------------------------------------
-- Pattern 2: last-tab + float boundary.
------------------------------------------------------------

local function scn_last_tab_float_close()
  -- #30425 / #17796 / #31236 -- float in tab A, close the
  -- only non-current window in tab B.
  pcall(ops.op_open_float)
  local ts = list_tabs()
  if #ts <= 1 then pcall(cmd, 'tabnew') end
  for _ = 1, 4 do pcall(cmd, 'only') end
  pcall(cmd, 'tabnext'); pcall(cmd, 'only')
  local ws = list_wins()
  if #ws > 1 then
    pcall(api.nvim_win_close, ws[R.one_of_n(#ws)], true)
  end
  if #list_tabs() > 1 then pcall(cmd, 'tabclose') end
  pcall(api.nvim_buf_delete, list_bufs()[1] or 0, { force = true })
  safe(cmd, 'redrawstatus')
end

local function scn_bdelete_with_float_in_other_tab()
  -- #30425 -- bdelete on a non-float buffer when a float is
  -- in another tab anchored to that buffer.
  local extra_bufs = {}
  for _ = 1, 4 do
    extra_bufs[#extra_bufs + 1] = api.nvim_create_buf(false, true)
  end
  pcall(ops.op_open_float); pcall(cmd, 'tabnew'); pcall(cmd, 'only')
  for _, b in ipairs(extra_bufs) do
    pcall(api.nvim_buf_delete, b, { force = true })
  end
  pcall(cmd, 'bdelete'); safe(cmd, 'redrawstatus')
end

------------------------------------------------------------
-- Pattern 3: extmark + signcolumn / statuscolumn.
------------------------------------------------------------

local function scn_extmark_set_then_buf_set_lines()
  -- #27127 -- extmark with sign_text + signcolumn=auto + window
  -- buffer swap + bufdelete + set_lines.
  pcall(api.nvim_set_option_value, 'signcolumn', 'auto:3', {})
  local b = pick_buf(); if not b then return end
  local ns = api.nvim_create_namespace('fzc' .. rand_word(6))
  pcall(api.nvim_buf_set_extmark, b, ns, 0, 0, { sign_text = 'h' })
  pcall(api.nvim_win_set_buf, 0, api.nvim_create_buf(false, true))
  pcall(api.nvim_buf_delete, b, { unload = true, force = true })
  pcall(api.nvim_buf_set_lines, b, 0, -1, false, { '' })
  safe(cmd, 'redrawstatus')
end

local function scn_statuscolumn_with_extmark()
  -- #32849 -- statuscolumn set to %s%l + extmark + visual-block
  -- input.
  pcall(api.nvim_set_option_value, 'statuscolumn', '%s%l', {})
  local b = pick_buf(); if not b then return end
  local ns = api.nvim_create_namespace('fzc' .. rand_word(6))
  pcall(api.nvim_buf_set_extmark, b, ns, 0, 0, {
    sign_text = rand_word(1),
    virt_text = { { rand_printable(R.num(0, 30)), 'Error' } },
  })
  pcall(api.nvim_input, '<C-v>jj<Esc>'); safe(cmd, 'redrawstatus')
end

local function scn_extmark_invalidate_then_undo()
  -- #27209 / #24894 -- invalidate=true extmark, then undo.
  -- undolevels=-1 plus extmark has historically been a NULL
  -- deref site.
  local b = pick_buf(); if not b then return end
  pcall(api.nvim_buf_set_option, b, 'undolevels', -1)
  local ns = api.nvim_create_namespace('fzc' .. rand_word(6))
  pcall(api.nvim_buf_set_lines, b, 0, -1, false, { 'a', 'b', 'c' })
  pcall(api.nvim_buf_set_extmark, b, ns, 0, 0, { invalidate = true })
  pcall(cmd, 'undo'); pcall(cmd, 'redo'); pcall(cmd, 'undo')
  safe(cmd, 'redrawstatus')
end

local function scn_undo_set_lines()
  -- #19608 -- set_lines + :delete + :undo.
  local b = pick_buf(); if not b then return end
  pcall(api.nvim_buf_set_lines, b, 0, -1, false, { 'aa' })
  pcall(cmd, 'delete'); pcall(cmd, 'undo'); safe(cmd, 'redrawstatus')
end

------------------------------------------------------------
-- Pattern 4/5: explicit signcol/statuscol + term chan-send.
------------------------------------------------------------

local function scn_chan_send_huge_term_paste()
  -- #16040 / #19075 -- chansend a huge payload into an open_term
  -- channel; VLA stack-overflow in libvterm on_text.
  local bs = list_bufs(); if #bs == 0 then return end
  local b = R.pick(bs)
  local ok, ch = pcall(api.nvim_open_term, b, {})
  if not ok or not ch then return end
  local nlines = R.num(2000, 8000)
  local payload = {}
  for _ = 1, nlines do
    payload[#payload + 1] = string.rep('x', 187) .. '\r'
  end
  pcall(api.nvim_chan_send, ch, table.concat(payload))
end

local function scn_chan_send_ansi_burst()
  -- Escapes / control bytes into an open_term channel.
  local bs = list_bufs(); if #bs == 0 then return end
  local b = R.pick(bs)
  local ok, ch = pcall(api.nvim_open_term, b, {})
  if not ok or not ch then return end
  local pieces = {}
  for _ = 1, R.num(50, 500) do
    pieces[#pieces + 1] = string.char(R.num(1, 31))
  end
  pcall(api.nvim_chan_send, ch, table.concat(pieces))
end

------------------------------------------------------------
-- Newer patterns (B6-B11).
------------------------------------------------------------

local function scn_nvim_echo_arena_free()
  -- #38289 (vim_spec.lua:4280-4295) -- nvim_echo with a custom
  -- kind followed by a guicursor change and nvim__redraw flush,
  -- then :messages.  The original test comment:
  --   "ui_flush -> arena_mem_free go brrr"
  -- The bug was a use-after-free where pending redraw work
  -- captured a stale pointer that was freed by ui_flush.  We
  -- bias toward custom kinds that are NOT one of the well-known
  -- ones ('echo', 'echomsg', 'echoerr', 'lua_print', etc.) to
  -- reach the buggy branch.
  local custom_kinds = {
    'progress', 'status', 'diagnostic', 'quickfix', 'completion',
    'history', 'search', 'tabpage', 'command', 'lua', 'foo', 'bar',
  }
  pcall(api.nvim_echo, { { rand_printable(R.num(1, 8)) } }, true,
    { kind = R.pick(custom_kinds) })
  pcall(api.nvim_set_option_value, 'guicursor', R.pick({
    '', 'n-v:cursor', 'a:blinkon0', 'i-ci:ver25-Cursor',
  }), {})
  pcall(api.nvim__redraw, { flush = true })
  pcall(cmd, 'messages')
end

local function scn_nvim_redraw_flush()
  -- vim_spec.lua:6133-6430 -- nvim__redraw variants. Each
  -- tests a different redraw trigger; together they cover the
  -- arena_flush / ui_flush / status_flush paths.
  local opts = {}
  local which = R.one_of_n(8)
  if which == 0 then opts.cursor = true
  elseif which == 1 then opts.statusline = true
  elseif which == 2 then opts.statuscolumn = true
  elseif which == 3 then opts.tabline = true
  elseif which == 4 then opts.winbar = true
  elseif which == 5 then
    opts.buf = pick_buf() or 0; opts.valid = R.chance(1, 2)
  elseif which == 6 then
    opts.win = pick_win() or 0; opts.range = { R.num(0, 50), R.num(0, 50) }
  else
    opts.flush = true; opts.valid = R.chance(1, 2)
  end
  -- Combine two flags often to widen the dispatch.
  if R.chance(1, 3) then opts.flush = true end
  if R.chance(1, 4) and not opts.win and not opts.buf then
    opts.win = pick_win() or 0
  end
  pcall(api.nvim__redraw, opts)
end

local function scn_long_pattern_autocmd()
  -- fast_spec.lua:97 -- autocmd with an 80000-byte pattern.
  -- Long patterns stress the autotree regex compilation path
  -- and the E339 pattern-too-long limit.  We also try patterns
  -- of mixed glob / literal shapes to hit different branches.
  local pattern
  local shape = R.one_of_n(4)
  if shape == 0 then
    pattern = string.rep('a', R.num(1000, 80000))
  elseif shape == 1 then
    pattern = string.rep('?', R.num(100, 5000))
  elseif shape == 2 then
    pattern = ('/'):rep(R.num(100, 1000))
  else
    pattern = rand_printable(R.num(80000, 80000))
  end
  pcall(api.nvim_create_autocmd, R.pick({
    'BufRead', 'BufReadPost', 'FileType', 'User',
  }), {
    pattern = pattern,
    callback = function() end,
  })
end

local function scn_popmenu_wildmenu()
  -- ui/popupmenu_spec, vim/wildmenu_spec -- open the wildmenu
  -- by feeding printable / control / function keys, then close
  -- it abruptly via <Esc> or <C-c>.  The pum + mode transition
  -- has been a redraw race source.
  pcall(api.nvim_set_option_value, 'wildmenu', true, {})
  pcall(api.nvim_set_option_value, 'wildoptions', R.pick({
    '', 'pum', 'pum,tag', 'tag,pum',
  }), {})
  pcall(api.nvim_input, R.pick({
    'i<Tab>', 'i<S-Tab>', 'i<Up>', 'i<Down>',
    'i<Esc>', 'i<C-c>', 'i<CR>', 'i<C-y>', 'i<C-e>',
  }))
  safe(cmd, 'redrawstatus')
end

local function scn_timer_fast_event()
  -- lua/timer_spec.lua -- timer callback fires in a fast event
  -- context where many API functions are forbidden. Calling
  -- them triggers an error path; calling the safe subset from
  -- there exercises the fast-event -> normal-event transition.
  local ms = R.num(0, 30)
  local body = R.pick({
    [[function() pcall(vim.api.nvim_buf_set_lines, 0, 0, -1, false, { 'tmr' }) end]],
    [[function() pcall(vim.cmd, 'redrawstatus') end]],
    [[function() local _ = vim.fn.byteidx('ab', 1) end]],
    [[function() pcall(vim.api.nvim_create_autocmd, 'User', { callback = function() end }) end]],
    [[function() pcall(vim.api.nvim__redraw, { flush = true }) end]],
  })
  local ok = pcall(vim.fn.timer_start, ms, loadstring(body)(), {})
  if ok then safe(cmd, 'redrawstatus') end
end

local function scn_buf_attach_in_fast_event()
  -- nvim_buf_attach in a fast-event (timer) callback that
  -- re-enters the API on_lines path.  Reentry through the
  -- fast-event boundary has been a state-machine bug source.
  local target = pick_buf(); if not target then return end
  local ms = R.num(0, 30)
  local body = string.format([[
    pcall(vim.api.nvim_buf_attach, %d, false, {
      on_lines = function(_, b)
        pcall(vim.api.nvim_buf_set_lines, b, -1, -1, false, { 'fl' })
      end,
      on_detach = function() end,
    })
  ]], target)
  local ok = pcall(vim.fn.timer_start, ms, loadstring(body)(), {})
  if ok then
    -- Give the timer a chance to fire, then mutate the buffer
    -- so the on_lines callback runs.
    pcall(api.nvim_buf_set_lines, target, 0, 0, true, { 'fire' })
    safe(cmd, 'redrawstatus')
  end
end

------------------------------------------------------------
-- Dispatch tables.
------------------------------------------------------------

local SCENARIOS = {
  { w = 10, name = 'scn_winleave_open_float',         fn = scn_winleave_open_float },
  { w = 10, name = 'scn_winclosed_reentrant_close',   fn = scn_winclosed_reentrant_close },
  { w =  8, name = 'scn_winclosed_reentrant_bufdel',  fn = scn_winclosed_reentrant_buf_delete },
  { w = 10, name = 'scn_bufunload_reentrant_del',     fn = scn_bufunload_reentrant_bufdelete },
  { w =  8, name = 'scn_on_lines_closes_win',         fn = scn_on_lines_closes_win },
  { w =  7, name = 'scn_winnew_delete_target',        fn = scn_winnew_delete_target_buf },
  { w =  6, name = 'scn_deco_provider_chain',         fn = scn_deco_provider_chain },
  { w =  6, name = 'scn_buf_attach_recursive',        fn = scn_buf_attach_recursive_lines },
  { w =  6, name = 'scn_statuscol_eval_complex',      fn = scn_statuscolumn_eval_complex },
  { w =  6, name = 'scn_open_term_on_input',          fn = scn_open_term_on_input },
  { w =  6, name = 'scn_tabnew_nested',               fn = scn_tabnew_nested_open_tabpage },
  { w =  5, name = 'scn_multi_cb_same_event',         fn = scn_multi_callback_same_event },
  { w =  5, name = 'scn_attach_detach_cycle',         fn = scn_attach_detach_cycle },
  { w =  5, name = 'scn_deco_provider_full',          fn = scn_deco_provider_full_hooks },
  { w =  7, name = 'scn_buf_attach_ondetach',         fn = scn_buf_attach_ondetach_chain },
  { w =  7, name = 'scn_termclose_bwipe',             fn = scn_termclose_bwipe_chanclose },
  { w =  6, name = 'scn_quickfix_nested',             fn = scn_quickfix_nested_autocmd },
  { w =  7, name = 'scn_winleave_nested_close',       fn = scn_winleave_nested_win_close },
  { w =  6, name = 'scn_dirchange_nested',            fn = scn_dirchange_nested },
  { w =  6, name = 'scn_langmap_input_chain',         fn = scn_langmap_with_input_chain },
  { w =  9, name = 'scn_last_tab_float_close',        fn = scn_last_tab_float_close },
  { w =  8, name = 'scn_bdelete_float_other_tab',     fn = scn_bdelete_with_float_in_other_tab },
  { w = 10, name = 'scn_extmark_buf_set_lines',       fn = scn_extmark_set_then_buf_set_lines },
  { w = 10, name = 'scn_statuscol_extmark_visual',    fn = scn_statuscolumn_with_extmark },
  { w =  8, name = 'scn_extmark_invalidate_undo',     fn = scn_extmark_invalidate_then_undo },
  { w =  6, name = 'scn_undo_set_lines',              fn = scn_undo_set_lines },
  { w =  6, name = 'scn_chan_send_huge_term',         fn = scn_chan_send_huge_term_paste },
  { w =  4, name = 'scn_chan_send_ansi_burst',        fn = scn_chan_send_ansi_burst },
  { w =  8, name = 'scn_nvim_echo_arena_free',        fn = scn_nvim_echo_arena_free },
  { w =  7, name = 'scn_nvim_redraw_flush',           fn = scn_nvim_redraw_flush },
  { w =  6, name = 'scn_long_pattern_autocmd',        fn = scn_long_pattern_autocmd },
  { w =  5, name = 'scn_popmenu_wildmenu',            fn = scn_popmenu_wildmenu },
  { w =  4, name = 'scn_timer_fast_event',            fn = scn_timer_fast_event },
  { w =  5, name = 'scn_buf_attach_in_fast_event',    fn = scn_buf_attach_in_fast_event },
}

local EXTRA_OPS = {
  { w = 5, name = 'set_statuscolumn',  fn = op_set_statuscolumn },
  { w = 4, name = 'set_signcolumn',    fn = op_set_signcolumn },
  { w = 3, name = 'redraw',            fn = op_redraw },
}

-- Merge into a single dispatch table.
local OPS = ops.OPS
for _, s in ipairs(SCENARIOS) do OPS[#OPS + 1] = s end
for _, o in ipairs(EXTRA_OPS) do OPS[#OPS + 1] = o end
C.reset_weight_cache(OPS)

------------------------------------------------------------
-- Replay path.  When MODE='replay=...', REPLAY_LOG is a table
-- of {kind, name, ...} entries (one per captured op).  We
-- replay them in order, with a per-round teardown block at
-- every round boundary.  The replay path bypasses PRNG-driven
-- dispatch; it just calls each captured op's fn().
------------------------------------------------------------
if REPLAY_LOG then
  CURRENT_ROUND = 1
  for _, e in ipairs(REPLAY_LOG.ops) do
    if e.round and e.round > CURRENT_ROUND then
      C.teardown_floats(api, S.floats)
      C.teardown_bufs(api, S.scratch_bufs)
      C.teardown_autocmds(api, S.auids, S.augroups)
      CURRENT_ROUND = e.round
    end
    local op = OPS
    for i = 1, #op do
      if op[i].name == e.name then
        safe(op[i].fn); break
      end
    end
  end
  C.teardown_floats(api, S.floats)
  C.teardown_bufs(api, S.scratch_bufs)
  C.teardown_autocmds(api, S.auids, S.augroups)
  print('replay done; rounds=' .. CURRENT_ROUND)
  return
end

------------------------------------------------------------
-- Main loop.
------------------------------------------------------------
for round = 1, ROUNDS do
  CURRENT_ROUND = round
  _round_ops[1] = 0

  -- Pick one op / scenario per round, weighted by w. The round
  -- counter is mixed into the u32 to break the PRNG cycle, so a
  -- single 200-round standalone run actually sees the full
  -- dispatch surface instead of 3-4 ops.
  local op = C.pick_weighted(OPS, R, round)
  safe(op.fn)

  -- Traps (high-cost but rare). One trap per ~6 rounds.
  if R.chance(1, 6) then
    local trap = C.pick_weighted(ops.TRAPS, R, round * 31)
    safe(trap.fn)
  end

  -- Periodic teardown. Every 5 rounds, redrawstatus; every
  -- 50 rounds, full teardown.
  if round % 5 == 0 then safe(cmd, 'redrawstatus') end
  if round % 50 == 0 then
    C.teardown_floats(api, S.floats)
    C.teardown_bufs(api, S.scratch_bufs)
    C.teardown_autocmds(api, S.auids, S.augroups)
    if not QUIET then
      io.write(string.format('round=%d/%d  wins=%d  bufs=%d  tabs=%d\n',
        round, ROUNDS,
        #api.nvim_list_wins(), #api.nvim_list_bufs(),
        #api.nvim_list_tabpages()))
      io.flush()
    end
  end
end

C.teardown_floats(api, S.floats)
C.teardown_bufs(api, S.scratch_bufs)
C.teardown_autocmds(api, S.auids, S.augroups)
safe(cmd, 'redrawstatus')
print('done seed=' .. tostring(arg and arg[1] or '42'))