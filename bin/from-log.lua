#!/usr/bin/env -S nvim -l
-- bin/from-log.lua -- Translate fuzz-crashhunter.lua's dispatch log
-- (output of `log=path`) into a self-contained repro.lua that calls
-- the same vim.api / vim.cmd sequence directly. No dofile, no PRNG,
-- no input file. Per-round `do ... end` blocks mirror the source's
-- for-round reset. See README.md for the autocmd-callback LIMITATION.
--
-- Usage: bin/from-log.lua <log.lua> [output.lua]
--   default output: <log>.repro.lua next to the log file

local function usage()
  io.write([[
usage: bin/from-log.lua <log.lua> [output.lua]
]])
end

if #arg < 1 then usage() os.exit(2) end

local log_path = arg[1]
local log
do
  -- The log file may be truncated by a crash (no trailing `return log`).
  -- Append it to a temp copy and dofile that.
  local tmp = os.tmpname()
  local f = io.open(tmp, 'w')
  local src = io.open(log_path, 'r'):read('*a')
  f:write(src)
  if not src:match('return log%s*$') then
    f:write('\nreturn log\n')
  end
  f:close()
  log = dofile(tmp)
  os.remove(tmp)
end

local out_path = arg[2]
if not out_path then
  local base = log_path:gsub('%.lua$', '')
  out_path = base .. '.repro.lua'
end

-- Build standalone repro
local lines = {}
local function emit(s) lines[#lines + 1] = s end

-- Some scenarios/traps from fuzz-crashhunter.lua need a separate
-- helper sub-function in the generated repro so we can call them
-- multiple times. Emit each once, on first reference.
local emitted_helpers = {}
local function emit_helper(helper_name, body)
  if emitted_helpers[helper_name] then return end
  emit(body)
  emitted_helpers[helper_name] = true
end

-- We only know how to translate a handful of `name` values to
-- concrete vim.api / vim.cmd calls. Unknown names emit a
-- `-- (not modeled) <name>` comment so the repro at least shows
-- the dispatch sequence to a human reader.
local function not_modeled(name)
  emit('-- not modeled: ' .. name .. ' (requires fuzz-crashhunter.lua replay)')
end

-- Mirror of fuzz-crashhunter.lua's ser_arg: render a value as a
-- Lua-literal expression so the generated repro.lua can re-emit it
-- directly. Used to format individual args after `op.sargs` is
-- loadstring-parsed back into a Lua table.
local function ser_arg(v)
  local t = type(v)
  if t == 'nil' then
    return 'nil'
  elseif t == 'boolean' then
    return tostring(v)
  elseif t == 'number' then
    if v ~= v or v == math.huge or v == -math.huge then
      return 'nil'
    end
    return tostring(v)
  elseif t == 'string' then
    return string.format('%q', v)
  elseif t == 'table' then
    local parts = {}
    for k, vv in pairs(v) do
      local ks
      if type(k) == 'string' then
        ks = '[' .. string.format('%q', k) .. ']'
      elseif type(k) == 'number' then
        ks = '[' .. tostring(k) .. ']'
      end
      if ks then
        parts[#parts + 1] = ks .. '=' .. ser_arg(vv)
      end
    end
    return '{' .. table.concat(parts, ',') .. '}'
  end
  return string.format('"<%s not serializable>"', t)
end

emit('vim.o.swapfile = false')
emit('vim.o.shadafile = "NONE"')
emit('local api = vim.api')
emit('local function safe(fn, ...) return pcall(fn, ...) end')
emit('')
emit('local function make_varied_stub(variants)')
emit('  local counter = 0')
emit('  local stub')
emit('  stub = function(...)')
emit('    counter = counter + 1')
emit('    local idx = ((counter * 31) % #variants) + 1')
emit('    local v = variants[idx]')
emit('    if v then v(stub, counter, ...) end')
emit('  end')
emit('  return stub')
emit('end')
emit('')
-- Stub callback forward declarations.
--
-- Some stub variants reference other stubs (cross-event recursion,
-- e.g. a WinLeave variant that installs a WinClosed callback and
-- vice versa). Lua locals are in scope from their declaration line
-- to the end of the enclosing block, so any reference that appears
-- BEFORE the matching `local _stub_cb_xxx = make_varied_stub(...)`
-- rebinds a global to nil.  Pre-declaring every stub name up front
-- reserves a local slot for each; the later `local _stub_cb_xxx =
-- ...` reassigns the same slot rather than introducing a new one,
-- so closures captured during the table literal correctly resolve
-- to the locals and see their assigned values when invoked.
local _stub_cb_winleave
local _stub_cb_winclosed
local _stub_cb_winclosed_buf
local _stub_cb_bufunload
local _stub_cb_on_lines
emit('local _stub_cb_winleave')
emit('local _stub_cb_winclosed')
emit('local _stub_cb_winclosed_buf')
emit('local _stub_cb_bufunload')
emit('local _stub_cb_on_lines')

emit('local _stub_cb_winleave = make_varied_stub({')
emit('  function(_self, n)')
emit('    local b = api.nvim_create_buf(false, true)')
emit('    pcall(api.nvim_open_win, b, false, {')
emit('      relative = "editor", row = (n % 5), col = (n % 7),')
emit('      width = ((n % 10) + 5), height = ((n % 4) + 3),')
emit('    })')
emit('  end,')
emit('  function()')
emit('    pcall(api.nvim_win_close, 0, true)')
emit('  end,')
emit('  function()')
emit('    local bs = api.nvim_list_bufs()')
emit('    if #bs > 1 then pcall(api.nvim_buf_delete, bs[#bs], { force = true }) end')
emit('  end,')
emit('  function(_self, n)')
emit('    pcall(api.nvim_buf_set_lines, 0, 0, 0, true, { "fz" .. tostring(n) })')
emit('  end,')
emit('  function() end,')
emit('  function()')
emit('    pcall(vim.cmd, "tabnew")')
emit('  end,')
emit('  function(_self, n)')
emit('    -- scenario fragment: open float + install WinClosed cb that closes parent')
emit('    local b = api.nvim_create_buf(false, true)')
emit('    local ok, w = pcall(api.nvim_open_win, b, false, {')
emit('      relative = "editor", row = 0, col = 0, width = 12, height = 4,')
emit('    })')
emit('    if ok and type(w) == "number" then')
emit('      pcall(api.nvim_create_autocmd, "WinClosed", {')
emit('        pattern = tostring(w), nested = true,')
emit('        callback = function() pcall(api.nvim_win_close, 0, true) end,')
emit('      })')
emit('    end')
emit('  end,')
emit('  function()')
emit('    -- install on_lines callback that recursively mutates (bounded)')
emit('    local bs = api.nvim_list_bufs()')
emit('    if #bs > 0 then')
emit('      local fired = 0')
emit('      pcall(api.nvim_buf_attach, bs[1], false, {')
emit('        on_lines = function(_, b)')
emit('          fired = fired + 1')
emit('          if fired > 2 then return end')
emit('          pcall(api.nvim_buf_set_lines, b, 0, 0, true, { "fzwl_inl" })')
emit('        end,')
emit('      })')
emit('    end')
emit('  end,')
emit('  function()')
emit('    -- open_term + on_input that mutates buf')
emit('    local bs = api.nvim_list_bufs()')
emit('    if #bs > 0 then')
emit('      local ok, ch = pcall(api.nvim_open_term, bs[1], {')
emit('        on_input = function(_, _t, b, _d)')
emit('          pcall(api.nvim_buf_set_lines, b, 0, -1, false, { "fzwl_tin" })')
emit('        end,')
emit('      })')
emit('      if ok and ch then pcall(api.nvim_chan_send, ch, "x") end')
emit('    end')
emit('  end,')
emit('  function()')
emit('    -- set decoration provider with on_line mutating')
emit('    local ns = api.nvim_create_namespace("fz_stub")')
emit('    pcall(api.nvim_set_decoration_provider, ns, {')
emit('      on_line = function(_, _w, b, row)')
emit('        pcall(api.nvim_buf_set_extmark, b, ns, row, 0, { sign_text = "X" })')
emit('      end,')
emit('    })')
emit('  end,')
emit('  function()')
emit('    -- timer that mutates later')
emit('    pcall(vim.fn.timer_start, 0, function()')
emit('      pcall(api.nvim_buf_set_lines, 0, 0, 0, true, { "fzwl_tm" })')
emit('    end)')
emit('  end,')
emit('  function()')
emit('    -- user command recursive (bounded)')
emit('    local name = "FzS" .. tostring(math.random(99999))')
emit('    pcall(api.nvim_create_user_command, name, function(a)')
emit('      local d = tonumber(a.args) or 0')
emit('      if d > 2 then return end')
emit('      pcall(api.nvim_cmd, { cmd = name, args = { tostring(d + 1) } }, {})')
emit('    end, { nargs = "1" })')
emit('    pcall(api.nvim_cmd, { cmd = name, args = { "0" } }, {})')
emit('  end,')
emit('  function()')
emit('    -- install recursive WinClosed callback (cross-event)')
emit('    pcall(api.nvim_create_autocmd, "WinClosed", {')
emit('      nested = true, callback = _stub_cb_winclosed,')
emit('    })')
emit('  end,')
emit('})')
emit('')
emit('local _stub_cb_winclosed = make_varied_stub({')
emit('  function()')
emit('    pcall(api.nvim_win_close, 0, true)')
emit('  end,')
emit('  function(_self, n)')
emit('    local ws = api.nvim_list_wins()')
emit('    if #ws > 1 then pcall(api.nvim_win_close, ws[1 + (n % #ws)], true) end')
emit('  end,')
emit('  function()')
emit('    for _, b in ipairs(api.nvim_list_bufs()) do')
emit('      if api.nvim_buf_is_valid(b) and not api.nvim_buf_is_loaded(b) then')
emit('        pcall(api.nvim_buf_delete, b, { force = true, unload = true })')
emit('        return')
emit('      end')
emit('    end')
emit('  end,')
emit('  function() end,')
emit('  function(_self, n)')
emit('    pcall(api.nvim_buf_set_lines, 0, 0, 0, true, { "fw" .. tostring(n) })')
emit('  end,')
emit('  function() pcall(vim.cmd, "tabnew") end,')
emit('  function()')
emit('    -- install recursive WinLeave callback (cross-event)')
emit('    pcall(api.nvim_create_autocmd, "WinLeave", {')
emit('      nested = true, callback = _stub_cb_winleave,')
emit('    })')
emit('  end,')
emit('  function()')
emit('    -- install on_lines callback that mutates buf')
emit('    local bs = api.nvim_list_bufs()')
emit('    if #bs > 0 then')
emit('      pcall(api.nvim_buf_attach, bs[1], false, {')
emit('        on_lines = function(_, b)')
emit('          pcall(api.nvim_buf_set_lines, b, 0, 0, true, { "fzwc_inl" })')
emit('        end,')
emit('      })')
emit('    end')
emit('  end,')
emit('  function()')
emit('    -- open_term + on_input that mutates buf')
emit('    local bs = api.nvim_list_bufs()')
emit('    if #bs > 0 then')
emit('      local ok, ch = pcall(api.nvim_open_term, bs[1], {')
emit('        on_input = function(_, _t, b, _d)')
emit('          pcall(api.nvim_buf_set_lines, b, 0, -1, false, { "fzwc_tin" })')
emit('        end,')
emit('      })')
emit('      if ok and ch then pcall(api.nvim_chan_send, ch, "y") end')
emit('    end')
emit('  end,')
emit('  function()')
emit('    -- decoration provider')
emit('    local ns = api.nvim_create_namespace("fz_stub_wc")')
emit('    pcall(api.nvim_set_decoration_provider, ns, {')
emit('      on_buf = function(_, b, tick)')
emit('        pcall(api.nvim_buf_set_extmark, b, ns, 0, 0, { sign_text = "Y" })')
emit('        return tick')
emit('      end,')
emit('    })')
emit('  end,')
emit('  function()')
emit('    -- timer')
emit('    pcall(vim.fn.timer_start, 0, function()')
emit('      pcall(api.nvim_buf_set_lines, 0, 0, 0, true, { "fzwc_tm" })')
emit('    end)')
emit('  end,')
emit('})')
emit('')
emit('local _stub_cb_winclosed_buf = make_varied_stub({')
emit('  function(_self, n)')
emit('    local bs = api.nvim_list_bufs()')
emit('    if #bs > 1 then pcall(api.nvim_buf_delete, bs[1 + (n % #bs)], { force = true }) end')
emit('  end,')
emit('  function()')
emit('    for _, b in ipairs(api.nvim_list_bufs()) do')
emit('      if api.nvim_buf_is_valid(b) and not api.nvim_buf_is_loaded(b) then')
emit('        pcall(api.nvim_buf_delete, b, { force = true, unload = true })')
emit('        return')
emit('      end')
emit('    end')
emit('  end,')
emit('  function() end,')
emit('  function()')
emit('    pcall(api.nvim_buf_set_lines, 0, 0, 0, true, { "x" })')
emit('  end,')
emit('  function()')
emit('    -- install recursive WinLeave (cross-event)')
emit('    pcall(api.nvim_create_autocmd, "WinLeave", {')
emit('      nested = true, callback = _stub_cb_winleave,')
emit('    })')
emit('  end,')
emit('  function()')
emit('    -- open_term + on_input')
emit('    local bs = api.nvim_list_bufs()')
emit('    if #bs > 0 then')
emit('      local ok, ch = pcall(api.nvim_open_term, bs[1], {')
emit('        on_input = function(_, _t, b, _d)')
emit('          pcall(api.nvim_buf_set_lines, b, 0, -1, false, { "fwcb_tin" })')
emit('        end,')
emit('      })')
emit('      if ok and ch then pcall(api.nvim_chan_send, ch, "z") end')
emit('    end')
emit('  end,')
emit('  function()')
emit('    -- timer + mutate')
emit('    pcall(vim.fn.timer_start, 0, function()')
emit('      local bs = api.nvim_list_bufs()')
emit('      if #bs > 1 then pcall(api.nvim_buf_delete, bs[#bs], { force = true }) end')
emit('    end)')
emit('  end,')
emit('})')
emit('')
emit('local _stub_cb_bufunload = make_varied_stub({')
emit('  function()')
emit('    local bs = api.nvim_list_bufs()')
emit('    if #bs >= 2 then pcall(api.nvim_buf_delete, bs[#bs], { force = true }) end')
emit('  end,')
emit('  function()')
emit('    pcall(api.nvim_win_close, 0, true)')
emit('  end,')
emit('  function()')
emit('    local bs = api.nvim_list_bufs()')
emit('    if #bs >= 2 then pcall(api.nvim_buf_delete, bs[1], { force = true }) end')
emit('  end,')
emit('  function() end,')
emit('  function()')
emit('    pcall(api.nvim_buf_set_lines, 0, 0, 0, true, { "u" })')
emit('  end,')
emit('  function()')
emit('    -- install on_lines that recursively mutates')
emit('    local bs = api.nvim_list_bufs()')
emit('    if #bs > 0 then')
emit('      local fired = 0')
emit('      pcall(api.nvim_buf_attach, bs[1], false, {')
emit('        on_lines = function(_, b)')
emit('          fired = fired + 1')
emit('          if fired > 2 then return end')
emit('          pcall(api.nvim_buf_set_lines, b, -1, -1, false, { "fzbu_inl" })')
emit('        end,')
emit('      })')
emit('    end')
emit('  end,')
emit('  function()')
emit('    -- open_term + on_input')
emit('    local bs = api.nvim_list_bufs()')
emit('    if #bs > 0 then')
emit('      local ok, ch = pcall(api.nvim_open_term, bs[1], {')
emit('        on_input = function(_, _t, b, _d)')
emit('          pcall(api.nvim_buf_set_lines, b, 0, -1, false, { "fzbu_tin" })')
emit('        end,')
emit('      })')
emit('      if ok and ch then pcall(api.nvim_chan_send, ch, "u") end')
emit('    end')
emit('  end,')
emit('  function()')
emit('    -- decoration provider')
emit('    local ns = api.nvim_create_namespace("fz_stub_bu")')
emit('    pcall(api.nvim_set_decoration_provider, ns, {')
emit('      on_line = function(_, _w, b, row)')
emit('        pcall(api.nvim_buf_set_extmark, b, ns, row, 0, { sign_text = "U" })')
emit('      end,')
emit('    })')
emit('  end,')
emit('  function()')
emit('    -- timer')
emit('    pcall(vim.fn.timer_start, 0, function()')
emit('      local bs = api.nvim_list_bufs()')
emit('      if #bs > 1 then pcall(api.nvim_buf_delete, bs[1], { force = true }) end')
emit('    end)')
emit('  end,')
emit('})')
emit('')
emit('local _stub_cb_on_lines = make_varied_stub({')
emit('  function()')
emit('    pcall(api.nvim_win_close, 0, true)')
emit('  end,')
emit('  function()')
emit('    local b = api.nvim_create_buf(false, true)')
emit('    pcall(api.nvim_open_win, b, false, {')
emit('      relative = "editor", row = 0, col = 0, width = 10, height = 5,')
emit('    })')
emit('  end,')
emit('  function(_self, n)')
emit('    pcall(api.nvim_buf_set_lines, 0, 0, 0, true, { "zol" .. tostring(n) })')
emit('  end,')
emit('  function() end,')
emit('  function()')
emit('    local bs = api.nvim_list_bufs()')
emit('    if #bs > 1 then pcall(api.nvim_buf_delete, bs[#bs], { force = true }) end')
emit('  end,')
emit('  function()')
emit('    -- install recursive BufUnload callback (cross-event)')
emit('    pcall(api.nvim_create_autocmd, "BufUnload", {')
emit('      nested = true, callback = _stub_cb_bufunload,')
emit('    })')
emit('  end,')
emit('  function()')
emit('    -- open_term + on_input')
emit('    local bs = api.nvim_list_bufs()')
emit('    if #bs > 0 then')
emit('      local ok, ch = pcall(api.nvim_open_term, bs[1], {')
emit('        on_input = function(_, _t, b, _d)')
emit('          pcall(api.nvim_buf_set_lines, b, 0, -1, false, { "fzol_tin" })')
emit('        end,')
emit('      })')
emit('      if ok and ch then pcall(api.nvim_chan_send, ch, "o") end')
emit('    end')
emit('  end,')
emit('  function()')
emit('    -- decoration provider')
emit('    local ns = api.nvim_create_namespace("fz_stub_ol")')
emit('    pcall(api.nvim_set_decoration_provider, ns, {')
emit('      on_line = function(_, _w, b, row)')
emit('        pcall(api.nvim_buf_set_extmark, b, ns, row, 0, { sign_text = "O" })')
emit('      end,')
emit('    })')
emit('  end,')
emit('  function()')
emit('    -- timer')
emit('    pcall(vim.fn.timer_start, 0, function()')
emit('      pcall(api.nvim_buf_set_lines, 0, 0, 0, true, { "fzol_tm" })')
emit('    end)')
emit('  end,')
emit('})')
emit('')

-- Tracked float IDs, in creation order.  Required because closing floats
-- via nvim_list_wins() gives a different close order than the fuzzer's
-- tracked S.floats list, and the crash only reproduces with the latter.
emit('local floats = {}')
emit('')
emit('local function open_float(cfg, enter)')
emit('  local _buf = api.nvim_create_buf(false, true)')
emit('  local ok, win = pcall(api.nvim_open_win, _buf, enter, cfg)')
emit('  if ok and type(win) == "number" then floats[#floats + 1] = win end')
emit('end')
emit('')

local open_float_count = 0

-- Bucket ops by `op.round` (stamped by api/cmd proxy in
-- fuzz-crashhunter.lua). Ops without a round (e.g. setup before the
-- for-loop) go into pre-round (key=0). This lets us emit per-round
-- blocks so we can call teardown between rounds, which is required to
-- reproduce crashes that depend on per-round state reset (otherwise
-- flattening all 80 rounds into one run would leave stale bufs/wins
-- and the bug would not manifest).
local by_round = {}
local max_round = 0
for i, op in ipairs(log.ops) do
  local r = op.round or 0
  by_round[r] = by_round[r] or {}
  by_round[r][#by_round[r] + 1] = op
  if r > max_round then max_round = r end
end

-- Per-round teardown helper: mirrors what the source does at
-- round%50, but we call it after EVERY round so each round starts
-- from a clean-enough state. The fuzzer's source uses round%50, but
-- the crash only reproduces when state is reset (we observed the
-- standalone replay of a flat cap.log does NOT crash; per-round
-- teardown makes it crash).  Closing all windows of non-current
-- tabs first preserves the current tab's window count (closing
-- one window when there is only one in a tab triggers a different
-- shutdown path that we want to defer to the final cleanup).
emit('')
emit('local function teardown_round()')
emit('  local curtab = api.nvim_get_current_tabpage()')
emit('  for _, t in ipairs(api.nvim_list_tabpages()) do')
emit('    if t ~= curtab then')
emit('      for _, w in ipairs(api.nvim_tabpage_list_wins(t)) do')
emit('        pcall(api.nvim_win_close, w, true)')
emit('      end')
emit('      pcall(api.nvim_tabpage_close, t, true)')
emit('    end')
emit('  end')
emit('  for i = #floats, 1, -1 do')
emit('    pcall(api.nvim_win_close, floats[i], true)')
emit('    floats[i] = nil')
emit('  end')
emit('  for _, b in ipairs(api.nvim_list_bufs()) do')
emit('    if api.nvim_buf_is_valid(b) and not api.nvim_buf_is_loaded(b) then')
emit('      pcall(api.nvim_buf_delete, b, { force = true })')
emit('    end')
emit('  end')
emit('end')
emit('')

local function emit_op(op)
  if op.kind == 'op' and op.name == 'open_float' then
    open_float_count = open_float_count + 1
    local a = op.args or {}
    -- nvim_open_win(buf, enter, cfg) — `enter` is a positional arg, NOT
    -- part of the config dict.  Strip it from the config serialization
    -- and pass it separately, otherwise nvim returns "invalid key: enter".
    local parts = {}
    for k, v in pairs(a) do
      if k == 'enter' then
        -- skip; passed as positional arg below
      elseif k == 'focusable' or k == 'noautocmd' then
        -- boolean
        parts[#parts + 1] = string.format('%s=%s', k, tostring(v == 'true' or v == true))
      elseif k == 'style' or k == 'border' or k == 'relative' then
        -- string
        local s = tostring(v)
        parts[#parts + 1] = string.format('%s=%q', k, s)
      elseif k == 'width' or k == 'height' or k == 'row' or k == 'col' or k == 'zindex' then
        parts[#parts + 1] = string.format('%s=%s', k, tostring(v))
      end
    end
    local cfg_str = '{' .. table.concat(parts, ',') .. '}'
    local enter = (a.enter == 'true' or a.enter == true)
    emit(string.format('open_float(%s, %s)', cfg_str, tostring(enter)))
  elseif op.kind == 'op' and op.name == 'tabnew' then
    emit("safe(vim.cmd, 'tabnew')")
  elseif op.kind == 'op' and op.name == 'tabclose' then
    emit("if #api.nvim_list_tabpages() > 1 then safe(vim.cmd, 'tabclose') end")
  elseif op.kind == 'op' and op.name == 'tabnext' then
    emit("safe(vim.cmd, 'tabnext')")
  elseif op.kind == 'op' and op.name == 'tabprev' then
    emit("safe(vim.cmd, 'tabprev')")
  elseif op.kind == 'op' and op.name == 'tabfirst' then
    emit("safe(vim.cmd, 'tabfirst')")
  elseif op.kind == 'op' and op.name == 'tablast' then
    emit("safe(vim.cmd, 'tablast')")
  elseif op.kind == 'op' and op.name == 'tabmove' then
    emit("safe(vim.cmd, 'tabmove')")
  elseif op.kind == 'op' and op.name == 'tab_wincmd' then
    -- op_tab_wincmd record_args({cmd = ...})
    local cmd = (op.args and op.args.cmd) or op.cmd or 'tabnext'
    emit(string.format("safe(vim.cmd, %q)", cmd))
  elseif op.kind == 'op' and op.name == 'win_split' then
    emit("safe(vim.cmd, 'split')")
  elseif op.kind == 'op' and op.name == 'win_only' then
    emit("safe(vim.cmd, 'only')")
  elseif op.kind == 'op' and op.name == 'win_wincmd' then
    local cmd = (op.args and op.args.key) or op.cmd or 'w'
    emit(string.format("safe(vim.cmd, 'wincmd %s')", cmd))
  elseif op.kind == 'op' and op.name == 'redrawstatus' then
    emit("safe(vim.cmd, 'redrawstatus')")
  elseif op.kind == 'api' or op.kind == 'cmd_invocation' then
    -- Real vim.api.* / vim.cmd.* call captured by the proxy in
    -- fuzz-crashhunter.lua. `sargs` is a loadstring()-able Lua
    -- expression that reconstructs the args tuple. We eval it here
    -- once so the emitted repro.lua calls vim.api.xxx(...) with the
    -- exact same primitive/table args.
    -- Portable across Lua 5.1 (loadstring) and 5.4/5.5 (load with
    -- explicit "return" prefix, since `loadstring` was removed).
    local _loadstring = loadstring or function(s)
      return load('return ' .. s, 'sargs')
    end
    local args = nil
    if op.sargs and type(op.sargs) == 'string' then
      local chunk = _loadstring(op.sargs)
      if chunk then
        local ok, val = pcall(chunk)
        if ok then args = val end
      end
    end
    -- Fallback to op.args if sargs failed (older log format).
    if not args and op.args then
      args = op.args
    end
    local args_str = ''
    if args and #args > 0 then
      local parts = {}
      -- Pick a stub callback based on the autocmd event. The captured
      -- op's first arg is the event name (string); the second is the
      -- options table that contains `callback`. We use the event name
      -- to choose which stub fires on dispatch, so the WinLeave
      -- handler in the repro actually opens floats (matching what
      -- scenario_winleave_open_float did at capture time).
      local event = op.kind == 'cmd_invocation' and nil
        or (args[1] and type(args[1]) == 'string' and args[1] or nil)
      local cb_var = '_stub_cb'
      if event == 'WinLeave' then cb_var = '_stub_cb_winleave'
      elseif event == 'WinClosed' then cb_var = '_stub_cb_winclosed'
      elseif event == 'BufUnload' then cb_var = '_stub_cb_bufunload'
      elseif event == 'BufWritePost' or event == 'BufWritePre' then
        cb_var = '_stub_cb_winclosed_buf'
      end
      for i, a in ipairs(args) do
        parts[i] = ser_arg(a):gsub(
          '"<function: not serializable>"', cb_var)
      end
      args_str = table.concat(parts, ', ')
    end
    if op.kind == 'cmd_invocation' then
      emit(string.format('safe(vim.cmd, %s)',
        args and #args >= 1 and ser_arg(args[1]) or '""'))
    elseif args_str ~= '' then
      emit(string.format('safe(%s, %s)', op.name, args_str))
    else
      emit(string.format('safe(%s)', op.name))
    end
  elseif op.kind == 'scenario' or op.kind == 'trap' then
    -- Scenario and trap entries from fuzz-crashhunter.lua's main loop.
    -- These calls are dispatched through the api/cmd proxy and already
    -- captured as `kind='api'` ops (round-stamped).  Anything tagged
    -- here is just a high-level dispatch marker; the actual effects
    -- are already in the api/cmd sequence of this round. Skip.
    if op.name == 'redrawstatus' then
      emit("safe(vim.cmd, 'redrawstatus')")
    end
  elseif op.kind == 'teardown' then
    -- Per-round source teardowns are skipped: from-log.lua always
    -- emits `teardown_round()` between rounds to mirror the implicit
    -- state reset.
  elseif op.kind == 'redraw' then
    emit("safe(vim.cmd, 'redrawstatus')")
  end
end

-- Pre-round ops (round=0): emitted once before the round loop.
if by_round[0] then
  for _, op in ipairs(by_round[0]) do emit_op(op) end
end

emit('')
local last_round = 0
for r = 1, max_round do
  if by_round[r] then
    emit(string.format('do  -- round %d', r))
    for _, op in ipairs(by_round[r]) do
      emit_op(op)
    end
    emit('end')
    last_round = r
  end
end
emit('')

-- Some crashes only fire after an additional iteration (round 22+).
-- ASAN aborts the fuzzer before round 22+ is captured, so we replay
-- the LAST captured round a few extra times to mimic the continued
-- accumulation. The bug is in close_windows / do_buffer_ext, so
-- adding more open-float + win_close + buf_delete cycles increases
-- the chance of hitting the UAF on standalone replay.
if last_round > 0 then
  for extra = 1, 3 do
    emit(string.format('do  -- extra round %d (round %d replayed)',
      extra, last_round))
    for _, op in ipairs(by_round[last_round]) do
      emit_op(op)
    end
    emit('end')
  end
  emit('')
end
emit('for _, b in ipairs(api.nvim_list_bufs()) do')
emit('  if api.nvim_buf_is_valid(b) and not api.nvim_buf_is_loaded(b) then')
emit('    pcall(api.nvim_buf_delete, b, { force = true, unload = true })')
emit('  end')
emit('end')
emit('for _, w in ipairs(api.nvim_list_wins()) do')
emit('  pcall(api.nvim_win_close, w, true)')
emit('end')
emit('safe(vim.cmd, "redrawstatus")')
emit('os.exit(0)')

local f = assert(io.open(out_path, 'w'))
f:write(table.concat(lines, '\n') .. '\n')
f:close()

print(('wrote %d ops across %d rounds (open_float=%d) to %s'):format(
  #log.ops, max_round, open_float_count, out_path))