#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALIASES_SRC="$REPO_DIR/aliases"
GITCONFIG="$HOME/.gitconfig"
BACKUP="$GITCONFIG.bak"

if [[ ! -f "$ALIASES_SRC" ]]; then
  echo "error: aliases file not found: $ALIASES_SRC" >&2
  exit 1
fi

if [[ -f "$GITCONFIG" ]]; then
  cp -f "$GITCONFIG" "$BACKUP"
  echo "backup $GITCONFIG -> $BACKUP"
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
{ printf '[alias]\n'; cat "$ALIASES_SRC"; } > "$tmp"

# Validate the source parses as a git config file.
git config --file "$tmp" --list >/dev/null

while IFS= read -r key; do
  value="$(git config --file "$tmp" "$key")"
  git config --global "$key" "$value"
  echo "set    $key"
done < <(git config --file "$tmp" --name-only --get-regexp '^alias\.')

echo "done."
