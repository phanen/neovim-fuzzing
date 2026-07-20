vim.o.swapfile = false
vim.o.shadafile = "NONE"
local api = vim.api
local function safe(fn, ...) return pcall(fn, ...) end

local _stub_cb_winleave = function()
  local _b = api.nvim_create_buf(false, true)
  pcall(api.nvim_open_win, _b, false, {
    relative = "editor", row = 0, col = 0, width = 10, height = 5,
  })
end
local _stub_cb_winclosed = function(args)
  pcall(api.nvim_win_close, 0, true)
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_valid(b) and not api.nvim_buf_is_loaded(b) then
      pcall(api.nvim_buf_delete, b, { force = true, unload = true })
      break
    end
  end
end
local _stub_cb_winclosed_buf = function(args)
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_valid(b) and not api.nvim_buf_is_loaded(b) then
      pcall(api.nvim_buf_delete, b, { force = true, unload = true })
      break
    end
  end
end
local _stub_cb_bufunload = function(args)
  local _bs = api.nvim_list_bufs()
  if #_bs >= 2 then
    pcall(api.nvim_buf_delete, _bs[#_bs], { force = true })
  end
end
local _stub_cb_on_lines = function()
  pcall(api.nvim_win_close, 0, true)
end

local floats = {}

local function open_float(cfg, enter)
  local _buf = api.nvim_create_buf(false, true)
  local ok, win = pcall(api.nvim_open_win, _buf, enter, cfg)
  if ok and type(win) == "number" then floats[#floats + 1] = win end
end


local function teardown_round()
  local curtab = api.nvim_get_current_tabpage()
  for _, t in ipairs(api.nvim_list_tabpages()) do
    if t ~= curtab then
      for _, w in ipairs(api.nvim_tabpage_list_wins(t)) do
        pcall(api.nvim_win_close, w, true)
      end
      pcall(api.nvim_tabpage_close, t, true)
    end
  end
  for i = #floats, 1, -1 do
    pcall(api.nvim_win_close, floats[i], true)
    floats[i] = nil
  end
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_valid(b) and not api.nvim_buf_is_loaded(b) then
      pcall(api.nvim_buf_delete, b, { force = true })
    end
  end
end


do  -- round 1
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 2, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.cmd, "redrawstatus")
end
do  -- round 2
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzcpxoqcf")
safe(vim.api.nvim_buf_set_extmark, 2, 3, 0, 0, {["sign_text"]="h"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_win_set_buf, 0, 4)
safe(vim.api.nvim_buf_delete, 2, {["unload"]=true,["force"]=true})
safe(vim.api.nvim_buf_set_lines, 2, 0, -1, false, {[1]=""})
safe(vim.cmd, "redrawstatus")
end
do  -- round 3
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzctrjqzz")
safe(vim.api.nvim_buf_set_extmark, 1, 4, 0, 0, {["sign_text"]="h"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_win_set_buf, 0, 5)
safe(vim.api.nvim_buf_delete, 1, {["unload"]=true,["force"]=true})
safe(vim.api.nvim_buf_set_lines, 1, 0, -1, false, {[1]=""})
safe(vim.cmd, "redrawstatus")
end
do  -- round 4
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 6, false, {["noautocmd"]=false,["relative"]="cursor",["focusable"]=true,["width"]=82,["height"]=3,["row"]=-30,["col"]=-45,["zindex"]=140})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 7, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "tabnext")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 9, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.cmd, "only")
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_win_close, 1006, true)
safe(vim.api.nvim_list_tabpages)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_delete, 1, {["force"]=true})
safe(vim.cmd, "redrawstatus")
end
do  -- round 5
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, 'redrawstatus')
end
do  -- round 6
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_set_lines, 2, 0, -1, false, {[1]="aa"})
safe(vim.cmd, "delete")
safe(vim.cmd, "undo")
safe(vim.cmd, "redrawstatus")
end
do  -- round 7
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 10, false, {["noautocmd"]=false,["relative"]="win",["width"]=131,["height"]=3,["row"]=-8,["col"]=49,["zindex"]=76,["external"]=true,["hide"]=true,["focusable"]=false})
safe(vim.api.nvim_buf_delete, 10, {["force"]=true})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 11, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "only")
safe(vim.cmd, "tabnext")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 13, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.cmd, "only")
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_win_close, 1002, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 14, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_list_tabpages)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_delete, 2, {["force"]=true})
safe(vim.cmd, "redrawstatus")
end
do  -- round 8
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
end
do  -- round 9
safe(vim.api.nvim_paste, "\0\2\3\6\21\22\23\24\27\127`abcdefghijklmnopqrstuvwxyz{|}~0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~KLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~TUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~", true, 1)
end
do  -- round 10
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_set_lines, 6, 0, -1, false, {[1]="aa"})
safe(vim.cmd, "delete")
safe(vim.cmd, "undo")
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, 'redrawstatus')
end
do  -- round 11
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzcnqdhrq")
safe(vim.api.nvim_buf_set_extmark, 8, 5, 0, 0, {["sign_text"]="h"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_win_set_buf, 0, 15)
safe(vim.api.nvim_buf_delete, 8, {["unload"]=true,["force"]=true})
safe(vim.api.nvim_buf_set_lines, 8, 0, -1, false, {[1]=""})
safe(vim.cmd, "redrawstatus")
end
do  -- round 13
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_create_autocmd, "WinClosed", {["nested"]=true,["callback"]=_stub_cb_winclosed})
safe(vim.api.nvim_win_close, 1009, true)
safe(vim.cmd, "redrawstatus")
end
do  -- round 14
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 16, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 17, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.cmd, "redrawstatus")
end
do  -- round 15
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_buf_set_name, 19, "/tmp/fzc_fgfyhrsw.txt")
safe(vim.api.nvim_paste, "\0\2\3\6\21\22\23\24\27\127", true, 0)
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, 'redrawstatus')
end
do  -- round 16
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 20, false, {["noautocmd"]=false,["relative"]="win",["width"]=99,["height"]=45,["row"]=-19,["col"]=26,["zindex"]=135,["anchor"]="NW",["focusable"]=false,["style"]="minimal"})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "only")
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 21, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 22, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.cmd, "only")
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
safe(vim.api.nvim_buf_delete, 3, {["force"]=true})
safe(vim.cmd, "redrawstatus")
end
do  -- round 17
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 23, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 24, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 25, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.cmd, "redrawstatus")
end
do  -- round 18
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnext")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 27, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 28, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 29, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 30, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.cmd, "tabclose")
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 31, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 32, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 33, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 34, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.cmd, "redrawstatus")
end
do  -- round 19
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 35, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 36, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 37, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 38, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 39, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.cmd, "redrawstatus")
end
do  -- round 20
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_autocmd, "BufUnload", {["nested"]=true,["callback"]=_stub_cb_bufunload})
safe(vim.api.nvim_buf_delete, 39, {["force"]=true})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 41, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 42, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 43, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 44, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 45, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
end

do  -- extra round 1 (round 20 replayed)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_autocmd, "BufUnload", {["nested"]=true,["callback"]=_stub_cb_bufunload})
safe(vim.api.nvim_buf_delete, 39, {["force"]=true})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 41, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 42, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 43, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 44, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 45, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
end
do  -- extra round 2 (round 20 replayed)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_autocmd, "BufUnload", {["nested"]=true,["callback"]=_stub_cb_bufunload})
safe(vim.api.nvim_buf_delete, 39, {["force"]=true})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 41, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 42, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 43, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 44, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 45, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
end
do  -- extra round 3 (round 20 replayed)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_autocmd, "BufUnload", {["nested"]=true,["callback"]=_stub_cb_bufunload})
safe(vim.api.nvim_buf_delete, 39, {["force"]=true})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 41, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 42, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 43, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 44, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 45, false, {["relative"]="editor",["width"]=10,["height"]=5,["row"]=0,["col"]=0})
end

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
-- Source crash: afl-findings/daily-2026-07-20/default/crashes/id:000004,sig:06,src:000000,time:1916013,execs:3138,op:havoc,rep:3 (1046 bytes)
-- Run with (from repo root):
--   ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:symbolize=0:allocator_may_return_null=1" \
--   deps/neovim/build-afl/bin/nvim --headless --clean -i NONE -n \
--     -l <this-repro>
-- Expected: rc=134 and an AddressSanitizer report.
