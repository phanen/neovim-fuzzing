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
safe(vim.cmd, "set langmap=xX,Xx,yY,Yy")
safe(vim.api.nvim_buf_set_keymap, 0, "i", "<F2>", ":lua vim.api.nvim_buf_set_lines(0, 0, 0, true, {\"fzlm\"})<CR>", {["noremap"]=true,["silent"]=true})
safe(vim.api.nvim_input, "<F2>")
safe(vim.cmd, "redrawstatus")
end
do  -- round 2
safe(vim.api.nvim_list_bufs)
end
do  -- round 3
safe(vim.api.nvim_list_wins)
end
do  -- round 4
safe(vim.api.nvim_list_wins)
end
do  -- round 5
safe(vim.cmd, "wincmd L")
safe(vim.cmd, "redrawstatus")
end
do  -- round 6
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_paste, "\0\2\3\6\21\22\23\24\27\127lmnopqrstuvwxyz{|}~+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~abcdefghijklmnopqrstuvwxyz{|}~opqrstuvwxyz{|}~^_`abcdefghijklmnopqrstuvwxyz{|}~", true, 2)
end
do  -- round 8
safe(vim.api.nvim_list_wins)
end
do  -- round 9
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.api.nvim_list_tabpages)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_buf_set_lines, 0, 0, 0, true, {[1]="fzwl1"})
safe(vim.cmd, "redrawstatus")
end
do  -- round 10
safe(vim.api.nvim_list_bufs)
safe(vim.cmd, "redrawstatus")
end
do  -- round 11
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim__redraw, {["win"]=0,["range"]={[2]=0,[1]=27},["flush"]=true})
end
do  -- round 12
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_delete)
end
do  -- round 13
safe(vim.cmd, "set langmap=xX,Xx,yY,Yy")
safe(vim.api.nvim_buf_set_keymap, 0, "i", "<F2>", ":lua vim.api.nvim_buf_set_lines(0, 0, 0, true, {\"fzlm\"})<CR>", {["noremap"]=true,["silent"]=true})
safe(vim.api.nvim_input, "<F2>")
safe(vim.cmd, "redrawstatus")
end
do  -- round 14
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_win_call, 1000, _stub_cb)
safe(vim.api.nvim_buf_set_lines, 0, 0, -1, false, {[2]="Z[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~]^_`abcdefghijklmnopqrstuvwxyz{|}~ !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~23456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~)*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~",[1]="$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"})
safe(vim.api.nvim_win_set_cursor, 0, {[2]=0,[1]=1})
end
do  -- round 15
safe(vim.cmd, "tabnext")
safe(vim.api.nvim_exec_autocmds, "User FzStub", {})
safe(vim.cmd, "redrawstatus")
end
do  -- round 16
safe(vim.api.nvim_create_autocmd, "QuickFixCmdPost", {["callback"]=_stub_cb,["nested"]=true})
safe(vim.api.nvim_buf_set_lines, 0, 0, -1, false, {[1]="foo bar",[2]="baz foo",[3]="qux bar",[4]="extra line"})
safe(vim.cmd, "vimgrep /foo/ %")
safe(vim.cmd, "redrawstatus")
end
do  -- round 17
safe(vim.api.nvim_list_bufs)
end
do  -- round 18
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_set_option, 1, "undolevels", -1)
safe(vim.api.nvim_create_namespace, "fzcapbpir")
safe(vim.api.nvim_buf_set_lines, 1, 0, -1, false, {[1]="a",[2]="b",[3]="c"})
safe(vim.api.nvim_buf_set_extmark, 1, 3, 0, 0, {["invalidate"]=true})
safe(vim.cmd, "undo")
safe(vim.cmd, "redo")
safe(vim.cmd, "undo")
safe(vim.cmd, "redrawstatus")
end
do  -- round 19
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_list_bufs)
end
do  -- round 20
safe(vim.api.nvim_list_bufs)
safe(vim.cmd, "redrawstatus")
end
do  -- round 21
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_win_set_buf, 1000, 1)
safe(vim.api.nvim_input, "uu<Esc><CR>apux<CR>ppad<Esc><Esc><Esc>d<Esc>xxiaaidix<Esc>daaiud<CR>paixaxi<CR><Esc>daai<Esc><CR>udp<Esc>duxiippuiux<Esc>dddpxpi<CR>ipxip<Esc>u<CR><Esc><CR>ipxx<CR>x<CR>ipx<CR>a<Esc>pdd<CR>uxaaixpdppaxu<Esc>paua<Esc>uxuxpiu<Esc>pap<Esc>xadx<Esc><Esc>duda<CR>ix<Esc><CR><CR>uiaxa<Esc>daxi<Esc>up<Esc><Esc><Esc>duppai<Esc>a<Esc>axpxxadadaud<Esc>i<Esc>dpi<CR>xa<Esc><CR>iddp<CR><Esc>axa<Esc>uipx<Esc>pxaixp<Esc>dd<CR>aaiaappipxxapda<Esc><CR><CR>dpau<Esc>iidd<Esc>upp<CR><Esc>adauua<Esc>dddaidiapuida<CR>iipp<CR><CR>d<Esc>ixd<CR>diiaa<CR>iupxd<CR>apdu<Esc>ixdd<CR><CR><Esc>d<Esc><Esc>ia<CR><CR>dix<Esc>d<Esc>axu<CR>pdu<Esc>x<CR>aippxaa<CR>daauxpad<Esc>uuxpiuxiiu<Esc>uad<Esc>auuxudip<Esc><Esc>apxpiia<Esc>xdax<CR>xp<CR>aapapuxdaxudiuxxp<Esc>apax<CR>adxd")
end
do  -- round 22
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_open_term, 1, {})
safe(vim.api.nvim_create_autocmd, "TermClose", {["callback"]=_stub_cb,["nested"]=true})
safe(vim.api.nvim_chan_send, 3, "exit\13")
safe(vim.cmd, "redrawstatus")
end
do  -- round 23
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_open_term, 1, {})
end
do  -- round 24
safe(vim.api.nvim_list_bufs)
end
do  -- round 25
safe(vim.api.nvim_exec_autocmds, "WinEnter", {["modeline"]=false,["data"]={[1]="|}~;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~TUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"},["pattern"]="*.lua"})
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, "redrawstatus")
safe(vim.api.nvim_buf_delete, 1, {["force"]=true})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_delete, 2, {["force"]=true})
end

do  -- extra round 1 (round 25 replayed)
safe(vim.api.nvim_exec_autocmds, "WinEnter", {["modeline"]=false,["data"]={[1]="|}~;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~TUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"},["pattern"]="*.lua"})
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, "redrawstatus")
safe(vim.api.nvim_buf_delete, 1, {["force"]=true})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_delete, 2, {["force"]=true})
end
do  -- extra round 2 (round 25 replayed)
safe(vim.api.nvim_exec_autocmds, "WinEnter", {["modeline"]=false,["data"]={[1]="|}~;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~TUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"},["pattern"]="*.lua"})
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, "redrawstatus")
safe(vim.api.nvim_buf_delete, 1, {["force"]=true})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_delete, 2, {["force"]=true})
end
do  -- extra round 3 (round 25 replayed)
safe(vim.api.nvim_exec_autocmds, "WinEnter", {["modeline"]=false,["data"]={[1]="|}~;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~TUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"},["pattern"]="*.lua"})
safe(vim.cmd, "redrawstatus")
safe(vim.cmd, "redrawstatus")
safe(vim.api.nvim_buf_delete, 1, {["force"]=true})
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_delete, 2, {["force"]=true})
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
-- Source crash: afl-findings/daily-2026-07-30/default/crashes/id:000000,sig:04,src:000000,time:1215269,execs:7886,op:havoc,rep:2 (866 bytes)
-- Run with (from repo root):
--   ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:symbolize=0:allocator_may_return_null=1" \
--   deps/neovim/build-afl/bin/nvim --headless --clean -i NONE -n \
--     -l <this-repro>
-- Expected: rc=134 and an AddressSanitizer report.
