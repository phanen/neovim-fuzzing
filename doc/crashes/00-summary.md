# Crash Patterns: Quick Summary

A one-page cheat sheet. The other docs in this folder drill down.

## Top patterns a fuzzer should hit

The five originally documented patterns have been augmented with
six newer ones pulled from neovim's functional API tests; see
`07-newer-patterns.md` for the sources.

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

6. **`nvim_echo` + custom `kind` + redraw** (#38289).
   `vim.api.nvim_echo(..., true, {kind='foo'})` then
   `set guicursor=` then `nvim__redraw({flush=true})` then
   `:messages`. The original test comment was
   `ui_flush -> arena_mem_free go brrr`. A pending redraw was
   capturing a stale pointer that the flush freed.

7. **`nvim__redraw` variants**. The full set in
   `vim_spec.lua:6133-6430` (range / valid / cursor / statusline /
   statuscolumn / winbar / tabline / flush) is a state machine that
   has produced several stale-pointer bugs. Any random subset
   combined with `flush=true` is worth exercising.

8. **80k-byte pattern in `nvim_create_autocmd`** (`fast_spec.lua:97`).
   Long patterns stress the autotree regex compilation path and
   `E339: Pattern too long`. Also worth covering patterns of mixed
   glob / literal shapes that route through different compilation
   branches.

9. **popmenu / wildmenu closed without selection**. Opening a
   pum via `wildoptions=pum` and abruptly closing it via `<Esc>`,
   `<C-c>`, `<C-y>`, `<C-e>` has been a redraw race source.

10. **timer callback in fast-event**. `vim.fn.timer_start` callback
    runs in a fast-event context where many API functions are
    forbidden. Calling them triggers an error path; calling the
    safe subset from there exercises the fast-event -> normal-event
    transition.

11. **`nvim_buf_attach` in a fast-event (timer) callback** that
    re-enters the API on the `on_lines` path. Reentry through the
    fast-event boundary has been a state-machine bug source.

## Weight recipe

If you are tuning a fuzzer's dispatch weights to bias toward these
patterns, the live weights in `fuzz-crashhunter.lua` are:

```
window ops                  ~12%
  open_float                10
  close_random_win          10
  win_set_buf               8
buffer ops                  ~12%
  create_buf                9
  delete_buf                9
  buf_set_lines             9
  buf_set_extmark           8
signcolumn / statuscolumn    9%
  set_statuscolumn          5
  set_signcolumn            4
extmark scenarios           ~14%
  scn_extmark_buf_set_lines 10
  scn_statuscol_extmark     10
  scn_extmark_invalidate     8
  scn_undo_set_lines         6
last-tab + float            ~17%
  scn_last_tab_float_close   9
  scn_bdelete_float_other    8
autocmd reentrancy          ~95%
  (20 scenarios, weights 5-10 each)
terminal chan-send          ~10%
  scn_chan_send_huge         6
  scn_chan_send_ansi_burst   4
  open_term_chan             2
newer patterns (B6-B11)     ~30%
  scn_nvim_echo_arena_free   8
  scn_nvim_redraw_flush      7
  scn_long_pattern_autocmd   6
  scn_popmenu_wildmenu       5
  scn_timer_fast_event       4
  scn_buf_attach_in_fast     5
redraw                       3%
misc                         ~5%
```

The percentages add up to >100 because the dispatch weights are
relative, not percentages. The OPS table is a single flat list; see
`SCENARIOS` and `EXTRA_OPS` in `fuzz-crashhunter.lua`.

## What `fuzz-crashhunter.lua` does differently from a broad fuzzer

- Smaller op surface (~50 ops from `lib/fuzz-ops.lua` plus 6
  helper ops) plus ~35 targeted scenarios.
- Dispatch weights are biased toward the patterns above.
- Explicit scenarios for the autocmd-reentrancy patterns
  (close-window callback, delete-buf callback, on_lines callback).
- Explicit `statuscolumn_set` and `signcolumn_set` ops, not
  random strings.
- A `term_chan_send_huge` scenario for #16040.
- `scn_nvim_echo_arena_free` for #38289.
- `scn_nvim_redraw_flush` for the nvim__redraw variant set.
- `scn_long_pattern_autocmd` for the 80k pattern path.
- `scn_popmenu_wildmenu` for the pum close race.
- `scn_timer_fast_event` and `scn_buf_attach_in_fast_event` for
  the fast-event reentry paths.
- Round-mixed weighted dispatch (every round XORs the round
  counter into the u32, so the PRNG cycle does not collapse a
  200-round standalone run to 3-4 ops).
- Smaller `ROUNDS` default (500) so AFL finds the high-value
  inputs in fewer iterations.

The broad-coverage harness lives in `lib/fuzz-ops.lua`; the
targeted harness for these patterns lives in
`fuzz-crashhunter.lua`. Both share `lib/fuzz-common.lua` for
PRNG, weighted dispatch, varied-callback factory, behavior
pools, and api/cmd log proxies.

## Architecture

`fuzz-crashhunter.lua` is a thin layer (~250 lines of actual
logic) over two libraries:

- `lib/fuzz-common.lua`: PRNG, byte-stream helpers, random text
  generators, win/buf/tab picking, teardown, weighted dispatch,
  varied-callback factory, behavior pools, arg serializer, api/cmd
  log proxies.
- `lib/fuzz-ops.lua`: the 50-ish basic op functions and the trap
  set. `F.install(ctx)` returns an `ops` table whose `OPS` and
  `TRAPS` fields drive the dispatch.

`fuzz-crashhunter.lua` defines only the scenarios (the glue that
combines autocmd registration + varied callback + triggering op +
optional follow-up). Scenarios are appended to `ops.OPS` to form a
single weighted dispatch that the main loop walks.