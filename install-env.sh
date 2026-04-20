#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NVIM_SOURCE="$REPO_DIR/neovim"
NVIM_TARGET="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
BIN_SOURCE="$REPO_DIR/wezterm"
BIN_TARGET="$HOME/.local/bin"

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
  local find_args=("${@:3}")

  if [[ ! -d "$source_dir" ]]; then
    echo "error: source directory not found: $source_dir" >&2
    exit 1
  fi

  while IFS= read -r -d '' file; do
    rel="${file#"$source_dir"/}"
    link_file "$file" "$target_dir/$rel"
  done < <(find "$source_dir" -type f "${find_args[@]}" -print0)
}

echo "==> neovim config -> $NVIM_TARGET"
link_tree "$NVIM_SOURCE" "$NVIM_TARGET"

echo "==> wezterm scripts -> $BIN_TARGET"
link_tree "$BIN_SOURCE" "$BIN_TARGET" -executable

case ":$PATH:" in
  *":$BIN_TARGET:"*) ;;
  *) echo "warning: $BIN_TARGET is not in \$PATH — add it to your shell rc" >&2 ;;
esac

echo "done."
