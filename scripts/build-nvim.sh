#!/usr/bin/env bash
# scripts/build-nvim.sh
# Build neovim from ./deps/neovim with AddressSanitizer + UBSan for fuzzing.
# Re-runnable; safe to invoke after `git pull` inside deps/neovim.
#
# Strategy: neovim runs codegen during build (preload_nlua.lua + gen_*.lua)
# which dlopen()s libnlua0.so. If libnlua0.so is built with ASAN, dlopen
# ordering trips the ASAN runtime ("ASan runtime does not come first").
# We therefore patch src/nvim/CMakeLists.txt to disable sanitizers on the
# nlua0 codegen target while leaving them on main_lib / nvim binary.
#
# Two CMake passes:
#   1) clean tree, no sanitizers -> populates codegen artifacts as a fallback
#   2) reconfigure with sanitizers -> nlua0 is exempt, nvim binary is sanitized

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/deps/neovim"
BUILD="$ROOT/deps/neovim/build"

if [[ ! -d "$SRC" ]]; then
  echo "fatal: $SRC not found. Run: git clone --depth 1 https://github.com/neovim/neovim.git deps/neovim" >&2
  exit 2
fi

if [[ "${1:-}" == "--pull" ]]; then
  (cd "$SRC" && git pull --ff-only)
fi

CMKL="$SRC/src/nvim/CMakeLists.txt"
if ! grep -q "fz_no_sanitize_nlua0" "$CMKL"; then
  # Idempotent patch: inject a `target_compile_options(nlua0 PRIVATE -fno-sanitize=all)`
  # marker line right after `add_library(nlua0 MODULE)`.
  python3 - "$CMKL" <<'PY'
import sys, re
p = sys.argv[1]
src = open(p).read()
if "fz_no_sanitize_nlua0" in src:
    sys.exit(0)
new = re.sub(
    r"add_library\(nlua0 MODULE\)\n",
    "add_library(nlua0 MODULE)\n"
    "# fz_no_sanitize_nlua0: keep nlua0 codegen host library un-sanitized to\n"
    "# avoid ASan runtime init ordering issues when libnlua0.so is dlopened\n"
    "# by luajit during the build-time gen_*.lua codegen step.\n"
    "if(NOT WIN32)\n"
    "  target_compile_options(nlua0 PRIVATE -fno-sanitize=all -fno-sanitize-recover=all)\n"
    "  target_link_options(nlua0 PRIVATE -fno-sanitize=all)\n"
    "endif()\n",
    src, count=1)
open(p, 'w').write(new)
PY
  echo "patched: $CMKL (nlua0 sanitizer exemption)"
fi

SAN_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer -fno-sanitize-recover=all"
LDFLAGS="-fsanitize=address,undefined"

# The build itself runs nvim in headless mode to regenerate helptags. Those
# subprocess invocations do not free everything on exit, which trips
# LeakSanitizer and aborts the build. Disable leak detection for the build
# subprocess; the fuzzer run keeps the default (LSAN enabled).
export ASAN_OPTIONS="detect_leaks=0:abort_on_error=0"

cd "$SRC"

# Pass 1: clean tree, no sanitizers -> populates codegen + binary as a baseline.
echo "=== pass 1: codegen (no sanitizers) ==="
cmake -S . -B "$BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_C_COMPILER=gcc \
  -DCMAKE_CXX_COMPILER=g++ \
  -DENABLE_LIBINTL=OFF \
  -DSTRIP=OFF >/dev/null
cmake --build "$BUILD" --parallel "$(nproc)"

# Pass 2: reconfigure with sanitizers. nlua0 is exempt by the patch above;
# the gen_*.lua codegen step will reuse pass-1 artifacts so nlua0 doesn't
# need to be sanitized at this point.
echo "=== pass 2: ASAN/UBSAN ==="
cmake -S . -B "$BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_C_COMPILER=gcc \
  -DCMAKE_CXX_COMPILER=g++ \
  -DCMAKE_C_FLAGS="$SAN_FLAGS" \
  -DCMAKE_CXX_FLAGS="$SAN_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
  -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS" \
  -DENABLE_LIBINTL=OFF \
  -DSTRIP=OFF >/dev/null
cmake --build "$BUILD" --parallel "$(nproc)"

# Stage the binary at the repo root for easy invocation.
mkdir -p "$ROOT/out"
cp -f "$BUILD/bin/nvim" "$ROOT/out/nvim"

echo
echo "OK: built $ROOT/out/nvim"
echo "    quick check:"
"$ROOT/out/nvim" --version | head -3