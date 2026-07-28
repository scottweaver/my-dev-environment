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
| `envsync push [msg]` | `capture` + commit on a short-lived branch + PR with auto-merge. Merges itself once the CI secret-scan checks pass. Installs the `gh` CLI and walks through GitHub login automatically if needed (brew on macOS, release binary into `~/.local/bin` on Bazzite). |
| `envsync pull` | Pull from GitHub, then re-apply (`install`). |
| `envsync status` | Show drift: repo vs remote, package manifests vs installed, extensions, broken links. |
| `envsync scan` | Scan the repo working tree for tokens/keys/credentials. Runs automatically before every `push` and blocks the push on findings (override: `DEV_ENV_ALLOW_SECRETS=1`). |
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
default `~/Projects/my-dev-environment`).

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
