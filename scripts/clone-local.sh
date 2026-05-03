#!/usr/bin/env bash
# Clone or sync GitHub repos to a local directory as bare mirrors.
#
# Idempotent: first run clones with --mirror; subsequent runs fetch and
# prune, keeping branches and tags in sync with upstream.
#
# Usage:
#   OWNER=qte77 [VISIBILITY=public] [DEST=./mirrors] scripts/clone-local.sh
#   CONFIG=config/repos.yaml         [DEST=./mirrors] scripts/clone-local.sh
#
# Env:
#   OWNER       GitHub user/org → uses `gh repo list` (mutually exclusive with CONFIG)
#   CONFIG      YAML list of {source: <url>} (default: config/repos.yaml)
#   DEST        Local directory for bare clones (default: ./mirrors)
#   VISIBILITY  Pass-through to `gh repo list --visibility` (public|private|internal)
#   LIMIT       Pass-through to `gh repo list --limit` (default: 1000)
#
# Requires: git, and `gh` (authenticated for private repos) when OWNER is set.
set -euo pipefail

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

DEST="${DEST:-./mirrors}"
mkdir -p "$DEST"

if [ -n "${OWNER:-}" ]; then
  sources=$(gh repo list "$OWNER" --limit "${LIMIT:-1000}" \
    ${VISIBILITY:+--visibility "$VISIBILITY"} \
    --json url -q '.[].url' | sed 's|$|.git|')
else
  sources=$(yq -r '.[].source' "${CONFIG:-config/repos.yaml}")
fi

while read -r src; do
  [ -z "$src" ] && continue
  name=$(basename "$src" .git)
  tgt="$DEST/$name.git"
  if [ -d "$tgt" ]; then
    echo "Updating $name..."
    git -C "$tgt" remote update
  else
    echo "Cloning $name..."
    git clone --mirror "$src" "$tgt"
  fi
done <<< "$sources"
