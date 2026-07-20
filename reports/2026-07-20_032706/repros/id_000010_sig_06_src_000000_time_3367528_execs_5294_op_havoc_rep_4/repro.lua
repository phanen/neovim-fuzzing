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
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 2, false, {["height"]=50,["row"]=35,["col"]=47,["zindex"]=159,["focusable"]=false,["relative"]="cursor",["noautocmd"]=false,["width"]=3})
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
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
end
do  -- round 3
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzcqsgcmg")
safe(vim.api.nvim_buf_set_extmark, 2, 3, 7, 67, {["virt_text"]={[1]={[2]="Comment",[1]="FGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~xyz{|}~&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~HIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~uvwxyz{|}~\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~/0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~NOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~ !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~GHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~cdefghijklmnopqrstuvwxyz{|}~&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~\\]^_`abcdefghijklmnopqrstuvwxyz{|}~MNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~yz{|}~,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~ !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~56789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~IJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~BCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"}}})
end
do  -- round 4
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 4, true, {["focusable"]=true,["bufpos"]={[1]=0,[2]=4,[3]=10},["anchor"]="NW",["width"]=197,["height"]=21,["row"]=-45,["col"]=38,["zindex"]=-14,["relative"]="editor",["noautocmd"]=false})
safe(vim.api.nvim_buf_delete, 4, {["force"]=true})
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
safe(vim.api.nvim_buf_delete, 2, {["force"]=true})
safe(vim.cmd, "redrawstatus")
end
do  -- round 5
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 6, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, 'redrawstatus')
end
do  -- round 6
safe(vim.api.nvim_list_bufs)
end
do  -- round 7
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzcnqdhrq")
safe(vim.api.nvim_buf_set_extmark, 3, 4, 0, 0, {["sign_text"]="h"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_win_set_buf, 0, 8)
safe(vim.api.nvim_buf_delete, 3, {["force"]=true,["unload"]=true})
safe(vim.api.nvim_buf_set_lines, 3, 0, -1, false, {[1]=""})
safe(vim.cmd, "redrawstatus")
end
do  -- round 9
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_create_autocmd, "WinClosed", {["nested"]=true,["callback"]=_stub_cb_winclosed})
safe(vim.api.nvim_win_close, 1004, true)
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 9, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.cmd, "redrawstatus")
end
do  -- round 10
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 10, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 11, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, 'redrawstatus')
end
do  -- round 11
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_buf_set_name, 13, "/tmp/fzc_fgfyhrsw.txt")
safe(vim.api.nvim_paste, "\0\2\3\6\21\22\23\24\27\127", true, 0)
end
do  -- round 12
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 14, false, {["focusable"]=false,["style"]="minimal",["anchor"]="NW",["width"]=99,["height"]=45,["row"]=-19,["col"]=26,["zindex"]=135,["relative"]="win",["noautocmd"]=false})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "only")
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 15, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 16, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
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
do  -- round 13
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 17, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 18, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 19, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.cmd, "redrawstatus")
end
do  -- round 14
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnext")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 21, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 22, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 23, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 24, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.cmd, "tabclose")
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 25, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 26, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 27, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 28, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.cmd, "redrawstatus")
end
do  -- round 15
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 29, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 30, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 31, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 32, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 33, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, 'redrawstatus')
end
do  -- round 16
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_autocmd, "BufUnload", {["nested"]=true,["callback"]=_stub_cb_bufunload})
safe(vim.api.nvim_buf_delete, 15, {["force"]=true})
safe(vim.api.nvim_buf_delete, 9, {["force"]=true})
safe(vim.api.nvim_buf_delete, 9, {["force"]=true})
safe(vim.cmd, "redrawstatus")
end
do  -- round 18
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnext")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 35, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 36, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 37, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 38, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 39, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 40, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.cmd, "tabclose")
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 41, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 42, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 43, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 44, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 45, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 46, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.cmd, "redrawstatus")
end
do  -- round 19
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 47, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 48, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 49, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 50, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 51, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 52, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 53, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.cmd, "redrawstatus")
end
do  -- round 20
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzcjdnmcd")
safe(vim.api.nvim_buf_set_extmark, 48, 6, 0, 0, {["sign_text"]="h"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_win_set_buf, 0, 55)
safe(vim.api.nvim_buf_delete, 48, {["force"]=true,["unload"]=true})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 56, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 57, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 58, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 59, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 60, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 61, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 62, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
end

do  -- extra round 1 (round 20 replayed)
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzcjdnmcd")
safe(vim.api.nvim_buf_set_extmark, 48, 6, 0, 0, {["sign_text"]="h"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_win_set_buf, 0, 55)
safe(vim.api.nvim_buf_delete, 48, {["force"]=true,["unload"]=true})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 56, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 57, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 58, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 59, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 60, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 61, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 62, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
end
do  -- extra round 2 (round 20 replayed)
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzcjdnmcd")
safe(vim.api.nvim_buf_set_extmark, 48, 6, 0, 0, {["sign_text"]="h"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_win_set_buf, 0, 55)
safe(vim.api.nvim_buf_delete, 48, {["force"]=true,["unload"]=true})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 56, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 57, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 58, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 59, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 60, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 61, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 62, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
end
do  -- extra round 3 (round 20 replayed)
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_create_namespace, "fzcjdnmcd")
safe(vim.api.nvim_buf_set_extmark, 48, 6, 0, 0, {["sign_text"]="h"})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_win_set_buf, 0, 55)
safe(vim.api.nvim_buf_delete, 48, {["force"]=true,["unload"]=true})
safe(vim.api.nvim_win_close, 0, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 56, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 57, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 58, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 59, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 60, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 61, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 62, false, {["height"]=5,["row"]=0,["col"]=0,["relative"]="editor",["width"]=10})
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
-- Source crash: afl-findings/daily-2026-07-20/default/crashes/id:000010,sig:06,src:000000,time:3367528,execs:5294,op:havoc,rep:4 (1001 bytes)
-- Run with (from repo root):
--   ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:symbolize=0:allocator_may_return_null=1" \
--   deps/neovim/build-afl/bin/nvim --headless --clean -i NONE -n \
--     -l <this-repro>
-- Expected: rc=134 and an AddressSanitizer report.
