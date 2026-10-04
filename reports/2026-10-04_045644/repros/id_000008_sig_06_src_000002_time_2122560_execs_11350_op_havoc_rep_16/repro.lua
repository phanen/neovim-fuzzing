vim.o.swapfile = false
vim.o.shadafile = "NONE"
local api = vim.api
local function safe(fn, ...) return pcall(fn, ...) end

local function make_varied_stub(variants)
  local counter = 0
  local stub
  stub = function(...)
    counter = counter + 1
    local idx = ((counter * 31) % #variants) + 1
    local v = variants[idx]
    if v then v(stub, counter, ...) end
  end
  return stub
end

local _stub_cb_winleave
local _stub_cb_winclosed
local _stub_cb_winclosed_buf
local _stub_cb_bufunload
local _stub_cb_on_lines
local _stub_cb_winleave = make_varied_stub({
  function(_self, n)
    local b = api.nvim_create_buf(false, true)
    pcall(api.nvim_open_win, b, false, {
      relative = "editor", row = (n % 5), col = (n % 7),
      width = ((n % 10) + 5), height = ((n % 4) + 3),
    })
  end,
  function()
    pcall(api.nvim_win_close, 0, true)
  end,
  function()
    local bs = api.nvim_list_bufs()
    if #bs > 1 then pcall(api.nvim_buf_delete, bs[#bs], { force = true }) end
  end,
  function(_self, n)
    pcall(api.nvim_buf_set_lines, 0, 0, 0, true, { "fz" .. tostring(n) })
  end,
  function() end,
  function()
    pcall(vim.cmd, "tabnew")
  end,
  function(_self, n)
    -- scenario fragment: open float + install WinClosed cb that closes parent
    local b = api.nvim_create_buf(false, true)
    local ok, w = pcall(api.nvim_open_win, b, false, {
      relative = "editor", row = 0, col = 0, width = 12, height = 4,
    })
    if ok and type(w) == "number" then
      pcall(api.nvim_create_autocmd, "WinClosed", {
        pattern = tostring(w), nested = true,
        callback = function() pcall(api.nvim_win_close, 0, true) end,
      })
    end
  end,
  function()
    -- install on_lines callback that recursively mutates (bounded)
    local bs = api.nvim_list_bufs()
    if #bs > 0 then
      local fired = 0
      pcall(api.nvim_buf_attach, bs[1], false, {
        on_lines = function(_, b)
          fired = fired + 1
          if fired > 2 then return end
          pcall(api.nvim_buf_set_lines, b, 0, 0, true, { "fzwl_inl" })
        end,
      })
    end
  end,
  function()
    -- open_term + on_input that mutates buf
    local bs = api.nvim_list_bufs()
    if #bs > 0 then
      local ok, ch = pcall(api.nvim_open_term, bs[1], {
        on_input = function(_, _t, b, _d)
          pcall(api.nvim_buf_set_lines, b, 0, -1, false, { "fzwl_tin" })
        end,
      })
      if ok and ch then pcall(api.nvim_chan_send, ch, "x") end
    end
  end,
  function()
    -- set decoration provider with on_line mutating
    local ns = api.nvim_create_namespace("fz_stub")
    pcall(api.nvim_set_decoration_provider, ns, {
      on_line = function(_, _w, b, row)
        pcall(api.nvim_buf_set_extmark, b, ns, row, 0, { sign_text = "X" })
      end,
    })
  end,
  function()
    -- timer that mutates later
    pcall(vim.fn.timer_start, 0, function()
      pcall(api.nvim_buf_set_lines, 0, 0, 0, true, { "fzwl_tm" })
    end)
  end,
  function()
    -- user command recursive (bounded)
    local name = "FzS" .. tostring(math.random(99999))
    pcall(api.nvim_create_user_command, name, function(a)
      local d = tonumber(a.args) or 0
      if d > 2 then return end
      pcall(api.nvim_cmd, { cmd = name, args = { tostring(d + 1) } }, {})
    end, { nargs = "1" })
    pcall(api.nvim_cmd, { cmd = name, args = { "0" } }, {})
  end,
  function()
    -- install recursive WinClosed callback (cross-event)
    pcall(api.nvim_create_autocmd, "WinClosed", {
      nested = true, callback = _stub_cb_winclosed,
    })
  end,
})

local _stub_cb_winclosed = make_varied_stub({
  function()
    pcall(api.nvim_win_close, 0, true)
  end,
  function(_self, n)
    local ws = api.nvim_list_wins()
    if #ws > 1 then pcall(api.nvim_win_close, ws[1 + (n % #ws)], true) end
  end,
  function()
    for _, b in ipairs(api.nvim_list_bufs()) do
      if api.nvim_buf_is_valid(b) and not api.nvim_buf_is_loaded(b) then
        pcall(api.nvim_buf_delete, b, { force = true, unload = true })
        return
      end
    end
  end,
  function() end,
  function(_self, n)
    pcall(api.nvim_buf_set_lines, 0, 0, 0, true, { "fw" .. tostring(n) })
  end,
  function() pcall(vim.cmd, "tabnew") end,
  function()
    -- install recursive WinLeave callback (cross-event)
    pcall(api.nvim_create_autocmd, "WinLeave", {
      nested = true, callback = _stub_cb_winleave,
    })
  end,
  function()
    -- install on_lines callback that mutates buf
    local bs = api.nvim_list_bufs()
    if #bs > 0 then
      pcall(api.nvim_buf_attach, bs[1], false, {
        on_lines = function(_, b)
          pcall(api.nvim_buf_set_lines, b, 0, 0, true, { "fzwc_inl" })
        end,
      })
    end
  end,
  function()
    -- open_term + on_input that mutates buf
    local bs = api.nvim_list_bufs()
    if #bs > 0 then
      local ok, ch = pcall(api.nvim_open_term, bs[1], {
        on_input = function(_, _t, b, _d)
          pcall(api.nvim_buf_set_lines, b, 0, -1, false, { "fzwc_tin" })
        end,
      })
      if ok and ch then pcall(api.nvim_chan_send, ch, "y") end
    end
  end,
  function()
    -- decoration provider
    local ns = api.nvim_create_namespace("fz_stub_wc")
    pcall(api.nvim_set_decoration_provider, ns, {
      on_buf = function(_, b, tick)
        pcall(api.nvim_buf_set_extmark, b, ns, 0, 0, { sign_text = "Y" })
        return tick
      end,
    })
  end,
  function()
    -- timer
    pcall(vim.fn.timer_start, 0, function()
      pcall(api.nvim_buf_set_lines, 0, 0, 0, true, { "fzwc_tm" })
    end)
  end,
})

local _stub_cb_winclosed_buf = make_varied_stub({
  function(_self, n)
    local bs = api.nvim_list_bufs()
    if #bs > 1 then pcall(api.nvim_buf_delete, bs[1 + (n % #bs)], { force = true }) end
  end,
  function()
    for _, b in ipairs(api.nvim_list_bufs()) do
      if api.nvim_buf_is_valid(b) and not api.nvim_buf_is_loaded(b) then
        pcall(api.nvim_buf_delete, b, { force = true, unload = true })
        return
      end
    end
  end,
  function() end,
  function()
    pcall(api.nvim_buf_set_lines, 0, 0, 0, true, { "x" })
  end,
  function()
    -- install recursive WinLeave (cross-event)
    pcall(api.nvim_create_autocmd, "WinLeave", {
      nested = true, callback = _stub_cb_winleave,
    })
  end,
  function()
    -- open_term + on_input
    local bs = api.nvim_list_bufs()
    if #bs > 0 then
      local ok, ch = pcall(api.nvim_open_term, bs[1], {
        on_input = function(_, _t, b, _d)
          pcall(api.nvim_buf_set_lines, b, 0, -1, false, { "fwcb_tin" })
        end,
      })
      if ok and ch then pcall(api.nvim_chan_send, ch, "z") end
    end
  end,
  function()
    -- timer + mutate
    pcall(vim.fn.timer_start, 0, function()
      local bs = api.nvim_list_bufs()
      if #bs > 1 then pcall(api.nvim_buf_delete, bs[#bs], { force = true }) end
    end)
  end,
})

local _stub_cb_bufunload = make_varied_stub({
  function()
    local bs = api.nvim_list_bufs()
    if #bs >= 2 then pcall(api.nvim_buf_delete, bs[#bs], { force = true }) end
  end,
  function()
    pcall(api.nvim_win_close, 0, true)
  end,
  function()
    local bs = api.nvim_list_bufs()
    if #bs >= 2 then pcall(api.nvim_buf_delete, bs[1], { force = true }) end
  end,
  function() end,
  function()
    pcall(api.nvim_buf_set_lines, 0, 0, 0, true, { "u" })
  end,
  function()
    -- install on_lines that recursively mutates
    local bs = api.nvim_list_bufs()
    if #bs > 0 then
      local fired = 0
      pcall(api.nvim_buf_attach, bs[1], false, {
        on_lines = function(_, b)
          fired = fired + 1
          if fired > 2 then return end
          pcall(api.nvim_buf_set_lines, b, -1, -1, false, { "fzbu_inl" })
        end,
      })
    end
  end,
  function()
    -- open_term + on_input
    local bs = api.nvim_list_bufs()
    if #bs > 0 then
      local ok, ch = pcall(api.nvim_open_term, bs[1], {
        on_input = function(_, _t, b, _d)
          pcall(api.nvim_buf_set_lines, b, 0, -1, false, { "fzbu_tin" })
        end,
      })
      if ok and ch then pcall(api.nvim_chan_send, ch, "u") end
    end
  end,
  function()
    -- decoration provider
    local ns = api.nvim_create_namespace("fz_stub_bu")
    pcall(api.nvim_set_decoration_provider, ns, {
      on_line = function(_, _w, b, row)
        pcall(api.nvim_buf_set_extmark, b, ns, row, 0, { sign_text = "U" })
      end,
    })
  end,
  function()
    -- timer
    pcall(vim.fn.timer_start, 0, function()
      local bs = api.nvim_list_bufs()
      if #bs > 1 then pcall(api.nvim_buf_delete, bs[1], { force = true }) end
    end)
  end,
})

local _stub_cb_on_lines = make_varied_stub({
  function()
    pcall(api.nvim_win_close, 0, true)
  end,
  function()
    local b = api.nvim_create_buf(false, true)
    pcall(api.nvim_open_win, b, false, {
      relative = "editor", row = 0, col = 0, width = 10, height = 5,
    })
  end,
  function(_self, n)
    pcall(api.nvim_buf_set_lines, 0, 0, 0, true, { "zol" .. tostring(n) })
  end,
  function() end,
  function()
    local bs = api.nvim_list_bufs()
    if #bs > 1 then pcall(api.nvim_buf_delete, bs[#bs], { force = true }) end
  end,
  function()
    -- install recursive BufUnload callback (cross-event)
    pcall(api.nvim_create_autocmd, "BufUnload", {
      nested = true, callback = _stub_cb_bufunload,
    })
  end,
  function()
    -- open_term + on_input
    local bs = api.nvim_list_bufs()
    if #bs > 0 then
      local ok, ch = pcall(api.nvim_open_term, bs[1], {
        on_input = function(_, _t, b, _d)
          pcall(api.nvim_buf_set_lines, b, 0, -1, false, { "fzol_tin" })
        end,
      })
      if ok and ch then pcall(api.nvim_chan_send, ch, "o") end
    end
  end,
  function()
    -- decoration provider
    local ns = api.nvim_create_namespace("fz_stub_ol")
    pcall(api.nvim_set_decoration_provider, ns, {
      on_line = function(_, _w, b, row)
        pcall(api.nvim_buf_set_extmark, b, ns, row, 0, { sign_text = "O" })
      end,
    })
  end,
  function()
    -- timer
    pcall(vim.fn.timer_start, 0, function()
      pcall(api.nvim_buf_set_lines, 0, 0, 0, true, { "fzol_tm" })
    end)
  end,
})

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
safe(vim.api.nvim_get_option_info, "cmdheight")
safe(vim.api.nvim_set_option_value, "cmdheight", 26396, {})
end
do  -- round 2
safe(vim.cmd, "set langmap=xX,Xx,yY,Yy")
safe(vim.api.nvim_buf_set_keymap, 0, "i", "<F2>", ":lua vim.api.nvim_buf_set_lines(0, 0, 0, true, {\"fzlm\"})<CR>", {["silent"]=true,["noremap"]=true})
safe(vim.api.nvim_input, "<F2>")
safe(vim.cmd, "redrawstatus")
end
do  -- round 3
safe(vim.api.nvim_set_var, "fz_devexw", -350297)
safe(vim.api.nvim_input, "<Esc>ipdxpda<Esc>u<CR><Esc>pixpiiup<CR>uxxp<Esc>auxxuxxa<Esc><CR>pi<CR>ixai<Esc><CR>x<Esc><CR>uxuaux<CR><Esc>dii<Esc>aa<Esc>x<Esc>uppxiai<Esc><Esc>duad<Esc>u<CR>dpi<Esc><Esc><CR>ida<Esc>iu<CR>uaxxia<CR><CR><Esc>pdp<Esc><Esc>d<CR>ppuupdu<CR>xpiuxu<CR>u<CR>uax<CR>ppiu<Esc>a<CR><Esc>x<Esc>xdd<CR>a<Esc>dpx<CR>auaudauiipippidud<CR>pudaax<CR><CR>aiiddpax<CR>dpap<Esc>axa<Esc><Esc>pi<Esc>d<CR>dix<Esc>uuia<Esc>pipid<CR><CR>d<CR>paaidpa<CR>xdpiapp<CR><CR><CR>xxddia<Esc><CR>iaia<Esc>x<Esc>a<Esc>ipdxpda<Esc>u<CR><Esc>pixpiiup<CR>uxxp<Esc>auxxuxxa<Esc><CR>pi<CR>ixai<Esc><CR>x<Esc><CR>uxuaux<CR><Esc>dii<Esc>aa<Esc>x<Esc>uppxiai<Esc><Esc>duad<Esc>u<CR>dpi<Esc><Esc><CR>ida<Esc>iu<CR>uaxxia<CR><CR><Esc>pdp<Esc><Esc>d<CR>ppuupdu<CR>xpiuxu<CR>u<CR>uax<CR>ppiu<Esc>a<CR><Esc>x<Esc>xdd<CR>a<Esc>dpx<CR>auaudauiipippidud<CR>pudaax<CR><CR>aiiddpax<CR>dpap<Esc>axa<Esc><Esc>pi<Esc>d<CR>dix<Esc>uuia<Esc>pipid<CR><CR>d<CR>paaidpa<CR>xdpiapp<CR><CR><CR>xxddia<Esc><CR>iaia<Esc>x<Esc>a<Esc>ipdxpda<Esc>u<CR><Esc>pixpiiup<CR>uxxp<Esc>auxxuxxa<Esc><CR>pi<CR>ixai<Esc><CR>x<Esc><CR>uxuaux<CR><Esc>dii<Esc>aa<Esc>x<Esc>uppxiai<Esc><Esc>duad<Esc>u<CR>dpi<Esc><Esc><CR>ida<Esc>iu<CR>uaxxia<CR><CR><Esc>pdp<Esc><Esc>d<CR>ppuupdu<CR>xpiuxu<CR>u<CR>uax<CR>ppiu<Esc>a<CR><Esc>x<Esc>xdd<CR>a<Esc>dpx<CR>auaudauiipippidud<CR>pudaax<CR><CR>aiiddpax<CR>dpap<Esc>axa<Esc><Esc>pi<Esc>d<CR>dix<Esc>uuia<Esc>pipid<CR><CR>d")
end
do  -- round 4
safe(vim.cmd, "normal! <C-r>")
end
do  -- round 5
safe(vim.api.nvim_create_namespace, "fzclyhtmj")
safe(vim.api.nvim_set_decoration_provider, 4, {["on_line"]=_stub_cb,["on_buf"]=_stub_cb})
safe(vim.api.nvim_list_bufs)
safe(vim.cmd, "redrawstatus")
safe(vim.api.nvim_buf_set_extmark, 1, 4, 0, 0, {["ephemeral"]=true,["sign_text"]="q"})
safe(vim.cmd, "redrawstatus")
end
do  -- round 6
safe(vim.api.nvim_input, "ÔRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~")
end
do  -- round 7
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 2, true, {["zindex"]=188,["hide"]=true,["title"]="./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~IJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~defghijklmnopqrstuvwxyz{|}~",["noautocmd"]=false,["footer"]="efghijklmnopqrstuvwxyz{|}~mnopqrstuvwxyz{|}~456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~fghijklmnopqrstuvwxyz{|}~",["focusable"]=true,["footer_pos"]="center",["border"]={[1]="+",[2]="-",[3]="+",[4]="|",[5]="+",[6]="-",[7]="+",[8]="|"},["title_pos"]="right",["relative"]="editor",["width"]=156,["height"]=32,["row"]=33,["col"]=-21})
end
do  -- round 8
safe(vim.cmd, "set langmap=xX,Xx,yY,Yy")
safe(vim.api.nvim_buf_set_keymap, 0, "i", "<F2>", ":lua vim.api.nvim_buf_set_lines(0, 0, 0, true, {\"fzlm\"})<CR>", {["silent"]=true,["noremap"]=true})
safe(vim.api.nvim_input, "<F2>")
safe(vim.cmd, "redrawstatus")
end
do  -- round 9
safe(vim.api.nvim_create_autocmd, "DirChanged", {["nested"]=true,["callback"]=_stub_cb})
safe(vim.cmd, "cd /")
safe(vim.cmd, "cd /tmp")
safe(vim.cmd, "redrawstatus")
end
do  -- round 10
safe(vim.cmd, "redrawstatus")
end
do  -- round 11
safe(vim.api.nvim_list_bufs)
end
do  -- round 12
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_attach, 1, false, {["on_lines"]=_stub_cb,["on_detach"]=_stub_cb})
safe(vim.api.nvim_buf_set_lines, 1, 0, 0, true, {[1]="%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~WXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"})
safe(vim.api.nvim_buf_set_lines, 1, 1, 1, false, {[1]="abcdefghijklmnopqrstuvwxyz{|}~HIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"})
safe(vim.cmd, "redrawstatus")
safe(vim.api.nvim_buf_set_extmark, 1, 4, 0, 0, {["ephemeral"]=true,["virt_text"]={[1]={[2]="Comment",[1]="0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~QRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"}}})
safe(vim.api.nvim_buf_set_extmark, 1, 4, 0, 0, {["ephemeral"]=true,["sign_text"]="c"})
safe(vim.api.nvim_buf_set_extmark, 1, 4, 1, 0, {["ephemeral"]=true,["sign_text"]="w"})
end
do  -- round 13
safe(vim.api.nvim_set_option_value, "statuscolumn", "%s%l", {})
safe(vim.api.nvim_list_bufs)
end
do  -- round 14
safe(vim.cmd, "tabnext")
end
do  -- round 15
safe(vim.cmd, "set langmap=xX,Xx,yY,Yy")
safe(vim.api.nvim_buf_set_keymap, 0, "i", "<F2>", ":lua vim.api.nvim_buf_set_lines(0, 0, 0, true, {\"fzlm\"})<CR>", {["silent"]=true,["noremap"]=true})
safe(vim.api.nvim_input, "<F2>")
safe(vim.cmd, "redrawstatus")
safe(vim.api.nvim_input, "<CR><Esc><Esc>xip<CR>puiaidxa<CR>u<CR>ap<CR><Esc>x<Esc>uxapx<CR>xdx<CR>didp<CR>iiu<CR>px<Esc>aia<CR>pp<Esc><Esc>a<Esc><CR>ux<Esc>dpupxa<Esc>updi<CR>uxiua<Esc>i<Esc><CR>i<Esc>pdi<Esc>aaxd<CR>auu<CR>iua<Esc>dd<Esc>uua<Esc>pupxpad<Esc>a<CR>updpiaauiap<Esc>d<Esc>uua<Esc>uppapd<CR>p<CR><CR><Esc>i<CR>aadpxiuppiuaap<Esc>ixii<Esc>pxx<Esc>ipx<CR><Esc>u<Esc>uxxdd<Esc><Esc><CR>adaauaiiad<CR>dx<CR>x<Esc>dxdx<Esc>i<Esc><CR>ixapdpppxxpiu<Esc>xxidpuu<CR>u<Esc>iddppx<Esc><CR>ax<Esc>d<Esc>uai<Esc>p<CR><Esc><Esc>xip<CR>puiaidxa<CR>u<CR>ap<CR><Esc>x<Esc>uxapx<CR>xdx<CR>didp<CR>iiu<CR>px<Esc>aia<CR>pp<Esc><Esc>a<Esc><CR>ux<Esc>dpupxa<Esc>updi<CR>uxiua<Esc>i<Esc><CR>i<Esc>pdi<Esc>aaxd<CR>auu<CR>iua<Esc>dd<Esc>uua<Esc>pupxpad<Esc>a<CR>updpiaauiap<Esc>d<Esc>uua<Esc>uppapd<CR>p<CR><CR><Esc>i<CR>aadpxiuppiuaap<Esc>ixii<Esc>pxx<Esc>ipx<CR><Esc>u<Esc>uxxdd<Esc><Esc><CR>adaauaiiad<CR>dx<CR>x<Esc>dxdx<Esc>i<Esc><CR>ixapdpppxxpiu<Esc>xxidpuu<CR>u<Esc>iddppx<Esc><CR>ax<Esc>d<Esc>uai")
safe(vim.cmd, "redrawstatus")
end
do  -- round 17
safe(vim.cmd, "tabfirst")
end
do  -- round 19
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_clear_namespace, 1, 4, -7, 56)
end
do  -- round 20
safe(vim.api.nvim_get_option_info, "hlsearch")
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_set_option_value, "hlsearch", false, {["win"]=1000})
safe(vim.cmd, "redrawstatus")
end
do  -- round 21
safe(vim.api.nvim_list_wins)
end
do  -- round 22
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_open_term, 1, {["on_input"]=_stub_cb})
safe(vim.api.nvim_buf_set_lines, 1, 2, 2, false, {[1]="()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~yz{|}~CDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"})
end

do  -- extra round 1 (round 22 replayed)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_open_term, 1, {["on_input"]=_stub_cb})
safe(vim.api.nvim_buf_set_lines, 1, 2, 2, false, {[1]="()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~yz{|}~CDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"})
end
do  -- extra round 2 (round 22 replayed)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_open_term, 1, {["on_input"]=_stub_cb})
safe(vim.api.nvim_buf_set_lines, 1, 2, 2, false, {[1]="()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~yz{|}~CDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"})
end
do  -- extra round 3 (round 22 replayed)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_open_term, 1, {["on_input"]=_stub_cb})
safe(vim.api.nvim_buf_set_lines, 1, 2, 2, false, {[1]="()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~yz{|}~CDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"})
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
-- Source crash: afl-findings/daily-2026-10-04/default/crashes/id:000008,sig:06,src:000002,time:2122560,execs:11350,op:havoc,rep:16 (1012 bytes)
-- Run with (from repo root):
--   ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:symbolize=0:allocator_may_return_null=1" \
--   deps/neovim/build-afl/bin/nvim --headless --clean -i NONE -n \
--     -l <this-repro>
-- Expected: rc=134 and an AddressSanitizer report.
