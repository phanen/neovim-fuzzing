#!/usr/bin/env bash
# scripts/daily-fuzz.sh
# Daily autonomous fuzzing run: pull upstream nvim, build AFL+ASAN,
# fuzz for DURATION seconds, generate self-contained reporos for every
# AFL saved crash, write a JSON report, persist everything under
# reports/$(date -u +%Y-%m-%d_%H%M%S)/. Each run gets its own
# minute-precision subdir; back-to-back runs don't overwrite.
#
# Used both as a cron entry and as the body of .github/workflows/daily-fuzz.yml.
# Both invocations end up writing the same artifacts: report.json,
# fuzz.log, repros/<crash-id>/{crash.bin,repro.lua,repro.min.lua,
# verify.err}.
#
# Usage:
#   scripts/daily-fuzz.sh                          # default 1h
#   scripts/daily-fuzz.sh --duration 600          # 10 minutes
#   scripts/daily-fuzz.sh --duration 3600 --no-pull
#
# Exit codes:
#   0   fuzz finished cleanly (may or may not have found crashes)
#   1   pre-flight failed (no AFL, no nvim source, etc.)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DURATION=3600
# ROUNDS is shared between the AFL session (per-input dispatch budget)
# and the per-repro capture step in repro-from-crash.sh. 25 is short
# enough for AFL to iterate fast and long enough for the bugs in
# doc/crashes/ to fire.
CAPTURE_ROUNDS="${ROUNDS:-25}"
DO_PULL=1
DO_BUILD=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --duration) DURATION="$2"; shift 2 ;;
    --no-pull)  DO_PULL=0; shift ;;
    --no-build) DO_BUILD=0; shift ;;
    --help|-h)
      grep '^# ' "$0" | sed 's/^# //; s/^#//' ; exit 0 ;;
    *)  echo "unknown arg: $1" >&2 ; exit 2 ;;
  esac
done

DATE="$(date -u +%F)"
DATETIME="$(date -u +%Y-%m-%d_%H%M%S)"
TS="$(date -u +%FT%TZ)"
REPORT_DIR="$ROOT/reports/$DATETIME"
mkdir -p "$REPORT_DIR"/repros

# Single source of truth for the ASAN_OPTIONS used in the AFL fuzz
# session and (passed via env) in the per-repro capture/verify
# steps. Mirrored into report.json's `runtime.asan_options` field
# and into each repro.lua's footer so reproductions match the run
# exactly. soft_rss_limit_mb is AFL-side only; repro capture
# inherits the rest verbatim.
FUZZ_ASAN_OPTIONS='detect_leaks=0:abort_on_error=1:symbolize=0:allocator_may_return_null=1:soft_rss_limit_mb=8192'
REPRO_ASAN_OPTIONS='detect_leaks=0:abort_on_error=1:symbolize=0:allocator_may_return_null=1'

FUZZ_LOG="$REPORT_DIR/fuzz.log"

# Resolve build artifact paths. CI runners run on a fresh checkout
# each day, so always run a full build. Local runs reuse the existing
# build-afl/bin/nvim if it's newer than deps/neovim/HEAD; the rebuild
# takes ~3-5 min so we want to skip when possible.
NVIM_BIN="$ROOT/deps/neovim/build-afl/bin/nvim"

# Sanity checks: refuse to run if the env is broken.
require_prereqs() {
  for cmd in git timeout afl-fuzz; do
    command -v "$cmd" >/dev/null 2>&1 || {
      echo "fatal: $cmd not in PATH" >&2 ; return 1 ;}
  done
  [[ -x "$ROOT/fuzz-crashhunter.sh" ]] || { echo "fatal: fuzz-crashhunter.sh missing" >&2 ; return 1 ;}
  [[ -x "$ROOT/scripts/repro-all.sh" ]]  || { echo "fatal: scripts/repro-all.sh missing"  >&2 ; return 1 ;}
  [[ -x "$ROOT/scripts/build-nvim-afl.sh" ]] || { echo "fatal: scripts/build-nvim-afl.sh missing" >&2 ; return 1 ;}
  return 0
}

# Refresh deps/neovim + rebuild nvim if upstream advanced. Skippable
# via --no-pull for repeat invocations on the same day.
refresh_neovim() {
  local NVIM_SRC="$ROOT/deps/neovim"
  if [[ ! -d "$NVIM_SRC/.git" ]]; then
    echo "fatal: deps/neovim is not a git checkout; clone first" >&2
    return 1
  fi
  if (( DO_PULL )); then
    if ! bash "$ROOT/scripts/update-nvim.sh" --no-build >/dev/null 2>&1; then
      echo "WARN: deps/neovim pull failed; proceeding with current tree" >&2
    fi
  fi
  if (( DO_BUILD )) && { [[ ! -x "$NVIM_BIN" ]] || is_nvim_stale; }; then
    echo "==> rebuilding AFL+ASAN nvim..."
    # Don't redirect the build log to disk; let it stream into the
    # GH Actions step log. The user can read it directly there and
    # we don't pollute reports/<date>/ with a 100kB+ file.
    ASAN_OPTIONS="detect_leaks=0:abort_on_error=0" \
      bash "$ROOT/scripts/build-nvim-afl.sh" --asan \
      || { echo "fatal: nvim build failed (see step log above)" >&2 ; return 1 ;}
  fi
  [[ -x "$NVIM_BIN" ]] || { echo "fatal: build missing, pass without --no-build" >&2 ; return 1 ; }
  return 0
}

# Was the cached build from a previous run, before today's upstream?
is_nvim_stale() {
  local mtime
  mtime=$(stat -c '%Y' "$NVIM_BIN" 2>/dev/null || echo 0)
  local src_mtime
  src_mtime=$(git -C "$ROOT/deps/neovim" log -1 --format=%ct HEAD 2>/dev/null || echo 0)
  (( src_mtime > mtime ))
}

mkdir_corpus() {
  local seed="$ROOT/afl-corpus-bytes"
  if [[ ! -d "$seed" ]] || [[ -z "$(ls -A "$seed" 2>/dev/null)" ]]; then
    bash "$ROOT/scripts/make-seed-corpus.sh" bytes >/dev/null
  fi
}

# Run AFL for $DURATION seconds against the fuzz-crashhunter harness.
# Save all crashes to afl-findings/daily-<date>/. Snapshot the corpus
# to afl-snapshots/daily-<date>/. Teardown removes AFL's transient
# sync dirs but keeps the findings.
run_fuzz() {
  local FINDINGS="$ROOT/afl-findings/daily-$DATE"
  local SNAPSHOT="$ROOT/afl-snapshots/daily-$DATE"
  rm -rf "$FINDINGS" "$SNAPSHOT"
  mkdir -p "$ROOT/afl-corpus-bytes"

  echo "==> running AFL for ${DURATION}s..."
  echo "==> findings: $FINDINGS"
  echo "==> log: $FUZZ_LOG"

  # AFL++ 5.03a's setup_dirs_fds() does NOT mkdir -p the -o target
  # itself; the parent must already exist or it errors out with
  # 'Unable to create ...: No such file or directory' before any
  # fuzzing happens (turning a 1h run into a 2s crash -> 0 repros).
  mkdir -p "$FINDINGS" "$SNAPSHOT"

  (
    cd "$ROOT"
    ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:symbolize=0:allocator_may_return_null=1:soft_rss_limit_mb=8192" \
    AFL_SKIP_CPUFREQ=1 \
    AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 \
    ROUNDS="$CAPTURE_ROUNDS" \
    timeout "$DURATION" "$ROOT/fuzz-crashhunter.sh" \
      -i afl-corpus-bytes -o "$FINDINGS" -t 30000 \
      2>&1 || true
  ) >"$FUZZ_LOG" 2>&1
  echo "==> AFL finished; $(grep -c 'saved_crash' "$FUZZ_LOG" 2>/dev/null || echo 0) crash events"

  mkdir -p "$ROOT/afl-snapshots"
  [[ -d "$FINDINGS/default/crashes" ]] && \
    cp -r "$FINDINGS/default" "$SNAPSHOT" 2>/dev/null || true
}

# Collapse AFL saved crashes via afl-cmin before per-crash repro.
# A fuzz session typically emits many inputs that hit the same ASAN
# site (same edge coverage), so the 50+ crash files in default/crashes/
# often collapse to 1-3 unique ones. Doing this here turns an O(N)
# repro loop into O(unique). Per-crash repro+minimize is still needed
# because afl-cmin returns AFL binary inputs, not Lua repros.
afl_cmin_crashes() {
  local FINDINGS="$ROOT/afl-findings/daily-$DATE"
  local CRASHES="$FINDINGS/default/crashes"
  local UNIQ="$FINDINGS/uniq-crashes"
  [[ -d "$CRASHES" ]] || return 0
  shopt -s nullglob
  local n=$(printf '%s\n' "$CRASHES"/id:* | wc -l)
  shopt -u nullglob
  (( n > 0 )) || { echo "no crashes to collapse" >&2; return 0; }
  (( n > 1 )) || { echo "only 1 crash; afl-cmin unnecessary" >&2; export REPRO_FINDINGS_DIR="$CRASHES"; return 0; }

  local cmin
  cmin=$(command -v afl-cmin 2>/dev/null || true)
  [[ -x "$cmin" ]] || { echo "WARN: afl-cmin not found; using full crash set" >&2; export REPRO_FINDINGS_DIR="$CRASHES"; return 0; }

  rm -rf "$UNIQ"
  mkdir -p "$UNIQ"
  echo "==> afl-cmin collapsing $n crash(es)..."
  if ASAN_OPTIONS="$FUZZ_ASAN_OPTIONS" \
       ROUNDS="$CAPTURE_ROUNDS" \
       "$cmin" -C -i "$CRASHES" -o "$UNIQ" -m none -t 5000 \
         -- "$NVIM_BIN" \
           --headless --clean -i NONE -n \
           -l "$ROOT/fuzz-crashhunter.lua" \
           @@ \
       >"$REPORT_DIR/afl-cmin.log" 2>&1; then
    :
  fi
  local uniq_n
  uniq_n=$(ls -1 "$UNIQ"/id:* 2>/dev/null | wc -l || echo 0)
  echo "==> afl-cmin kept $uniq_n / $n crash(es) (see $REPORT_DIR/afl-cmin.log)"
  if (( uniq_n > 0 )); then
    export REPRO_FINDINGS_DIR="$UNIQ"
  else
    echo "WARN: afl-cmin produced no output; falling back to full crash set" >&2
    export REPRO_FINDINGS_DIR="$CRASHES"
  fi
}

# Convert every AFL saved crash into a self-contained (minimized) repro.
# Call repro-from-crash.sh directly per crash -- repro-all.sh iterates
# over a crash DIR and writes to $ROOT/repros/, neither matches this
# caller (we need per-crash $REPORT_DIR/repros/<id>/ output, with build.log
# captured alongside). repro-from-crash.sh writes repro.lua, .min.lua,
# and .dofile.lua to whatever $2 points at.
generate_repros() {
  local FINDINGS="${REPRO_FINDINGS_DIR:-$ROOT/afl-findings/daily-$DATE/default/crashes}"
  local REPRO_OUT="$REPORT_DIR/repros"
  [[ -d "$FINDINGS" ]] || { echo "no findings at $FINDINGS" >&2 ; return 0 ;}
  shopt -s nullglob
  local raw=( "$FINDINGS"/id:* )
  shopt -u nullglob
  local crashes=()
  for c in "${raw[@]}"; do
    [[ -f "$c" ]] || continue
    case "$c" in
      *.repro.lua|*.min.lua) continue ;;
    esac
    crashes+=( "$c" )
  done
  [[ ${#crashes[@]} -gt 0 ]] || { echo "no crash inputs to process" >&2 ; return 0 ;}

  # Total wall-clock budget for this stage. Workflow timeout-minutes is
  # 120; fuzz uses DURATION (default 60min); teardown + write_json_report
  # need ~5min. Default 50min for repro+minimize leaves 5min slack.
  local budget_sec="${GENERATE_REPROS_BUDGET_SEC:-3000}"
  local start_ts=$(date +%s)
  export start_ts budget_sec REPRO_OUT ROOT \
         ASAN_OPTIONS_FOR_REPRO="$REPRO_ASAN_OPTIONS"

  echo "==> generating reporos for ${#crashes[@]} crash(es) (budget=${budget_sec}s, parallel=$(nproc))..."

  # Per-crash directory layout: reports/<date>/repros/<id>/{crash.bin,
  # repro.lua, repro.min.lua, verify.err}. The <id> matches what
  # write_md_report / write_json_report use, so the on-disk path and
  # the report's per-crash key line up.
  printf '%s\n' "${crashes[@]}" \
    | xargs -P "$(nproc)" -I{} bash -c '
        set -euo pipefail
        crash="$1"
        elapsed=$(( $(date +%s) - start_ts ))
        if (( elapsed >= budget_sec )); then
          echo "  [$(basename "$crash")] SKIP (budget exhausted at ${elapsed}s)"
          exit 0
        fi
        # Sanitize: colons break NTFS (artifact upload downloads as zip
        # on Windows runners); matches write_json_report keying.
        id=$(basename "$crash" | tr ",/:" "____")
        out="$REPRO_OUT/$id/repro.lua"
        mkdir -p "$(dirname "$out")"
        # Preserve the raw AFL input bytes alongside the repro.
        # Self-contained repros are lossy (from-log.lua rebuilds ops
        # from the dispatch log; partial ASAN-aborted captures are not
        # always recoverable); crash.bin is ground truth for re-fuzzing.
        cp -f "$crash" "$REPRO_OUT/$id/crash.bin"
        if ASAN_OPTIONS_FOR_REPRO="$ASAN_OPTIONS_FOR_REPRO" \
             bash "$ROOT/scripts/repro-from-crash.sh" --minimize "$crash" "$out"; then
          echo "  [$id] OK"
        else
          echo "  [$id] FAILED"
        fi
      ' _ {}
}

# Build report.json. The on-disk layout is report.json only; any
# historical report.md is gone.
write_json_report() {
  local FINDINGS="$ROOT/afl-findings/daily-$DATE/default/crashes"
  local FINDINGS_REL="afl-findings/daily-$DATE/default/crashes"
  local repro_entries=()
  if [[ -d "$FINDINGS" ]]; then
    for c in "$FINDINGS"/id:*; do
      [[ -f "$c" ]] || continue
      case "$c" in
        *.repro.lua|*.min.lua) continue ;;
      esac
      local id kind rounds size asan_lines=0
      id=$(basename "$c" | tr ',/:' '____')
      local out="$REPORT_DIR/repros/$id"
      # Pick the strongest repro we have. repro.min.lua (post-minimizer)
      # > repro.lua (full self-contained) > crash.bin (raw AFL input;
      # only useful when bin/from-log.lua couldn't reconstruct).
      if [[ -f "$out/repro.min.lua" ]]; then
        kind="min"
        size=$(wc -c < "$out/repro.min.lua" 2>/dev/null || echo 0)
      elif [[ -f "$out/repro.lua" ]]; then
        kind="full"
        size=$(wc -c < "$out/repro.lua" 2>/dev/null || echo 0)
      else
        kind="raw"
        size=$(wc -c < "$out/crash.bin" 2>/dev/null || echo 0)
      fi
      # rounds: number of dispatch rounds the bug actually needs.
      #   kind=min   -> bisected floor from minimize-repro.sh step 2
      #   kind=full  -> captured ROUNDS (max round comment in repro.lua)
      #   kind=raw   -> 0 (only AFL input bytes preserved, no replay)
      case "$kind" in
        min)
          rounds=$(grep -oE 'do  -- round [0-9]+$' "$out/repro.min.lua" 2>/dev/null \
            | grep -oE '[0-9]+' | sort -n | tail -1)
          rounds=${rounds:-0}
          ;;
        full)
          rounds=$(grep -oE 'do  -- round [0-9]+$' "$out/repro.lua" 2>/dev/null \
            | grep -oE '[0-9]+' | sort -n | tail -1)
          rounds=${rounds:-0}
          ;;
        *)
          rounds=0
          ;;
      esac
      if [[ -f "$out/verify.err" ]]; then
        local n
        n=$(grep -c AddressSanitizer "$out/verify.err" 2>/dev/null || true)
        n=${n:-0}
        asan_lines=$n
      fi
      # Crash file path: repo-root-relative (no absolute paths in json).
      local crash_rel="$FINDINGS_REL/$(basename "$c")"
      repro_entries+=( "$id|$kind|$rounds|$size|$asan_lines|$crash_rel" )
    done
  fi

  # No AFL crashes this run -> nothing to report. Skip writing report.json
  # entirely so the CI commit step has nothing to persist and bails out.
  if (( ${#repro_entries[@]} == 0 )); then
    echo "no AFL crashes; skipping report.json"
    return 0
  fi

  # Hand off to bin/write-json-report.lua for the actual JSON assembly.
  # Bash side does the per-crash filesystem probe (kinds, sizes, rounds,
  # verify.err ASAN count); the Lua side handles git rev-parse, binary
  # sha256, fuzz.log ASAN count, and the JSON encoding with 2-space
  # indent so the bot's auto-commit diff is meaningful.
  printf '%s\n' "${repro_entries[@]:-}" \
    | nvim -l "$ROOT/bin/write-json-report.lua" \
        --report-dir     "$REPORT_DIR" \
        --crashes-dir    "$FINDINGS" \
        --fuzz-log       "$FUZZ_LOG" \
        --root           "$ROOT" \
        --date           "$DATETIME" \
        --ts             "$TS" \
        --duration       "${DURATION}s" \
        --capture-rounds "$CAPTURE_ROUNDS" \
        --asan-options   "$FUZZ_ASAN_OPTIONS" \
        --nvim-bin       "$ROOT/deps/neovim/build-afl/bin/nvim" \
        --afl-bin        "/usr/local/bin/afl-fuzz" \
        --patches-dir    "patches" \
    > "$REPORT_DIR/report.json"
}

# Persist the report directory by committing in a follow-up step
# (the CI workflow handles that). Locally we leave the artifacts on
# disk under reports/<datetime>/.

# Top-level: run the pipeline. Each helper does its own error
# handling so a missing crash dir doesn't bail the whole run.
# write_json_report skips writing report.json when AFL produced no
# crashes -- the CI commit step then sees nothing to persist.
main() {
  require_prereqs || return 1
  refresh_neovim   || return 1
  mkdir_corpus
  run_fuzz
  afl_cmin_crashes || true
  generate_repros
  write_json_report
  echo
  echo "==> done. json: $REPORT_DIR/report.json"
  return 0
}

_on_term=0
trap '_on_term=1; exit 143' TERM INT
trap '
  if [[ "$_on_term" == 1 && -d "$REPORT_DIR" && ! -f "$REPORT_DIR/report.json" ]]; then
    write_json_report || true
  fi
' EXIT

main "$@"
