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
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_list_wins)
end
do  -- round 2
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 2, false, {["relative"]="editor",["noautocmd"]=false,["width"]=87,["height"]=37,["row"]=-7,["split"]="left",["zindex"]=290,["focusable"]=true,["col"]=-30})
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
do  -- round 3
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 4, false, {["relative"]="editor",["noautocmd"]=true,["width"]=84,["height"]=6,["row"]=37,["split"]="right",["zindex"]=721,["focusable"]=true,["col"]=16})
safe(vim.api.nvim_buf_delete, 4, {["force"]=true})
end
do  -- round 4
safe(vim.api.nvim_list_wins)
end
do  -- round 5
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_set_keymap, "i", "f88", "", {})
safe(vim.cmd, "redrawstatus")
end
do  -- round 6
safe(vim.api.nvim_list_wins)
end
do  -- round 7
safe(vim.api.nvim_list_bufs)
end
do  -- round 8
safe(vim.api.nvim_list_wins)
end
do  -- round 9
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_buf_set_name, 5, "/tmp/fz_twwvxgbt.txt")
end
do  -- round 10
safe(vim.cmd, "redrawstatus")
end
do  -- round 11
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:2", {})
end
do  -- round 12
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 10, false, {["relative"]="editor",["noautocmd"]=false,["width"]=165,["height"]=33,["row"]=3,["col"]=-43,["zindex"]=305,["footer_pos"]="right",["footer"]="BCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~\\]^_`abcdefghijklmnopqrstuvwxyz{|}~-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~",["anchor"]="right",["focusable"]=false,["hide"]=true})
safe(vim.api.nvim_buf_delete, 10, {["force"]=true})
safe(vim.cmd, "tabnew")
safe(vim.cmd, "only")
safe(vim.api.nvim_buf_delete, 6, {["force"]=true})
safe(vim.api.nvim_buf_delete, 7, {["force"]=true})
safe(vim.api.nvim_buf_delete, 8, {["force"]=true})
safe(vim.api.nvim_buf_delete, 9, {["force"]=true})
safe(vim.cmd, "bdelete")
safe(vim.cmd, "redrawstatus")
end
do  -- round 13
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_open_term, 5, {})
safe(vim.api.nvim_create_autocmd, "TermClose", {["nested"]=true,["callback"]=_stub_cb})
safe(vim.api.nvim_chan_send, 3, "exit\13")
safe(vim.cmd, "redrawstatus")
end
do  -- round 14
safe(vim.cmd, "wincmd l")
safe(vim.api.nvim_input, "<CR>ipipp<CR>udauapuaddiddx<Esc>iu<Esc>uudauaiaid<CR>daapidp<Esc>d<CR>p<Esc>xuadi<Esc><CR><CR><CR>iaxuxxdd<Esc>pu<Esc>uppi<Esc>paixp<CR><Esc>daipidu<CR>p<Esc><Esc>daux<CR><CR>xup<CR>iia<Esc>papp<Esc><Esc>ia<Esc><CR>pidu<Esc>uuipaudpp<Esc>pa<CR>pd<Esc><CR><CR><CR><CR><CR><CR><CR><CR><Esc>d<CR>uupdpdi<Esc><Esc>ux<Esc>didpap<Esc><CR>idup<CR>dpx<Esc>xu<Esc>udpd<CR>i<Esc>d<Esc><Esc><CR>dxuappx<CR>ai<CR>iidaduiuidpd<Esc>uxip<Esc>ap<CR><Esc><Esc>upudx<CR><Esc>i<CR><Esc>d<CR><Esc>pa<CR>xui<Esc>ida<CR>ipipp<CR>udauapuaddiddx<Esc>iu<Esc>uudauaiaid<CR>daapidp<Esc>d<CR>p<Esc>xuadi<Esc><CR><CR><CR>iaxuxxdd<Esc>pu<Esc>uppi<Esc>paixp<CR><Esc>daipidu<CR>p<Esc><Esc>daux<CR><CR>xup<CR>iia<Esc>papp<Esc><Esc>ia<Esc><CR>pidu<Esc>uuipaudpp<Esc>pa<CR>pd<Esc><CR><CR><CR><CR><CR><CR><CR><CR><Esc>d<CR>uupdpdi<Esc><Esc>ux<Esc>didpap<Esc><CR>idup<CR>dpx<Esc>xu<Esc>udpd<CR>i<Esc>d<Esc><Esc><CR>dxuappx<CR>ai<CR>iidaduiuidpd<Esc>uxip<Esc>ap<CR><Esc><Esc>upudx<CR><Esc>i<CR><Esc>d<CR><Esc>pa<CR>xui<Esc>ida<CR>ipipp<CR>udauapuaddiddx<Esc>iu<Esc>uudauaiaid<CR>daapidp<Esc>d<CR>p<Esc>xuadi<Esc><CR><CR><CR>iaxuxxdd<Esc>pu<Esc>uppi<Esc>paixp<CR><Esc>daipidu<CR>p<Esc><Esc>daux<CR><CR>xup<CR>iia<Esc>papp<Esc><Esc>ia<Esc><CR>pidu<Esc>uuipaudpp<Esc>pa<CR>pd<Esc><CR><CR><CR><CR><CR><CR><CR><CR><Esc>d<CR>uupdpdi<Esc><Esc>ux<Esc>didpap<Esc><CR>idup<CR>dpx<Esc>xu<Esc>udpd<CR>i<Esc>d<Esc><Esc><CR>dxuappx<CR>ai<CR>ii")
end
do  -- round 15
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_set_lines, 5, 53, 96, true, {})
safe(vim.cmd, "redrawstatus")
end
do  -- round 16
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_input, "<M-ý¾‘¾ƒ„>")
end
do  -- round 17
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_list_bufs)
end
do  -- round 18
safe(vim.api.nvim_list_bufs)
safe(vim.api.nvim_buf_set_lines, 3, 0, -1, false, {[1]="aa"})
safe(vim.cmd, "delete")
safe(vim.cmd, "undo")
safe(vim.cmd, "redrawstatus")
end
do  -- round 19
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_buf_set_name, 12, "/tmp/fz_rvcfyyba.txt")
end
do  -- round 20
safe(vim.api.nvim_list_bufs)
safe(vim.cmd, "redrawstatus")
end
do  -- round 21
safe(vim.api.nvim_cmd, {["cmd"]="__FzRectwjo"}, {})
safe(vim.cmd, "redrawstatus")
end
do  -- round 23
safe(vim.api.nvim_create_autocmd, "QuickFixCmdPost", {["nested"]=true,["callback"]=_stub_cb})
safe(vim.api.nvim_buf_set_lines, 0, 0, -1, false, {[1]="foo bar",[2]="baz foo",[3]="qux bar",[4]="extra line"})
safe(vim.cmd, "vimgrep /foo/ %")
safe(vim.cmd, "redrawstatus")
end
do  -- round 24
safe(vim.api.nvim_list_wins)
end
do  -- round 25
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 13, false, {["relative"]="win",["noautocmd"]=false,["width"]=46,["height"]=22,["row"]=16,["col"]=-6,["zindex"]=487,["win"]=0,["focusable"]=true,["external"]=true})
safe(vim.api.nvim_buf_delete, 13, {["force"]=true})
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
safe(vim.cmd, "redrawstatus")
safe(vim.api.nvim_buf_is_valid, 12)
safe(vim.api.nvim_buf_delete, 12, {["force"]=true})
safe(vim.api.nvim_buf_is_valid, 5)
safe(vim.api.nvim_buf_delete, 5, {["force"]=true})
safe(vim.api.nvim_buf_delete, 5, {["force"]=true})
safe(vim.api.nvim_chan_send, 3, "\3")
safe(vim.cmd, "redrawstatus")
end

do  -- extra round 1 (round 25 replayed)
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 13, false, {["relative"]="win",["noautocmd"]=false,["width"]=46,["height"]=22,["row"]=16,["col"]=-6,["zindex"]=487,["win"]=0,["focusable"]=true,["external"]=true})
safe(vim.api.nvim_buf_delete, 13, {["force"]=true})
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
safe(vim.cmd, "redrawstatus")
safe(vim.api.nvim_buf_is_valid, 12)
safe(vim.api.nvim_buf_delete, 12, {["force"]=true})
safe(vim.api.nvim_buf_is_valid, 5)
safe(vim.api.nvim_buf_delete, 5, {["force"]=true})
safe(vim.api.nvim_buf_delete, 5, {["force"]=true})
safe(vim.api.nvim_chan_send, 3, "\3")
safe(vim.cmd, "redrawstatus")
end
do  -- extra round 2 (round 25 replayed)
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 13, false, {["relative"]="win",["noautocmd"]=false,["width"]=46,["height"]=22,["row"]=16,["col"]=-6,["zindex"]=487,["win"]=0,["focusable"]=true,["external"]=true})
safe(vim.api.nvim_buf_delete, 13, {["force"]=true})
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
safe(vim.cmd, "redrawstatus")
safe(vim.api.nvim_buf_is_valid, 12)
safe(vim.api.nvim_buf_delete, 12, {["force"]=true})
safe(vim.api.nvim_buf_is_valid, 5)
safe(vim.api.nvim_buf_delete, 5, {["force"]=true})
safe(vim.api.nvim_buf_delete, 5, {["force"]=true})
safe(vim.api.nvim_chan_send, 3, "\3")
safe(vim.cmd, "redrawstatus")
end
do  -- extra round 3 (round 25 replayed)
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 13, false, {["relative"]="win",["noautocmd"]=false,["width"]=46,["height"]=22,["row"]=16,["col"]=-6,["zindex"]=487,["win"]=0,["focusable"]=true,["external"]=true})
safe(vim.api.nvim_buf_delete, 13, {["force"]=true})
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
safe(vim.cmd, "redrawstatus")
safe(vim.api.nvim_buf_is_valid, 12)
safe(vim.api.nvim_buf_delete, 12, {["force"]=true})
safe(vim.api.nvim_buf_is_valid, 5)
safe(vim.api.nvim_buf_delete, 5, {["force"]=true})
safe(vim.api.nvim_buf_delete, 5, {["force"]=true})
safe(vim.api.nvim_chan_send, 3, "\3")
safe(vim.cmd, "redrawstatus")
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
-- Source crash: afl-findings/daily-2026-08-27/default/crashes/id:000003,sig:09,src:000008,time:3497787,execs:21442,op:trim,rep:4 (992 bytes)
-- Run with (from repo root):
--   ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:symbolize=0:allocator_may_return_null=1" \
--   deps/neovim/build-afl/bin/nvim --headless --clean -i NONE -n \
--     -l <this-repro>
-- Expected: rc=134 and an AddressSanitizer report.
