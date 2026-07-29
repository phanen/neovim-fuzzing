# Newer crash patterns

Patterns 6-11 from `00-summary.md`. Pulled from neovim's
functional API tests, not from CVEs. Each entry lists the
upstream test, the test's reproduction shape, the fuzzer's
scenario, and the rationale.

## 6. `nvim_echo` + custom `kind` + redraw

- Upstream: `test/functional/api/vim_spec.lua:4280-4296`
  ("no use-after-free for custom kind with :messages #38289")
- Issue: #38289 (use-after-free in `ui_flush -> arena_mem_free`)
- Reproduction shape:
  ```
  vim.api.nvim_echo({ { 'a' } }, true, { kind = 'foo' })
  vim.o.guicursor = ''
  vim.api.nvim__redraw({ flush = true })
  vim.cmd.messages()
  ```
- Fuzzer scenario: `scn_nvim_echo_arena_free`
  - `nvim_echo` with a custom `kind` (one of `progress`, `status`,
    `diagnostic`, `quickfix`, `completion`, `history`, `search`,
    `tabpage`, `command`, `lua`, `foo`, `bar`).
  - `nvim_set_option_value('guicursor', <random valid value>)`
  - `nvim__redraw({ flush = true })`
  - `:messages`
- Why custom kinds? The bug was on the path that handles
  user-defined kinds, not the well-known ones (`echo`, `echomsg`,
  `echoerr`, `lua_print`). Biasing toward custom kinds reaches the
  buggy branch.

## 7. `nvim__redraw` variants

- Upstream: `test/functional/api/vim_spec.lua:6133-6430`
  (the entire `nvim__redraw` describe block + range + topline
  subsections)
- Reproduction shape: every flag combination has a test. The
  union of `{cursor, statusline, statuscolumn, tabline, winbar,
  range, valid, flush}` x `{buf, win, both}` has been a steady
  source of stale-pointer / flush-ordering bugs.
- Fuzzer scenario: `scn_nvim_redraw_flush`
  - One of 7 randomly chosen flag sets per round, plus an optional
    `flush=true` overlay and an optional `win=` to widen the
    dispatch.
- `nvim__redraw` is the entry point for the arena_flush /
  ui_flush / status_flush paths. Every flag set exercises a
  different subset of those paths.

## 8. Long pattern in `nvim_create_autocmd`

- Upstream: `test/functional/api/fast_spec.lua:97`
  ("do not trigger os_breakcheck()" — the `aupat` variable)
- Reproduction shape:
  ```
  local aupat = ('a'):rep(80000)
  vim.api.nvim_create_autocmd('User', { pattern = aupat,
    callback = function() end })
  ```
- Fuzzer scenario: `scn_long_pattern_autocmd`
  - Random pattern shape: 1k-80k of `a`, 100-5k of `?`,
    100-1k of `/`, or 80k of printable ASCII.
  - Random event from `{BufRead, BufReadPost, FileType, User}`.
  - Empty callback body so the bug is in registration, not
    dispatch.
- Why long patterns? They stress the autotree regex compilation
  path and the E339 "Pattern too long" limit. Different shapes
  route through different compilation branches (literal `a`,
  glob `?`, regex `/`, mixed printable).

## 9. popmenu / wildmenu close race

- Upstream: `test/functional/ui/popupmenu_spec.lua`,
  `test/functional/vim/wildmenu_spec.lua`
- Reproduction shape: open the wildmenu with `wildoptions=pum`
  then feed keys that close it abruptly (`<Esc>`, `<C-c>`,
  `<C-y>`, `<C-e>`).
- Fuzzer scenario: `scn_popmenu_wildmenu`
  - Set `wildmenu=true` and `wildoptions` to one of `''`, `'pum'`,
    `'pum,tag'`, `'tag,pum'`.
  - Feed one of `i<Tab>`, `i<S-Tab>`, `i<Up>`, `i<Down>`,
    `i<Esc>`, `i<C-c>`, `i<CR>`, `i<C-y>`, `i<C-e>`.
- The pum + mode transition has been a redraw race source. Mode
  flips from insert to normal while a pum is open go through a
  re-entrancy check that has had bugs.

## 10. Timer callback in fast-event

- Upstream: `test/functional/lua/timer_spec.lua`
- Reproduction shape:
  ```
  vim.fn.timer_start(0, function()
    pcall(vim.api.nvim_buf_set_lines, 0, 0, -1, false, { 'tmr' })
  end, {})
  ```
- Fuzzer scenario: `scn_timer_fast_event`
  - Random `ms` in `[0, 30]` (the fast-event window is short).
  - Random body from 5 candidates: `nvim_buf_set_lines`,
    `redrawstatus`, `vim.fn.byteidx`,
    `nvim_create_autocmd`, `nvim__redraw({flush=true})`.
- Timer callbacks run in a fast-event context where most API
  functions are forbidden. `pcall` catches the error, but the
  error path itself has been buggy (some paths assume the
  caller is in a normal event).

## 11. `nvim_buf_attach` in a fast-event with `on_lines` reentry

- Upstream: `test/functional/lua/buffer_updates_spec.lua`
  (the `on_lines` reentry cases, the `attach/detach cycle`,
  and the `on_detach` chain tests)
- Reproduction shape:
  ```
  vim.fn.timer_start(0, function()
    pcall(vim.api.nvim_buf_attach, <buf>, false, {
      on_lines = function(_, b)
        pcall(vim.api.nvim_buf_set_lines, b, -1, -1, false, { 'fl' })
      end,
      on_detach = function() end,
    })
  end, {})
  vim.api.nvim_buf_set_lines(<buf>, 0, 0, true, { 'fire' })
  ```
- Fuzzer scenario: `scn_buf_attach_in_fast_event`
  - Random `ms` in `[0, 30]`.
  - Body builds an `attach + on_lines` closure with the picked
    target buffer id baked in.
  - Outer code triggers the on_lines by mutating the buffer.
- `nvim_buf_attach` is normally forbidden in a fast-event; the
  timer callback path makes it run anyway. The combination of
  attach-in-fast-event + on_lines reentry has been a state-
  machine bug source.

## Discovery mechanics

These patterns were not in the original top-5 because they did
not show up as CVEs or as AFL-found bugs in the public issue
tracker at the time the harness was written. They were added
because scanning `test/functional/api/*.lua` for autocmd
reentrancy, callback fast-event handling, and redraw state
machine edges turned up:

- `nvim_echo` -> `:messages` -> `nvim__redraw` paths in
  `vim_spec.lua` (the comment `arena_mem_free go brrr` made
  it obvious).
- `nvim__redraw` flag combinations in `vim_spec.lua:6133-6430`.
- 80k pattern + autocmd in `fast_spec.lua:97`.
- `wildoptions=pum` + abrupt close in `popupmenu_spec.lua`.
- `vim.fn.timer_start` body errors in `lua/timer_spec.lua`.

The pattern-recognition heuristic was: any test that exercises a
re-entry path into the API, or any test that mutates state while
a redraw is pending, or any test that calls a normally-forbidden
function from a fast-event context.

## Coverage check

To verify these patterns actually fire from the harness:

```
$ nvim --headless --clean -i NONE -n -l fuzz-crashhunter.lua 777 200 log=/tmp/fz.log
$ grep -oE 'name="vim\.api\.[^"]+"' /tmp/fz.log | sort -u
```

The output should include `nvim_echo`, `nvim__redraw`,
`nvim_chan_send`, `nvim_set_decoration_provider`,
`nvim_buf_attach`, `nvim_create_autocmd` (with long patterns),
`nvim_open_term`, and `nvim_buf_set_keymap`. If any of those is
missing, increase `ROUNDS` or set a seed with more byte
variation.