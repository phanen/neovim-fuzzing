#!/usr/bin/env bash
# scripts/build-nvim-afl.sh
# Build neovim with AFL instrumentation. Optionally combine with
# AddressSanitizer (--asan) so AFL coverage feedback observes memory
# crashes too. Requires afl-clang-lto (preferred) or afl-clang-fast
# (fallback) installed and the dependency tree present at ./deps/neovim.
#
# Usage:
#   scripts/build-nvim-afl.sh             # AFL only
#   scripts/build-nvim-afl.sh --asan      # AFL + AddressSanitizer
#
# Env overrides:
#   CC/CXX           override compiler (default: afl-clang-lto)
#   FZ_AFL_NO_ALLOWLIST=1   instrument everything (slower; broader bitmap)
#   FZ_AFL_NO_CCACHE=1      skip ccache wrap (set automatically)
#
# Why afl-denylist.txt: nvim's build-time codegen (`gen_*.lua`) dlopen()s
# `libnlua0.so` through the system `luajit`, which is NOT linked against
# the AFL runtime. Excluding `src/nlua0.c` via AFL_LLVM_DENYLIST keeps
# libnlua0.so free of `__afl_area_ptr` references so dlopen succeeds.
# nlua0 is a build-time helper only, so omitting it from instrumentation
# does not reduce coverage on the nvim binary itself.
#
# Why the ccache patch: nvim's cmake (deps/neovim/cmake/Deps.cmake) auto-
# detects ccache and hardcodes it into CMakeCache.txt + the ninja launcher
# before any of our env vars take effect. ccache only hashes compile
# arguments by default; it does NOT see AFL_LLVM_DENYLIST as a cache key.
# That means a stale .o built without the denylist will be returned on
# subsequent builds and libnlua0.so will end up referencing
# `__afl_area_ptr`, breaking dlopen. We therefore patch Deps.cmake (same
# idempotent style as build-nvim.sh patches src/nvim/CMakeLists.txt) to
# skip the ccache wrap when FZ_AFL_NO_CCACHE is set, and we set that
# variable before invoking cmake here. Same trick is reapplied on every
# run, so a `git pull` upstream change to Deps.cmake is automatically
# re-patched.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/deps/neovim"
BUILD="$SRC/build-afl"
DENYLIST="$ROOT/scripts/afl-denylist.txt"
DEPS_CMAKE="$SRC/cmake/Deps.cmake"

WITH_ASAN=0
if [[ "${1:-}" == "--asan" ]]; then
  WITH_ASAN=1
  shift
fi
if [[ $# -gt 0 ]]; then
  echo "usage: $0 [--asan]" >&2
  exit 2
fi

if [[ ! -d "$SRC" ]]; then
  echo "fatal: $SRC not found." >&2
  exit 2
fi
if ! command -v afl-clang-fast >/dev/null 2>&1 \
  && ! command -v afl-clang-lto >/dev/null 2>&1 \
  && ! command -v afl-gcc >/dev/null 2>&1; then
  echo "fatal: afl-clang-fast, afl-clang-lto, or afl-gcc required in PATH." >&2
  exit 2
fi
if [[ ! -f "$DENYLIST" ]]; then
  echo "fatal: $DENYLIST not found." >&2
  exit 2
fi

# Default to afl-clang-lto (newer LLVM PCGUARD, smaller bitmap, better
# stability). Fall back to afl-clang-fast if LTO isn't installed.
if [[ -z "${CC:-}" ]]; then
  if command -v afl-clang-lto >/dev/null 2>&1; then
    CC=afl-clang-lto
  else
    CC=afl-clang-fast
  fi
fi
if [[ -z "${CXX:-}" ]]; then
  if command -v afl-clang-lto++ >/dev/null 2>&1; then
    CXX=afl-clang-lto++
  else
    CXX=afl-clang-fast++
  fi
fi

# Patch Deps.cmake to skip ccache setup when FZ_AFL_NO_CCACHE is set.
# Idempotent: the marker comment is the sentinel.
if ! grep -q "fz_no_ccache_afl" "$DEPS_CMAKE"; then
  python3 - "$DEPS_CMAKE" <<'PY'
import sys, re
p = sys.argv[1]
src = open(p).read()
if "fz_no_ccache_afl" in src:
    sys.exit(0)
# Wrap the ccache detection so it can be opted-out via FZ_AFL_NO_CCACHE.
new = re.sub(
    r"find_program\(CACHE_PRG NAMES ccache sccache\)\n",
    "if(DEFINED ENV{FZ_AFL_NO_CCACHE} AND \"$ENV{FZ_AFL_NO_CCACHE}\" STREQUAL \"1\")\n"
    "  # fz_no_ccache_afl: skip ccache wrap under AFL because ccache's\n"
    "  # argument-only hash cannot detect env-var driven changes\n"
    "  # (AFL_LLVM_DENYLIST, AFL_USE_ASAN, ...), causing stale hits\n"
    "  # on libnlua0.so that then reference __afl_area_ptr and break\n"
    "  # the system-luajit dlopen of the build-time codegen helper.\n"
    "  set(CACHE_PRG \"\")\n"
    "else()\n"
    "  find_program(CACHE_PRG NAMES ccache sccache)\n"
    "endif()\n",
    src, count=1)
open(p, 'w').write(new)
PY
  echo "patched: $DEPS_CMAKE (FZ_AFL_NO_CCACHE guard for ccache)"
fi

# Instrumentation scope: AFL++ accepts either ALLOWLIST or DENYLIST,
# not both. Default to ALLOWLIST (afl-allowlist.txt) which keeps the
# coverage bitmap focused on the surfaces our fuzzer drives (win/buf/
# tab/autocmd/extmark/keys/etc.) -- this matches Kevin Goodsell's
# stability-100% setup. Set FZ_AFL_NO_ALLOWLIST=1 to fall back to
# DENYLIST-only (excludes just nlua0). Set neither env var (or
# AFLLIST_NONE=1) to instrument everything.
ALLOWLIST="$ROOT/scripts/afl-allowlist.txt"
if [[ -z "${FZ_AFL_NO_ALLOWLIST:-}" && -f "$ALLOWLIST" ]]; then
  export AFL_LLVM_ALLOWLIST="$ALLOWLIST"
  echo "AFL allowlist: $ALLOWLIST ($(grep -c . "$ALLOWLIST") entries)"
else
  # Fall back to denylist path (only nlua0 excluded).
  export AFL_LLVM_DENYLIST="$DENYLIST"
  echo "AFL denylist: $DENYLIST"
fi

# Tell the patched Deps.cmake to skip the ccache wrap. See the patch
# comment in $DEPS_CMAKE for the full rationale.
export FZ_AFL_NO_CCACHE=1

# afl-clang-fast 5.00c honors AFL_USE_ASAN=1 by adding
# `-fsanitize=address,<many>` to its compile invocation (verified
# via `afl-clang-fast -v` against an empty TU: the env var adds
#  -fsanitize=address,alignment,...,signed-integer-overflow,...
# and pulls in libclang_rt.asan_static-x86_64.a at link time).
# However, cmake's target_link_libraries does not propagate those
# injected flags from afl-clang-fast into dependent shared libs
# (notably libnlua0.so, which is a build-time codegen helper, not a
# fuzzing target), and afl-clang-fast does not add -fsanitize=undefined
# on its own. We pass both -fsanitize=address and -fsanitize=undefined
# explicitly through CMAKE_C/CXX/LINKER flags so the sanitizer is
# bound at cmake's link step, independent of AFL_USE_ASAN's
# flag-injection behavior.
SAN_FLAGS=()
if (( WITH_ASAN )); then
  if ! command -v clang >/dev/null 2>&1 && ! command -v afl-clang-fast >/dev/null 2>&1; then
    echo "fatal: --asan needs clang (afl-clang-fast is fine)." >&2
    exit 2
  fi
  export AFL_USE_ASAN=1
  # UBSAN pairs well with ASAN; the same detangler needed.
  export AFL_USE_UBSAN=1
  SAN_FLAGS=(
    -DCMAKE_C_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer -fno-sanitize-recover=all"
    -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer -fno-sanitize-recover=all"
    -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address,undefined -fno-sanitize-recover=all"
    -DCMAKE_SHARED_LINKER_FLAGS="-fsanitize=address,undefined -fno-sanitize-recover=all"
  )
fi

cd "$SRC"

# Disable LeakSanitizer for build-time nvims that do their own gen_*.
# See scripts/build-nvim.sh for the same justification: cjson/luv
# startup intentionally retains state through _exit().
export ASAN_OPTIONS="detect_leaks=0:abort_on_error=0"

cmake -S . -B "$BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DENABLE_LIBINTL=OFF \
  "${SAN_FLAGS[@]}"

# Why this sed: with `--asan`, afl-clang-fast forces `-fsanitize=address`
# onto the clang command line AFTER any user-provided `-fno-sanitize=all`,
# overriding it. That makes any source going through afl-clang-fast land
# `__asan_report_*` references in its .o. Those get linked into
# `libnlua0.so`, which the build-time gen_*.lua step then dlopen()s via
# the system `luajit`. luajit has no ASAN runtime, so dlopen fails. We
# could also work around this by extending afl-denylist.txt, but
# `-fsanitize=` instrumentation is not actually filtered by that path
# list -- it is unconditional when AFL_USE_ASAN=1. Switching to
# `-fsanitize-ignorelist` is unreliable across afl-cc versions, so we
# patch the ninja rules instead: divert the nlua0 build entirely to
# plain system clang AND strip -fsanitize= so the .o files are clean
# for dlopen. nlua0.c and mpack/*.c become uninstrumented AND
# un-sanitized; both are build-time codegen helpers, so neither coverage
# nor ASAN signal is lost on the actual fuzzer target (nvim binary).
RULES="$BUILD/CMakeFiles/rules.ninja"
if [[ -f "$RULES" ]]; then
  python3 - "$RULES" <<'PY'
import sys, re
p = sys.argv[1]
src = open(p).read()
# Rewrite only the nlua0-specific rules; never touch libnvim / nvim_bin.
# Append -fno-sanitize=all to the end so it overrides the global
# -fsanitize=address,undefined from CMAKE_C_FLAGS / _LINKER_FLAGS.
# Match afl-clang-fast, afl-clang-lto, and the C++ siblings (the
# `++` form) -- CI defaults to afl-clang-lto, the previous regex
# only matched afl-clang-fast and silently no-op'd.
def rewrite_rule(text, rule_name):
    pattern = re.compile(
        r"(rule " + re.escape(rule_name) + r"\n(?:  .*\n)*?  command = )"
        r"[^/\n]*?/usr/bin/afl-clang-[A-Za-z0-9+]+([^\n]*)")
    new, n = pattern.subn(r"\1/usr/bin/clang\2 -fno-sanitize=all", text)
    if n:
        print(f"patched: rule {rule_name} ({n} command line)")
    return new
src = rewrite_rule(src, "C_COMPILER__nlua0_unscanned_Release")
src = rewrite_rule(src, "C_MODULE_LIBRARY_LINKER__nlua0_Release")
open(p, 'w').write(src)
PY
fi

cmake --build "$BUILD" --parallel "$(nproc)"

echo
if (( WITH_ASAN )); then
  echo "OK: built $BUILD/bin/nvim (AFL + ASAN/UBSAN)"
else
  echo "OK: built $BUILD/bin/nvim (AFL only)"
fi