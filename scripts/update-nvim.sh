#!/usr/bin/env bash
# scripts/update-nvim.sh
# Pull latest nvim master into deps/neovim and rebuild the AFL+ASan
# binary (deps/neovim/build-afl/bin/nvim). The fuzzer and repro
# pipeline both target this binary; the regular ASan build at
# out/nvim is for post-mortem debugging only.
#
# Usage:
#   scripts/update-nvim.sh             # pull + rebuild
#   scripts/update-nvim.sh --no-build  # pull only
#   scripts/update-nvim.sh --reset     # throw away local patches + pull
#
# Side effects:
#   - deps/neovim working tree is fast-forwarded (or merged with ours)
#   - deps/neovim/build-afl/bin/nvim is rebuilt and replaced
#   - any prior crash artifacts in out/ stay around

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NVIM_SRC="$ROOT/deps/neovim"

if [[ ! -d "$NVIM_SRC/.git" ]]; then
  echo "fatal: $NVIM_SRC is not a git checkout" >&2
  echo "       run: git clone --depth 1 https://github.com/neovim/neovim.git deps/neovim" >&2
  exit 2
fi

DO_BUILD=1
RESET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build) DO_BUILD=0; shift ;;
    --reset)    RESET=1;    shift ;;
    *)          echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

cd "$NVIM_SRC"

if (( RESET )); then
  echo "update-nvim: discarding local changes..."
  git checkout -- .
  git clean -fd
fi

echo "update-nvim: fetching upstream master..."
git fetch origin master

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/master)

if [[ "$LOCAL" == "$REMOTE" ]]; then
  echo "update-nvim: already at upstream master ($LOCAL)"
else
  echo "update-nvim: fast-forwarding $LOCAL -> $REMOTE"
  if ! git merge --ff-only origin/master; then
    echo "fatal: local changes block fast-forward; rerun with --reset" >&2
    exit 1
  fi
fi

if (( DO_BUILD )); then
  echo "update-nvim: rebuilding AFL+ASan build..."
  ASAN_OPTIONS="detect_leaks=0:abort_on_error=0" \
    "$ROOT/scripts/build-nvim-afl.sh" --asan
  echo "update-nvim: done.  deps/neovim/build-afl/bin/nvim updated."
else
  echo "update-nvim: --no-build set, skipping build"
fi
