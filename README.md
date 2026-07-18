# neovim-fuzzing

Neovim AFL++ fuzzer harness.

## Build

```bash
# Build nvim with AFL+ASAN instrumentation
git clone --depth 1 https://github.com/neovim/neovim.git deps/neovim
scripts/build-nvim-afl.sh --asan

# Generate the byte-level seed corpus
scripts/make-seed-corpus.sh bytes
mkdir -p afl-findings-bytes

# Fuzz (Ctrl-C to stop; saved crashes land in afl-findings-bytes/).
./fuzz-crashhunter.sh -i afl-corpus-bytes -o afl-findings-bytes -t 30000

# Generate a self-contained repro for a saved crash.
scripts/repro-from-crash.sh --minimize \
  afl-findings-bytes/default/crashes/id:000000,sig:06,* \
  out/repro.lua

# Replay a repro to confirm ASAN triggers.
VIMRUNTIME=./deps/neovim/runtime \
  ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:symbolize=1:allocator_may_return_null=1" \
  ./deps/neovim/build-afl/bin/nvim --headless --clean -i NONE -n \
  -l out/repro.lua
# rc=134, ASAN heap-use-after-free
```

## Credits
* https://github.com/KevinGoodsell/fuzzing-nvim
