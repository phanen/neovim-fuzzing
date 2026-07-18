#!/usr/bin/env bash
# scripts/make-seed-corpus.sh
# Generate the AFL seed corpus that fuzz-crashhunter.sh needs.
# AFL refuses to start without seeds ("No usable test cases in <dir>").
#
# Strategy: 1KB /dev/urandom seeds. AFL mutates each byte
# independently; bigger seeds give the autodictionary more signal.
#
# Usage:
#   scripts/make-seed-corpus.sh                       # populate afl-corpus-bytes
#   scripts/make-seed-corpus.sh bytes my-class        # custom directory name
#
# Idempotent: existing seeds are left alone.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Always writes into afl-corpus-bytes/ (the canonical corpus dir for
# the byte-stream fuzzer). Custom names go under afl-corpus-<name>/.
SEED_COUNT=4
SEED_SIZE=1024

write_byte_seeds() {
  local dir="$1"
  mkdir -p "$dir"
  for i in $(seq 1 "$SEED_COUNT"); do
    if [[ -f "$dir/seed-$i" ]]; then continue; fi
    dd if=/dev/urandom of="$dir/seed-$i" bs="$SEED_SIZE" count=1 status=none
  done
}

if [[ $# -gt 0 && "$1" != "bytes" ]]; then
  # Custom name: scripts/make-seed-corpus.sh my-class → afl-corpus-my-class
  dir="$ROOT/afl-corpus-$1"
else
  dir="$ROOT/afl-corpus-bytes"
fi

write_byte_seeds "$dir"
echo "make-seed-corpus: $dir ($(ls "$dir" | wc -l) seeds)"
