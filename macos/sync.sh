# macos/sync.sh — partition: macOS-only setup.
#
# Sourced by envsync when running on Darwin. Runs BEFORE the shared
# partition so Homebrew (and everything the Brewfile installs: zsh, git,
# node, nvim, ...) exists before shared config is applied.
#
# Manages:
#   macos/Brewfile    Homebrew taps/formulae/casks (brew bundle)
#   macos/bin/        -> ~/.local/bin (macOS-only scripts, optional)

MACOS_DIR="$REPO_DIR/macos"

ensure_homebrew() {
  if have brew; then
    log "ok     Homebrew"
    return
  fi
  info "installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Put brew on PATH for the rest of this run (Apple Silicon vs Intel).
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

apply_brewfile() {
  local brewfile="$MACOS_DIR/Brewfile"
  if [[ ! -f "$brewfile" ]]; then
    log "skip   Brewfile (none in repo yet — run 'envsync capture')"
    return
  fi
  have brew || { warn "brew not on PATH; skipping Brewfile"; return 0; }
  info "brew bundle ($brewfile)"
  brew bundle --file="$brewfile" || warn "brew bundle finished with errors (see above)"
}

# iTerm2 settings sync: iTerm natively supports loading its settings from
# a custom folder, and (with "Save changes: Automatically" set in its
# General > Settings pane) writes changes straight back to that folder.
# Pointing it at the repo makes macos/iterm/com.googlecode.iterm2.plist
# the live settings file — repo-is-truth, same model as the symlinks.
configure_iterm() {
  local prefs_dir="$MACOS_DIR/iterm"
  [[ -f "$prefs_dir/com.googlecode.iterm2.plist" ]] || return 0
  local folder loaded
  folder="$(defaults read com.googlecode.iterm2 PrefsCustomFolder 2>/dev/null || true)"
  loaded="$(defaults read com.googlecode.iterm2 LoadPrefsFromCustomFolder 2>/dev/null || true)"
  if [[ "$folder" == "$prefs_dir" && "$loaded" == 1 ]]; then
    log "ok     iTerm2 settings from repo ($prefs_dir)"
    return 0
  fi
  info "pointing iTerm2 at repo settings folder"
  defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$prefs_dir"
  defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
  warn "restart iTerm2 to load the shared settings (if it was running during"
  warn "  this install and the setting doesn't stick, quit iTerm2 fully and"
  warn "  re-run 'envsync install')"
}

# Rust comes from rustup (not the Homebrew rust formula): rustup honors
# per-project rust-toolchain.toml pinning, and having cargo on PATH before
# `brew bundle` stops bundle's cargo entries from spawning a nested
# `brew install --formula rust` that races the main install loop.
ensure_rustup() {
  if have cargo; then
    log "ok     rust (cargo on PATH)"
    return 0
  fi
  info "installing rustup (rust toolchain manager)"
  curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path
  # zshrc already sources ~/.cargo/env; do the same for this run.
  # shellcheck source=/dev/null
  [[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
}

link_macos_bin() {
  local src="$MACOS_DIR/bin" dest="$HOME/.local/bin" file
  [[ -d "$src" ]] || return 0
  info "macos bin scripts -> $dest"
  while IFS= read -r -d '' file; do
    [[ -x "$file" ]] || continue
    link_file "$file" "$dest/$(basename "$file")"
  done < <(find "$src" -maxdepth 1 -type f -print0)
}

macos_install() {
  ensure_homebrew
  ensure_rustup
  apply_brewfile
  link_macos_bin
  configure_iterm
}

macos_capture() {
  have brew || { warn "brew not found; skipping Brewfile capture"; return 0; }
  info "capture Brewfile"
  mkdir -p "$MACOS_DIR"
  # --no-vscode: extensions are managed separately (newer brew only).
  brew bundle dump --force --describe --no-vscode --file="$MACOS_DIR/Brewfile" 2>/dev/null \
    || brew bundle dump --force --describe --file="$MACOS_DIR/Brewfile"
}

macos_status() {
  if have brew && [[ -f "$MACOS_DIR/Brewfile" ]]; then
    info "Homebrew drift"
    brew bundle check --file="$MACOS_DIR/Brewfile" --verbose || true
    log ""
  fi
  if [[ -f "$MACOS_DIR/iterm/com.googlecode.iterm2.plist" ]]; then
    if [[ "$(defaults read com.googlecode.iterm2 PrefsCustomFolder 2>/dev/null || true)" == "$MACOS_DIR/iterm" ]]; then
      log "ok     iTerm2 settings from repo"
    else
      log "UNSET  iTerm2 custom settings folder (run 'envsync install')"
    fi
    log ""
  fi
}
