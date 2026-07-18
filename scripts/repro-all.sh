#!/usr/bin/env bash
# scripts/repro-all.sh -- Generate a minimized standalone reproducer
# for every AFL crash input in afl-findings-bytes/. Each crash gets
# its own output directory under ./repros/<crash-id>/ containing:
#
#   repro.lua         - full self-contained repro (148 ops typical)
#   repro.min.lua     - minimized repro (~6.5KB, ~27 ops)
#   repro.dofile.lua  - dofile fallback (if self-contained doesn't crash)
#   dispatch.log      - captured fuzz-crashhunter.lua dispatch log
#   verify.err        - ASAN report from running the full repro
#
# Usage:
#   scripts/repro-all.sh [--minimize] [crash-dir]
#
# Default crash-dir: afl-findings-bytes/default/crashes
#
# Each crash is processed sequentially (the minimization loop is
# CPU-bound and forks per op, so parallel runs would not be much
# faster and would fight over /tmp).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MINIMIZE=0
case "${1:-}" in
  --minimize|-m)
    MINIMIZE=1
    shift
    ;;
esac

CRASH_DIR="${1:-afl-findings-bytes/default/crashes}"
[ -d "$CRASH_DIR" ] || { echo "no such dir: $CRASH_DIR" >&2; exit 2; }

OUT_ROOT="${ROOT}/repros"
mkdir -p "$OUT_ROOT"

# Discover crash files: id:NNNN*, exclude README.txt and any
# existing repro.lua (those are outputs from a prior run, not
# AFL inputs).
shopt -s nullglob
crashes=( "$CRASH_DIR"/id:* )
shopt -u nullglob
# Filter to plain files only (no .repro.lua, no .min.lua).
filtered=()
for f in "${crashes[@]}"; do
  [ -f "$f" ] || continue
  case "$f" in
    *.repro.lua|*.min.lua) continue ;;
  esac
  filtered+=( "$f" )
done
crashes=( "${filtered[@]}" )

if [ ${#crashes[@]} -eq 0 ]; then
  echo "no crash files in $CRASH_DIR" >&2
  exit 1
fi

echo "Found ${#crashes[@]} crash(es) in $CRASH_DIR"
echo "Output: $OUT_ROOT/"
[ "$MINIMIZE" = "1" ] && echo "Mode: --minimize (full pipeline + delta-debug)" || echo "Mode: capture + emit + verify (no minimize)"
echo

total=${#crashes[@]}
idx=0
pass=0
fail=0
declare -a crash_ids

for crash in "${crashes[@]}"; do
  idx=$((idx + 1))
  id=$(basename "$crash" | sed 's/[^a-zA-Z0-9._-]/_/g')
  crash_ids+=( "$id" )
  out_dir="$OUT_ROOT/$id"
  mkdir -p "$out_dir"

  echo "========================================"
  echo "[$idx/$total] $id"
  echo "========================================"

  repro="$out_dir/repro.lua"
  # Run repro-from-crash.sh with --tee to a per-crash log file so we
  # can show full minimizer progress (per-round, per-op dots) while
  # still being able to grep for PASS/FAIL afterwards.
  log="$out_dir/build.log"
  if [ "$MINIMIZE" = "1" ]; then
    if ! bash "$ROOT/scripts/repro-from-crash.sh" --minimize "$crash" "$repro" \
        >"$log" 2>&1; then
      echo "  script returned non-zero (see $log)"
    fi
  else
    if ! bash "$ROOT/scripts/repro-from-crash.sh" "$crash" "$repro" \
        >"$log" 2>&1; then
      echo "  script returned non-zero (see $log)"
    fi
  fi
  # Stream relevant lines from the build log to stdout, but also
  # surface per-op progress dots so the user knows the minimizer
  # is alive (each attempt spawns an nvim subprocess).
  while IFS= read -r line; do
    case "$line" in
      "  baseline OK"*|"step "*|"MINIMIZED"*)
        echo "$line" ;;
      "  round "*|"    end-drop"*|"    mid-drop"*|"    ["*"s]"*)
        echo "$line" ;;
      "  DROPPED round"*)
        echo "$line" ;;
      "  minimized:"*)
        echo "$line" ;;
      "  FINAL:"*|"  crash:"*)
        echo "$line" ;;
    esac
  done < "$log"

  # Verify final state. Pick the smallest successful repro in order:
  #   1. repro.min.lua (minimized)
  #   2. repro.lua      (full self-contained)
  #   3. repro.dofile.lua (fallback that re-runs the fuzzer)
  REPRO_NVIM="$ROOT/deps/neovim/build-afl/bin/nvim" \
    source "$ROOT/scripts/_lib-asan.sh"
  final=""
  for cand in "$out_dir/repro.min.lua" "$out_dir/repro.lua" "$out_dir/repro.dofile.lua"; do
    [ -s "$cand" ] || continue
    summary=$(_asan_repro_summary "$cand" "$out_dir/verify.err")
    kind=$(basename "$cand")
    if [[ "$summary" == *"PASS"* ]]; then
      echo "  RESULT: $summary"
      final="$cand"
      pass=$((pass + 1))
      break
    else
      echo "  candidate $kind: $summary  (no crash)"
    fi
  done
  if [ -z "$final" ]; then
    echo "  RESULT: no candidate crashed (FAIL)"
    fail=$((fail + 1))
  fi
  echo
done

echo "========================================"
echo "SUMMARY: $pass/$total PASS, $fail FAIL"
echo "Outputs in: $OUT_ROOT/"
ls "$OUT_ROOT/"
echo
echo "Quick run any repro:"
echo "  VIMRUNTIME=$ROOT/deps/neovim/runtime \\"
echo "  ASAN_OPTIONS=\"detect_leaks=0:abort_on_error=1:symbolize=1:allocator_may_return_null=1\" \\"
echo "    $ROOT/deps/neovim/build-afl/bin/nvim --headless --clean -i NONE -n \\"
echo "      -l $OUT_ROOT/<crash-id>/repro.min.lua"

[ "$fail" -eq 0 ]
