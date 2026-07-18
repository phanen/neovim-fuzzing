#!/usr/bin/env bash
# scripts/minimize-repro.sh -- Iteratively shrink a captured dispatch
# log's emitted repro.lua down to the minimum number of vim.api / vim.cmd
# calls that still triggers the ASan crash.
#
# Strategy:
#   1. Run bin/from-log.lua to produce the full self-contained repro
#      (with per-round `do ... end` blocks for all captured rounds).
#   2. Binary search the minimum number of rounds K (1..max_round)
#      such that the first K rounds + final teardown still crash.
#   3. Within those K rounds, run delta-debugging per round: drop ops
#      from end, then drop ops from middle one at a time, keeping only
#      the ops that ASAN still requires.
#   4. Try dropping whole rounds (a round can sometimes be skipped
#      entirely if its state is rebuilt by later rounds).
#
# Usage:
#   scripts/minimize-repro.sh <cap.log>
#
# Writes the minimized repro to /tmp/minimize/MIN.lua (or
# /tmp/minimize/MINIMAL.lua if whole-round drop isn't tried) and prints
# per-round op counts.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

cap_log="${1:-}"
[ -z "$cap_log" ] && { echo "usage: $0 <cap.log>" >&2; exit 2; }
[ -f "$cap_log" ] || { echo "no such file: $cap_log" >&2; exit 2; }

mkdir -p /tmp/minimize && rm -f /tmp/minimize/*

# Step 1: emit full self-contained repro
echo "step 1/4: bin/from-log.lua -> /tmp/minimize/full.lua"
bin/from-log.lua "$cap_log" /tmp/minimize/full.lua >/dev/null
max_round=$(grep -oE 'do  -- round [0-9]+$' /tmp/minimize/full.lua \
  | grep -oE '[0-9]+' | sort -n | tail -1)
echo "  max_round = $max_round"

# Step 2: binary search minimum number of rounds
echo "step 2/4: binary search rounds K=[1, $max_round]"
build_round_prefix() {
  local k="$1" out="$2"
  python3 - "$k" "$out" /tmp/minimize/full.lua <<'PY'
import sys
k = int(sys.argv[1]); out = sys.argv[2]; src_path = sys.argv[3]
src = open(src_path).read().split('\n')
rounds = []
for i, ln in enumerate(src):
    s = ln.strip()
    if s.startswith('do  -- round ') and 'extra' not in s and 'replayed' not in s:
        n = int(s.split('round ')[1])
        rounds.append((i, n))
teardown_start = next(i for i, ln in enumerate(src) if 'Final teardown' in ln)
# end of last regular round: line just before 'extra round' or teardown
last_reg_end = None
for j in range(rounds[-1][0] + 1, len(src)):
    s = src[j].strip()
    if s.startswith('do  -- extra') or 'Final teardown' in src[j]:
        last_reg_end = j - 1
        break
# footer
footer_start = None
for i, ln in enumerate(src):
    if ln.strip() == '-- ':
        footer_start = i
        break
header = '\n'.join(src[:rounds[0][0]])
teardown = '\n'.join(src[teardown_start:teardown_start + len(src) - teardown_start])
if footer_start and footer_start > teardown_start:
    teardown = '\n'.join(src[teardown_start:footer_start])
parts = [header]
for i, (line, n) in enumerate(rounds):
    if n > k:
        break
    end = rounds[i + 1][0] - 1 if i + 1 < len(rounds) else last_reg_end
    parts.append('\n'.join(src[line:end + 1]))
parts.append(teardown)
if footer_start:
    parts.append('\n'.join(src[footer_start:]))
open(out, 'w').write('\n'.join(parts))
PY
}

test_candidate() {
  local repro="$1"
  ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:symbolize=0:allocator_may_return_null=1" \
    FUZZ_QUIET=1 \
      timeout 30 "$ROOT/deps/neovim/build-afl/bin/nvim" --headless --clean -i NONE -n \
        -l "$repro" >/dev/null 2>/dev/null \
        && return 1 || return 0
}

lo=1
hi=$max_round
best=0
while [ $lo -le $hi ]; do
  mid=$(( (lo + hi) / 2 ))
  candidate=/tmp/minimize/repro_k$mid.lua
  build_round_prefix "$mid" "$candidate"
  if test_candidate "$candidate"; then
    best=$mid
    hi=$(( mid - 1 ))
    echo "  K=$mid: rc=134 (crash)"
  else
    lo=$(( mid + 1 ))
    echo "  K=$mid: rc=0  (no crash)"
  fi
done

if [ $best -eq 0 ]; then
  echo "  no K triggered; using full repro"
  best=$max_round
fi

build_round_prefix "$best" /tmp/minimize/minimal.lua
echo "  -> K=$best rounds kept: /tmp/minimize/minimal.lua"

# Step 3: per-round op-level minimization
echo "step 3/4: per-round delta-debugging on /tmp/minimize/minimal.lua"
python3 - <<'PY'
import sys, subprocess, os, random
repro_path = '/tmp/minimize/minimal.lua'
out_path = '/tmp/minimize/MIN.lua'
orig = open(repro_path).read().split('\n')

i = 0
while i < len(orig) and not orig[i].strip().startswith('do  -- round '):
    i += 1
header_end = i
teardown_start = next(j for j, ln in enumerate(orig) if 'Final teardown' in orig[j])
rounds = []
while i < teardown_start:
    s = orig[i].strip()
    if not s.startswith('do  -- round '):
        i += 1
        continue
    j = i + 1
    while j < teardown_start:
        if orig[j].strip() == 'end' and not orig[j].startswith(' '):
            break
        j += 1
    rounds.append((i, j))
    i = j + 1

round_numbers = []
for rs, _ in rounds:
    s = orig[rs].strip()
    if s.startswith('do  -- round ') and 'extra' not in s and 'replayed' not in s:
        n = int(s.split('round ')[1])
        round_numbers.append(n)
    else:
        round_numbers.append(None)

# Immutable set of all original op lines per round (for filtering
# in get_full_text — must distinguish dropped ops from non-op lines).
all_ops_per_round = []
ops_per_round = []  # mutated during reduction
for rs, re_ in rounds:
    ops = []
    for k in range(rs + 1, re_):
        if orig[k].lstrip().startswith('safe('):
            ops.append(k)
    ops_per_round.append(list(ops))
    all_ops_per_round.append(set(ops))

header = '\n'.join(orig[:header_end])
teardown = '\n'.join(orig[teardown_start:])

def get_full_text(round_subset):
    parts = [header]
    for ri_, (rs, re_) in enumerate(rounds):
        keep = round_subset.get(ri_)
        if keep is None or keep == set():
            continue
        block = [orig[rs]]
        for k in range(rs + 1, re_):
            if k in all_ops_per_round[ri_]:
                if keep is not None and k in keep:
                    block.append(orig[k])
            else:
                block.append(orig[k])
        block.append(orig[re_])
        parts.append('\n'.join(block))
    parts.append(teardown)
    return '\n'.join(parts)

def crash_p(repro_text):
    p = '/tmp/minimize/_test.lua'
    open(p, 'w').write(repro_text)
    env = os.environ.copy()
    env['ASAN_OPTIONS'] = 'detect_leaks=0:abort_on_error=1:symbolize=0:allocator_may_return_null=1'
    env['FUZZ_QUIET'] = '1'
    try:
        rc = subprocess.run(
            ['./deps/neovim/build-afl/bin/nvim', '--headless', '--clean',
             '-i', 'NONE', '-n', '-l', p],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            env=env, timeout=20,
        ).returncode
    except subprocess.TimeoutExpired:
        return False
    return rc == 134 or rc == -6

bset = {ri: set(ops_per_round[ri]) for ri in range(len(rounds))}
assert crash_p(get_full_text(bset)), "baseline fails"
print("  baseline OK", flush=True)

import time
t_start = time.time()
total_attempts = 0
attempt_marker = [0]  # mutable for nested

def crash_p_quiet(repro_text):
    """Same as crash_p but prints a progress dot every 20 attempts so
    the user knows the loop is alive (each attempt spawns an nvim
    subprocess and takes ~0.2-1s)."""
    attempt_marker[0] += 1
    if attempt_marker[0] % 20 == 0:
        elapsed = time.time() - t_start
        print(f"    [{elapsed:5.0f}s] tried {attempt_marker[0]} drop candidates",
              flush=True)
    return crash_p(repro_text)

# Reduce ops within each round
for ri in range(len(rounds)):
    initial = len(ops_per_round[ri])
    if initial <= 1:
        continue
    print(f"  round {round_numbers[ri]} (start {initial} ops): "
          f"trying end-drop...", flush=True)
    ops = list(ops_per_round[ri])
    end_dropped = 0
    while len(ops) > 1:
        last = ops[-1]
        subset = {r: set(ops_per_round[r]) for r in range(len(rounds))}
        subset[ri].discard(last)
        if crash_p_quiet(get_full_text(subset)):
            ops.pop()
            ops_per_round[ri] = ops
            end_dropped += 1
        else:
            break
    print(f"    end-drop: removed {end_dropped}, now {len(ops)} ops; "
          f"trying mid-drop...", flush=True)
    k_idx = 1
    mid_dropped = 0
    while k_idx < len(ops) - 1:
        subset = {r: set(ops_per_round[r]) for r in range(len(rounds))}
        subset[ri].discard(ops[k_idx])
        if crash_p_quiet(get_full_text(subset)):
            ops.pop(k_idx)
            ops_per_round[ri] = ops
            mid_dropped += 1
        else:
            k_idx += 1
    elapsed = time.time() - t_start
    print(f"    mid-drop: removed {mid_dropped}; round {round_numbers[ri]}: "
          f"{initial} -> {len(ops)} ops  [{elapsed:5.0f}s]",
          flush=True)

# Try dropping whole rounds
print("  trying whole-round drop...", flush=True)
random.seed(0)
order = list(range(len(rounds)))
random.shuffle(order)
for ri in order:
    subset = {r: set(ops_per_round[r]) for r in range(len(rounds))}
    subset[ri] = set()
    if crash_p_quiet(get_full_text(subset)):
        ops_per_round[ri] = []
        elapsed = time.time() - t_start
        print(f"  DROPPED round {round_numbers[ri]}  [{elapsed:5.0f}s]",
              flush=True)

final_subset = {ri: set(ops_per_round[ri]) for ri in range(len(rounds))}
final_text = get_full_text(final_subset)
open(out_path, 'w').write(final_text)
sz = os.path.getsize(out_path)
total = sum(len(o) for o in ops_per_round)
final_safe = sum(1 for ln in final_text.split('\n') if ln.lstrip().startswith('safe('))
print(f"  FINAL: {total} ops, {final_safe} safe() in text, {sz} bytes", flush=True)
print(f"  crash: {crash_p(final_text)}", flush=True)
PY

echo
echo "step 4/4: final verification"
ls -la /tmp/minimize/MIN.lua 2>/dev/null
ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:symbolize=1:allocator_may_return_null=1" \
  FUZZ_QUIET=1 \
    timeout 30 "$ROOT/deps/neovim/build-afl/bin/nvim" --headless --clean -i NONE -n \
      -l /tmp/minimize/MIN.lua 2>/tmp/minimize/verify.err 1>/dev/null \
      && rc=0 || rc=$?
echo "  rc=$rc  ASAN=$(grep -c AddressSanitizer /tmp/minimize/verify.err)  (PASS if rc=134 and ASAN>0)"

echo
echo "=========================================================================="
echo "MINIMIZED REPRO: /tmp/minimize/MIN.lua"
echo "Round breakdown:"
for r in $(grep -oE 'do  -- round [0-9]+$' /tmp/minimize/MIN.lua | grep -oE '[0-9]+'); do
  c=$(awk "/^do  -- round $r\$/,/^end\$/" /tmp/minimize/MIN.lua | grep -c '^safe(')
  echo "  round $r: $c ops"
done
echo
echo "Run with:"
echo "  VIMRUNTIME=$ROOT/deps/neovim/runtime \\"
echo "  ASAN_OPTIONS=\"detect_leaks=0:abort_on_error=1:symbolize=1:allocator_may_return_null=1\" \\"
echo "    $ROOT/deps/neovim/build-afl/bin/nvim --headless --clean -i NONE -n \\"
echo "      -l /tmp/minimize/MIN.lua"
