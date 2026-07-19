-- Auto-generated from /tmp/repro-from-crash/id:000038_sig:06_src:000000_time:1078970_execs:3248_op:havoc_rep:11.log
-- by bin/from-log.lua.  Reproduces a captured fuzz-crashhunter.lua run.
-- Run with the ASan/UBSan-enabled nvim:
--   VIMRUNTIME=./deps/neovim/runtime \
--   ASAN_OPTIONS="detect_leaks=0:abort_on_error=0" \
--   out/nvim --headless --clean -i NONE -n -l /home/runner/work/neovim-fuzzing/neovim-fuzzing/reports/2026-07-19_115735/repros/id_000038_sig_06_src_000000_time_1078970_execs_3248_op_havoc_rep_11/repro.lua

vim.o.swapfile = false
vim.o.shadafile = "NONE"
local api = vim.api
local function safe(fn, ...) return pcall(fn, ...) end

-- Stub callbacks for captured autocmd registrations. The fuzzer
-- scenarios wire real closures to WinLeave / WinClosed /
-- BufUnload that open floats, close windows, or delete buffers
-- during autocmd dispatch, which is the reentrancy path the
-- bug lives on. The ser_arg sentinel `function` placeholder in
-- cap.log has no callable body, so without these stubs the
-- WinClosed handler is a no-op and the bug-triggering code
-- path (close_windows -> do_buffer_ext UAF) is never reached.
local _stub_cb_winleave = function()
  -- mirrors scenario_winleave_open_float body: open a scratch float
  local _b = api.nvim_create_buf(false, true)
  pcall(api.nvim_open_win, _b, false, {
    relative = "editor", row = 0, col = 0, width = 10, height = 5,
  })
end
local _stub_cb_winclosed = function(args)
  -- mirrors scenario_winclosed_reentrant_close body: close current win.
  pcall(api.nvim_win_close, 0, true)
  -- also drop a scratch buf if any remain, mirroring
  -- scenario_winclosed_reentrant_buf_delete body (the dispatcher
  -- has no way to know which WinClosed scenario this callback
  -- came from since ser_arg records only the event name).
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_valid(b) and not api.nvim_buf_is_loaded(b) then
      pcall(api.nvim_buf_delete, b, { force = true, unload = true })
      break
    end
  end
end
local _stub_cb_winclosed_buf = function(args)
  -- mirrors scenario_winclosed_reentrant_buf_delete specifically
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_valid(b) and not api.nvim_buf_is_loaded(b) then
      pcall(api.nvim_buf_delete, b, { force = true, unload = true })
      break
    end
  end
end
local _stub_cb_bufunload = function(args)
  -- mirrors scenario_bufunload_reentrant_bufdelete
  local _bs = api.nvim_list_bufs()
  if #_bs >= 2 then
    pcall(api.nvim_buf_delete, _bs[#_bs], { force = true })
  end
end
local _stub_cb_on_lines = function()
  -- mirrors scenario_on_lines_closes_win
  pcall(api.nvim_win_close, 0, true)
end

local floats = {}

local function open_float(cfg, enter)
  local _buf = api.nvim_create_buf(false, true)
  local ok, win = pcall(api.nvim_open_win, _buf, enter, cfg)
  if ok and type(win) == "number" then floats[#floats + 1] = win end
end


-- Per-round cleanup. Keeps current tab, discards the rest.
local function teardown_round()
  -- Close every non-current tab (and its windows).
  local curtab = api.nvim_get_current_tabpage()
  for _, t in ipairs(api.nvim_list_tabpages()) do
    if t ~= curtab then
      for _, w in ipairs(api.nvim_tabpage_list_wins(t)) do
        pcall(api.nvim_win_close, w, true)
      end
      pcall(api.nvim_tabpage_close, t, true)
    end
  end
  -- Close floats tracked by open_float() in reverse creation order.
  for i = #floats, 1, -1 do
    pcall(api.nvim_win_close, floats[i], true)
    floats[i] = nil
  end
  -- Delete scratch bufs (skip loaded ones; those need :bd, not :bw).
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_valid(b) and not api.nvim_buf_is_loaded(b) then
      pcall(api.nvim_buf_delete, b, { force = true })
    end
  end
end


-- Per-round replay blocks. Source fuzzer only calls
-- teardown_floats/bufs/autocmds at round%50 (NEVER every round),
-- so we mirror that: no teardown between rounds; the crash
-- depends on state accumulated across all 21 captured rounds.
do  -- round 1
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 2, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.cmd, "redrawstatus")
end
do  -- round 2
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnext")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 4, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 5, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.cmd, "tabclose")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 6, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 7, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.cmd, "redrawstatus")
end
do  -- round 3
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_create_autocmd, "WinClosed", {["nested"]=true,["callback"]=_stub_cb_winclosed})
safe(vim.api.nvim_win_close, 1002, true)
safe(vim.cmd, "redrawstatus")
end
do  -- round 4
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_open_term, 3, {})
safe(vim.api.nvim_chan_send, 3, "\9\8\25\1\18\29\30\16\25\14\1\6\9\3\15\18\17\9\20\26\13\9\20\12\16\28\29\29\18\11\22\1\31\18\30\7\13\25\6\15\31\17\31\22\14\7\11\14\15\18\23\18\14\20\13\21\24\22\26\26\8\23")
end
do  -- round 5
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 8, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 9, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.cmd, 'tabnew')
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, 'redrawstatus')
end
do  -- round 6
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 11, false, {["row"]=-49,["col"]=-2,["zindex"]=181,["noautocmd"]=true,["relative"]="win",["focusable"]=true,["width"]=156,["height"]=22})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "only")
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 12, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 13, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.cmd, "only")
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_win_close, 0, true)
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "tabnext")
safe(vim.cmd, "only")
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_list_tabpages)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_delete, 1, {["force"]=true})
safe(vim.cmd, "redrawstatus")
end
do  -- round 7
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 14, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 15, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 16, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.cmd, "redrawstatus")
end
do  -- round 8
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnext")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 18, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 19, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 20, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 21, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.cmd, "tabclose")
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 22, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 23, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 24, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 25, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.cmd, "redrawstatus")
end
do  -- round 9
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 26, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 27, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 28, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 29, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 30, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.cmd, "redrawstatus")
end
do  -- round 10
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzcjvovcm")
safe(vim.api.nvim_buf_set_extmark, 17, 15, 0, 0, {["sign_text"]="h"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_win_set_buf, 0, 32)
safe(vim.api.nvim_buf_delete, 17, {["force"]=true,["unload"]=true})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 33, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 34, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 35, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 36, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 37, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
end

-- Extra replay of last captured round (mimics the rounds the
-- fuzzer never logged because ASAN aborted first).
do  -- extra round 1 (round 10 replayed)
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzcjvovcm")
safe(vim.api.nvim_buf_set_extmark, 17, 15, 0, 0, {["sign_text"]="h"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_win_set_buf, 0, 32)
safe(vim.api.nvim_buf_delete, 17, {["force"]=true,["unload"]=true})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 33, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 34, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 35, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 36, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 37, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
end
do  -- extra round 2 (round 10 replayed)
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzcjvovcm")
safe(vim.api.nvim_buf_set_extmark, 17, 15, 0, 0, {["sign_text"]="h"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_win_set_buf, 0, 32)
safe(vim.api.nvim_buf_delete, 17, {["force"]=true,["unload"]=true})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 33, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 34, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 35, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 36, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 37, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
end
do  -- extra round 3 (round 10 replayed)
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzcjvovcm")
safe(vim.api.nvim_buf_set_extmark, 17, 15, 0, 0, {["sign_text"]="h"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_win_set_buf, 0, 32)
safe(vim.api.nvim_buf_delete, 17, {["force"]=true,["unload"]=true})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 33, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 34, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 35, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 36, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 37, false, {["row"]=0,["col"]=0,["relative"]="editor",["width"]=10,["height"]=5})
end

-- Final teardown (mirrors teardown_floats/bufs/autocmds + redrawstatus
-- at end of fuzz-crashhunter.lua main loop). The bug-trigger path lives in
-- close_windows / do_buffer_ext; the captured ops stop short of
-- the actual crashing op because ASAN aborts before round 22 is
-- captured. We delete every scratch buf first (which calls
-- close_windows on each one) then close remaining windows.
-- Delete every unloaded scratch buf FIRST. This is what calls
-- close_windows on each buf -> UAF on re-entry when WinClosed
-- handler is wired. After bufs are deleted (and UAF detected)
-- close the remaining float windows.
for _, b in ipairs(api.nvim_list_bufs()) do
  if api.nvim_buf_is_valid(b) and not api.nvim_buf_is_loaded(b) then
    pcall(api.nvim_buf_delete, b, { force = true, unload = true })
  end
end
for _, w in ipairs(api.nvim_list_wins()) do
  pcall(api.nvim_win_close, w, true)
end
safe(vim.cmd, "redrawstatus")
os.exit(0)
-- 
-- Source crash: afl-findings/daily-2026-07-19/default/crashes/id:000038,sig:06,src:000000,time:1078970,execs:3248,op:havoc,rep:11 (1042 bytes)
-- Run with (from repo root):
--   ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:symbolize=0:allocator_may_return_null=1" \
--   deps/neovim/build-afl/bin/nvim --headless --clean -i NONE -n \
--     -l <this-repro>
-- Expected: rc=134 and an AddressSanitizer report.
