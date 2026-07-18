#!/usr/bin/env bash
# fuzz-crashhunter.sh -- AFL++ launcher for fuzz-crashhunter.lua.
#
# Same dispatch contract as fuzz-afl.sh but bound to the targeted
# crash-pattern fuzzer instead of fuzz.lua's broad-coverage dispatch.
# Pass `@@` for AFL to substitute the corpus path; fuzz-crashhunter.lua
# consumes the bytes via lib/fuzz-common.lua's resolve_bytes().
#
# Usage:
#   ./fuzz-crashhunter.sh -i afl-corpus-bytes -o afl-findings-bytes
#   ./fuzz-crashhunter.sh -- -M master -S slave1 -i ... -o ...
#
# Environment overrides (same as fuzz-afl.sh):
#   NVIM_BIN       AFL-instrumented nvim path (auto-detect by default)
#   VIMRUNTIME     runtime/ dir (default ./deps/neovim/runtime)
#   ROUNDS         dispatch budget per run (default 200)
#   AFL_TIMEOUT    per-exec timeout in ms (default 30000)
#   AFL_ASAN_OPTS  ASAN_OPTIONS (default detect_leaks=0:abort_on_error=1:symbolize=0)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

_resolve_nvim_bin() {
  if [[ -n "${NVIM_BIN:-}" && -x "$NVIM_BIN" ]]; then
    printf '%s\n' "$NVIM_BIN"
    return 0
  fi
  local candidate
  for candidate in $ROOT/deps/neovim/build-afl/bin/nvim; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  # Fall back to the system nvim (best-effort, no AFL coverage
  # feedback; only useful for replaying a captured log).
  if command -v nvim >/dev/null 2>&1; then
    command -v nvim
    return 0
  fi
  echo "fuzz-crashhunter: no nvim binary found; set NVIM_BIN or run scripts/build-nvim-afl.sh" >&2
  return 1
}

NVIM_BIN="$(_resolve_nvim_bin)"
export NVIM_BIN
export VIMRUNTIME="${VIMRUNTIME:-$ROOT/deps/neovim/runtime}"
export ROUNDS="${ROUNDS:-80}"
export FUZZ_LUA="${FUZZ_LUA:-$ROOT/fuzz-crashhunter.lua}"

# Prefer the locally-patched afl-fuzz (fork-server race fix). Falls back
# to PATH's afl-fuzz if the patched binary is absent -- the unpatched
# 5.00c binary still works but misclassifies some ASAN crashes as
# timeouts. See doc/crashes/ for the upstream-not-tracked race.
_resolve_afl_fuzz() {
  if [[ -n "${AFL_FUZZ_BIN:-}" && -x "$AFL_FUZZ_BIN" ]]; then
    printf '%s\n' "$AFL_FUZZ_BIN"; return 0
  fi
  if [[ -x /home/phan/b/aflplusplus/afl-fuzz ]]; then
    printf '%s\n' /home/phan/b/aflplusplus/afl-fuzz; return 0
  fi
  command -v afl-fuzz
}
AFL_BIN="$(_resolve_afl_fuzz)"
if [[ ! -x "$AFL_BIN" ]]; then
  echo "fuzz-crashhunter: no afl-fuzz binary found" >&2
  exit 2
fi

# Default ASAN_OPTIONS. Notable choices baked in here so the user never
# has to remember them:
#   detect_leaks=0           nvim leaks cjson/luv at exit; LSAN would scream
#   abort_on_error=1         ASAN abort() on first error -- AFL classifies
#                            signal 6 as a crash reliably
#   symbolize=0              required by AFL++ 5.03a check_asan_opts()
#                            (it refuses custom ASAN_OPTIONS otherwise)
#   allocator_may_return_null=1   OOM returns NULL, no abort on alloc fail
#                            (afl-1 notes_for_asan.html recommends this)
#   soft_rss_limit_mb=8192    ASAN stops reporting after 8 GB RSS --
#                            virtual address is fine to be huge on 64-bit,
#                            only RSS costs real RAM
#   log_path=...             every ASAN-detected error writes the full
#                            report to <log_path>.<pid>. Without this,
#                            ASAN's DisableCoreDumperIfNecessary() forces
#                            RLIMIT_CORE=0 and coredumpctl can't recover
#                            the stack. We point at a project-local
#                            directory so the artifact survives across
#                            sessions and isn't at risk of being on a
#                            read-only mount.
ASAN_LOG_DIR="${ASAN_LOG_DIR:-$ROOT/afl-asan-logs}"
mkdir -p "$ASAN_LOG_DIR"
# Wipe stale logs from prior runs only when an explicit fresh start
# would help (don't shred on every invocation if AFL reuses this dir).
# If you want fresh logs, set AFL_ASAN_LOG_FRESH=1.
if [[ "${AFL_ASAN_LOG_FRESH:-1}" == "1" ]]; then
  rm -f "$ASAN_LOG_DIR"/crash.* 2>/dev/null || true
fi
export ASAN_OPTIONS="${AFL_ASAN_OPTS:-detect_leaks=0:abort_on_error=1:symbolize=0:allocator_may_return_null=1:soft_rss_limit_mb=8192:log_path=$ASAN_LOG_DIR/crash}"
export AFL_SKIP_CPUFREQ=1
export AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1
export AFL_MAP_SIZE="${AFL_MAP_SIZE:-65536}"

# Note for the user in case they want to grep the file later.
echo "fuzz-crashhunter: ASAN reports -> $ASAN_LOG_DIR/crash.<pid>" >&2

# ASAN on 64-bit reserves ~20 TB virtual address for its shadow map;
# RLIMIT_AS truncation in AFL causes the fork server to SIGABRT before
# any input. Strip any -m the caller may have forwarded in $@ below.
# The soft_rss_limit_mb in ASAN_OPTIONS gives RSS-only protection.

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  cat <<EOF
Usage: $0 [-h] [afl-fuzz options ...]

Example:
  $0 -i afl-corpus-bytes -o afl-findings-bytes
  ROUNDS=120 $0 -i afl-corpus-bytes -o afl-findings-bytes -t 30000
  $0 -i afl-corpus-bytes -o afl-findings-bytes -M master

NOTE 1: AFL options go directly; do NOT pass '--' to start the
target binary argv. The launcher hardcodes the nvim invocation
(\$NVIM_BIN -l \$FUZZ_LUA @@) and any '--' (and tokens after it)
in argv are dropped with a warning. For example,
'$0 -i corp -o out -- -M master' is WRONG; use
'$0 -i corp -o out -M master' instead.

NOTE 2: Distributed mode (AFL++ 5.03a) accepts EITHER -M <name> OR
-S <name> per process, never both. Multi-node fuzzing requires
multiple processes -- one per terminal:
  Terminal 1 (master):  $0 -i corp -o out -M master
  Terminal 2 (slave 1): $0 -i corp -o out -S slave1
  Terminal 3 (slave 2): $0 -i corp -o out -S slave2
Each slave auto-syncs to master's out_dir.

Tunables (set as env vars BEFORE invoking this script):
  ROUNDS         dispatch budget per run (default 80; -t 10000 fits ~25ms/run)
  FUZZ_LUA       path to fuzzer script (default ./fuzz-crashhunter.lua)
  NVIM_BIN       AFL-instrumented nvim path (auto-detected)
  AFL_FUZZ_BIN   afl-fuzz binary path. Resolution order:
                   1. \$AFL_FUZZ_BIN if set and executable
                   2. /home/phan/b/aflplusplus/afl-fuzz (local patched build)
                   3. afl-fuzz on PATH
                 The patched build forkserver race-fixes a lost-crash
                 issue where ASAN+64-bit child SIGABRT was misclassified
                 as timeout; see patches/afl-forkserver.c.patch.
  VIMRUNTIME     runtime/ dir (default ./deps/neovim/runtime)
  AFL_TIMEOUT    per-exec timeout in ms (default 30000)
  AFL_ASAN_OPTS  ASAN_OPTIONS override
                 default: detect_leaks=0:abort_on_error=1:symbolize=0
                          allocator_may_return_null=1:soft_rss_limit_mb=8192
                          + log_path=\$ASAN_LOG_DIR/crash
  ASAN_LOG_DIR   where ASAN reports land (default ./afl-asan-logs)

ASAN-on-64-bit caveat (per afl notes_for_asan.html):
  ASAN on 64-bit reserves ~20 TB of virtual address space for its
  shadow map. On this nvim binary the VmPeak at startup is ~21 TB.
  DO NOT pass -m: AFL's child memory limit (RLIMIT_AS) truncates
  ASAN's startup allocation and the fork server aborts with SIGABRT
  before any input is processed.

  For real OOM protection, use one of:
    1. cgroups (root-required): see afl's experimental/asan_cgroups
    2. recidivm to find exact ASAN virtual size and pass that as -m
    3. ASAN's own soft_rss_limit_mb (already in ASAN_OPTIONS above) to
       stop reporting after 8 GB resident -- the virtual size is
       harmless, only RSS costs real RAM

The fuzzer targets the crash families documented in doc/crashes/:
autocmd reentrancy, last-tab + float boundary, extmark + signcol /
statuscolumn sync, undolevels=-1 + extmark, and libvterm VLA
stack-overflow. Each dispatch is one op or scenario; ROUNDS rounds
per corpus entry. AFL finds most new edges in the first 100-200
rounds for this fuzzer because every op is biased toward high-density
crash paths.
EOF
  exit 0
fi

afl_args=()
have_i=0
have_o=0
have_t=0
have_m=0
have_I=0
# If user passed `--`, everything after it is interpreted as target
# binary args. We do NOT forward that part -- the launcher hardcodes
# the nvim invocation it wants. Stop at the first `--` so it doesn't
# break AFL's option parsing (argv-after-`--` is treated as target
# binary by getopt).
seen_dashdash=0
for arg in "$@"; do
  if [[ $seen_dashdash -eq 1 ]]; then
    echo "fuzz-crashhunter: dropping token after '--': '$arg'" >&2
    continue
  fi
  if [[ "$arg" == "--" ]]; then
    seen_dashdash=1
    echo "fuzz-crashhunter: stripping user's '--' before AFL options; the launcher provides its own nvim invocation." >&2
    continue
  fi
  if [[ "$arg" == "-i" || "$arg" == "--input" ]]; then
    have_i=1
  elif [[ "$arg" == "-o" || "$arg" == "--output" ]]; then
    have_o=1
  elif [[ "$arg" == "-t" ]]; then
    have_t=1
  elif [[ "$arg" == "-m" ]]; then
    have_m=1
    echo "fuzz-crashhunter: dropping '-m' from argv; on 64-bit + ASAN, ASAN reserves ~21 TB virtual address space and any -m cap truncates the fork server." >&2
    echo "  Use ASAN_OPTIONS=soft_rss_limit_mb or cgroups for OOM protection." >&2
    continue
  elif [[ "$arg" == "-I" ]]; then
    have_I=1
  fi
  afl_args+=("$arg")
done
if (( ! have_i )); then
  afl_args+=(-i "${AFL_CORPUS_DIR:-$ROOT/afl-corpus-bytes}")
fi
if (( ! have_o )); then
  afl_args+=(-o "${AFL_FINDINGS_DIR:-$ROOT/afl-findings-bytes}")
fi
if (( ! have_t )); then
  afl_args+=(-t "${AFL_TIMEOUT:-30000}")
fi

# Lost-crash safety net: even when AFL's fork-server v1 misclassifies a
# child SIGABRT as not-a-crash (a known AFL++ 5.00 race on 64-bit +
# ASAN), this callback fires from the parent before AFL's bookkeeping
# runs, copying the corpus entry that triggered the abnormal exit to a
# side directory. The callback runs as a shell command; %s is replaced
# with the input file path. See docs of -I in afl-fuzz(1).
if (( ! have_I )); then
  SNAPSHOT_DIR="$ROOT/afl-snapshots"
  mkdir -p "$SNAPSHOT_DIR"
  # `set` strings break in weird ways under AFL's -I shell expansion;
  # keep this command free of $ expansions beyond %s so we don't lose
  # the input path.
  SNAPSHOT_CMD='mkdir -p '"$SNAPSHOT_DIR"'/captured && ts=$(date +%Y%m%d-%H%M%S) && cp -n %s '"$SNAPSHOT_DIR"'/captured/${ts}-$((RANDOM)) && echo "${ts} ${0}: captured %s" >> '"$SNAPSHOT_DIR"'/log.txt'
  afl_args+=(-I "$SNAPSHOT_CMD")
fi

exec "$AFL_BIN" \
  "${afl_args[@]}" \
  -- "$NVIM_BIN" \
    --headless \
    --clean \
    -i NONE \
    -n \
    -l "$FUZZ_LUA" \
    @@