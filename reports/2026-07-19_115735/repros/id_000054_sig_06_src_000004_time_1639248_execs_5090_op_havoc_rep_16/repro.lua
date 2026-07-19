-- Auto-generated from /tmp/repro-from-crash/id:000054_sig:06_src:000004_time:1639248_execs:5090_op:havoc_rep:16.log
-- by bin/from-log.lua.  Reproduces a captured fuzz-crashhunter.lua run.
-- Run with the ASan/UBSan-enabled nvim:
--   VIMRUNTIME=./deps/neovim/runtime \
--   ASAN_OPTIONS="detect_leaks=0:abort_on_error=0" \
--   out/nvim --headless --clean -i NONE -n -l /home/runner/work/neovim-fuzzing/neovim-fuzzing/reports/2026-07-19_115735/repros/id_000054_sig_06_src_000004_time_1639248_execs_5090_op_havoc_rep_16/repro.lua

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
safe(vim.api.nvim_open_win, 2, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.cmd, "redrawstatus")
end
do  -- round 2
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnext")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 4, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 5, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.cmd, "tabclose")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 6, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 7, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
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
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 8, false, {["width"]=152,["height"]=40,["row"]=10,["col"]=3,["zindex"]=160,["bufpos"]={[1]=2,[2]=11,[3]=7},["noautocmd"]=true,["focusable"]=true,["relative"]="win"})
safe(vim.api.nvim_buf_delete, 8, {["force"]=true})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 9, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 10, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "tabnext")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 12, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 13, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.cmd, "only")
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 14, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 15, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_win_close, 1011, true)
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_list_tabpages)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_delete, 1, {["force"]=true})
safe(vim.cmd, "redrawstatus")
end
do  -- round 5
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 16, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 17, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 18, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, 'redrawstatus')
end
do  -- round 6
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzcqqgfjl")
safe(vim.api.nvim_buf_set_extmark, 2, 3, 0, 0, {["sign_text"]="h"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_win_set_buf, 0, 20)
safe(vim.api.nvim_buf_delete, 2, {["force"]=true,["unload"]=true})
safe(vim.api.nvim_buf_set_lines, 2, 0, -1, false, {[1]=""})
safe(vim.cmd, "redrawstatus")
end
do  -- round 7
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnext")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 21, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 22, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 23, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 24, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.cmd, "tabclose")
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 25, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 26, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 27, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 28, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.cmd, "redrawstatus")
end
do  -- round 8
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 29, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 30, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 31, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 32, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 33, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.cmd, "redrawstatus")
end
do  -- round 9
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzcknzorn")
safe(vim.api.nvim_buf_set_extmark, 18, 4, 0, 0, {["sign_text"]="h"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_win_set_buf, 0, 35)
safe(vim.api.nvim_buf_delete, 18, {["force"]=true,["unload"]=true})
safe(vim.api.nvim_buf_set_lines, 18, 0, -1, false, {[1]=""})
safe(vim.cmd, "redrawstatus")
end
do  -- round 10
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, 'redrawstatus')
end
do  -- round 11
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_create_autocmd, "WinClosed", {["nested"]=true,["callback"]=_stub_cb_winclosed})
safe(vim.api.nvim_win_close, 1031, true)
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 36, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 37, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 38, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 39, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 40, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.cmd, "redrawstatus")
end
do  -- round 12
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 41, false, {["width"]=152,["height"]=40,["row"]=10,["col"]=3,["zindex"]=160,["bufpos"]={[1]=12,[2]=11,[3]=7},["noautocmd"]=true,["focusable"]=true,["relative"]="win"})
safe(vim.api.nvim_buf_delete, 41, {["force"]=true})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 42, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 43, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 44, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 45, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 46, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "tabnext")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 48, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 49, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 50, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 51, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 52, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.cmd, "only")
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 53, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 54, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 55, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 56, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 57, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_win_close, 1045, true)
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_list_tabpages)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_delete, 2, {["force"]=true})
safe(vim.cmd, "redrawstatus")
end
do  -- round 13
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 58, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 59, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 60, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 61, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 62, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 63, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.cmd, "redrawstatus")
end
do  -- round 14
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzcqqgfjl")
safe(vim.api.nvim_buf_set_extmark, 60, 3, 0, 0, {["sign_text"]="h"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_win_set_buf, 0, 65)
safe(vim.api.nvim_buf_delete, 60, {["force"]=true,["unload"]=true})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 66, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 67, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 68, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 69, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 70, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 71, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_win_close, 0, true)
end

-- Extra replay of last captured round (mimics the rounds the
-- fuzzer never logged because ASAN aborted first).
do  -- extra round 1 (round 14 replayed)
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzcqqgfjl")
safe(vim.api.nvim_buf_set_extmark, 60, 3, 0, 0, {["sign_text"]="h"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_win_set_buf, 0, 65)
safe(vim.api.nvim_buf_delete, 60, {["force"]=true,["unload"]=true})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 66, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 67, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 68, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 69, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 70, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 71, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_win_close, 0, true)
end
do  -- extra round 2 (round 14 replayed)
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzcqqgfjl")
safe(vim.api.nvim_buf_set_extmark, 60, 3, 0, 0, {["sign_text"]="h"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_win_set_buf, 0, 65)
safe(vim.api.nvim_buf_delete, 60, {["force"]=true,["unload"]=true})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 66, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 67, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 68, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 69, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 70, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 71, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_win_close, 0, true)
end
do  -- extra round 3 (round 14 replayed)
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzcqqgfjl")
safe(vim.api.nvim_buf_set_extmark, 60, 3, 0, 0, {["sign_text"]="h"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_win_set_buf, 0, 65)
safe(vim.api.nvim_buf_delete, 60, {["force"]=true,["unload"]=true})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 66, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 67, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 68, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 69, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 70, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 71, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_win_close, 0, true)
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
-- Source crash: afl-findings/daily-2026-07-19/default/crashes/id:000054,sig:06,src:000004,time:1639248,execs:5090,op:havoc,rep:16 (67 bytes)
-- Run with (from repo root):
--   ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:symbolize=0:allocator_may_return_null=1" \
--   deps/neovim/build-afl/bin/nvim --headless --clean -i NONE -n \
--     -l <this-repro>
-- Expected: rc=134 and an AddressSanitizer report.
