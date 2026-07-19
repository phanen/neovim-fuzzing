-- Auto-generated from /tmp/repro-from-crash/id:000014_sig:06_src:000000_time:394726_execs:1311_op:havoc_rep:13.log
-- by bin/from-log.lua.  Reproduces a captured fuzz-crashhunter.lua run.
-- Run with the ASan/UBSan-enabled nvim:
--   VIMRUNTIME=./deps/neovim/runtime \
--   ASAN_OPTIONS="detect_leaks=0:abort_on_error=0" \
--   out/nvim --headless --clean -i NONE -n -l /home/runner/work/neovim-fuzzing/neovim-fuzzing/reports/2026-07-19_115735/repros/id_000014_sig_06_src_000000_time_394726_execs_1311_op_havoc_rep_13/repro.lua

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
do  -- round 3
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzcuvwuxa")
safe(vim.api.nvim_buf_set_extmark, 2, 3, 0, 0, {["sign_text"]="h"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_win_set_buf, 0, 4)
safe(vim.api.nvim_buf_delete, 2, {["unload"]=true,["force"]=true})
safe(vim.api.nvim_buf_set_lines, 2, 0, -1, false, {[1]=""})
safe(vim.cmd, "redrawstatus")
end
do  -- round 4
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 5, false, {["title_pos"]="center",["title"]="abcdefghijklmnopqrstuvwxyz{|}~/0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~CDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~ !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~JKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~_`abcdefghijklmnopqrstuvwxyz{|}~LMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~|}~0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~",["focusable"]=true,["style"]="minimal",["relative"]="cursor",["width"]=159,["height"]=2,["row"]=5,["col"]=-30,["zindex"]=132,["noautocmd"]=false,["bufpos"]={[1]=2,[2]=44,[3]=29}})
safe(vim.api.nvim_buf_delete, 5, {["force"]=true})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "tabnext")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 6, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.cmd, "only")
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_win_close)
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabclose")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 7, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_delete, 1, {["force"]=true})
safe(vim.cmd, "redrawstatus")
end
do  -- round 5
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:7", {})
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, 'redrawstatus')
end
do  -- round 6
safe(vim.cmd, "tablast")
safe(vim.cmd, 'tabnext')
end
do  -- round 7
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:7", {})
end
do  -- round 8
safe(vim.api.nvim_list_tabpages)
if #api.nvim_list_tabpages() > 1 then safe(vim.cmd, 'tabclose') end
end
do  -- round 9
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_set_lines, 4, 0, -1, false, {[1]="aa"})
safe(vim.cmd, "delete")
safe(vim.cmd, "undo")
safe(vim.cmd, "redrawstatus")
end
do  -- round 10
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_create_autocmd, "WinClosed", {["nested"]=true,["callback"]=_stub_cb_winclosed})
safe(vim.api.nvim_win_close, 1002, true)
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, 'redrawstatus')
end
do  -- round 11
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzcbvmbnn")
safe(vim.api.nvim_buf_set_extmark, 2, 4, 0, 0, {["sign_text"]="h"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_win_set_buf, 0, 8)
safe(vim.api.nvim_buf_delete, 2, {["unload"]=true,["force"]=true})
safe(vim.api.nvim_buf_set_lines, 2, 0, -1, false, {[1]=""})
safe(vim.cmd, "redrawstatus")
end
do  -- round 13
end
do  -- round 14
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 9, true, {["focusable"]=false,["style"]="minimal",["relative"]="editor",["width"]=7,["height"]=23,["row"]=14,["col"]=-2,["zindex"]=127,["noautocmd"]=false})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 10, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 11, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "tabnext")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 13, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.cmd, "only")
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_win_close)
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabclose")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 14, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 15, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 16, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_delete, 2, {["force"]=true})
safe(vim.cmd, "redrawstatus")
end
do  -- round 15
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 17, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 18, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, 'redrawstatus')
end
do  -- round 17
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnext")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 20, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 21, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 22, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.cmd, "tabclose")
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 23, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 24, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 25, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.cmd, "redrawstatus")
end
do  -- round 19
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 26, false, {["bufpos"]={[1]=17,[2]=6,[3]=39},["external"]=true,["relative"]="win",["width"]=163,["height"]=44,["row"]=15,["col"]=19,["zindex"]=76,["noautocmd"]=false,["focusable"]=true})
safe(vim.api.nvim_buf_delete, 26, {["force"]=true})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 27, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 28, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 29, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "tabnext")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 31, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 32, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 33, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.cmd, "only")
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 34, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 35, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 36, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_win_close)
safe(vim.api.nvim_list_tabpages)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_delete, 3, {["force"]=true})
safe(vim.cmd, "redrawstatus")
end
do  -- round 20
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 37, false, {["title_pos"]="center",["title"]="<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~56789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~",["focusable"]=false,["border"]="shadow",["relative"]="win",["width"]=63,["height"]=36,["row"]=29,["col"]=-7,["zindex"]=124,["noautocmd"]=false})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 38, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 39, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 40, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "tabnext")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 42, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 43, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 44, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.cmd, "only")
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 45, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 46, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 47, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_win_close, 1037, true)
safe(vim.api.nvim_list_tabpages)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_delete, 4, {["force"]=true})
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, 'redrawstatus')
end
do  -- round 21
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 48, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 49, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 50, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 51, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.cmd, "redrawstatus")
end
do  -- round 22
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzcokqiif")
safe(vim.api.nvim_buf_set_extmark, 34, 10, 0, 0, {["sign_text"]="h"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_win_set_buf, 0, 53)
safe(vim.api.nvim_buf_delete, 34, {["unload"]=true,["force"]=true})
safe(vim.api.nvim_buf_set_lines, 34, 0, -1, false, {[1]=""})
safe(vim.cmd, "redrawstatus")
end
do  -- round 23
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_autocmd, "BufUnload", {["nested"]=true,["callback"]=_stub_cb_bufunload})
safe(vim.api.nvim_buf_delete, 48, {["force"]=true})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 54, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 55, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 56, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 57, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
end

-- Extra replay of last captured round (mimics the rounds the
-- fuzzer never logged because ASAN aborted first).
do  -- extra round 1 (round 23 replayed)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_autocmd, "BufUnload", {["nested"]=true,["callback"]=_stub_cb_bufunload})
safe(vim.api.nvim_buf_delete, 48, {["force"]=true})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 54, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 55, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 56, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 57, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
end
do  -- extra round 2 (round 23 replayed)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_autocmd, "BufUnload", {["nested"]=true,["callback"]=_stub_cb_bufunload})
safe(vim.api.nvim_buf_delete, 48, {["force"]=true})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 54, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 55, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 56, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 57, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
end
do  -- extra round 3 (round 23 replayed)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_autocmd, "BufUnload", {["nested"]=true,["callback"]=_stub_cb_bufunload})
safe(vim.api.nvim_buf_delete, 48, {["force"]=true})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 54, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 55, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 56, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 57, false, {["width"]=10,["height"]=5,["row"]=0,["col"]=0,["relative"]="editor"})
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
-- Source crash: afl-findings/daily-2026-07-19/default/crashes/id:000014,sig:06,src:000000,time:394726,execs:1311,op:havoc,rep:13 (1124 bytes)
-- Run with (from repo root):
--   ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:symbolize=0:allocator_may_return_null=1" \
--   deps/neovim/build-afl/bin/nvim --headless --clean -i NONE -n \
--     -l <this-repro>
-- Expected: rc=134 and an AddressSanitizer report.
