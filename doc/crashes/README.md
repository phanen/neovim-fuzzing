# Neovim Crash Pattern Field Guide

A survey of upstream `neovim/neovim` crash issues, distilled into
patterns that a fuzzer can hit. Each entry maps a known regression to
the API surface it touches, so a focused fuzzer can target the same
path under AFL without rediscovering it from scratch.

## Files

```
README.md                         this file
01-top-crashes-table.md           issue-numbered index, fastest scannable
02-crash-by-subsystem.md          crash families grouped by API area
03-asan-error-patterns.md         ASAN error classes + what provokes them
04-autocmd-reentrancy.md          use-after-free from autocmd callbacks
05-extmark-state-machine.md       extmark / signcolumn / decoration sync
06-async-resource-lifetime.md    libuv, libvterm, RPC stack-corruption
```

## Reading order

If you only have time for one document, read
`02-crash-by-subsystem.md`.  It tells you which areas of the API are
historically fragile and which fields to bias a fuzzer's weight
distribution toward.

If you are debugging a specific sanitizer report, jump to
`03-asan-error-patterns.md` and find the ASAN error class first; that
narrows the suspect code path to a single subsystem.
