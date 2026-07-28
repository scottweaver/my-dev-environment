#!/usr/bin/env bash
# install-agents.sh — symlink Claude Code agent configuration (skills,
# agents, commands, etc.) from this repo into ~/.claude/.
#
# Behavior:
#   - Already-correct symlink → no-op
#   - Symlink pointing elsewhere → re-link
#   - Regular file at the target → backup with timestamp suffix, then link
#   - Nothing at the target → link
#
# Idempotent; safe to re-run.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_SOURCE="$REPO_DIR/shared/claude-code"
CLAUDE_TARGET="$HOME/.claude"

timestamp="$(date +%Y%m%d-%H%M%S)"

link_file() {
  local src="$1"
  local dest="$2"

  mkdir -p "$(dirname "$dest")"

  if [[ -L "$dest" ]]; then
    if [[ "$(readlink -f "$dest")" == "$src" ]]; then
      echo "ok     $dest"
      return
    fi
    echo "relink $dest (was -> $(readlink "$dest"))"
    rm "$dest"
  elif [[ -e "$dest" ]]; then
    local backup="${dest}.bak.${timestamp}"
    echo "backup $dest -> $backup"
    mv "$dest" "$backup"
  else
    echo "link   $dest"
  fi

  ln -s "$src" "$dest"
}

link_tree() {
  local source_dir="$1"
  local target_dir="$2"

  if [[ ! -d "$source_dir" ]]; then
    echo "error: source directory not found: $source_dir" >&2
    exit 1
  fi

  while IFS= read -r -d '' file; do
    rel="${file#"$source_dir"/}"
    link_file "$file" "$target_dir/$rel"
  done < <(find "$source_dir" -type f -print0)
}

if [[ ! -d "$CLAUDE_SOURCE" ]]; then
  echo "error: $CLAUDE_SOURCE not found" >&2
  exit 1
fi

link_tree "$CLAUDE_SOURCE" "$CLAUDE_TARGET"
