---
name: agent-sync
description: Sync agent rule files to other AI tooling formats (e.g. `.claude/rules/*.md` → `.cursor/rules/*.mdc`) by running the project's sync script. Reads the script path from `.claude/rules/PROJECT.md` bindings with auto-detect fallback. Invoke explicitly with `/agent-sync [mode]`, or organically on phrases like "sync the agent rules", "sync rules to cursor", "run the rules sync", "are the cursor rules in sync", "regenerate the cursor rules", or after editing files under `.claude/rules/` when the project has a sync script configured. Modes: sync (default), check, clean, watch.
---

# agent-sync — mirror agent rules into other tools' formats

Runs the project's agent-rules sync script. The canonical case: a project keeps its source-of-truth rules in `.claude/rules/*.md` and mirrors them into `.cursor/rules/*.mdc` (or another tool's format) via a checked-in script. This skill makes that script invokable by name from any session, without remembering where it lives or what its modes are.

The skill is project-agnostic; the per-project value (the script path) lives in `.claude/rules/PROJECT.md`, same as the `daily-stand-up` / `wrap-up` bindings.

## When to invoke

- Explicit: `/agent-sync`, `/agent-sync check`, `/agent-sync clean`, `/agent-sync watch`.
- Organic: "sync the agent rules", "sync rules to cursor", "regenerate the cursor rules", "are the rules in sync?".
- **Proactively after rule edits**: when a session has just edited or created files under `.claude/rules/` and the project has a sync script bound, offer (don't silently run) a sync so the mirrored copies don't drift.

## Bindings

### 1. PROJECT.md (preferred)

Read the YAML frontmatter of `.claude/rules/PROJECT.md` for an `agent_sync` block:

```yaml
agent_sync:
  script: scripts/agent-sync.sh   # repo-relative path, run from project root
```

### 2. Auto-detect fallback

If the block is missing (or PROJECT.md itself is missing), probe for a script before giving up:

```bash
ls scripts/agent-sync.sh scripts/sync-claude-to-cursor-rules.sh 2>/dev/null
```

- **Exactly one hit** → confirm with the user ("found `scripts/agent-sync.sh` — use it?"), then proceed. After a successful run, offer to add the `agent_sync` block to PROJECT.md's frontmatter so future invocations skip the probe. (PROJECT.md edits in repos that gate `.claude/rules/` changes go through the project's normal branch/PR flow — don't commit to the default branch directly.)
- **No hits** → tell the user no sync script was found and stop. Don't write one unprompted; if they want one, that's a separate task.
- **Multiple hits** → ask which.

## Modes

Map the skill argument to the script's CLI. No argument means `sync`.

| Skill arg | Script invocation | What it does |
|---|---|---|
| *(none)* / `sync` | `<script>` | One-shot sync; regenerates all mirrored files and prunes stale generated ones |
| `check` | `<script> --check` | Exit 1 if mirrors are out of sync — for CI / pre-commit / "are we in sync?" questions |
| `clean` | `<script> --clean` | Remove generated files (only those carrying the script's generated-file marker) |
| `watch` | `<script> --watch` | Re-sync on change. **Long-running** — see below |

If the user passes a mode the script doesn't support, run `<script> --help` and relay the supported set.

## Workflow

1. **Resolve the script** via the bindings above. Verify it's executable (`test -x`); if not, run it via `bash <script>` rather than chmod-ing unprompted.
2. **Run from the project root** — these scripts typically use repo-relative paths internally and die elsewhere.
3. **Run the requested mode** and relay the script's own output (it reports per-file sync/prune lines and a summary).
4. **Report what changed**:
   - After `sync`: show the script's summary line; if the generated directory is git-tracked, also show `git status --short` for it so the user sees what would need committing. If it's gitignored, say so — nothing to commit.
   - After `check`: report in-sync / out-of-sync. If out of sync, show the script's diff output and offer to run `sync`.
   - After `clean`: list what was removed.

### Watch mode

`watch` blocks indefinitely. Don't run it in the foreground of a session turn:

- Default: run it as a background task (`run_in_background`) and tell the user it's watching; mention how to stop it.
- If the user seems to want it tied to their terminal instead, suggest they run `! <script> --watch` themselves so it lives in their session directly.
- If the script reports a missing watcher dependency (e.g. `fswatch` on macOS, `inotifywait` on Linux), relay the script's install hint and stop — don't install system packages unprompted.

## Don'ts

- **Don't hand-edit generated files** (e.g. `.cursor/rules/*.mdc` carrying a "DO NOT EDIT — generated" marker). Edits go in the source rules; the sync regenerates the mirror.
- **Don't write or modify the sync script itself** under this skill — this skill runs it. Script changes are normal feature work with the project's usual branch/review flow.
- **Don't commit anything unprompted.** Report what changed; the user decides whether/how generated-file changes ride along with their current work.
- **Don't auto-run on rule edits** — offer. A mid-task sync that dirties the working tree can pollute an unrelated diff.

## See also

- `~/.claude/skills/bootstrap-project/SKILL.md` — canonical PROJECT.md schema. The `agent_sync` block is optional; projects without a sync script simply omit it.
- The project's sync script header comment — authoritative for that project's modes, per-file activation directives, and generated-file markers.
