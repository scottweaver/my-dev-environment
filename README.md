# my-dev-environment

One repo to duplicate my dev environment across machines — macOS and Bazzite
Linux.

The entry point is **`envsync`**, a single dependency-free bash script
(compatible with macOS's stock bash 3.2). It detects the OS it's running on and
applies the matching **partitions** — three sub-projects, each owning its slice
of the environment:

| Partition | Applies on | Owns |
|---|---|---|
| `shared/` | both | zsh + Oh My Zsh, git aliases, neovim, claude-code, VS Code settings/extensions, npm globals, cross-platform `bin/` scripts |
| `macos/` | macOS only | Homebrew + Brewfile, `macos/bin/` |
| `bazzite/` | Bazzite only | Flatpak app manifest, `bazzite/bin/` (e.g. the flatpak wezterm wrapper) |

Each partition is a `sync.sh` sourced by `envsync`, exposing optional
`<name>_install / _adopt / _capture / _status` hooks. On macOS the order is
`macos` then `shared` (so Homebrew exists before shared config needs the tools
it installs); on Linux it's `bazzite` then `shared`.

## Quick start

**New Mac** (nothing installed yet):

```sh
curl -fsSLO https://raw.githubusercontent.com/scottweaver/my-dev-environment/main/envsync
bash envsync install
```

This clones the repo to `~/Projects/my-dev-environment`, installs Homebrew and
Oh My Zsh if missing, applies the Brewfile, symlinks all dotfiles, installs git
aliases, VS Code extensions, and global npm packages — and links `envsync`
itself into `~/.local/bin`.

**Machine with config the repo doesn't have yet** (first-time capture):

```sh
envsync adopt      # moves ~/.zshrc, ~/.claude skills/rules, VS Code settings INTO the repo, symlinks them back
envsync push       # capture manifests + commit + push
```

## Commands

| Command | What it does |
|---|---|
| `envsync install` | Bootstrap or refresh this machine from the repo. Idempotent. |
| `envsync adopt` | First-time: move this machine's existing dotfiles into the repo, then symlink back. |
| `envsync capture` | Refresh machine-state manifests: Brewfile (macOS), Flatpaks (Bazzite), VS Code extensions, npm globals, OMZ custom plugins, toolchain versions. |
| `envsync push [msg]` | Sync local `main` → `capture` → commit on a short-lived branch → PR → wait for the CI checks → merge → return to `main` with the merged result pulled. Installs the `gh` CLI and walks through GitHub login automatically if needed (brew on macOS, release binary into `~/.local/bin` on Bazzite). Falls back to `usb push` when GitHub is unreachable and a thumb drive is present. |
| `envsync pull` | Pull from GitHub, then re-apply (`install`). Falls back to `usb pull` when GitHub is unreachable. |
| `envsync usb init <drive>` | Set up a thumb drive as a portable fallback upstream + install source: bare repo (`my-dev-environment.git`) plus a bootstrap copy of `envsync` at the drive root. |
| `envsync usb push [msg]` | Offline push: `capture` + commit **directly on local `main`** + sync the drive. No PR/CI — the commits ride the next online `envsync push` as its PR, so branch protection still gates GitHub. The secret scan still runs and still blocks. |
| `envsync usb pull` | Fast-forward local `main` from the drive, then re-apply (`install`). |
| `envsync usb status` | Show where the drive is mounted and how far local `main` is ahead/behind it. |
| `envsync status` | Show drift: repo vs remote, package manifests vs installed, extensions, broken links. Also shows this machine's personal/client declaration. |
| `envsync scan` | Scan the repo working tree for tokens/keys/credentials (override on push: `DEV_ENV_ALLOW_SECRETS=1`) **and** for denylist patterns (no override — see [Client engagements](#client-engagements)). Runs automatically before every `push` and blocks it on findings. |
| `envsync client on '<label>'` | Declare this a **client machine**: all outbound sync (`push`, `usb push`, `usb init`, `capture`, `adopt`) is hard-blocked, with no override. Inbound (`install`, `pull`, `status`, `scan`) still works. |
| `envsync client off` | Declare this a personal machine (full sync). Leaving client mode requires retyping the engagement label at an interactive prompt. |
| `envsync client status` | Show this machine's declaration and denylist state. |
| `envsync agent-sync [args]` | Run [agent-sync](shared/bin/agent-sync) in the **current project**: mirror its `.claude/rules/*.md` into `.cursor/rules/*.mdc` so Cursor loads the same rules as Claude Code. Pass-through args: `--check`, `--watch`, `--clean`, `--help`. Aliases: `agentsync`, `rules`. |

## How syncing works

Two models, by file type:

* **Repo is source of truth (symlinked).** `shared/zsh/zshrc`,
  `shared/git/aliases`, `shared/neovim/`, `shared/claude-code/` (skills,
  agents, commands, `CLAUDE.md`), `shared/vscode/settings.json` and
  `keybindings.json`, everything in `*/bin/`. Edit them anywhere — the symlink
  means the repo copy *is* the live copy, so changes are picked up by plain
  `git` (and `envsync push`).
* **Machine is source of truth (captured).** `macos/Brewfile`,
  `bazzite/flatpaks.txt`, `shared/vscode/extensions.txt`,
  `shared/toolchains/npm-globals.txt`, `shared/zsh/omz-custom-plugins.txt`.
  Install things normally (`brew install`, `flatpak install`, etc.), then
  `envsync push` regenerates the manifests and commits.

Typical loop: change something → `envsync push` here → `envsync pull` on the
other machine (Mac or Bazzite — each applies only its own partitions).

## Thumb-drive fallback

For when GitHub is unreachable (or a machine has no account access), a thumb
drive can stand in as a **portable, detached upstream** and as an **initial
install source**. One-time setup, with the drive plugged in:

```sh
envsync usb init /Volumes/<drive>
```

That puts a bare repo (`my-dev-environment.git`) and a bootstrap copy of
`envsync` at the drive root. From then on the drive is auto-detected (scan of
`/Volumes`, `/run/media/$USER`, `/media/$USER`; override with `DEV_ENV_USB`)
and addressed by its mount path at each use — no git remote is stored, so
nothing goes stale when the volume name or OS changes.

* **Offline push/pull**: `envsync push` and `envsync pull` probe GitHub first
  and automatically divert to the drive when it's unreachable (or use
  `envsync usb push` / `usb pull` explicitly). Offline commits land directly
  on local `main` and are carried up as a normal CI-gated PR by the next
  online `envsync push`.
* **Bootstrap a new machine with no GitHub access**:
  `bash /Volumes/<drive>/envsync install` clones from the drive and wires
  `origin` back to GitHub for later.
* **Freshness**: every successful online `envsync push` also refreshes a
  plugged-in drive. If a squash-merge rewrote history the drive still holds,
  the refresh parks the drive's old tip under `refs/backup/` in the drive
  repo before overwriting — nothing is ever silently discarded.

## Client engagements

When a machine belongs to a client engagement (contract work, an employer's
laptop), the sync loop itself becomes an exfiltration channel: symlinked
dotfiles mean any edit made on that machine lands in the repo working tree,
`capture` snapshots machine state (Brewfile taps, npm registries, extensions),
and `push` carries all of it to personal GitHub or a thumb drive. Three
layered guards close that channel:

1. **Machine declaration (fail-closed).** Outbound commands (`push`,
   `usb push`, `usb init`, `capture`, `adopt`) refuse to run until the
   machine is declared with `envsync client on '<engagement>'` (client:
   outbound permanently blocked, no override) or `envsync client off`
   (personal: full sync). A brand-new, undeclared machine therefore cannot
   push *by default* — the guard does not depend on remembering to enable
   it. The declaration lives in `~/.config/envsync/machine.conf`,
   machine-local and never synced. Leaving client mode is interactive-only
   and requires retyping the engagement label.
2. **Denylist scan (no override).** `~/.config/envsync/denylist` holds one
   case-insensitive regex per line (`#` comments) — client names, internal
   hostnames/domains, project codenames. Every `push`/`usb push` on **every**
   machine greps the entire working tree against it and blocks on any hit.
   Unlike the credential scan, `DEV_ENV_ALLOW_SECRETS=1` does not bypass it,
   and findings print file:line only — the matched text is exactly what must
   not end up in terminal scrollback or CI logs. Seed the same patterns on
   your personal machines too: that is what catches client residue that
   hitches a ride through a shared browser profile, a pasted snippet, or a
   Claude/VS Code setting.
3. **Server-side backstop.** The `secret-scan` CI workflow (required by
   branch protection) loads the same pattern lines from the optional
   `ENVSYNC_DENYLIST` repository **secret** — patterns never appear in the
   repo itself — so even a push from a machine with no local denylist is
   caught before merge. Set it under *Settings → Secrets and variables →
   Actions*, one pattern per line.

Setup for an engagement, in order: on each personal machine run
`envsync client off` once (existing machines are undeclared and locked until
this) and add the engagement's patterns to `~/.config/envsync/denylist`; set
the `ENVSYNC_DENYLIST` repo secret; on the client machine — if personal
dotfiles are permitted there at all — run `envsync install`, then
`envsync client on '<engagement>'` immediately. Nothing in the repo, the
denylist mechanism, or CI config should ever name the client; the names live
only in machine-local files and the repo secret.

## Repo layout

```
envsync                          the entry point (detects OS, dispatches to partitions)
shared/
  sync.sh                        partition hooks (install/adopt/capture/status)
  zsh/zshrc                   -> ~/.zshrc
  zsh/omz-custom-plugins.txt     Oh My Zsh custom plugins (name<TAB>git-url)
  git/aliases                    git aliases (applied via git/install-aliases.sh)
  neovim/                     -> ~/.config/nvim
  claude-code/                -> ~/.claude   (skills, agents, commands, CLAUDE.md)
  vscode/                     -> VS Code user dir + extensions.txt manifest
  toolchains/                    npm globals + informational tool versions
  bin/                        -> ~/.local/bin (cross-platform scripts)
macos/
  sync.sh
  Brewfile                       Homebrew formulae/casks/taps (brew bundle)
  bin/                        -> ~/.local/bin (macOS-only scripts)
  iterm/                         iTerm2 settings (iTerm loads/saves this
                                 folder directly via its custom-folder mode)
bazzite/
  sync.sh
  flatpaks.txt                   Flatpak app manifest
  bin/                        -> ~/.local/bin (Linux-only scripts)
```

The Linux-era installers (`install-env.sh`, `install-agents.sh`,
`shared/git/install-aliases.sh`) still work standalone, but `envsync` covers
everything they do.

Config overrides: `DEV_ENV_REPO_URL` (remote), `DEV_ENV_HOME` (checkout path,
default `~/Projects/my-dev-environment`), `DEV_ENV_USB` (thumb-drive mount
point, default auto-detect).

## Secrets

All secrets live in **`~/.secrets/`** — a per-machine directory that is
**never synced**. `envsync install` creates it (mode 700) on every machine and
migrates the legacy single-file `~/.tokens` into `~/.secrets/tokens` if found.
Every plain file in the directory is sourced by the zshrc:

```sh
for f in "$HOME"/.secrets/*(N.); do source "$f"; done
```

Drop `export FOO=...` files in there freely; nothing in envsync reads, adopts,
captures, or commits their contents.

`envsync adopt` deliberately skips `~/.claude/settings.json` and git
`user.name`/`user.email` — those stay per-machine. The local `secrets/`
directory is a separate private repo and is gitignored here.

Guard rails built into `envsync`:

* every `push` runs a secret scan (private keys, AWS/GitHub/Anthropic/OpenAI/
  Slack/npm token formats, `password=`-style assignments, credentials embedded
  in URLs, plus any file *named* like a secret store: `.tokens`, `.secrets`,
  `id_rsa*`, `*.pem`) and refuses to push on a hit; `.gitignore` also blocks
  those filenames outright;
* captured Oh My Zsh plugin URLs are scrubbed of embedded `user:token@`
  credentials;
* manifest entries (plugin names/URLs, npm packages, VS Code extension ids,
  flatpak app ids) are validated before being passed to `git clone` /
  `npm install` / `code` / `flatpak install`, so a tampered manifest can't
  inject command-line options or escape its install directory;
* `main` is a protected branch — **including for admins** — requiring the
  GitHub Actions checks in `.github/workflows/secret-scan.yml` (`envsync scan`,
  gitleaks over full history, script syntax). Direct pushes are impossible;
  `envsync push` therefore ships every change as a short-lived auto-merge PR
  that only lands once CI is green.
