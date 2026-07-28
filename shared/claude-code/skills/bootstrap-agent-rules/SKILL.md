---
name: bootstrap-agent-rules
description: Bootstraps a project's agent-rules layer — .claude/rules/ with idiomatic coding rules (Rust and/or TypeScript, auto-detected), METHODOLOGIES.md workflow, a STATE.md session-memory file, a bespoke ARCHITECTURE.md, a CLAUDE.md authority map with AGENTS.md symlink, and (optionally, always ask first) Linear ticket integration. Invoke explicitly with /bootstrap-agent-rules or on phrases like "bootstrap the agent rules", "set up Claude rules for this project", "install the rules layer", "set up STATE.md and ARCHITECTURE.md", "give this project the standard rules".
---

# bootstrap-agent-rules

Installs the standard agent-rules layer into the current project. The
rule content was extracted and generalized from mature projects
(antikythera, TS-Optimizer); this skill stamps it into new ones.

End state after a full run:

```
CLAUDE.md                        authority map (or section appended to existing)
AGENTS.md -> CLAUDE.md           symlink (read natively by Cursor & others)
.cursor/rules/*.mdc              generated mirrors of .claude/rules (agent-sync)
.claude/rules/
  RUST_BEST_PRACTICES.md         if Rust detected
  TS_BEST_PRACTICES.md           if TypeScript detected
  METHODOLOGIES.md               workflow: branching, PRs, refactors, post-merge
  STATE.md                       session memory — filled from repo analysis
  ARCHITECTURE.md                bespoke — filled via design dialog
  LINEAR.md                      only if user opts in
  PROJECT.md                     only if user opts in (via bootstrap-project)
```

Templates live in `references/` next to this file. Files without
placeholders are copied verbatim; `*.template.md` files have
`{{PLACEHOLDER}}` slots you must fill — never leave a placeholder in
an installed file.

## Workflow

### 1. Preflight

- Confirm cwd is the project root (git repo). If not in a git repo,
  stop and ask.
- If `.claude/rules/` already has any of these files, switch to
  **merge mode**: show the user what exists, and only add what's
  missing — never overwrite an existing rules file without explicit
  approval.

### 2. Detect the stack

Look at the repo root **and first-level workspace/package directories**
(never inside `node_modules/`, `target/`, or vendored trees):

- `Cargo.toml` → install `RUST_BEST_PRACTICES.md`.
- `package.json` or `tsconfig.json` → install
  `TS_BEST_PRACTICES.md`.
- Both → both. Neither → ask the user which (or neither).

### 3. Install the fixed rule files

Copy from `references/` into `.claude/rules/`: the detected
best-practices file(s) and `METHODOLOGIES.md`.

- **Dereference symlinks** (`cp -L`) — the references may be symlinks
  into the dotfiles repo; the installed files must be real files.
- **Merge mode:** skip any file that already exists in the target
  (step 1's no-overwrite rule applies to this step too).

### 4. Generate STATE.md

Fill `STATE.template.md` from a quick repo analysis — `git log
--oneline -15`, `git branch -a`, the README, open TODOs. Write a real
"Active workstream" paragraph and "Next up" list, then **show the
draft to the user and confirm** before writing. Seed the progress log
with one entry in the template's full what/why/risk format: today's
date, headline "Rules layer bootstrapped".

### 5. Generate ARCHITECTURE.md — bespoke, via dialog

This file must reflect the project's *actual* architecture, not
boilerplate:

1. Analyze the repo: workspace/package layout, dependency manifests,
   entry points, obvious boundaries (API routes, wire formats,
   storage).
2. Draft the constraint sections you can infer, marking uncertain
   ones as proposals.
3. Run a short design dialog with the user: present the inferred
   constraints, ask what's binding vs. accidental, and what known
   constraints are missing. AskUserQuestion works well for 2–4
   concrete choices; free chat for the open-ended parts.
4. Fill the meta-sections with real values: **Audit triggers** get
   actual paths/globs from this repo; **Structural criteria** get
   this project's own structural/not-structural split.

Only write the file after the dialog. Keep every constraint
falsifiable and dated.

**Non-interactive runs** (subagent, CI, user unavailable): don't
skip the file and don't silently ship guesses — write it with every
unconfirmed constraint explicitly tagged `PROPOSED (<date>)` or
`TBD`, note in the "Established" line that the dialog is pending,
and surface the open questions in the run's summary. The same
fallback applies to the step-4 STATE.md confirmation.

### 6. CLAUDE.md + AGENTS.md

- No existing `CLAUDE.md`: fill `CLAUDE.template.md` (project name +
  short description). Authority-table row markers: a `{{*_ROW}}`
  prefix marks a conditional row — if that file was installed,
  delete **just the marker text** and keep the row; if not, delete
  the **entire line**. Unmarked rows always stay. A row must never
  point at a file that doesn't exist.
- Existing `CLAUDE.md`: append the "Agent memory and rules" and
  "Top-level defaults" sections (adapted to what was installed)
  instead of replacing the file; show the diff first.
- Symlink: `ln -sf CLAUDE.md AGENTS.md` (relative link, from the repo
  root). If `AGENTS.md` exists as a regular file, ask before
  replacing; offer to merge its content into CLAUDE.md first.

### 6b. Cursor mirrors

Cursor reads `AGENTS.md` (the symlink covers that) and
`.cursor/rules/*.mdc` — it does NOT load `.claude/rules/`. Run
`agent-sync` (installed on PATH by envsync; falls back to the
project's own `scripts/agent-sync.sh` if present) from the project
root to generate the `.cursor/rules/` mirrors. The generated files
are marked DO-NOT-EDIT; `.claude/rules/` stays the single source of
truth. Re-run `agent-sync` after any rules edit (or use
`agent-sync --check` in CI). Per-file Cursor activation is controlled
by a magic first-line comment in the source rule — see
`agent-sync --help`.

### 7. Linear integration — optional, ALWAYS ask first

Ask the user (AskUserQuestion): **"Set up Linear ticket integration
for this project?"** Options: yes / no / GitHub issues instead.

- **No** → skip; note in the summary that `/bootstrap-agent-rules`
  can add it later.
- **GitHub issues** → skip LINEAR.md; still offer the
  `bootstrap-project` step below with the GitHub tracker.
- **Yes**:
  1. Verify auth without reading any values:
     `zsh -ic 'test -n "$LINEAR_API_KEY"' 2>/dev/null || grep -rlq
     LINEAR_API_KEY ~/.secrets/ 2>/dev/null`. If absent, tell the
     user to add `export LINEAR_API_KEY=...` to a file under
     `~/.secrets/` and stop this step. Never ask for, print, or
     handle the key's value directly.
  2. Probe the workspace (teams → pick/confirm team → states,
     labels, projects; create a project in Linear only with explicit
     approval). Confirm the user's Linear user id for the
     auto-assignment rule (query `viewer { id name }`).
  3. Fill every `{{PLACEHOLDER}}` in `LINEAR.template.md` with probed
     UUIDs and write `.claude/rules/LINEAR.md`.
  4. Then invoke the `bootstrap-project` skill (it owns the
     PROJECT.md bindings schema consumed by daily-stand-up /
     wrap-up) rather than writing PROJECT.md by hand.

### 8. Wrap up

- List every file created/modified.
- Remind: rules load at session start — restart or `/clear` to pick
  them up.
- Offer to commit (project's normal branch/PR flow; the rules layer
  is a docs-only change).

## Don'ts

- Don't overwrite existing rules files without approval (merge mode).
- Don't leave `{{PLACEHOLDER}}` text in any installed file.
- Don't create anything in Linear without draft + explicit approval.
- Don't handle the Linear API key's value — env var only, sourced
  from `~/.secrets/`.
- Don't skip the ARCHITECTURE.md dialog and ship boilerplate — a
  wrong "binding constraint" is worse than none.
