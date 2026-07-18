# Crash by Subsystem

The fragility ranking below comes from the issue set in
`01-top-crashes-table.md`. Numbers are approximate; the rank order
itself is stable.

```
  +--- 1. Window / Frame / Float ------------------------ ~30%
  +--- 2. Buffer / extmark / signcolumn --------------- ~25%
  +--- 3. Autocmd / user callback ---------------------- ~20%
  +--- 4. UI / Terminal / msgpack ---------------------- ~15%
  +--- 5. Lua API / Tree-sitter ------------------------  ~5%
  +--- 6. Internal state (loclist / quickfix / tab) ----  ~5%
```

## 1. Window / Frame / Float

The dominant crash class. `winframe_*` functions walk `frp` chains
that get freed mid-iteration when an autocmd opens or closes a
floating window. The UAF manifests as either:

- A NULL deref of `alt_tabpage()` / `frame2win()` because the
  closing tabpage already removed its root frame.
- A heap-use-after-free in `update_window_hl` because the window
  pointer was freed by `win_free_mem()` but the screen-redraw code
  still has a reference (`curwin`, `wp`, or a captured `winref_T`).

Triggers (paraphrased from issues):

- `:bdelete` when a float is the only buffer in its tab (#17796).
- `:LspInfo | tabnew | %bd` (#30425) — float in tab A, deleting all
  buffers in tab B frees the holder window that tab A's float
  referenced.
- A `WinLeave` autocmd that opens a float, then `:tab split; :q`
  closes the only non-current tab (#31236).
- `WinClosed` autocmd that does `nvim_buf_delete` plus
  `nvim_open_win` on the same dispatch (#37211).
- `terminal` + `split` + `quit!` after stdin closes (#35681).
- `ml_flush_line` -> `set_curbuf(prev_buf, ...)` where `prev_buf ==
  curbuf` (#35681 root cause).

Fuzzer weights to bias:

```
open_float           10     already covered
close_random_win     10     already covered
scenario_last_tab_float_close   high value, see fuzz-crashhunter.lua
scenario_bdelete_with_float      high value
```

## 2. Buffer / extmark / signcolumn

`extmark_splice_impl` rewrites the marktree. Subscribers downstream
(`buf_signcols_count_range`, sign rendering, `statuscolumn`,
`virt_text`) must observe the rewrite. The crash happens when a
subscriber reads `b_prev_line_count` (or its analogue) before
`extmark_splice_impl` updated it, then dereferences a marktree node
that has already been removed.

Triggers:

- `signcolumn=auto:N` + extmark with `sign_text` + `nvim_buf_set_buf`
  + `nvim_buf_delete` (#27127).
- `statuscolumn="%s%l"` + extmark + visual-block delete (#32849).
- `undolevels=-1` + `nvim_buf_set_lines` (#24894).
- Neovide + Gitsigns + repeated `u` (#33067).

Fuzzer weights to bias:

```
buf_set_extmark      8     already covered
buf_set_lines        9     already covered
statuscolumn_set     high value, see fuzz-crashhunter.lua
signcolumn_set       high value
extmark_invalidate_then_undo   high value
```

## 3. Autocmd / user callback

The class of issue is "autocmd fires during a window/buffer mutation
and re-enters the API on a target that has just been freed." The
canonical example: `nvim_buf_attach(buf, false, { on_lines = function()
nvim_win_close(0, true) end })` (#13231). The fix in nvim is to
require `textlock` checks before buffer callbacks can mutate other
windows; the root class of bug remains whenever those checks are
missing or incomplete.

Triggers:

- `BufUnload` autocmd that deletes another buffer in the same
  tabpage (#33603).
- `WinScrolled` autocmd that closes windows (#13265).
- `:autocmd FileType qf wincmd J` + `:grep` + tabpage switch (#13699).
- `nvim_exec_autocmds` reentered from a `:doautocmd User Fz` body.

Fuzzer weights to bias:

```
autocmd_reentrant_close_win    high value
autocmd_reentrant_buf_delete   high value
doautocmd_in_callback          high value
```

## 4. UI / Terminal / msgpack

`uv_connect_t` is allocated on the C stack by `nvim --server
ip:port --remote-ui` (#32883). When the connection fails, libuv tries
to call the closed-cb after the stack frame has already returned,
producing a `SIGSEGV` in `uv__stream_destroy`. The fix is to
heap-allocate the request struct.

`libvterm`'s `on_text` callback compiles its codepoints into a VLA
`uint32_t codepoints[len]` where `len` is unbounded (#16040). A
12,250-line paste crashes the stack.

`parse_msgpack` under `receive_msgpack` runs on a libuv stream read
callback. Large messages can under-read the buffer length and leave
the session state machine pointing at an offset that no longer
belongs to a valid msgpack region (#27859).

Fuzzer weights to bias:

```
chan_send_huge_term_paste     high value
nvim_open_term_then_chan_send high value
remote_ui_invalid_options     medium (network setup required)
```

## 5. Lua API / Tree-sitter

Treesitter maintains a `TSNode` userdata on the Lua side. The
underlying tree node can be GC'd by `tree_gc` between Lua method
calls. Most symptoms are `node_check` UAFs (#25254, #14369). FFI
plugins also store raw `Window*` / `Buffer*` handles that go stale
after the handle is freed by Lua-side code (#28946).

Fuzzer weights to bias:

```
exec_lua_with_returning_table  low (FFI not under test)
treesitter_attach_then_mutate  only relevant with parser
```

## 6. Internal state (loclist / quickfix / tabpage)

LSP diagnostics can update the loclist at the same moment
`qf_jump` reads it (#12890). `qf_update_buffer` runs while a
`FileType qf` autocmd is mutating window layouts (#13699). The fix is
serialization around the loclist lock, but third-party setups that
schedule autocmd in the `qf` flow continue to race.

## Common root cause

Five patterns cover almost every crash above:

1. `autocmd` callback re-entrancy: `nvim_buf_delete`,
   `nvim_win_close`, `nvim_open_win` called from inside a
   `WinLeave`, `BufUnload`, `WinClosed`, `BufLeave`, `WinScrolled`
   autocmd.
2. extmark + signcolumn + statuscolumn triple-sync: any subscriber
   reading `b_prev_line_count` before `extmark_splice_impl` writes
   it.
3. Async resource stack-lifetime: `uv_connect_t` and
   `uint32_t codepoints[]` VLA allocated on the C stack and then
   used by an async callback.
4. LuaJIT GC race: a Lua-side reference to a C userdata (`TSNode`,
   `Buffer*`, `Window*`) outlives the C object.
5. last-non-float + last-tabpage boundary: closing the last non-
   floating window in the last tabpage can free the holder window
   referenced by a float in another tab.

`fuzz-crashhunter.lua` is built around the first three patterns;
they are the highest-density targets in the issue set.