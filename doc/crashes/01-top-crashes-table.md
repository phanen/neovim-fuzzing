# Top Neovim Crash Issues (2022-2026)

A flat list of the upstream issues referenced throughout this folder.
Issues are listed in roughly the order a fuzzer should target them:
window / autocmd re-entrancy first, then extmark state, then async
resource lifetime.

| Issue  | Subsystem         | ASAN class            | Reproducer hint                                |
|--------|-------------------|-----------------------|------------------------------------------------|
| #35681 | terminal buffer   | SIGSEGV (NULL deref)  | `term` + `split` + `quit!` after stdin closes  |
| #31236 | window + autocmd  | SIGSEGV (NULL deref)  | `WinLeave` autocmd opens float; close tab      |
| #37211 | window + autocmd  | SIGSEGV               | `WinClosed` opens a float in another tab       |
| #30425 | window + tabpage  | SIGSEGV               | `:LspInfo | tabnew | %bd` with float in other tab |
| #17796 | window + bdelete  | SIGSEGV               | open float; `:bdelete` when it is only buffer  |
| #33838 | grid / macos      | SIGSEGV               | alacritty + 6 tabpages + terminal resize       |
| #33067 | extmark / signcol | heap-use-after-free   | undo + `statuscolumn` + Gitsigns               |
| #27127 | extmark / signcol | heap-use-after-free   | extmark + `nvim_win_set_buf` + bufdelete       |
| #32849 | statuscolumn      | heap-use-after-free   | `statuscolumn="%s%l"` + extmark + visual       |
| #27209 | extmark undo      | heap-use-after-free   | extmark `invalidate=true` + undo               |
| #24894 | extmark undo      | SIGSEGV               | `undolevels=-1` + `nvim_buf_set_lines`         |
| #11377 | extmark undo      | heap-use-after-free   | extmark in read-only buffer                    |
| #33603 | buffer autocmd    | SIGSEGV               | `BufUnload` autocmd deletes buf in last tab    |
| #13265 | window autocmd    | heap-use-after-free   | `WinScrolled` closes window via `nvim_win_close` |
| #13231 | buffer callback   | SIGSEGV               | `nvim_buf_attach` callback closes window       |
| #13699 | quickfix autocmd  | heap-use-after-free   | `qf_jump` + FileType autocmd                   |
| #35415 | vimscript const   | SIGABRT (assert)      | `const _ = mapnew(g:xs, ...)` twice            |
| #27859 | msgpack           | SIGSEGV               | macos + Alacritty, large UI attach message     |
| #32883 | remote UI         | SIGSEGV               | `nvim --server ip:port --remote-ui` fails      |
| #16040 | libvterm          | stack-overflow        | `chansend` of 12k lines                       |
| #19075 | libvterm          | stack-overflow        | same family as #16040                         |
| #32113 | termkey           | heap-buffer-overflow  | serial port at 1M baud                        |
| #28946 | FFI plugin        | SIGSEGV               | FFI plugin commits stale win pointer           |
| #25254 | treesitter        | heap-use-after-free   | `ts_node_end_point` after buffer mutation      |
| #14369 | treesitter        | heap-buffer-overflow  | `ts_query_cursor_next_capture` on bad code     |
| #22112 | LSP startup       | SIGSEGV               | rust_analyzer launch race                     |
| #19608 | extmark undo      | SIGSEGV               | `nvim_buf_set_lines` + `:delete` + `:undo`     |
| #30400 | utf8 / regex      | SIGSEGV (NULL deref)  | case-folding invalid unicode + `:TOhtml`       |
| #12988 | fold + screen     | heap-buffer-overflow  | `fdm=syntax` + `zo` in narrow terminal         |
| #36616 | statusline        | SIGSEGV               | complex `%{% ... %}` trunc expr               |
| #12890 | quickfix loclist  | data race / UAF       | LSP diag + `qf_jump` simultaneous              |
| #9739  | inc + float       | SIGSEGV               | `:set inccommand` + float open                 |

## How to use this table

When writing or tuning a fuzzer, scan the leftmost two columns: they
say which `vim.api` surface is most fragile. Bias dispatch weights
toward those APIs first.

The third column is the ASAN class. `SIGSEGV` and `SIGABRT` are
runtime signals; `heap-use-after-free`, `heap-buffer-overflow`, and
`stack-buffer-overflow` are ASAN-detected memory errors that
otherwise look like an ordinary segfault at the signal layer.

The fourth column is a one-liner reproducer. Every entry has a longer
write-up in one of the per-subsystem docs.