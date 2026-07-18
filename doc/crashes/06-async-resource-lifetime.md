# Async Resource Lifetime Crash Patterns

Three crash families in this set are about stack-allocated
resources that get used by an async callback after the stack frame
has already returned. The signature is `stack-use-after-return` in
ASAN, or `SIGSEGV` in a non-ASAN build.

## Pattern A: uv_connect_t on the stack (#32883)

```
nvim --server ip:port --remote-ui
  -> remote_request() { uv_connect_t req; ... uv_tcp_connect(&req, ...) }
  -> return              <- req is on the stack, now invalid
  -> libuv calls cb      <- cb sees req in its destructor chain
  -> uv__stream_destroy
  -> SIGSEGV
```

The libuv API takes `&req` and calls `req->cb` on completion. If
the call fails synchronously (connection refused, DNS lookup
error), the cb can be invoked from inside `uv_tcp_connect` before
the function returns. The fix (PR #36405) heap-allocates the
connect struct.

The fuzzer has no reliable way to reproduce this without a network
target. `fuzz-crashhunter.lua` does not exercise this pattern
directly; it is left to manual reproduction.

## Pattern B: libvterm on_text VLA (#16040 / #19075)

```
let chan = nvim_open_term(0, {})
let lines = repeat([repeat('x', 187) .. "\r"], 12250)
call chansend(chan, lines)
```

Libvterm's `on_text` callback is called once per chansend batch.
It builds a `uint32_t codepoints[len]` VLA sized to the input
length. A 12,250-line paste produces a VLA of ~2 MB, well past the
default 8 MB stack. `SIGSEGV` from stack exhaustion.

Fix in nvim (PR #16593): chunk chansend at the nvim side so
`on_text` never sees a single batch larger than 64 KB.

`fuzz-crashhunter.lua` exercises this via
`scenario_chan_send_huge_term_paste`, which opens a terminal and
chansends a configurable-length line.

## Pattern C: msgpack session state (#27859)

```
remote UI sends a multi-MB msgpack
  -> read_cb fires from libuv
  -> parse_msgpack parses the framing
  -> prepare_call processes the call
  -> receive_msgpack updates session->msg_pos
  -> SIGSEGV: session->msg_pos is past the actual buffer
```

The crash is on macOS + Alacritty specifically because of how
those stack large messages through the UI thread. PR #27348 fixes
the framing math.

This is also difficult to reach from the in-process fuzzer; the
fuzzer cannot easily emulate a remote UI client. Out of scope for
`fuzz-crashhunter.lua`.

## Pattern D: buf_updates_send_changes (#13231)

This sits on the boundary of the autocmd-reentrancy class
(see `04-autocmd-reentrancy.md`) and the async-lifetime class.
The `on_lines` callback fires synchronously from
`buf_updates_send_changes`, but the buffer reference it captures
goes stale before the callback runs. The crash is heap-use-after-
free, not stack-use-after-return, so it lives in the autocmd doc.

## Why these are harder to fuzz

The async resource patterns need:

- A network target (for #32883, #27859).
- A terminal allocator hooked (for #16040, #19075).
- A specific libuv version whose async-callback timing exposes the
  race.

The fuzzer can approximate #16040 directly by chansending to an
`nvim_open_term` channel. The others require either an AFL
`deferred init` shim that intercepts the async setup, or a custom
nvim build with a `--fuzz-async` flag.

`fuzz-crashhunter.lua` includes the term-paste scenario as a
"low-effort, high-value" target. The other two are documented
here so future fuzzer revisions know what's left to reach.