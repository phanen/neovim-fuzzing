-- Auto-generated from /tmp/repro-from-crash/id:000026_sig:06_src:000000_time:737718_execs:2230_op:havoc_rep:14.log
-- by bin/from-log.lua.  Reproduces a captured fuzz-crashhunter.lua run.
-- Run with the ASan/UBSan-enabled nvim:
--   VIMRUNTIME=./deps/neovim/runtime \
--   ASAN_OPTIONS="detect_leaks=0:abort_on_error=0" \
--   out/nvim --headless --clean -i NONE -n -l /tmp/minimize/full.lua

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
end
do  -- round 2
safe(vim.api.nvim_create_buf, false, true)
end
do  -- round 4
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
end
do  -- round 5
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
end
do  -- round 7
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
end
do  -- round 8
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.cmd, "tabclose")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
end
do  -- round 9
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_create_buf, false, true)
end
do  -- round 11
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.cmd, "tabnew")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.cmd, "bdelete")
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
end
do  -- round 13
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_open_win, 61, false, {["col"]=0,["relative"]="editor",["width"]=10,["height"]=5,["row"]=0})
end
do  -- round 14
safe(vim.api.nvim_list_wins)
safe(vim.api.nvim_create_autocmd, "WinClosed", {["callback"]=_stub_cb_winclosed,["nested"]=true})
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
safe(vim.api.nvim_create_buf, false, true)
end
do  -- round 15
safe(vim.api.nvim_create_autocmd, "WinLeave", {["callback"]=_stub_cb_winleave})
safe(vim.cmd, "tabnew")
end
do  -- round 17
safe(vim.api.nvim_set_option_value, "signcolumn", "auto:3", {})
safe(vim.api.nvim_buf_delete, 61, {["force"]=true,["unload"]=true})
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
