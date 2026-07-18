#!/usr/bin/env bash
# scripts/repro-from-crash.sh — Generate a SELF-CONTAINED standalone
# reproducer for a saved AFL crash input.
#
# The captured dispatch log goes through `bin/from-log.lua` to emit a
# single repro.lua that does NOT depend on fuzz-crashhunter.lua, dofile, or any
# input file. It reproduces the bug 100% on the ASan nvim build.
#
# - First we capture the fuzzer dispatch log via fuzz-crashhunter.lua's
#   `log=path` argument so we know exactly which vim.api / vim.cmd
#   sequence was running when AFL hit the crash.
# - Then from-log.lua parses the log, groups ops by round (mirroring
#   the fuzzer's `for round=1,ROUNDS` per-iteration reset), and emits
#   an explicit sequence with stub callbacks for WinLeave / WinClosed /
#   BufUnload that mirror the bodies of fuzz-crashhunter.lua's scenarios
#   (otherwise the WinClosed handler hits "E117: Unknown function"
#   and the reentrancy path the bug lives on is never taken).
# - The repro ends with a final teardown (closes all open windows and
#   deletes all scratch bufs) that runs the `close_windows` ->
#   `do_buffer_ext` -> `nvim_buf_delete` path which is the UAF source.
#
# Pass --minimize to additionally shrink the repro via
# `scripts/minimize-repro.sh` (delta-debug rounds + per-op + whole-round
# drop). End-to-end one-command pipeline:
#   scripts/repro-from-crash.sh --minimize <crash-file>
#
# Run the repro with the same patched-AFL+ASAN build that produced
# the crash:
#
#   VIMRUNTIME=./deps/neovim/runtime \
#   ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:symbolize=0:allocator_may_return_null=1" \
#   ./deps/neovim/build-afl/bin/nvim --headless --clean -i NONE -n \
#     -l <out>.repro.lua
#
# Expected: rc=134 (SIGABRT) and an AddressSanitizer
# heap-use-after-free report on stderr pointing at close_windows /
# do_buffer_ext.
#
# Usage:
#   scripts/repro-from-crash.sh [--minimize] <crash-file> [<out-repro.lua>]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MINIMIZE=0
case "${1:-}" in
  --minimize|-m)
    MINIMIZE=1
    shift
    ;;
esac

crash_file="${1:-}"
out_repro="${2:-}"
[ -z "$crash_file" ] && {
  echo "usage: $0 <crash-file> [<out-repro.lua>]" >&2
  echo "  crash-file: AFL saved crash (path or glob)" >&2
  exit 2
}

if [[ "$crash_file" == *"*"* ]]; then
  IFS= read -r -d '' crash_file < <(
    compgen -G "$crash_file" 2>/dev/null | head -n1 | tr '\n' '\0' \
      || true
  )
  [ -z "${crash_file:-}" ] && { echo "no glob match" >&2; exit 2; }
fi
[ ! -f "$crash_file" ] && { echo "not a file: $crash_file" >&2; exit 2; }

abs_crash="$(cd "$(dirname "$crash_file")" && pwd)/$(basename "$crash_file")"
# Default output: alongside the crash, named <crash>.repro.lua
[ -n "$out_repro" ] || out_repro="${abs_crash%.???}.repro.lua"

mkdir -p /tmp/repro-from-crash
log_path="/tmp/repro-from-crash/$(basename "$crash_file" | tr ',/' '__').log"

echo "step 1/3: capture fuzz-crashhunter.lua dispatch with log=$log_path"
echo "  -> source line will show (NN bytes); should match $(wc -c < "$abs_crash") bytes"
echo

ROUNDS="${REPRO_CAPTURE_ROUNDS:-25}" FUZZ_QUIET=1 VIMRUNTIME="$ROOT/deps/neovim/runtime" \
  ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:symbolize=0:allocator_may_return_null=1" \
    timeout 60 "$ROOT/deps/neovim/build-afl/bin/nvim" --headless --clean -i NONE -n \
      -l "$ROOT/fuzz-crashhunter.lua" "$abs_crash" "${REPRO_CAPTURE_ROUNDS:-25}" \
      "log=$log_path" \
      2>/tmp/repro-from-crash/run.err || true

# Step 2: emit self-contained repro.lua from the dispatch log.
echo "step 2/3: bin/from-log.lua -> $out_repro"
bin/from-log.lua "$log_path" "$out_repro"

# Append a self-test footer that prints the runtime checks for
# whether ASAN recovered a violation during the script. Footer
# uses repo-root-relative paths (anchored on $ROOT) so the repro
# is portable across CI runners and local dev. ASAN_OPTIONS comes
# from the daily-fuzz.sh caller (so the footer matches the actual
# ASAN_OPTIONS used to capture this crash, not a hardcoded copy
# that could drift).
#
# Default to a minimal capture-step opts if the caller didn't pass
# ASAN_OPTIONS_FOR_REPRO. daily-fuzz.sh always passes its own.
asan_opts="${ASAN_OPTIONS_FOR_REPRO:-detect_leaks=0:abort_on_error=1:symbolize=0:allocator_may_return_null=1}"
rel_crash="${abs_crash#$ROOT/}"  # strip repo-root prefix
echo "-- " >> "$out_repro"
echo "-- Source crash: $rel_crash ($(wc -c < "$abs_crash") bytes)" >> "$out_repro"
echo "-- Run with (from repo root):" >> "$out_repro"
printf -- '--   ASAN_OPTIONS="%s" \\\n' "$asan_opts" >> "$out_repro"
echo '--   deps/neovim/build-afl/bin/nvim --headless --clean -i NONE -n \' >> "$out_repro"
echo "--     -l <this-repro>" >> "$out_repro"
echo "-- Expected: rc=134 and an AddressSanitizer report." >> "$out_repro"

# Step 3: verify the generated repro actually crashes with ASAN.
# Uses scripts/_lib-asan.sh so the run/check logic is shared with
# scripts/repro-all.sh and any future caller.
echo "step 3/3: verify repro triggers ASAN"
REPRO_NVIM="$ROOT/deps/neovim/build-afl/bin/nvim" \
  source "$ROOT/scripts/_lib-asan.sh"
asan_log="/tmp/repro-from-crash/verify.err"
_asan_run "$out_repro" "$asan_log" >/dev/null
_asan_check "$asan_log" >/dev/null
if [ "$ASAN_LINES" -gt 0 ]; then
  rc=134
else
  rc=0
fi

if [ "$rc" -eq 134 ] || grep -q AddressSanitizer "$asan_log"; then
  echo "  rc=$rc  ASAN=$ASAN_LINES lines  (PASS)"

  if [ "$MINIMIZE" = "1" ]; then
    echo
    echo "step 4/4: minimize via scripts/minimize-repro.sh"
    bash "$ROOT/scripts/minimize-repro.sh" "$log_path" || true
    min_repro="/tmp/minimize/MIN.lua"
    if [ -s "$min_repro" ]; then
      REPRO_NVIM="$ROOT/deps/neovim/build-afl/bin/nvim" \
        source "$ROOT/scripts/_lib-asan.sh"
      _asan_run "$min_repro" /tmp/repro-from-crash/verify-min.err >/dev/null
      _asan_check /tmp/repro-from-crash/verify-min.err >/dev/null
      if [ "$ASAN_LINES" -gt 0 ]; then
        min_size=$(wc -c < "$min_repro")
        echo "  minimized: $min_size bytes, $ASAN_LINES ASAN lines (rc=134) (PASS)"
        echo
        echo "MINIMIZED REPRO: $min_repro"
        cp "$min_repro" "${out_repro%.lua}.min.lua"
        echo "  also copied to: ${out_repro%.lua}.min.lua"
      else
        echo "  minimize FAIL: ASAN=0 (keeping full repro at $out_repro)"
      fi
    fi
  fi
else
  echo "  rc=$rc  ASAN=0  (FAIL: self-contained repro did not crash)"
  echo "  Pass the raw crash file directly to fuzz-crashhunter.lua:"
  echo "    nvim --headless --clean -i NONE -n \\"
  echo "      -l $ROOT/fuzz-crashhunter.lua <crash-file> 25"
  echo "  (ROUNDS=25 default; ASAN will re-trigger via the in-tree"
  echo "  code path the fuzzer originally hit.)"
fi
echo
echo "=========================================================================="
echo "Repro command (paste this):"
echo
echo "  VIMRUNTIME=$ROOT/deps/neovim/runtime \\"
echo "  ASAN_OPTIONS=\"detect_leaks=0:abort_on_error=1:symbolize=0:allocator_may_return_null=1\" \\"
echo "  $ROOT/deps/neovim/build-afl/bin/nvim \\"
echo "    --headless --clean -i NONE -n \\"
echo "    -l $out_repro"
echo
echo "Expected: rc=134 and an AddressSanitizer heap-use-after-free"
echo "report on stderr pointing at close_windows / do_buffer_ext."
echo
echo "If the self-contained repro above does not crash, see"
echo "${out_repro%.lua}.dofile.lua (fallback that re-runs the fuzzer)."
echo
echo "Dispatch log captured at: $log_path"
echo "(review with: less $log_path)"
