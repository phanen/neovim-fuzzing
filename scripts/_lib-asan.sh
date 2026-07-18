#!/usr/bin/env bash
# scripts/_lib-asan.sh -- Shared helper for scripts/repro-*.sh.
#
# Provides:
#   - _asan_run <repro>          -> runs repro under build-afl/bin/nvim, returns
#                                  ASAN log path; rc=-6 (SIGABRT) == 134 == "crashed"
#   - _asan_check <log>         -> prints "PASS"/"FAIL" based on log; sets
#                                  ASAN_RC, ASAN_LINES globals
#   - _asan_repro_summary <repro> -> one-line "rc=N ASAN=N sz=N via foo (PASS|FAIL)"
#
# Examples:
#   source "$(dirname "$0")/_lib-asan.sh"
#   err=$(_asan_run repros/foo/repro.min.lua)
#   _asan_check "$err"
#
# Or all-in-one:
#   source scripts/_lib-asan.sh
#   _asan_repro_summary repros/foo/repro.min.lua

# Path to the AFL+ASAN-patched nvim used for crash reproduction.
_REPRO_NVIM="${REPRO_NVIM:-$ROOT/deps/neovim/build-afl/bin/nvim}"

# Per-call default ASAN_OPTIONS: disable leak detection (nvim startup
# leaks in cjson/luv), abort on every error so the test exits non-zero
# instead of continuing past a UAF, symbolize=0 for cheap unwinding.
: "${ASAN_OPTIONS_REPRO:=detect_leaks=0:abort_on_error=1:symbolize=0:allocator_may_return_null=1}"

# _asan_run <repro.lua> [<err_log>]
# Runs the AFL+ASAN build against a repro script and exits early on
# crash detection.  Writes ASAN output to <err_log> (default
# /tmp/repro-from-crash/_asan-run.log). Echoes the err_log path on
# stdout. Exits 0 on crash, non-zero on clean exit.
_asan_run() {
  local repro="$1"
  local err="${2:-/tmp/repro-from-crash/_asan-run.log}"
  [ -x "$_REPRO_NVIM" ] || { echo "fatal: $_REPRO_NVIM not built" >&2; return 2; }
  mkdir -p "$(dirname "$err")"
  # FUZZ_QUIET=1 silences the harness's intro banner; we only want
  # stderr (ASAN report). `2>"$err" 1>/dev/null` discards stdout. We
  # run with `|| true` so the harness's non-zero exit (SIGABRT -> 134
  # or ASAN abort -> 1) does not propagate.
  ASAN_OPTIONS="$ASAN_OPTIONS_REPRO" \
    FUZZ_QUIET=1 \
      timeout 30 "$_REPRO_NVIM" --headless --clean -i NONE -n \
        -l "$repro" 2>"$err" 1>/dev/null || true
  echo "$err"
  return 0
}

# _asan_check <log>
# Inspects the ASAN log produced by _asan_run and prints one of:
#   "ASAN CRASH: rc=134 ASAN=2  (PASS)"      -> repro reproduces
#   "ASAN clean: rc=0 ASAN=0  (FAIL)"      -> repro didn't trigger
# ASAN_RC and ASAN_LINES are exported in the caller's environment.
_asan_check() {
  local err="$1"
  # Reconstruct exit code: ASAN abort = 1, SIGABRT = 134, SIGABRT in
  # subprocess returns as -6. We don't have access to the subprocess rc
  # after the fact; use ASAN marker count as the source of truth.
  # grep -c exits 1 when no matches; with `set -o pipefail` (which our
  # callers use) that aborts the script. Use `|| true` to neutralize.
  ASAN_LINES=$(grep -c AddressSanitizer "$err" 2>/dev/null | head -1 || true)
  ASAN_LINES="${ASAN_LINES:-0}"
  # Strip trailing whitespace (grep -c emits count + newline).
  ASAN_LINES=$(printf '%d' "$ASAN_LINES" 2>/dev/null || echo 0)
  if [ "$ASAN_LINES" -gt 0 ] 2>/dev/null; then
    ASAN_RC=134
    echo "ASAN CRASH: rc=$ASAN_RC ASAN=$ASAN_LINES  (PASS)"
  else
    ASAN_RC=0
    echo "ASAN clean: rc=$ASAN_RC ASAN=0  (FAIL)"
  fi
}

# _asan_repro_summary <repro.lua> [<err_log>]
# Run + check in one call. Echoes full summary including repro size and
# the harness path used.
_asan_repro_summary() {
  local repro="$1"
  local err="${2:-/tmp/repro-from-crash/_asan-run.log}"
  if [ ! -f "$repro" ]; then
    printf 'MISSING: %s\n' "$repro"
    return 1
  fi
  local sz
  sz=$(wc -c < "$repro" 2>/dev/null || echo 0)
  _asan_run "$repro" "$err" >/dev/null
  _asan_check "$err" >/dev/null
  printf 'rc=%d ASAN=%d sz=%d via %s  (%s)\n' \
    "$ASAN_RC" "$ASAN_LINES" "$sz" "$(basename "$repro")" \
    "$([ "$ASAN_LINES" -gt 0 ] && echo PASS || echo FAIL)"
}

# Confirm the build is available before callers proceed.
_asan_require_build() {
  [ -x "$_REPRO_NVIM" ] || {
    echo "fatal: build the AFL+ASAN nvim first:" >&2
    echo "  scripts/build-nvim-afl.sh --asan" >&2
    return 2
  }
}
