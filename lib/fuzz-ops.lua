-- Reusable op function bodies, shared between fuzz.lua (PRNG-driven
-- dispatch) and fuzz-bytes.lua (byte-driven dispatch). Each consumer
-- creates a context table and calls install(ctx) once; the returned
-- ops table closes over the captured ctx fields and is then callable
-- as a normal table-of-functions:
--
--   local F = require('fuzz-ops')
--   local ops = F.install({
--     api=vim.api, cmd=vim.cmd, R=my_prng, S=my_state,
--     list_wins=C.list_wins, list_bufs=C.list_bufs, list_tabs=C.list_tabs,
--     pick_win=C.pick_win, pick_buf=C.pick_buf, pick_tab=C.pick_tab,
--     rand_printable=C.rand_printable, rand_buf=C.rand_buf, rand_word=C.rand_word,
--     cap=C.cap, safe=C.safe,
--     record_args=record_args, consume_args=consume_args,
--   })
--   ops.op_open_float()
--   ops.op_buf_set_extmark()
--   ops.OPS -- the dispatch table with weights
--
-- Putting the op bodies in install() (instead of as module-level
-- functions) means each consumer gets its own private ops that
-- close over its own private ctx.  No global state, no copy-paste.

local M = {}

-- Module-level constants ----------------------------------------------
-- These don't depend on ctx; they're pure data shared between any
-- invocation of install().

local PRINTABLE = ' !"#$%&\'()*+,-./0123456789:;<=>?@' ..
                  'ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`' ..
                  'abcdefghijklmnopqrstuvwxyz{|}~'

local AUTOCMD_EVENTS = {
  'BufAdd', 'BufDelete', 'BufWipeout', 'BufRead', 'BufReadPost',
  'BufWritePost', 'BufNewFile', 'BufFilePost', 'BufEnter', 'BufLeave',
  'BufModifiedSet', 'BufHidden',
  'WinNew', 'WinEnter', 'WinLeave', 'WinClosed', 'WinScrolled',
  'TabNew', 'TabEnter', 'TabLeave', 'TabClosed',
  'FileType', 'Syntax', 'OptionSet', 'User',
  'VimEnter', 'VimLeave', 'VimResume', 'VimSuspend',
  'InsertEnter', 'InsertLeave', 'InsertCharPre',
  'CmdlineEnter', 'CmdlineLeave', 'CmdlineChanged',
  'TextChanged', 'TextChangedI', 'TextChangedP',
  'CursorMoved', 'CursorMovedI', 'ModeChanged',
  'SessionLoadPost', 'StdinReadPost', 'TermClose', 'TermEnter', 'TermLeave',
  'FocusGained', 'FocusLost',
}

local VIM_CMDS = nil  -- populated inside install() because it depends on R

local SPECIAL_KEYS = {
  '<Esc>', '<CR>', '<C-c>', '<C-l>', '<C-g>', '<C-w>', '<C-w>w', '<C-w>j',
  '<C-w>k', '<C-w>h', '<C-w>l', '<C-w>c', '<C-w>q', '<C-w>n', '<C-w>v',
  '<C-w>s', '<C-w>=', '<C-w>_', '<C-w>|', '<C-w>r', '<C-w>R', '<C-w>T',
  '<Tab>', '<S-Tab>', '<BS>', '<Del>', '<Up>', '<Down>', '<Left>', '<Right>',
  '<Home>', '<End>', '<PageUp>', '<PageDown>', '<Insert>',
  '<F1>', '<F2>', '<F3>', '<F4>', '<F5>', '<F6>', '<F7>', '<F8>',
  '<S-F1>', '<S-F2>',
  '<C-LeftMouse>', '<C-RightMouse>', '<2-LeftMouse>', '<3-LeftMouse>',
  '<C-I>', '<C-O>', '<C-A>', '<C-B>', '<C-D>', '<C-E>', '<C-F>', '<C-N>',
  '<C-P>', '<C-R>', '<C-T>', '<C-U>', '<C-V>', '<C-X>', '<C-Y>', '<C-Z>',
  '<M-x>', '<M-1>', '<M-!>',
  '\\12', '\\15', '\\1', '\\2', '\\3',
}

local OPT_NAMES = {
  'wrap', 'number', 'relativenumber', 'cursorline', 'cursorcolumn',
  'hlsearch', 'incsearch', 'list', 'paste', 'virtualedit', 'showcmd',
  'ruler', 'laststatus', 'cmdheight', 'splitbelow', 'splitright',
  'hidden', 'lazyredraw', 'autoread', 'modified', 'readonly', 'equalalways',
  'winfixheight', 'winfixwidth', 'winfixbuf',
  'undolevels', 'undofile', 'backup', 'swapfile', 'shadafile',
  'textwidth', 'tabstop', 'shiftwidth', 'expandtab', 'softtabstop',
  'completeopt', 'wildmode', 'keymodel', 'selectmode',
  'guifont', 'linespace', 'mouse', 'mousemodel', 'ttymouse',
  'display', 'redrawtime', 'maxmem', 'maxmempattern',
  'syntax', 'filetype',
}

local OPT_BOOL = { 'wrap', 'number', 'relativenumber', 'cursorline',
  'cursorcolumn', 'hlsearch', 'incsearch', 'list', 'paste',
  'splitbelow', 'splitright', 'hidden', 'lazyredraw', 'autoread',
  'readonly', 'equalalways', 'expandtab', 'undofile', 'backup',
  'swapfile', 'mouse', 'ruler', 'showcmd' }

local KEYMAP_LHS = {
  'a', 'b', 'x', 'f', 'gx', 'gX', '<F1>', '<S-Tab>', '<C-l>', '<C-a>',
  '<A-x>', '<M-y>', '<leader>a', '<leader>x', '<Plug>(fz-test)',
  '<silent>x', '<nowait>x', '<expr>x', '<unique>x',
  '  ', '<NL>', '<Space><Space>',
}

local CALLBACK_BODY = table.concat({
  'function(args)',
  '  if math.random(2) == 1 then return end',
  '  local ev = args and args.event or ""',
  -- when triggered, run a random tiny mutation to exercise nested code paths
  '  pcall(vim.api.nvim_buf_set_lines, 0, 0, -1, false, { vim.fn.line(".") })',
  '  pcall(vim.api.nvim_set_hl, 0, "Normal", { fg = "#abcdef" })',
  '  pcall(vim.cmd, "redrawstatus")',
  'end',
}, ' ')

local HASH_NS_PREFIX = 'fz'

-- Install: produce an ops table bound to the caller's context. --------
function M.install(ctx)
  -- Capture the context fields as locals; they become upvalues for
  -- every op defined below. The op bodies are unchanged from the
  -- original fuzz.lua source so re-syncing is mechanical.
  local api = ctx.api
  local cmd = ctx.cmd
  local R = ctx.R
  local S = ctx.S
  local list_wins = ctx.list_wins
  local list_bufs = ctx.list_bufs
  local list_tabs = ctx.list_tabs
  local pick_win = ctx.pick_win
  local pick_buf = ctx.pick_buf
  local pick_tab = ctx.pick_tab
  local rand_printable = ctx.rand_printable
  local rand_buf = ctx.rand_buf
  local rand_word = ctx.rand_word
  local cap = ctx.cap
  local safe = ctx.safe
  local record_args = ctx.record_args
  local consume_args = ctx.consume_args

  -- Random helpers ----------------------------------------------------

  local function rand_special_key()
    return R.pick(SPECIAL_KEYS)
  end
  local function rand_event()
    return R.pick(AUTOCMD_EVENTS)
  end

  -- VIM_CMDS depends on R; build it once after R is captured so the
  -- inline calls to R.num() are valid.
  VIM_CMDS = {
    'redraw', 'redraw!', 'redrawstatus', 'normal! gg', 'normal! G',
    'normal! 0$', 'normal! dG', 'normal! yy', 'normal! p', 'normal! P',
    'normal! u', 'normal! <C-r>', 'normal! dd', 'normal! o<Esc>',
    'normal! i<Esc>', 'normal! a<Esc>', 'normal! R<Esc>', 'normal! v<Esc>',
    'split', 'vsplit', 'new', 'vnew', 'enew', 'tabnew', 'tabnext', 'tabprev',
    'tabnext', 'tabnext', 'only', 'all', 'close', 'wincmd w', 'wincmd h',
    'wincmd j', 'wincmd k', 'wincmd l', 'wincmd q', 'wincmd p',
    'edit .', 'write', 'quit', 'qall', 'wall', 'bwipe', 'bdelete',
    'set wrap', 'set nowrap', 'set number', 'setnonumber', 'set relativenumber',
    'set norelativenumber', 'set cursorline', 'set nocursorline',
    'set hlsearch', 'set nohlsearch', 'set incsearch', 'set noincsearch',
    'set list', 'set nolist', 'set paste', 'set nopaste', 'set virtualedit=all',
    'set virtualedit=onemore', 'set virtualedit=', 'set showcmd', 'set noshowcmd',
    'set ruler', 'set noruler', 'set laststatus=0', 'set laststatus=1',
    'set laststatus=2', 'set laststatus=3', 'set cmdheight=1', 'set cmdheight=2',
    'diffthis', 'diffoff', 'let g:fz = ' .. R.num(0, 100000),
    'echo "x"', 'echom "x"', 'echoerr "x"',
    'execute "normal! ' .. R.num(0, 100) .. 'G"',
    'unlet! g:fz', 'unlet! g:fz2',
  }

  -- Op bodies (verbatim from fuzz.lua's operation section) -----------

  local op_open_float
  local op_close_random_win
  local op_win_set_buf
  local op_win_set_cursor
  local op_win_set_hl
  local op_win_set_size
  local op_win_set_position
  local op_win_split
  local op_win_only
  local op_win_wincmd
  local op_win_call_buf
  local op_create_buf
  local op_delete_buf
  local op_buf_set_lines
  local op_buf_set_name
  local op_buf_set_mark
  local op_buf_set_extmark
  local op_buf_clear_extmark
  local op_buf_call
  local op_tabnew
  local op_tabclose
  local op_tabnext
  local op_tabmove
  local op_tab_set_win
  local op_tab_wincmd
  local op_autocmd_create
  local op_autocmd_exec
  local op_autocmd_del
  local op_augroup_create
  local op_augroup_clear
  local op_autocmd_clear_all
  local op_ui_attach
  local op_ui_detach
  local op_option_set
  local op_set_var
  local op_input_random
  local op_feedkeys
  local op_exec_cmd
  local op_eval
  local op_user_command
  local op_timer_start
  local trap_huge_input
  local trap_special_key_largest
  local trap_recursive_exec2
  local trap_paste_weird
  local trap_input_lots
  local op_redraw
  local scenario_open_float_then_set_buf
  local scenario_extmark_then_modify_buf
  local scenario_autocmd_recursive_input
  local scenario_user_command_recursive_exec2
  local op_set_decoration_provider
  local op_win_text_height
  local op_exec_lua
  local op_open_term_chan_send
  local op_set_keymap

  -- Window ops ---------------------------------------------------------

  function op_open_float()
    local rel = R.pick({ 'editor', 'win', 'cursor' })
    local cfg = {
      relative = rel,
      width    = R.num(1, 200),
      height   = R.num(1, 50),
      row      = R.num(-50, 50),
      col      = R.num(-50, 50),
      focusable = R.chance(1, 2),
      style    = R.chance(1, 4) and 'minimal' or nil,
      border   = R.chance(1, 3) and R.pick({ 'single', 'double', 'rounded', 'solid', 'shadow' }) or nil,
      zindex   = R.chance(1, 5) and R.num(-100, 1000) or R.num(50, 200),
      noautocmd = R.chance(1, 5),
    }
    if rel ~= 'cursor' and R.chance(1, 3) then
      cfg.anchor = R.pick({ 'NW', 'NE', 'SW', 'SE', 'top', 'bottom', 'left', 'right' })
    end
    if R.chance(1, 5) then
      cfg.split = R.pick({ 'left', 'right', 'above', 'below' })
    end
    if R.chance(1, 6) then
      cfg.win = pick_win() or 0
    end
    if R.chance(1, 6) then
      cfg.bufpos = { pick_buf() or 0, R.num(-5, 50), R.num(-1, 50) }
    end
    if R.chance(1, 8) then cfg.hide = true end
    if R.chance(1, 8) then cfg.external = true end
    if R.chance(1, 4) then
      cfg.title = rand_printable(R.num(0, 12))
      cfg.title_pos = R.pick({ 'left', 'center', 'right' })
    end
    if R.chance(1, 4) then
      cfg.footer = rand_printable(R.num(0, 12))
      cfg.footer_pos = R.pick({ 'left', 'center', 'right' })
    end
    if cfg.border and R.chance(1, 5) then
      cfg.border = { '+', '-', '+', '|', '+', '-', '+', '|' }
    end
    local enter = R.chance(1, 4)
    record_args({
      relative = cfg.relative,
      width = cfg.width,
      height = cfg.height,
      row = cfg.row,
      col = cfg.col,
      focusable = cfg.focusable,
      style = cfg.style,
      border = cfg.border,
      zindex = cfg.zindex,
      noautocmd = cfg.noautocmd,
      anchor = cfg.anchor,
      split = cfg.split,
      hide = cfg.hide,
      external = cfg.external,
      title = cfg.title,
      footer = cfg.footer,
      enter = enter,
    })
    local buf = api.nvim_create_buf(false, true)
    local ok, win = pcall(api.nvim_open_win, buf, enter, cfg)
    if ok and type(win) == 'number' then
      S.floats[#S.floats + 1] = win
      cap(S.floats, 32)
    else
      pcall(api.nvim_buf_delete, buf, { force = true })
    end
  end

  function op_close_random_win()
    local ws = list_wins()
    if #ws <= 1 then return end
    local w = ws[R.one_of_n(#ws)]
    pcall(api.nvim_win_close, w, true)
  end

  function op_win_set_buf()
    local w = pick_win()
    local b = pick_buf()
    if not w or not b then return end
    pcall(api.nvim_win_set_buf, w, b)
  end

  function op_win_set_cursor()
    local w = pick_win()
    if not w then return end
    local row, col
    if R.chance(1, 5) then
      row, col = R.num(-100, 100000), R.num(-10, 10000)
    else
      row, col = R.num(1, 1000), R.num(0, 500)
    end
    pcall(api.nvim_win_set_cursor, w, { row, col })
  end

  function op_win_set_hl()
    local w = pick_win()
    if not w then return end
    local ns = S.highlight_ns or api.nvim_create_namespace('fz_hl')
    S.highlight_ns = ns
    pcall(api.nvim_win_set_hl_ns, w, ns)
    local name = 'Fz' .. R.num(1, 999)
    local spec = {}
    if R.chance(1, 6) then
      spec.link = R.pick({ 'Error', 'Comment', 'Visual', 'Search',
                           'Normal', 'Cursor', 'StatusLine' })
    else
      spec.fg = '#' .. string.format('%06x', R.u32() % 0x1000000)
      spec.bg = '#' .. string.format('%06x', R.u32() % 0x1000000)
      spec.bold = R.chance(1, 2) or nil
      spec.italic = R.chance(1, 4) or nil
      spec.underline = R.chance(1, 5) or nil
      if R.chance(1, 4) then spec.ctermfg = R.num(-10, 1000) end
      if R.chance(1, 4) then spec.ctermbg = R.num(-10, 1000) end
      if R.chance(1, 5) then
        spec.sp = '#' .. string.format('%06x', R.u32() % 0x1000000)
      end
      if R.chance(1, 5) then spec.blend = R.num(-10, 200) end
      if R.chance(1, 6) then spec.reverse = true end
      if R.chance(1, 6) then spec.strikethrough = true end
    end
    if R.chance(1, 8) then spec.default = true end
    pcall(api.nvim_set_hl, ns, name, spec)
  end

  function op_win_set_size()
    local w = pick_win()
    if not w then return end
    pcall(api.nvim_win_set_height, w, R.num(1, 50))
    if R.chance(1, 2) then
      pcall(api.nvim_win_set_width, w, R.num(1, 200))
    end
  end

  function op_win_set_position()
    local w = pick_win()
    if not w then return end
    local cfg = api.nvim_win_get_config(w)
    cfg.relative = R.pick({ 'editor', 'win', 'cursor' })
    cfg.row = R.num(-100, 100)
    cfg.col = R.num(-100, 100)
    cfg.width = R.num(1, 200)
    cfg.height = R.num(1, 50)
    pcall(api.nvim_win_set_config, w, cfg)
  end

  function op_win_split()
    pcall(cmd, R.pick({ 'split', 'vsplit', 'new', 'vnew', 'split | wincmd p' }))
  end

  function op_win_only()
    pcall(cmd, R.pick({ 'only', 'all' }))
  end

  function op_win_wincmd()
    local key = R.pick({ 'h', 'j', 'k', 'l', 'w', 'W', 't', 'b', 'p',
                         'H', 'L', 'J', 'K', 'r', 'R', 'x', '=' })
    record_args({ key = key })
    pcall(cmd, 'wincmd ' .. key)
  end

  function op_win_call_buf()
    local w = pick_win()
    if not w then return end
    pcall(function()
      api.nvim_win_call(w, function()
        pcall(api.nvim_buf_set_lines, 0, 0, -1, false,
              { rand_printable(R.num(0, 5)), rand_printable(R.num(0, 10)) })
        pcall(api.nvim_win_set_cursor, 0, { 1, 0 })
      end)
    end)
  end

  -- Buffer ops -------------------------------------------------------

  function op_create_buf()
    local listed = R.chance(1, 4)
    local scratch = R.chance(1, 2)
    local ok, buf = pcall(api.nvim_create_buf, listed, scratch)
    if ok and buf then
      S.scratch_bufs[#S.scratch_bufs + 1] = buf
      cap(S.scratch_bufs, 32)
      pcall(api.nvim_buf_set_name, buf, '/tmp/fz_' .. rand_word(8) .. '.txt')
    end
  end

  function op_delete_buf()
    local bs = list_bufs()
    if #bs <= 1 then return end
    local b = bs[R.one_of_n(#bs)]
    pcall(api.nvim_buf_delete, b, { force = true, unload = R.chance(1, 2) })
  end

  function op_buf_set_lines()
    local b = pick_buf()
    if not b then return end
    local n = R.num(0, 6)
    local lines = {}
    for _ = 1, n do
      lines[#lines + 1] = R.chance(1, 8) and rand_buf(R.num(0, 8))
                                  or rand_printable(R.num(0, 30))
    end
    local start, finish, strict
    if R.chance(1, 5) then
      start, finish = R.num(-100, 10000), R.num(-100, 10000)
      strict = R.chance(1, 2)
    else
      start, finish = R.num(-1, 100), R.num(-1, 100)
      strict = R.chance(1, 2)
    end
    pcall(api.nvim_buf_set_lines, b, start, finish, strict, lines)
  end

  function op_buf_set_name()
    local b = pick_buf()
    if not b then return end
    pcall(api.nvim_buf_set_name, b,
      '/tmp/' .. rand_word(R.num(4, 16))
              .. '.' .. R.pick({ 'txt', 'lua', 'md' }))
  end

  function op_buf_set_mark()
    local b = pick_buf()
    if not b then return end
    local name = R.pick({ "'a", "'b", "'c", "'x", "'z", "'A", "'B" })
    pcall(api.nvim_buf_set_mark, b, name, R.num(0, 100), R.num(0, 100), {})
  end

  function op_buf_set_extmark()
    local b = pick_buf()
    if not b then return end
    local ns
    if #S.namespaces == 0 or R.chance(1, 4) then
      ns = api.nvim_create_namespace(HASH_NS_PREFIX .. rand_word(6))
      S.namespaces[#S.namespaces + 1] = ns
      cap(S.namespaces, 16)
    else
      ns = R.pick(S.namespaces)
    end
    local opts = {}
    if R.chance(1, 2) then opts.virt_text = { { rand_printable(R.num(1, 30)), 'Comment' } } end
    if R.chance(1, 3) then opts.virt_text_pos = R.pick({ 'eol', 'overlay', 'right_align', 'inline' }) end
    if R.chance(1, 4) then opts.hl_group = 'Error' end
    if R.chance(1, 4) then opts.sign_text = rand_word(1) end
    if R.chance(1, 5) then opts.spell = false end
    if R.chance(1, 5) then opts.ui_watched = true end
    if R.chance(1, 5) then opts.invalidate = true end
    if R.chance(1, 6) then opts.end_row = R.num(-10, 1000) end
    if R.chance(1, 6) then opts.end_col = R.num(-10, 1000) end
    if R.chance(1, 6) then opts.ephemeral = true end
    if R.chance(1, 5) then
      opts.conceal = string.char(R.num(32, 255))
    end
    if R.chance(1, 6) then
      opts.conceal_lines = R.pick({ '', ' ' })
    end
    if R.chance(1, 5) then
      opts.virt_lines = {
        { { rand_printable(R.num(0, 8)), 'Comment' } },
        { { rand_printable(R.num(0, 8)), 'Error' } },
      }
    end
    if R.chance(1, 6) then
      opts.virt_lines_above = {
        { { rand_printable(R.num(0, 4)), 'WarningMsg' } },
      }
    end
    if R.chance(1, 6) then
      opts.hl_mode = R.pick({ 'combine', 'replace', 'blend', 'mix' })
    end
    if R.chance(1, 8) then
      opts.url = rand_printable(R.num(4, 30))
    end
    if R.chance(1, 4) then opts.right_gravity = R.chance(1, 2) end
    if R.chance(1, 4) then opts.end_right_gravity = R.chance(1, 2) end
    if R.chance(1, 4) then opts.priority = R.num(-10, 8192) end
    local row, col
    if R.chance(1, 5) then
      row, col = R.num(-100, 100000), R.num(-10, 10000)
    else
      row, col = R.num(-2, 100), R.num(-2, 100)
    end
    pcall(api.nvim_buf_set_extmark, b, ns, row, col, opts)
  end

  function op_buf_clear_extmark()
    local b = pick_buf()
    if not b or #S.namespaces == 0 then return end
    local ns = R.pick(S.namespaces)
    pcall(api.nvim_buf_clear_namespace, b, ns,
      R.num(-10, 100), R.num(-10, 100))
  end

  function op_buf_call()
    local b = pick_buf()
    if not b then return end
    pcall(function()
      api.nvim_buf_call(b, function()
        pcall(api.nvim_buf_set_lines, 0, 0, -1, false,
              { rand_printable(R.num(0, 10)) })
      end)
    end)
  end

  -- Tabpage ops -------------------------------------------------------

  function op_tabnew() pcall(cmd, 'tabnew') end
  function op_tabclose()
    if #list_tabs() <= 1 then return end
    pcall(cmd, 'tabclose')
  end
  function op_tabnext()
    pcall(cmd, R.pick({ 'tabnext', 'tabnext', 'tabnext', 'tabprev',
                        'tabfirst', 'tablast' }))
  end
  function op_tabmove()
    if #list_tabs() <= 1 then return end
    pcall(cmd, 'tabmove ' .. R.num(-10, 10))
  end
  function op_tab_set_win()
    local t = pick_tab()
    local w = pick_win()
    if not t or not w then return end
    pcall(api.nvim_tabpage_set_win, t, w)
  end
  function op_tab_wincmd()
    local cmd_str = R.pick({ 'tabnext', 'tabprev', 'tabfirst', 'tablast',
                              'tabnew', 'tabclose', 'tab split', 'tab vsplit' })
    record_args({ cmd = cmd_str })
    pcall(cmd, cmd_str)
  end

  -- Autocmd ops ------------------------------------------------------

  function op_autocmd_create()
    local evs = { R.pick(AUTOCMD_EVENTS) }
    if R.chance(1, 3) then evs[#evs + 1] = R.pick(AUTOCMD_EVENTS) end
    local use_cb = R.chance(1, 2)
    local opts = {
      pattern = R.chance(1, 2) and R.pick({ '*', '*.lua', '*.txt', '/tmp/*' }) or nil,
      once    = R.chance(1, 5),
      nested  = R.chance(1, 5),
      group   = (#S.augroups > 0 and R.chance(1, 2))
                   and R.pick(S.augroups) or nil,
    }
    if R.chance(1, 4) then opts.buffer = pick_buf() end
    if R.chance(1, 3) then opts.desc = rand_word(R.num(2, 16)) end
    if use_cb then
      opts.callback = loadstring(CALLBACK_BODY)()
    else
      opts.command = R.pick({
        'let g:ev = expand("<amatch>")',
        'echo "x"',
        'setlocal wrap',
        'setlocal nowrap',
        'normal! gg',
        'normal! G',
        'doautocmd User FzUser',
        'call nvim_buf_set_lines(0,0,-1,false,[""])',
        'tabnew',
        'split',
      })
    end
    local ok, auid = pcall(api.nvim_create_autocmd, evs, opts)
    if ok and auid then
      S.auids[#S.auids + 1] = auid
      cap(S.auids, 64)
    end
  end

  function op_autocmd_exec()
    local ev = R.pick(AUTOCMD_EVENTS)
    local opts = {}
    if R.chance(1, 3) then opts.pattern = R.pick({ '*', '*.lua', '*.txt' }) end
    if R.chance(1, 3) then opts.buffer = pick_buf() end
    if R.chance(1, 3) then opts.modeline = R.chance(1, 4) end
    if R.chance(1, 3) then
      opts.group = (#S.augroups > 0) and R.pick(S.augroups) or nil
    end
    if R.chance(1, 3) then opts.data = { rand_printable(4) } end
    pcall(api.nvim_exec_autocmds, ev, opts)
  end

  function op_autocmd_del()
    if #S.auids == 0 then return end
    local idx = R.one_of_n(#S.auids)
    local auid = table.remove(S.auids, idx + 1)
    pcall(api.nvim_del_autocmd, auid)
  end

  function op_augroup_create()
    local name = 'fz' .. rand_word(8)
    local ok, id = pcall(api.nvim_create_augroup, name,
      { clear = R.chance(1, 3) })
    if ok and id then S.augroups[#S.augroups + 1] = id end
  end

  function op_augroup_clear()
    if #S.augroups == 0 then return end
    local id = table.remove(S.augroups, R.one_of_n(#S.augroups) + 1)
    pcall(api.nvim_del_augroup_by_id, id)
  end

  function op_autocmd_clear_all()
    pcall(api.nvim_clear_autocmds)
  end

  -- UI / option / option-like ----------------------------------------

  function op_ui_attach()
    local w, h = R.num(1, 200), R.num(1, 80)
    pcall(api.nvim_ui_attach, w, h, { ext_linegrid = R.chance(1, 2) })
  end
  function op_ui_detach() pcall(api.nvim_ui_detach) end

  function op_option_set()
    local name = R.pick(OPT_NAMES)
    local ok, kind = pcall(api.nvim_get_option_info, name)
    if not ok or not kind then return end
    local v
    if kind.type == 'boolean' or vim.tbl_contains(OPT_BOOL, name) then
      v = R.chance(1, 2)
    elseif kind.type == 'number' then
      v = R.num(-1000, 100000)
    elseif kind.type == 'string' then
      v = rand_word(R.num(2, 12))
    else
      v = R.num(-1, 1)
    end
    local opts = {}
    if R.chance(1, 3) then opts.win = pick_win() end
    if R.chance(1, 3) then opts.buf = pick_buf() end
    pcall(api.nvim_set_option_value, name, v, opts)
  end

  function op_set_var()
    local name = 'fz_' .. rand_word(6)
    local v
    local t = R.one_of_n(5)
    if t == 0 then v = rand_printable(R.num(0, 20))
    elseif t == 1 then v = R.num(-1e6, 1e6)
    elseif t == 2 then v = R.chance(1, 2)
    elseif t == 3 then
      local n = R.num(0, 5)
      local arr = {}
      for _ = 1, n do arr[#arr + 1] = rand_printable(R.num(0, 5)) end
      v = arr
    else
      local n = R.num(0, 4)
      local d = {}
      for _ = 1, n do
        d[rand_word(R.num(2, 6))] = rand_printable(R.num(0, 6))
      end
      v = d
    end
    pcall(api.nvim_set_var, name, v)
  end

  -- Input / exec / user commands -----------------------------------

  function op_input_random()
    if R.chance(1, 30) then
      local ch = string.char(R.num(1, 31))
      pcall(api.nvim_input, ch:rep(R.num(1000, 8000)))
      return
    end
    local pieces = {}
    local n = R.num(0, 6)
    for _ = 1, n do
      if R.chance(1, 4) then
        pieces[#pieces + 1] = rand_printable(R.num(0, 5))
      elseif R.chance(1, 2) then
        pieces[#pieces + 1] = rand_special_key()
      else
        pieces[#pieces + 1] = string.char(R.u8())
      end
    end
    if #pieces > 0 then
      pcall(api.nvim_input, table.concat(pieces))
    end
  end

  function op_feedkeys()
    if R.chance(1, 5) then
      pcall(api.nvim_feedkeys, rand_special_key() .. rand_special_key(),
        'L', false)
    elseif R.chance(1, 2) then
      pcall(api.nvim_feedkeys, rand_special_key(), 'n', false)
    else
      pcall(api.nvim_feedkeys, rand_printable(R.num(0, 8)), 'mx', false)
    end
  end

  function op_exec_cmd()
    if R.chance(1, 25) then
      pcall(api.nvim_exec2, 'echo ' .. string.rep('"x"', 100), {})
      return
    end
    local c = R.pick(VIM_CMDS)
    if c:find('let g:fz =') then
      c = 'let g:fz = ' .. R.num(0, 100000)
    elseif c:find('execute') then
      c = 'execute "normal! ' .. R.num(0, 100) .. 'G"'
    end
    pcall(cmd, c)
  end

  function op_eval()
    local e = R.pick({
      '1+1', '"a".."b"', 'len("foo")', 'getline(1)',
      'map([1,2,3], "v:val*2")', 'string({"a":1})',
      'range(' .. R.num(0, 20) .. ')', 'bufnr()',
      'winwidth(0)', 'winheight(0)',
      'getwininfo()', 'getbufinfo()',
      'argv()', 'argc()', 'line("$")', 'col(".")',
      'mode(1)', 'mode()', 'visualmode()',
      'garbagecollect(true)',
    })
    pcall(api.nvim_eval, e)
  end

  function op_user_command()
    local name = 'Fz' .. rand_word(6)
    S.user_cmds[#S.user_cmds + 1] = name
    cap(S.user_cmds, 32)
    local body = 'function(opts) pcall(vim.cmd, "redrawstatus") end'
    local ok = pcall(api.nvim_create_user_command, name,
      loadstring(body)(), {
        nargs = R.pick({ '*', '0', '1', '?', '+' }),
        bang = R.chance(1, 4),
        complete = R.chance(1, 3) and 'file' or nil,
      })
    if not ok then return end
    pcall(api.nvim_cmd, { cmd = name,
      args = { rand_word(R.num(0, 5)) } }, {})
  end

  function op_timer_start()
    local ms = R.num(0, 50)
    local body = 'function() pcall(vim.cmd, "redrawstatus") end'
    local opts = {}
    opts['repeat'] = R.chance(1, 5)
    local ok, t = pcall(vim.fn.timer_start, ms, loadstring(body)(), opts)
    if ok and t then
      S.timers[#S.timers + 1] = t
      cap(S.timers, 16)
    end
  end

  -- Crash-trap sequences -----------------------------------------------

  function trap_huge_input()
    pcall(api.nvim_input, ('\12'):rep(R.num(5000, 20000)))
  end

  function trap_special_key_largest()
    pcall(api.nvim_input,
      '<M-' .. vim.fn.nr2char(R.num(1, 0x7fffffff)) .. '>')
  end

  function trap_recursive_exec2()
    pcall(api.nvim_exec_lua, [[
      pcall(vim.api.nvim_create_user_command, '__FzRec', function()
        pcall(vim.api.nvim_exec2, 'echo "x"', {})
      end, {})
      pcall(vim.api.nvim_cmd, { cmd = '__FzRec' }, {})
    ]], {})
  end

  function trap_paste_weird()
    local text = string.char(0)
                .. string.char(2, 3, 6, 0x15, 0x16, 0x17, 0x18, 0x1b, 0x7f)
                .. rand_printable(R.num(0, 8))
    pcall(api.nvim_paste, text, R.chance(1, 2), R.num(-1, 3))
  end

  function trap_input_lots()
    local s = {}
    for _ = 1, R.num(200, 800) do
      s[#s + 1] = R.pick({ '<Esc>', '<CR>', 'i', 'a', 'x', 'd', 'p', 'u' })
    end
    pcall(api.nvim_input, table.concat(s))
  end

  -- Redraw coverage --------------------------------------------------

  function op_redraw()
    if R.chance(1, 4) then
      safe(cmd, 'redraw')
    else
      safe(cmd, 'redrawstatus')
    end
    if R.chance(1, 5) then
      pcall(api.nvim_ui_attach, R.num(20, 500), R.num(5, 80),
        { ext_linegrid = R.chance(1, 2) })
    end
  end

  -- Multi-step scenarios ----------------------------------------------

  function scenario_open_float_then_set_buf()
    local rel = R.pick({ 'editor', 'win', 'cursor' })
    local cfg = {
      relative = rel,
      width    = R.num(1, 200),
      height   = R.num(1, 50),
      row      = R.num(-50, 50),
      col      = R.num(-50, 50),
      focusable = R.chance(1, 2),
    }
    local buf = api.nvim_create_buf(false, true)
    local ok, win = pcall(api.nvim_open_win, buf, R.chance(1, 4), cfg)
    if not ok or type(win) ~= 'number' then
      pcall(api.nvim_buf_delete, buf, { force = true })
      return
    end
    S.floats[#S.floats + 1] = win
    cap(S.floats, 32)
    local bufs = list_bufs()
    if #bufs >= 2 then
      local other = bufs[R.one_of_n(#bufs)]
      pcall(api.nvim_win_set_buf, win, other)
    end
    pcall(api.nvim_win_set_cursor, win, {
      R.num(-100, 100000), R.num(-10, 10000),
    })
    safe(cmd, 'redrawstatus')
  end

  function scenario_extmark_then_modify_buf()
    local b = pick_buf()
    if not b then return end
    local ns = api.nvim_create_namespace(HASH_NS_PREFIX .. rand_word(6))
    S.namespaces[#S.namespaces + 1] = ns
    cap(S.namespaces, 16)
    local start_row = R.num(0, 50)
    local lines_count = R.num(1, 30)
    local ok = pcall(api.nvim_buf_set_extmark, b, ns,
      start_row, 0, {
        end_row = start_row + lines_count,
        virt_lines = {
          { { rand_printable(R.num(0, 8)), 'Comment' } },
          { { rand_printable(R.num(0, 8)), 'Error' } },
        },
        hl_mode = R.pick({ 'combine', 'replace', 'blend' }),
      })
    if not ok then return end
    local choice = R.one_of_n(3)
    if choice == 0 then
      pcall(api.nvim_buf_set_lines, b,
        R.num(-1, start_row + lines_count + 5),
        R.num(-1, start_row + lines_count + 5),
        R.chance(1, 2),
        { rand_printable(R.num(0, 20)),
          rand_printable(R.num(0, 20)) })
    elseif choice == 1 then
      pcall(api.nvim_buf_set_lines, b,
        R.num(-1, start_row), R.num(-1, lines_count + 1),
        R.chance(1, 2), {})
    else
      pcall(api.nvim_buf_set_lines, b,
        start_row + R.num(0, lines_count), 0, R.chance(1, 2),
        { rand_printable(R.num(0, 30)) })
    end
    pcall(api.nvim_buf_clear_namespace, b, ns,
      R.num(-5, 100), R.num(-5, 100))
    safe(cmd, 'redrawstatus')
  end

  function scenario_autocmd_recursive_input()
    local ev = R.pick({
      'CursorMoved', 'CursorMovedI', 'BufReadPost', 'TextChanged',
      'InsertCharPre', 'CmdlineChanged',
    })
    local body = loadstring(table.concat({
      'function(_) pcall(vim.api.nvim_buf_set_lines, 0, 0, -1, false, { vim.fn.line(".") }) end',
    }, ' '))()
    local ok, auid = pcall(api.nvim_create_autocmd, ev, {
      nested = true,
      callback = body,
      pattern = '*',
    })
    if not ok or not auid then return end
    S.auids[#S.auids + 1] = auid
    cap(S.auids, 64)
    pcall(api.nvim_input, R.pick({
      'j', 'k', 'h', 'l', 'gg', 'G', 'i<Esc>', 'a<Esc>',
      '<C-w>w', '<C-w>j', '<C-w>k',
    }))
    safe(cmd, 'redrawstatus')
  end

  function scenario_user_command_recursive_exec2()
    local name = '__FzRec' .. rand_word(4)
    local cmd_pat = 'echo "fz:" .. ("x"):rep(8)'
    local code = string.format([[
      pcall(vim.api.nvim_create_user_command, %q, function()
        pcall(vim.api.nvim_exec2, %q, {})
      end, {})
    ]], name, cmd_pat)
    pcall(api.nvim_exec_lua, code, {})
    pcall(api.nvim_cmd, { cmd = name }, {})
    safe(cmd, 'redrawstatus')
  end

  -- Newly-added high-value missing ops -------------------------------

  function op_set_decoration_provider()
    local ns
    if #S.namespaces == 0 or R.chance(1, 4) then
      ns = api.nvim_create_namespace(HASH_NS_PREFIX .. rand_word(6))
      S.namespaces[#S.namespaces + 1] = ns
      cap(S.namespaces, 16)
    else
      ns = R.pick(S.namespaces)
    end
    local opts = {}
    if R.chance(1, 2) then
      opts.on_start = function() return R.chance(1, 4) end
    end
    if R.chance(1, 2) then
      opts.on_buf = function(_, _buf, tick)
        pcall(api.nvim_buf_set_extmark, _buf, ns, 0, 0, {
          ephemeral = true,
          virt_text = { { rand_printable(R.num(0, 4)), 'Comment' } },
          virt_text_pos = 'eol',
        })
        return tick
      end
    end
    if R.chance(1, 2) then
      opts.on_win = function()
        return R.chance(1, 4)
      end
    end
    if R.chance(1, 2) then
      opts.on_line = function(_, _win, _buf, _row)
        pcall(api.nvim_buf_set_extmark, _buf, ns, _row, 0, {
          ephemeral = true, sign_text = rand_word(1),
        })
      end
    end
    if R.chance(1, 2) then
      opts.on_range = function(_, _win, _buf, br, bc, er, ec)
        pcall(api.nvim_buf_set_extmark, _buf, ns, br, bc, {
          ephemeral = true,
          end_row = er, end_col = ec,
          hl_group = R.pick({ 'Error', 'Comment', 'Search' }),
        })
      end
    end
    if R.chance(1, 2) then
      opts.on_end = function() end
    end
    pcall(api.nvim_set_decoration_provider, ns, opts)
  end

  function op_win_text_height()
    local w = pick_win()
    if not w then return end
    local opts = {}
    if R.chance(1, 3) then opts.start_row = R.num(-10, 1000) end
    if R.chance(1, 2) then opts.start_row = R.num(-1, 50) end
    if R.chance(1, 2) then opts.start_vcol = R.num(-10, 1000) end
    if R.chance(1, 3) then opts.end_row = R.num(-10, 1000) end
    if R.chance(1, 2) then opts.end_row = R.num(-1, 100) end
    if R.chance(1, 2) then opts.end_vcol = R.num(-10, 1000) end
    if R.chance(1, 2) then opts.max_height = R.num(-1, 200) end
    pcall(api.nvim_win_text_height, w, opts)
  end

  function op_exec_lua()
    local n = R.num(0, 6)
    local body
    if R.chance(1, 6) then
      body = 'error("fz: " .. (function() return ... end)())'
    elseif R.chance(1, 4) then
      body = 'pcall(vim.api.nvim_buf_set_lines, 0, 0, -1, false, { "x" })'
    elseif R.chance(1, 3) then
      body = 'pcall(vim.api.nvim_exec_lua, \'return 1\', {})'
    elseif R.chance(1, 3) then
      body = 'pcall(vim.api.nvim_command, "let g:fz_lua = 1")'
    elseif R.chance(1, 2) then
      body = 'return string.rep("a", ' .. R.num(0, 100000) .. ')'
    else
      body = 'local t = {} for i=1,' .. n .. ' do t[i]=i end return #t'
    end
    local args
    if R.chance(1, 3) then
      args = { rand_printable(R.num(0, 8)),
               R.num(-1000, 1000),
               R.chance(1, 2) }
    else
      args = {}
    end
    pcall(api.nvim_exec_lua, body, args)
  end

  function op_open_term_chan_send()
    local bufs = list_bufs()
    if #bufs == 0 then return end
    local b = R.pick(bufs)
    local opts = {}
    if R.chance(1, 2) then opts.force_crlf = R.chance(1, 2) end
    if R.chance(1, 4) then
      opts.on_input = function(_, _term, _buf, _data) end
    end
    local ok, ch = pcall(api.nvim_open_term, b, opts)
    if not ok or not ch then return end
    if R.chance(1, 3) then
      local pieces = {}
      for _ = 1, R.num(0, 8) do
        if R.chance(1, 4) then
          pieces[#pieces + 1] = string.char(R.num(1, 31))
        elseif R.chance(1, 2) then
          pieces[#pieces + 1] = rand_printable(R.num(0, 16))
        else
          pieces[#pieces + 1] = '\27[' .. R.num(0, 999) .. 'm'
        end
      end
      pcall(api.nvim_chan_send, ch, table.concat(pieces))
    end
  end

  function op_set_keymap()
    local mode = R.pick({ '', 'n', 'i', 'v', 'x', '!', 's', 'o', 'c', 't' })
    local lhs = R.pick(KEYMAP_LHS) .. R.num(0, 99)
    local opts = {}
    if R.chance(1, 3) then opts.expr = true end
    if R.chance(1, 3) then opts.nowait = true end
    if R.chance(1, 4) then opts.silent = true end
    if R.chance(1, 5) then opts.unique = true end
    if R.chance(1, 5) then opts.noremap = true end
    if R.chance(1, 4) then opts.replace_keycodes = true end
    if R.chance(1, 5) then opts.desc = rand_word(R.num(2, 12)) end
    if R.chance(1, 4) then opts.buffer = pick_buf() end
    local rhs
    if R.chance(1, 3) then
      opts.callback = loadstring(
        'function() pcall(vim.api.nvim_buf_set_lines, 0, 0, -1, false, { vim.fn.line(".") }) end'
      )()
      rhs = ''
    elseif R.chance(1, 2) then
      rhs = '"" .. vim.fn.line(".")'
    else
      rhs = R.pick({
        ':echo "x"<CR>', ':let g:fz_km = 1<CR>', '<Nop>',
        '<C-w>v', '<C-w>s', '<Esc>', 'i<Esc>', 'a<Esc>',
        rand_word(R.num(2, 10)), '',
      })
    end
    if opts.buffer then
      pcall(api.nvim_buf_set_keymap, opts.buffer, mode, lhs, rhs, opts)
    else
      pcall(api.nvim_set_keymap, mode, lhs, rhs, opts)
    end
  end

  -- Dispatch tables ---------------------------------------------------

  local OPS = {
    { w = 10, name = 'open_float',          fn = op_open_float },
    { w = 10, name = 'close_random_win',    fn = op_close_random_win },
    { w =  8, name = 'win_set_buf',         fn = op_win_set_buf },
    { w =  8, name = 'win_set_cursor',      fn = op_win_set_cursor },
    { w =  4, name = 'win_set_hl',          fn = op_win_set_hl },
    { w =  6, name = 'win_set_size',        fn = op_win_set_size },
    { w =  5, name = 'win_set_position',    fn = op_win_set_position },
    { w =  4, name = 'win_split',           fn = op_win_split },
    { w =  3, name = 'win_only',            fn = op_win_only },
    { w =  5, name = 'win_wincmd',          fn = op_win_wincmd },
    { w =  4, name = 'win_call_buf',        fn = op_win_call_buf },
    { w =  9, name = 'create_buf',          fn = op_create_buf },
    { w =  9, name = 'delete_buf',          fn = op_delete_buf },
    { w =  9, name = 'buf_set_lines',       fn = op_buf_set_lines },
    { w =  5, name = 'buf_set_name',        fn = op_buf_set_name },
    { w =  3, name = 'buf_set_mark',        fn = op_buf_set_mark },
    { w =  8, name = 'buf_set_extmark',     fn = op_buf_set_extmark },
    { w =  3, name = 'buf_clear_extmark',   fn = op_buf_clear_extmark },
    { w =  3, name = 'buf_call',            fn = op_buf_call },
    { w =  5, name = 'tabnew',              fn = op_tabnew },
    { w =  5, name = 'tabclose',            fn = op_tabclose },
    { w =  6, name = 'tabnext',             fn = op_tabnext },
    { w =  2, name = 'tabmove',             fn = op_tabmove },
    { w =  2, name = 'tab_set_win',         fn = op_tab_set_win },
    { w =  4, name = 'tab_wincmd',          fn = op_tab_wincmd },
    { w =  9, name = 'autocmd_create',      fn = op_autocmd_create },
    { w =  6, name = 'autocmd_exec',        fn = op_autocmd_exec },
    { w =  4, name = 'autocmd_del',         fn = op_autocmd_del },
    { w =  3, name = 'augroup_create',      fn = op_augroup_create },
    { w =  2, name = 'augroup_clear',       fn = op_augroup_clear },
    { w =  1, name = 'autocmd_clear_all',   fn = op_autocmd_clear_all },
    { w =  3, name = 'ui_attach',           fn = op_ui_attach },
    { w =  3, name = 'ui_detach',           fn = op_ui_detach },
    { w =  6, name = 'option_set',          fn = op_option_set },
    { w =  3, name = 'set_var',             fn = op_set_var },
    { w =  6, name = 'input_random',        fn = op_input_random },
    { w =  3, name = 'feedkeys',            fn = op_feedkeys },
    { w =  6, name = 'exec_cmd',            fn = op_exec_cmd },
    { w =  3, name = 'eval',                fn = op_eval },
    { w =  3, name = 'user_command',        fn = op_user_command },
    { w =  2, name = 'timer_start',         fn = op_timer_start },
    { w =  4, name = 'decoration_provider', fn = op_set_decoration_provider },
    { w =  4, name = 'win_text_height',     fn = op_win_text_height },
    { w =  3, name = 'exec_lua',            fn = op_exec_lua },
    { w =  2, name = 'open_term_chan',      fn = op_open_term_chan_send },
    { w =  3, name = 'set_keymap',          fn = op_set_keymap },
    { w =  3, name = 'redraw',              fn = op_redraw },
    { w =  3, name = 's_open_win_set_buf',  fn = scenario_open_float_then_set_buf },
    { w =  3, name = 's_extmark_modify_buf', fn = scenario_extmark_then_modify_buf },
    { w =  2, name = 's_autocmd_input',     fn = scenario_autocmd_recursive_input },
    { w =  2, name = 's_user_cmd_exec2',    fn = scenario_user_command_recursive_exec2 },
  }

  local TRAPS = {
    { w = 3, name = 'huge_input',          fn = trap_huge_input },
    { w = 2, name = 'special_key_largest', fn = trap_special_key_largest },
    { w = 2, name = 'recursive_exec2',     fn = trap_recursive_exec2 },
    { w = 2, name = 'paste_weird',         fn = trap_paste_weird },
    { w = 3, name = 'input_lots',          fn = trap_input_lots },
  }

  return {
    op_open_float = op_open_float,
    op_close_random_win = op_close_random_win,
    op_win_set_buf = op_win_set_buf,
    op_win_set_cursor = op_win_set_cursor,
    op_win_set_hl = op_win_set_hl,
    op_win_set_size = op_win_set_size,
    op_win_set_position = op_win_set_position,
    op_win_split = op_win_split,
    op_win_only = op_win_only,
    op_win_wincmd = op_win_wincmd,
    op_win_call_buf = op_win_call_buf,
    op_create_buf = op_create_buf,
    op_delete_buf = op_delete_buf,
    op_buf_set_lines = op_buf_set_lines,
    op_buf_set_name = op_buf_set_name,
    op_buf_set_mark = op_buf_set_mark,
    op_buf_set_extmark = op_buf_set_extmark,
    op_buf_clear_extmark = op_buf_clear_extmark,
    op_buf_call = op_buf_call,
    op_tabnew = op_tabnew,
    op_tabclose = op_tabclose,
    op_tabnext = op_tabnext,
    op_tabmove = op_tabmove,
    op_tab_set_win = op_tab_set_win,
    op_tab_wincmd = op_tab_wincmd,
    op_autocmd_create = op_autocmd_create,
    op_autocmd_exec = op_autocmd_exec,
    op_autocmd_del = op_autocmd_del,
    op_augroup_create = op_augroup_create,
    op_augroup_clear = op_augroup_clear,
    op_autocmd_clear_all = op_autocmd_clear_all,
    op_ui_attach = op_ui_attach,
    op_ui_detach = op_ui_detach,
    op_option_set = op_option_set,
    op_set_var = op_set_var,
    op_input_random = op_input_random,
    op_feedkeys = op_feedkeys,
    op_exec_cmd = op_exec_cmd,
    op_eval = op_eval,
    op_user_command = op_user_command,
    op_timer_start = op_timer_start,
    op_redraw = op_redraw,
    op_set_decoration_provider = op_set_decoration_provider,
    op_win_text_height = op_win_text_height,
    op_exec_lua = op_exec_lua,
    op_open_term_chan_send = op_open_term_chan_send,
    op_set_keymap = op_set_keymap,
    trap_huge_input = trap_huge_input,
    trap_special_key_largest = trap_special_key_largest,
    trap_recursive_exec2 = trap_recursive_exec2,
    trap_paste_weird = trap_paste_weird,
    trap_input_lots = trap_input_lots,
    scenario_open_float_then_set_buf = scenario_open_float_then_set_buf,
    scenario_extmark_then_modify_buf = scenario_extmark_then_modify_buf,
    scenario_autocmd_recursive_input = scenario_autocmd_recursive_input,
    scenario_user_command_recursive_exec2 = scenario_user_command_recursive_exec2,
    rand_special_key = rand_special_key,
    rand_event = rand_event,
    rand_printable = rand_printable,
    rand_buf = rand_buf,
    rand_word = rand_word,
    CAP = cap,  -- also aliased as plain `cap`
    cap = cap,
    OPS = OPS,
    TRAPS = TRAPS,
  }
end

return M
