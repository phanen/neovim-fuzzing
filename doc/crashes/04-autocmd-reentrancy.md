# Autocmd Re-entrancy Crash Patterns

The most reliable crash class in the issue set: an autocmd callback
re-enters a window/buffer/tabpage API while the original caller is
mid-operation. The autocmd target often holds a `winref_T` /
`bufref_T` that was supposed to defend against this, but the
defense has gaps around the last-non-float window and the last
tabpage.

## Pattern 1: autocmd opens a float during WinLeave (#31236)

```
WinLeave -> callback runs
  -> nvim_create_buf + nvim_open_win
  -> win_new_float allocates wp, attaches to current tabpage
user runs :tab split then :q
tabpage close path frees the new float
```

Why it crashes: `WinLeave` is fired while a window switch is in
progress. The new float gets registered into the outgoing tabpage's
frame tree. When the tabpage is closed, `win_close_othertab` walks
the new tree, but `frame2win` is called on a `frp == 0x0`
because the altwin lookup races the frame teardown.

The fix (PR #34943) holds a reference to the current tabpage
across the autocmd dispatch and re-checks `alt_tabpage()` after.

## Pattern 2: autocmd opens a float during WinClosed (#37211)

```
WinClosed -> callback runs
  -> nvim_buf_delete on the closing buffer
  -> nvim_open_win on the current tabpage (which has 0 windows now)
```

Why it crashes: `nvim_buf_delete` triggers a cascade that frees
the closing window's frame, but the callback then asks for a new
float on a tabpage that briefly had no windows. `win_close_othertab`
is later called on the closing window and walks a `wp` whose
parent frame was set up by the float. The float's parent frame
frees before `win_close` finishes.

## Pattern 3: autocmd deletes a buf during BufUnload (#33603)

```
BufUnload -> callback runs
  -> nvim_buf_delete on a *different* buffer in the same tabpage
```

Why it crashes: `BufUnload` fires while the buffer is still being
freed. The callback's `nvim_buf_delete` cascades through
`do_buffer_ext` -> `close_windows` -> `win_close_othertab`, which
hits `close_last_window_tabpage` -> `leave_tabpage` while the
caller is still inside `do_bufdel`.

## Pattern 4: BufLeave from inside :bd (#19608)

```
nvim_buf_set_lines(b, 0, 1, false, {}) -> creates undo entry
:delete  -> does not push undo, but mangles extmark tree
:undo    -> u_extmark_set walks corrupted marktree -> UAF
```

This is technically not autocmd reentrancy, but it shares the
shape: a sequence of operations leaves the buffer's marktree in a
state where a subsequent caller sees a stale node.

## Pattern 5: on_lines callback closes window (#13231)

```
nvim_buf_attach(buf, false, { on_lines = function() nvim_win_close(0, true) end })
nvim_buf_set_lines(buf, 0, 0, true, {})  -> fires on_lines
                                            -> nvim_win_close(0)
                                            -> win_free_mem
                                            -> window.c:2892 uses freed wp
```

The fix in PR #13240 added a `textlock` check that prevents
mutating window state from inside a buffer-callback context. The
class still triggers when the check is bypassed by user code
(`vim.cmd` from inside an autocmd) or when the check is incomplete
(#33603).

## Common defense in nvim core

Three layers:

1. `winref_T` / `bufref_T` -- captures a stale handle and prevents
   deref after free.
2. `textlock` -- a counter on the current execution context that
   disallows mutating window/buffer state from inside a callback.
3. `aucmd_prepbuf` / `aucmd_restbuf` -- bracket a section of code
   to be autocmd-aware, swapping in a "no-current-buffer" state.

The combination fails when:

- An autocmd fires across two different autocmd events (BufUnload
  then WinClosed), each with its own textlock layer.
- A Lua callback schedules a `vim.schedule(...)` that re-enters
  the API after the original autocmd has returned; the textlock
  counter has been decremented but the buffer state is still
  mid-teardown.
- The autocmd is `WinClosed` (post-free) and the callback calls
  `nvim_buf_delete` on a buffer that was attached to the just-
  freed window.

## Fuzzer exercises

`fuzz-crashhunter.lua` has explicit scenarios for these patterns:

- `scenario_last_tab_float_close`: opens a float in tab A,
  switches to tab B (the only other tab), closes tab B. Models
  #31236, #37211, #30425, #17796.
- `scenario_autocmd_reentrant_close_win`: installs a `WinClosed`
  callback that closes another window. Models #37211, #13265.
- `scenario_autocmd_reentrant_buf_delete`: installs a `BufUnload`
  callback that deletes another buffer. Models #33603, #19608.
- `scenario_on_lines_closes_win`: installs a `nvim_buf_attach`
  callback that closes the window. Models #13231.

Each scenario has a higher dispatch weight than the equivalent
plain op. The reason: the autocmd re-entrancy paths are not
discoverable by individual API calls. They require the autocmd to
be installed *first*, then a *triggering* op fires it. A fuzzer
that biases dispatch toward scenarios rather than independent ops
finds these bugs in O(1) rounds instead of O(N) where N is the
state-space of window/buffer combinations.