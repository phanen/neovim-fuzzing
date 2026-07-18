# Crash Patterns: Quick Summary

A one-page cheat sheet. The other docs in this folder drill down.

## Top 5 patterns a fuzzer should hit

1. **autocmd re-entrancy on window close** (#31236, #37211,
   #13265, #13231). A `WinLeave` / `WinClosed` / `BufUnload`
   callback opens a new window, deletes a buffer, or closes
   another window. The autocmd fires while the original caller is
   mid-`free`.

2. **last-non-float window in last tabpage** (#30425, #17796).
   `:bdelete` when a float is the only buffer in its tab, or
   closing the last non-current tab when a float is anchored to it.

3. **extmark + signcolumn/statuscolumn** (#27127, #32849,
   #33067, #27209). `signcolumn=auto:N` or `statuscolumn="%s%l"`
   plus extmarks with `sign_text` plus a buffer mutation plus a
   `:undo`.

4. **undolevels=-1 + extmark** (#24894). The undo header is NULL,
   `u_extmark_copy` calls into a NULL pointer.

5. **libvterm VLA stack-overflow** (#16040, #19075). `chansend`
   of ~12k lines into `nvim_open_term`.

## Weight recipe

If you are tuning a fuzzer's dispatch weights to bias toward these
patterns, a recipe that has found new regressions in practice:

```
window ops                  25%
  open_float                10
  close_random_win          10
  win_set_buf                5
buffer ops                  25%
  buf_set_extmark           12
  buf_set_lines             10
  create_buf                 3
autocmd ops                 15%
  autocmd_create             8
  autocmd_exec               4
  autocmd_del                3
signcolumn / statuscolumn    8%
extmark scenarios            8%
last-tab + float scenarios   7%
terminal chansend            7%
misc                         5%
```

Compared to `fuzz.lua`'s default distribution, the change is to
push `signcolumn` / `statuscolumn` into their own ops (rather than
random `option_set` values), add a small explicit `extmark scenarios`
bucket, and dedicate a non-trivial slice to the last-tab + float
boundary.

## What `fuzz-crashhunter.lua` does differently from `fuzz.lua`

- Smaller op surface (40 ops vs 50+), but the dispatch weights
  are biased toward the top-5 patterns above.
- Explicit scenarios for the autocmd-reentrancy patterns
  (close-window callback, delete-buf callback, on_lines callback).
- Explicit `statuscolumn_set` and `signcolumn_set` ops, not
  random strings.
- A `term_chan_send_huge` scenario for #16040.
- Smaller `ROUNDS` default (500) so AFL finds the high-value
  inputs in fewer iterations.

`fuzz.lua` is the broad-coverage harness. `fuzz-crashhunter.lua`
is the targeted harness for these patterns. Both share
`lib/fuzz-common.lua` for PRNG and state teardown.