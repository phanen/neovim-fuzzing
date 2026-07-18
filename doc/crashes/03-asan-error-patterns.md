# ASAN Error Patterns

Neovim's CI runs with `-fsanitize=address,undefined` for all
in-tree tests and most build artifacts. Every fuzzer in this repo
expects an ASan/UBSan build of `nvim` (see `scripts/build-nvim.sh`).

The classifier below maps an ASAN report line back to the area of
the API that produced it. When the fuzzer's AFL signal arrives as
"ASAN:DEADLYSIGNAL" or "ASAN: heap-use-after-free", the table tells
you which subsystem to suspect.

## Signal-level classes

`SIGSEGV` (signal 11) is what most crashes look like from the
outside. With ASan off, every entry below would have shown up as a
plain SIGSEGV. With ASan on, the signal is preceded by an
`==PID== ERROR: AddressSanitizer: <class>` line. Always read that
line before the stack trace; the class is the single most useful
piece of information.

| ASAN class                | What it means                                      | Common root         |
|---------------------------|----------------------------------------------------|---------------------|
| `heap-use-after-free`     | Read/write of freed heap memory                    | autocmd reentrancy  |
| `heap-buffer-overflow`    | OOB read/write on a still-live heap object         | extmark / fold      |
| `stack-buffer-overflow`   | OOB on the C stack                                 | libvterm VLA        |
| `stack-overflow`          | Recursion or huge VLA exhausted the stack          | recursive `exec2`   |
| `stack-use-after-return`  | Read of a stack variable after the frame returned  | `uv_connect_t`      |
| `SEGV on unknown address: 0x000000000000` | NULL deref                  | `set_curbuf` edge   |
| `ABRT (assert failed)`    | Internal vim assertion                             | const + mapnew      |

## 1. heap-use-after-free

This is the dominant ASAN class in the issue set. The pattern is
always the same shape:

```
READ of size N at 0x... thread T0
    #0 <reader>            src/nvim/<area>.c:<line>
    ...
freed by:
    #N win_free_mem        src/nvim/window.c:3325
    #N win_close_othertab  src/nvim/window.c:3280
    ...
allocated by:
    #N win_alloc           src/nvim/window.c:5462
    #N win_new_float       src/nvim/winfloat.c:61
    #N nvim_open_win       src/nvim/api/win_config.c:286
```

The reader is typically `update_window_hl`, `screen.c` redraw, or
any `update_topline` style frame walker. The freed-by path is
`nvim_win_close` -> `win_close_othertab` -> `win_free_mem`. The
allocated-by path is `nvim_open_win`.

Mapping to issues: #31236, #37211, #30425, #17796, #13265, #13231,
#13699, #12890, #27127, #27209, #33067, #32849, #25254.

Defensive heuristics an issue report should record:

- The window/buffer handle the reader was holding.
- Whether the reader was triggered from `update_screen`,
  `update_window_hl`, `build_stl_str_hl`, `eval`, or a Lua
  userdata method.
- The autocmd chain that triggered the close: usually
  `BufLeave -> WinLeave -> WinClosed` or
  `BufWipeout -> BufUnload`.

## 2. heap-buffer-overflow

Looks like:

```
WRITE of size 1 at 0x... thread T0
    #0 schar_from_ascii    screen.c:5240
    #1 ...
```

Common roots:

- `extmark_splice` writes beyond the line allocation (#12988 fold
  case, #27127 signcol case, #33067 prev-line-count case).
- Tree-sitter capture cursor writes past the capture buffer
  (#14369).
- Termkey `keyinfo[64]` overrun when a fast serial produces an
  unbounded CSI escape sequence (#32113).

## 3. stack-buffer-overflow / stack-overflow

Two distinct causes:

a. Libvterm VLA: `uint32_t codepoints[len]` in
   `libvterm/src/state.c:on_text()`. A long paste allocates a VLA
   the size of the input (#16040, #19075). The nvim-side fix is to
   buffer chansend chunks; the libvterm-side fix is to use `malloc`.

b. Recursive Lua callback: `nvim_exec2` reentered from inside a
   `nvim_create_user_command` body and not guarded by `textlock`
   (#13265 family).

## 4. stack-use-after-return

```
READ of size 4 at 0x... thread T0
    #0 <consumer>          src/nvim/<area>.c
freed by:
    #N <stack frame>       (the function that returned)
```

This is the signature of `#32883`: `uv_connect_t` allocated on the
stack of `remote_request`, then libuv calls back into
`uv__stream_destroy` after the function returns. The fix is to
heap-allocate the connect struct. The fuzzer pattern is
`nvim --server <ip>:<port> --remote-ui` against an unreachable
target.

## 5. SIGABRT (assertion failure)

Vim has many `assert(...)` macros throughout the evaluator.
`#35415` is the only one in this set: `mapnew(g:xs[i], { -> 0 })`
twice into `const` slots triggers `tv_item_lock` -> `set_var_const`
assertion. The nvim-side fix mirrors vim 8.2.1672.

Other common aborts that don't appear in the issue set but the
fuzzer can hit:

- `ml_line_invalid` in memline.c when an undo history references a
  freed line.
- `ga_concat_redraw` in eval.c when `garbagecollect(true)` is
  called from `nvim_eval` with a Lua side already holding a
  userdata.

## What to do when the ASAN class is unclear

If the report is truncated (often the case with AFL):

1. Check `ASAN_OPTIONS=symbolize=1:abort_on_error=1` in the runner.
2. Run with `--halt-on-error=1` and `--print-suppressions=0` to keep
   AFL output minimal.
3. The `freed by:` and `allocated by:` stacks are the highest-value
   parts of an ASAN report. If both are present, the fuzzer should
   bias the next run toward the API in `allocated by:` to get a
   shorter reproducer.

The `fuzz-crashhunter.lua` fuzzer in this repo biases its weights
toward the operations that historically trigger classes 1 (UAF) and
2 (heap-buffer-overflow); classes 3 and 4 require deeper host
configuration but are exercised opportunistically when present.