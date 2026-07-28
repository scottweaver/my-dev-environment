# shared/sync.sh — partition: config that applies on BOTH macOS and Bazzite.
#
# Sourced by envsync (not executable on its own). Helpers like link_file,
# adopt_file, link_tree, log/info/warn/have and $REPO_DIR/$OS are provided
# by envsync before this file is sourced.
#
# Manages:
#   shared/zsh/zshrc                  -> ~/.zshrc
#   shared/zsh/omz-custom-plugins.txt    Oh My Zsh custom plugin manifest
#   shared/git/aliases                   git aliases (via install-aliases.sh)
#   shared/neovim/                    -> ~/.config/nvim
#   shared/claude-code/               -> ~/.claude (skills, agents, commands, ...)
#   shared/vscode/settings.json,keybindings.json -> VS Code user dir
#   shared/vscode/extensions.txt         VS Code extension manifest
#   shared/toolchains/npm-globals.txt    global npm packages
#   shared/toolchains/versions.txt       informational toolchain versions
#   shared/bin/                       -> ~/.local/bin (cross-platform scripts)

SHARED_DIR="$REPO_DIR/shared"
SECRETS_DIR="$HOME/.secrets"

vscode_user_dir() {
  if [[ "$OS" == macos ]]; then
    printf '%s' "$HOME/Library/Application Support/Code/User"
  else
    printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/Code/User"
  fi
}

# ---------------------------------------------------------------- install ---

# ~/.secrets/ is the per-machine secret store: every plain file in it is
# sourced by shared/zsh/zshrc. It is created here but NEVER synced — nothing
# in envsync reads, adopts, captures, or commits its contents.
ensure_secrets() {
  if [[ ! -d "$SECRETS_DIR" ]]; then
    info "creating $SECRETS_DIR (per-machine secrets — never synced)"
    mkdir -p "$SECRETS_DIR"
  else
    log "ok     $SECRETS_DIR"
  fi
  chmod 700 "$SECRETS_DIR"
  # One-time migration from the old single-file location, ~/.tokens.
  if [[ -f "$HOME/.tokens" && ! -L "$HOME/.tokens" ]]; then
    if [[ -e "$SECRETS_DIR/tokens" ]]; then
      warn "$HOME/.tokens and $SECRETS_DIR/tokens both exist — merge by hand"
    else
      log "migrate $HOME/.tokens -> $SECRETS_DIR/tokens"
      mv "$HOME/.tokens" "$SECRETS_DIR/tokens"
    fi
  fi
  chmod 600 "$SECRETS_DIR"/* 2>/dev/null || true
}

ensure_ohmyzsh() {
  have zsh || { warn "zsh not installed; skipping Oh My Zsh"; return 0; }
  if [[ -d "${ZSH:-$HOME/.oh-my-zsh}" ]]; then
    log "ok     Oh My Zsh"
    return
  fi
  info "installing Oh My Zsh"
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
    "" --unattended
}

# Manifest format: one entry per line, "name<TAB>git-url". Lines starting
# with # are comments. kind is "plugins" or "themes"; entries install
# into $ZSH_CUSTOM/<kind>/<name>.
apply_omz_kind() {
  local kind="$1" manifest="$SHARED_DIR/zsh/omz-custom-$1.txt"
  [[ -f "$manifest" ]] || return 0
  local custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  [[ -d "$HOME/.oh-my-zsh" ]] || { warn "Oh My Zsh missing; skipping custom $kind"; return 0; }
  local name url
  while IFS=$'\t' read -r name url; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    [[ -n "$url" ]] || { warn "malformed $kind line: $name"; continue; }
    # Safety: name must be a plain directory name; url must not look
    # like a command-line option.
    case "$name" in
      */*|.*|-*) warn "refusing suspicious $kind name: $name"; continue ;;
    esac
    case "$url" in
      -*) warn "refusing suspicious $kind url: $url"; continue ;;
    esac
    if [[ -d "$custom/$kind/$name" ]]; then
      log "ok     omz ${kind%s} $name"
    else
      info "installing omz ${kind%s} $name"
      git clone --depth 1 -- "$url" "$custom/$kind/$name"
    fi
  done < "$manifest"
}

apply_omz_custom() {
  apply_omz_kind plugins
  apply_omz_kind themes
}

link_zsh() {
  if [[ -f "$SHARED_DIR/zsh/zshrc" ]]; then
    link_file "$SHARED_DIR/zsh/zshrc" "$HOME/.zshrc"
  else
    log "skip   zshrc (none in repo yet — run 'envsync adopt')"
  fi
  [[ -f "$SHARED_DIR/zsh/p10k.zsh" ]] \
    && link_file "$SHARED_DIR/zsh/p10k.zsh" "$HOME/.p10k.zsh"
  return 0
}

apply_git_aliases() {
  if [[ -f "$SHARED_DIR/git/install-aliases.sh" ]]; then
    info "git aliases"
    bash "$SHARED_DIR/git/install-aliases.sh"
  fi
}

link_neovim() {
  info "neovim config"
  link_tree "$SHARED_DIR/neovim" "${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
}

link_claude() {
  info "claude config (~/.claude)"
  link_tree "$SHARED_DIR/claude-code" "$HOME/.claude"
}

link_vscode() {
  local user_dir; user_dir="$(vscode_user_dir)"
  local f
  for f in settings.json keybindings.json; do
    [[ -f "$SHARED_DIR/vscode/$f" ]] && link_file "$SHARED_DIR/vscode/$f" "$user_dir/$f"
  done
  return 0
}

apply_vscode_extensions() {
  local manifest="$SHARED_DIR/vscode/extensions.txt"
  [[ -f "$manifest" ]] || return 0
  have code || { warn "'code' CLI not found; skipping VS Code extensions"; return 0; }
  info "VS Code extensions"
  local installed ext
  installed="$(code --list-extensions 2>/dev/null || true)"
  while IFS= read -r ext; do
    [[ -z "$ext" || "$ext" == \#* ]] && continue
    case "$ext" in
      -*|*[!A-Za-z0-9._-]*) warn "refusing suspicious extension id: $ext"; continue ;;
    esac
    if printf '%s\n' "$installed" | grep -qix -- "$ext"; then
      log "ok     $ext"
    else
      code --install-extension "$ext" || warn "failed to install $ext"
    fi
  done < "$manifest"
}

apply_npm_globals() {
  local manifest="$SHARED_DIR/toolchains/npm-globals.txt"
  [[ -f "$manifest" ]] || return 0
  have npm || { warn "npm not found; skipping global npm packages"; return 0; }
  info "global npm packages"
  local pkg
  while IFS= read -r pkg; do
    [[ -z "$pkg" || "$pkg" == \#* ]] && continue
    case "$pkg" in
      -*|*[!@A-Za-z0-9._/-]*) warn "refusing suspicious package name: $pkg"; continue ;;
    esac
    if npm ls -g --depth=0 -- "$pkg" >/dev/null 2>&1; then
      log "ok     $pkg"
    else
      npm install -g -- "$pkg" || warn "failed to install $pkg"
    fi
  done < "$manifest"
}

link_shared_bin() {
  # Cross-platform helper scripts + envsync itself -> ~/.local/bin.
  local dest="$HOME/.local/bin" file
  info "bin scripts -> $dest"
  link_file "$REPO_DIR/envsync" "$dest/envsync"
  if [[ -d "$SHARED_DIR/bin" ]]; then
    while IFS= read -r -d '' file; do
      [[ -x "$file" ]] || continue
      link_file "$file" "$dest/$(basename "$file")"
    done < <(find "$SHARED_DIR/bin" -maxdepth 1 -type f -print0)
  fi
  case ":$PATH:" in
    *":$dest:"*) ;;
    *) warn "$dest is not in \$PATH — add it in shared/zsh/zshrc" ;;
  esac
}

shared_install() {
  ensure_secrets
  ensure_ohmyzsh
  apply_omz_custom
  link_zsh
  apply_git_aliases
  link_neovim
  link_claude
  link_vscode
  apply_vscode_extensions
  apply_npm_globals
  link_shared_bin
}

# ------------------------------------------------------------------ adopt ---

shared_adopt() {
  info "adopt zsh config"
  adopt_file "$HOME/.zshrc" "$SHARED_DIR/zsh/zshrc"
  if [[ -f "$SHARED_DIR/zsh/zshrc" ]] && grep -qE '\.tokens|zshrc\.local' "$SHARED_DIR/zsh/zshrc" 2>/dev/null; then
    warn "shared/zsh/zshrc still references ~/.tokens or ~/.zshrc.local —"
    warn "  secrets belong in ~/.secrets/ (sourced by the zshrc, never synced)"
  fi
  if [[ -f "$SHARED_DIR/zsh/zshrc" ]] && ! grep -q '\.secrets' "$SHARED_DIR/zsh/zshrc" 2>/dev/null; then
    warn "shared/zsh/zshrc does not source ~/.secrets/ — add:"
    # shellcheck disable=SC2016  # literal snippet, must not expand here
    warn '  for f in "$HOME"/.secrets/*(N.); do source "$f"; done'
  fi
  adopt_file "$HOME/.p10k.zsh" "$SHARED_DIR/zsh/p10k.zsh"

  info "adopt claude config (skills, agents, commands, rules)"
  local item rel file src
  for item in skills agents commands hooks CLAUDE.md; do
    src="$HOME/.claude/$item"
    if [[ -f "$src" && ! -L "$src" ]]; then
      adopt_file "$src" "$SHARED_DIR/claude-code/$item"
    elif [[ -d "$src" ]]; then
      while IFS= read -r -d '' file; do
        [[ -L "$file" ]] && continue   # already linked (e.g. into this repo)
        rel="${file#"$HOME/.claude/"}"
        adopt_file "$file" "$SHARED_DIR/claude-code/$rel"
      done < <(find "$src" -type f -print0)
    fi
  done
  log "note   ~/.claude/settings.json is NOT adopted (may contain machine/secret config)"

  info "adopt VS Code settings"
  local user_dir; user_dir="$(vscode_user_dir)"
  adopt_file "$user_dir/settings.json"    "$SHARED_DIR/vscode/settings.json"
  adopt_file "$user_dir/keybindings.json" "$SHARED_DIR/vscode/keybindings.json"

  local nvim_dir="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
  if [[ -d "$nvim_dir" && ! -f "$SHARED_DIR/neovim/init.lua" ]]; then
    info "adopt neovim config"
    while IFS= read -r -d '' file; do
      [[ -L "$file" ]] && continue
      rel="${file#"$nvim_dir/"}"
      adopt_file "$file" "$SHARED_DIR/neovim/$rel"
    done < <(find "$nvim_dir" -type f -print0)
  elif [[ -f "$SHARED_DIR/neovim/init.lua" ]]; then
    log "skip   neovim (repo already has a config; 'envsync install' links it, merge by hand if needed)"
  fi
}

# ---------------------------------------------------------------- capture ---

capture_vscode() {
  have code || { warn "'code' CLI not found; skipping VS Code capture"; return 0; }
  info "capture VS Code extensions"
  mkdir -p "$SHARED_DIR/vscode"
  code --list-extensions | LC_ALL=C sort > "$SHARED_DIR/vscode/extensions.txt"
}

capture_npm_globals() {
  have npm || return 0
  info "capture global npm packages"
  mkdir -p "$SHARED_DIR/toolchains"
  # Package names only; skip npm itself and corepack.
  npm ls -g --depth=0 --parseable 2>/dev/null \
    | awk -F/ '/node_modules/ {n=$NF; if ($(NF-1) ~ /^@/) n=$(NF-1)"/"$NF; print n}' \
    | grep -vx -e npm -e corepack \
    | LC_ALL=C sort -u > "$SHARED_DIR/toolchains/npm-globals.txt" || true
}

capture_versions() {
  info "capture toolchain versions (informational)"
  mkdir -p "$SHARED_DIR/toolchains"
  local out="$SHARED_DIR/toolchains/versions.txt" tool ver
  : > "$out"
  for tool in zsh git nvim node npm python3 go rustc cargo java brew; do
    have "$tool" || continue
    if [[ "$tool" == go ]]; then
      ver="$(go version 2>/dev/null | head -1)"
    else
      ver="$("$tool" --version 2>/dev/null | head -1)"
      [[ -n "$ver" ]] || ver="$("$tool" --version 2>&1 | head -1)"
    fi
    printf '%-8s %s\n' "$tool" "$ver" >> "$out"
  done
}

capture_omz_kind() {
  local kind="$1" custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  [[ -d "$custom/$kind" ]] || return 0
  info "capture Oh My Zsh custom $kind"
  mkdir -p "$SHARED_DIR/zsh"
  local out="$SHARED_DIR/zsh/omz-custom-$kind.txt" dir name url
  {
    printf '# Oh My Zsh custom %s (name<TAB>git-url) — managed by envsync\n' "$kind"
    for dir in "$custom/$kind"/*/; do
      [[ -d "$dir/.git" ]] || continue
      name="$(basename "$dir")"
      url="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
      # Scrub any credentials embedded ahead of the host (user + token).
      url="$(printf '%s' "$url" | sed -E 's#(://)[^/@]*@#\1#')"
      [[ -n "$url" ]] && printf '%s\t%s\n' "$name" "$url"
    done
  } > "$out"
}

capture_omz_custom() {
  capture_omz_kind plugins
  capture_omz_kind themes
}

shared_capture() {
  capture_vscode
  capture_npm_globals
  capture_versions
  capture_omz_custom
}

# ----------------------------------------------------------------- status ---

shared_status() {
  if [[ -d "$SECRETS_DIR" ]]; then
    log "ok     $SECRETS_DIR (per-machine secrets — never synced)"
  else
    log "MISSING $SECRETS_DIR (run 'envsync install')"
  fi
  log ""
  if have code && [[ -f "$SHARED_DIR/vscode/extensions.txt" ]]; then
    info "VS Code extension drift (< only-in-repo, > only-on-machine)"
    { diff <(LC_ALL=C sort "$SHARED_DIR/vscode/extensions.txt") \
           <(code --list-extensions | LC_ALL=C sort) || true; } \
      | { grep '^[<>]' || log "ok     extensions match"; }
    log ""
  fi
  info "links"
  local pair src dest
  for pair in \
    "$SHARED_DIR/zsh/zshrc:$HOME/.zshrc" \
    "$SHARED_DIR/vscode/settings.json:$(vscode_user_dir)/settings.json" \
    "$SHARED_DIR/neovim/init.lua:${XDG_CONFIG_HOME:-$HOME/.config}/nvim/init.lua" \
    "$REPO_DIR/envsync:$HOME/.local/bin/envsync"; do
    src="${pair%%:*}"; dest="${pair#*:}"
    [[ -f "$src" ]] || continue
    if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
      log "ok     $dest"
    else
      log "UNLINKED $dest (run 'envsync install')"
    fi
  done
}
