# bazzite/sync.sh — partition: Bazzite (immutable Fedora) Linux-only setup.
#
# Sourced by envsync when running on Linux. Runs BEFORE the shared
# partition. Bazzite is image-based (rpm-ostree), so system packages are
# not managed here — apps come from Flatpak, captured as a manifest.
#
# Manages:
#   bazzite/flatpaks.txt    Flatpak app manifest (one app id per line)
#   bazzite/bin/            -> ~/.local/bin (Linux-only scripts, e.g. the
#                              flatpak wezterm wrapper)

BAZZITE_DIR="$REPO_DIR/bazzite"

apply_flatpaks() {
  local manifest="$BAZZITE_DIR/flatpaks.txt"
  [[ -f "$manifest" ]] || return 0
  have flatpak || { warn "flatpak not found; skipping flatpak apps"; return 0; }
  info "flatpak apps"
  local installed app
  installed="$(flatpak list --app --columns=application 2>/dev/null || true)"
  while IFS= read -r app; do
    [[ -z "$app" || "$app" == \#* ]] && continue
    # App ids are reverse-DNS: letters, digits, dots, dashes, underscores.
    case "$app" in
      -*|*[!A-Za-z0-9._-]*) warn "refusing suspicious flatpak id: $app"; continue ;;
    esac
    if printf '%s\n' "$installed" | grep -qx -- "$app"; then
      log "ok     $app"
    else
      flatpak install -y --noninteractive flathub "$app" \
        || warn "failed to install flatpak $app"
    fi
  done < "$manifest"
}

link_bazzite_bin() {
  local src="$BAZZITE_DIR/bin" dest="$HOME/.local/bin" file
  [[ -d "$src" ]] || return 0
  info "bazzite bin scripts -> $dest"
  while IFS= read -r -d '' file; do
    [[ -x "$file" ]] || continue
    link_file "$file" "$dest/$(basename "$file")"
  done < <(find "$src" -maxdepth 1 -type f -print0)
}

bazzite_install() {
  apply_flatpaks
  link_bazzite_bin
}

bazzite_capture() {
  have flatpak || return 0
  info "capture flatpak apps"
  mkdir -p "$BAZZITE_DIR"
  {
    printf '# Flatpak apps (one id per line) — managed by envsync\n'
    flatpak list --app --columns=application 2>/dev/null | LC_ALL=C sort
  } > "$BAZZITE_DIR/flatpaks.txt"
}

bazzite_status() {
  if have flatpak && [[ -f "$BAZZITE_DIR/flatpaks.txt" ]]; then
    info "flatpak drift (< only-in-repo, > only-on-machine)"
    { diff <(grep -v '^#' "$BAZZITE_DIR/flatpaks.txt" | LC_ALL=C sort) \
           <(flatpak list --app --columns=application | LC_ALL=C sort) || true; } \
      | { grep '^[<>]' || log "ok     flatpaks match"; }
    log ""
  fi
}
