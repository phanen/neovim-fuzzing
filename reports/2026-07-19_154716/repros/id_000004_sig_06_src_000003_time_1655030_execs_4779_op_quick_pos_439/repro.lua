-- Auto-generated from /tmp/repro-from-crash/id:000004_sig:06_src:000003_time:1655030_execs:4779_op:quick_pos:439.log
-- by bin/from-log.lua.  Reproduces a captured fuzz-crashhunter.lua run.
-- Run with the ASan/UBSan-enabled nvim:
--   VIMRUNTIME=./deps/neovim/runtime \
--   ASAN_OPTIONS="detect_leaks=0:abort_on_error=0" \
--   out/nvim --headless --clean -i NONE -n -l /home/runner/work/neovim-fuzzing/neovim-fuzzing/reports/2026-07-19_154716/repros/id_000004_sig_06_src_000003_time_1655030_execs_4779_op_quick_pos_439/repro.lua

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
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 2, false, {["height"]=43,["row"]=29,["col"]=-13,["bufpos"]={[1]=0,[2]=17,[3]=41},["noautocmd"]=false,["zindex"]=61,["border"]="rounded",["relative"]="editor",["focusable"]=true,["width"]=179})
safe(vim.api.nvim_buf_delete, 2, {["force"]=true})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "tabnext")
safe(vim.cmd, "only")
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_win_close)
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabclose")
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_delete, 1, {["force"]=true})
safe(vim.cmd, "redrawstatus")
end
do  -- round 2
safe(vim.api.nvim_list_bufs)
end
do  -- round 3
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 4, false, {["height"]=12,["row"]=7,["col"]=-14,["zindex"]=137,["anchor"]="NW",["noautocmd"]=false,["relative"]="editor",["focusable"]=true,["width"]=118})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "tabnext")
safe(vim.cmd, "only")
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_win_close, 1001, true)
safe(vim.api.nvim_list_tabpages)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_delete, 3, {["force"]=true})
safe(vim.cmd, "redrawstatus")
end
do  -- round 4
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
end
do  -- round 5
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 6, false, {["height"]=39,["row"]=7,["col"]=-32,["zindex"]=102,["noautocmd"]=false,["relative"]="win",["focusable"]=false,["width"]=70})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "tabnext")
safe(vim.cmd, "only")
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_win_close)
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabclose")
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_delete, 4, {["force"]=true})
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, 'redrawstatus')
end
do  -- round 6
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 8, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.cmd, "redrawstatus")
end
do  -- round 7
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 10, false, {["height"]=33,["row"]=23,["col"]=-42,["zindex"]=101,["anchor"]="SE",["noautocmd"]=true,["relative"]="editor",["focusable"]=false,["width"]=137})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "tabnext")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 11, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.cmd, "only")
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_win_close)
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabclose")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 12, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_delete, 5, {["force"]=true})
safe(vim.cmd, "redrawstatus")
end
do  -- round 8
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 17, false, {["height"]=15,["row"]=-43,["col"]=24,["zindex"]=133,["title"]="_`abcdefghijklmnopqrstuvwxyz{|}~3456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~",["title_pos"]="right",["noautocmd"]=false,["relative"]="win",["focusable"]=true,["width"]=199})
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 18, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.cmd, "only")
safe(vim.api.nvim_buf_delete, 13, {["force"]=true})
safe(vim.api.nvim_buf_delete, 14, {["force"]=true})
safe(vim.api.nvim_buf_delete, 15, {["force"]=true})
safe(vim.api.nvim_buf_delete, 16, {["force"]=true})
safe(vim.cmd, "bdelete")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 20, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.cmd, "redrawstatus")
end
do  -- round 9
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 21, false, {["height"]=13,["row"]=-31,["col"]=30,["zindex"]=114,["noautocmd"]=false,["relative"]="cursor",["focusable"]=false,["width"]=60})
open_float({}, false)
end
do  -- round 10
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 22, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 23, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, 'redrawstatus')
end
do  -- round 11
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 25, false, {["height"]=22,["row"]=-49,["col"]=1,["zindex"]=110,["anchor"]="NE",["title"]="=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~FGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~cdefghijklmnopqrstuvwxyz{|}~6789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~NOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~",["title_pos"]="center",["noautocmd"]=false,["relative"]="win",["focusable"]=false,["width"]=192})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "tabnext")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 26, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 27, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.cmd, "only")
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_win_close, 1007, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 28, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 29, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_list_tabpages)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_delete, 6, {["force"]=true})
safe(vim.cmd, "redrawstatus")
end
do  -- round 12
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzchtsbtz")
safe(vim.api.nvim_buf_set_extmark, 7, 3, 0, 0, {["sign_text"]="h"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_win_set_buf, 0, 30)
safe(vim.api.nvim_buf_delete, 7, {["unload"]=true,["force"]=true})
safe(vim.api.nvim_buf_set_lines, 7, 0, -1, false, {[1]=""})
safe(vim.cmd, "redrawstatus")
end
do  -- round 14
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_create_autocmd, "WinClosed", {["nested"]=true,["callback"]=_stub_cb_winclosed})
safe(vim.api.nvim_win_close, 1018, true)
safe(vim.cmd, "redrawstatus")
end
do  -- round 15
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 31, false, {["height"]=17,["row"]=-23,["col"]=45,["zindex"]=100,["anchor"]="NE",["noautocmd"]=false,["border"]="rounded",["relative"]="win",["focusable"]=false,["width"]=110})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 32, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 33, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "tabnext")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 35, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 36, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.cmd, "only")
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 37, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 38, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_win_close, 1028, true)
safe(vim.api.nvim_list_tabpages)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_delete, 7, {["force"]=true})
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, 'redrawstatus')
end
do  -- round 16
end
do  -- round 17
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzckkpbuo")
safe(vim.api.nvim_buf_set_extmark, 19, 4, 17, 7225, {["virt_text"]={[1]={[2]="Comment",[1]="RSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~EFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~efghijklmnopqrstuvwxyz{|}~VWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~yz{|}~*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~OPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~NOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~}~LMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~abcdefghijklmnopqrstuvwxyz{|}~klmnopqrstuvwxyz{|}~JKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~23456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~uvwxyz{|}~,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"}}})
safe(vim.api.nvim_paste, "\0\2\3\6\21\22\23\24\27\127NOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~HIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~89:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~", false, 3)
end
do  -- round 18
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 39, false, {["height"]=18,["row"]=47,["col"]=-15,["bufpos"]={[1]=33,[2]=8,[3]=45},["noautocmd"]=false,["zindex"]=367,["relative"]="cursor",["focusable"]=true,["width"]=179})
safe(vim.api.nvim_buf_delete, 39, {["force"]=true})
open_float({}, false)
end
do  -- round 19
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_delete, 11, {["unload"]=false,["force"]=true})
end
do  -- round 20
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 40, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 41, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 42, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, 'redrawstatus')
end
do  -- round 21
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzcyilscm")
safe(vim.api.nvim_buf_set_extmark, 34, 5, 0, 0, {["sign_text"]="h"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_win_set_buf, 0, 44)
safe(vim.api.nvim_buf_delete, 34, {["unload"]=true,["force"]=true})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 45, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 46, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 47, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
end

-- Extra replay of last captured round (mimics the rounds the
-- fuzzer never logged because ASAN aborted first).
do  -- extra round 1 (round 21 replayed)
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzcyilscm")
safe(vim.api.nvim_buf_set_extmark, 34, 5, 0, 0, {["sign_text"]="h"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_win_set_buf, 0, 44)
safe(vim.api.nvim_buf_delete, 34, {["unload"]=true,["force"]=true})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 45, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 46, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 47, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
end
do  -- extra round 2 (round 21 replayed)
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzcyilscm")
safe(vim.api.nvim_buf_set_extmark, 34, 5, 0, 0, {["sign_text"]="h"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_win_set_buf, 0, 44)
safe(vim.api.nvim_buf_delete, 34, {["unload"]=true,["force"]=true})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 45, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 46, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 47, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
end
do  -- extra round 3 (round 21 replayed)
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzcyilscm")
safe(vim.api.nvim_buf_set_extmark, 34, 5, 0, 0, {["sign_text"]="h"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_win_set_buf, 0, 44)
safe(vim.api.nvim_buf_delete, 34, {["unload"]=true,["force"]=true})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 45, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 46, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 47, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
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
-- Source crash: afl-findings/daily-2026-07-19/default/crashes/id:000004,sig:06,src:000003,time:1655030,execs:4779,op:quick,pos:439 (1024 bytes)
-- Run with (from repo root):
--   ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:symbolize=0:allocator_may_return_null=1" \
--   deps/neovim/build-afl/bin/nvim --headless --clean -i NONE -n \
--     -l <this-repro>
-- Expected: rc=134 and an AddressSanitizer report.
