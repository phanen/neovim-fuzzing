# Extmark State Machine Crash Patterns

`extmark_splice_impl` is a single C function that rewrites the
marktree after any buffer mutation. It runs on every
`nvim_buf_set_lines`, `nvim_buf_set_text`, undo, redo, and any
`nvim_buf_set_extmark` with `invalidate=true`.

After the splice, four subscribers need to be informed:

```
  extmark_splice_impl
       |
       +--> marktree itself          (always)
       |
       +--> buf_signcols_count_range (signcolumn rendering)
       |
       +--> buf_decor_remove         (statuscolumn + extmark hl)
       |
       +--> extmark_clear            (invalidate=true path)
```

The crash happens when a subscriber walks the marktree before
`b_prev_line_count` has been updated, or after the marktree node
it depends on has been removed by the same splice.

## Pattern A: signcolumn=auto:N + extmark + buf_set_buf (#27127)

```
vim.opt.signcolumn = 'auto:3'
ns = nvim_create_namespace('')
nvim_buf_set_extmark(buf, ns, 0, 0, { sign_text = 'h' })
nvim_win_set_buf(0, nvim_create_buf(false, true))
nvim_buf_delete(buf, { unload = true, force = true })
nvim_buf_set_lines(buf, 0, -1, false, { '' })   -- ASAN: heap-use-after-free
```

The crash path: the extmark is registered against `buf`. When
`nvim_win_set_buf` swaps the window's buffer, the extmark is
unhooked but the signcol counter still holds a stale `b_prev_line_count`
referencing the now-orphaned extmark. When `nvim_buf_set_lines`
runs the splice, `buf_signcols_count_range` walks the stale pointer.

## Pattern B: undolevels=-1 + nvim_buf_set_lines (#24894)

```
local buf = nvim_create_buf(false, true)
nvim_buf_set_option(buf, 'undolevels', -1)
nvim_buf_set_lines(buf, 0, 1, false, {})
```

`undolevels=-1` means "no undo header at all." `u_force_get_undo_header`
returns NULL but `u_extmark_set` still tries to splice the marktree
on the undo path. Splice with a NULL header crashes.

## Pattern C: statuscolumn + extmark + ModeChanged (#32849)

```
vim.o.statuscolumn = '%s%l'
local ns = nvim_create_namespace('fz')
nvim_buf_set_extmark(buf, ns, 0, 0, { sign_text = 'h' })
-- user runs <C-v>, j, j, <Esc>
```

The statusline render path calls `build_stl_str_hl`, which reads
`b_signcols_count_range`. While the user is in visual mode and
extmark splice happens, `buf_decor_remove` is called before
`b_signcols_count_range` is updated.

## Pattern D: extmark invalidate=true + undo (#27209)

```
local ns = nvim_create_namespace('fz')
nvim_buf_set_extmark(buf, ns, 0, 0, { invalidate = true })
-- user runs :undo
```

`invalidate=true` marks the extmark to be cleared on the next
splice. The splice happens on `:undo`. `extmark_clear` is called
from the splice path, but `buf_signcols_count_range` was already
frozen with the old (pre-clear) extmark as the basis for its
count.

## What the upstream PRs did

The recurring fix in this area has been to introduce or update
`b_prev_line_count`:

- PR #33410 added `b_prev_line_count` and forced
  `buf_signcols_count_range` to consult it before reading the
  marktree. Reduces but does not eliminate the class; #33067
  persists into 0.11 because the order of operations is still
  "splice first, count second" in some code paths.
- PR #27128 reordered `extmark_splice_impl` to release the
  marktree references before invoking
  `buf_signcols_count_range`. This was the fix for #27127.
- PR #27215 added a NULL check in `extmark_clear` for the
  `undolevels=-1` path. This was the fix for #27209.

## Fuzzer exercises

`fuzz-crashhunter.lua` has these patterns:

- `scenario_extmark_set_then_buf_set_lines` (the #27127
  shape): install a signcol/auto extmark, then mutate the buffer.
- `scenario_statuscolumn_with_extmark` (the #32849 shape):
  set `statuscolumn`, install an extmark, then run
  visual-mode inputs through `nvim_input`.
- `op_set_statuscolumn` and `op_set_signcolumn` (the #32849 /
  #33067 shape): explicit option-set ops with edge values.
- `op_set_extmark_invalidate_then_undo` (the #27209 shape):
  install an `invalidate=true` extmark, then run `undo` / `<C-r>`.

The signcolumn / statuscolumn option setters have their own ops
(not just `option_set`'s default value) because the auto:N value
in particular interacts with the signcol counter, and a default
random string/number does not exercise it.