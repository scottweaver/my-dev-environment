---
name: bootstrap-project
description: Creates or edits `.claude/rules/PROJECT.md` — the bindings file consumed by the portable `daily-stand-up` and `wrap-up` skills. Owns the canonical PROJECT.md schema, the interactive walkthrough, the file template, and the Linear/GitHub auto-detection helpers. Invoke explicitly when setting up a new project (phrases like "set up PROJECT.md", "bootstrap project bindings", "configure this project for stand-up", "init project skills", "create PROJECT.md") or referenced automatically by `daily-stand-up` / `wrap-up` when PROJECT.md is missing at run time.
---

# bootstrap-project

Creates or edits `.claude/rules/PROJECT.md` — the per-project bindings file consumed by the portable skills at `~/.claude/skills/daily-stand-up/` and `~/.claude/skills/wrap-up/`. This skill is both:

1. **Explicitly invokable** — run when standing up a new project so the stand-up / wrap-up skills work out of the box.
2. **Referenced by daily-stand-up and wrap-up** — when either of those skills detect that `PROJECT.md` is missing at run time, they defer to the walkthrough in this file.

This file is the single source of truth for:

- The PROJECT.md YAML-frontmatter schema.
- The interactive bootstrap walkthrough.
- The Linear / GitHub auto-detection helpers.
- The PROJECT.md file template.

If any of the above ever drift across the three skills, this file wins; update daily-stand-up + wrap-up to match.

## When to invoke

- **Explicit user intent**: `/bootstrap-project`, or phrases like "set up PROJECT.md", "bootstrap project bindings", "configure this project for the stand-up / wrap-up skills", "init project skills", "create PROJECT.md".
- **Organic, from another skill**: `daily-stand-up` or `wrap-up` detecting `.claude/rules/PROJECT.md` is missing at run time. The user-facing flow: the calling skill announces *"PROJECT.md missing — let me set that up first"*, the assistant runs the walkthrough below, then resumes the calling skill's workflow.

If invoked explicitly when PROJECT.md *already exists*, default to **edit mode** (see the section below) — don't silently overwrite.

## Workflow — create mode

### 1. Detect existing PROJECT.md

```bash
test -f .claude/rules/PROJECT.md && echo exists || echo missing
```

- **Missing** → proceed to step 2.
- **Exists** → switch to edit mode (see below).

### 2. Tracker selection

Ask: *"Which issue tracker does this project use?"*

- **Linear** → step 3.
- **GitHub Issues** → step 4.
- **Other** (Jira, Shortcut, none) — current schema doesn't cover; tell the user the schema needs extending and stop. Offer to extend the schema together if appropriate.

### 3. Linear bindings

Required:

- `workspace` — workspace slug (appears in `linear.app/<workspace>/issue/<id>`).
- `team_prefix` — uppercase ticket prefix (e.g. OSS, ENG).
- `assignee_id` — the user's Linear UUID.

**Auto-detect path** (try in order; fall back to asking the user only for what these can't determine):

1. **Look for `.claude/rules/LINEAR.md` in the project** — Linear-workspace-using projects typically have one. Pull workspace, team prefix, and (sometimes) assignee_id from its "Workspace constants" / equivalent table or its "Assignment" section. Show what you found and confirm.
2. **Probe the API for the current user** (only if step 1 didn't yield `assignee_id`):

   ```bash
   source ~/.zshrc
   curl -sS https://api.linear.app/graphql \
     -H "Authorization: $LINEAR_API_KEY" -H "Content-Type: application/json" \
     -d '{"query":"{ viewer { id name displayName } }"}' | jq .
   ```

   `viewer.id` is the authenticated user's `assignee_id`. Confirm with the user before binding.

3. **Ask the user** for anything still unknown.

Optional but recommended — `state_uuids` (`in_progress`, `in_review`, `done`). Skill `wrap-up` uses these for manual ticket flips when the GitHub→Linear auto-flip integration misses. If a team UUID is available (from LINEAR.md or elsewhere):

```bash
source ~/.zshrc
curl -sS https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" -H "Content-Type: application/json" \
  -d '{"query":"{ team(id:\"<team-uuid>\") { states { nodes { id name type } } } }"}' | jq .
```

Pluck the state UUIDs by `name`. Skip the whole `state_uuids` block if no team UUID is discoverable — the bindings remain valid without it (wrap-up will probe at flip time).

### 4. GitHub bindings

Required:

- `owner` — GitHub org or user.
- `repo` — repo name.
- `assignee` — gh login.

**Auto-detect path:**

```bash
gh repo view --json owner,name --jq '{owner: .owner.login, repo: .name}'
gh api user --jq .login
```

If `gh` is unavailable or unauthenticated, ask the user inline. Confirm all three values before binding.

### 5. State file

Ask: *"Does this project have a live state-tracking file (e.g. `STATE.md`)?"*

- **Yes** — ask for path; offer `.claude/rules/STATE.md` as the default. Ask which "next up" patterns to recognise. Offer these defaults; let the user trim/extend:
  - `**Next: {ID}**`
  - `**next up: {ID}**`
  - `Next up in Phase N: {ID}`

  The `{ID}` placeholder is substituted with the tracker-appropriate identifier shape at run time (`<team_prefix>-\d+` for Linear, `#\d+` for GitHub).

- **No** — bind `state_file.path: null`. Downstream behaviour:
  - `daily-stand-up` falls back to prompting the user inline for the T ticket.
  - `wrap-up` skips steps 4 + 6 + 7 entirely and emits a compact outcomes table.

### 6. Stand-up settings

- `no_blockers_sentinel` — ask. Offer `:none:` as a safe generic default. If the team uses a custom Slack emoji (e.g. `:none_nun:`), bind that **verbatim** — do not strip colons or otherwise normalise. The value is emitted byte-for-byte.

### 7. Wrap-up settings

Ask: *"Will you use the `wrap-up` skill in this project too?"*

- **No** — emit the `wrapup:` block as commented-out in the template so it's discoverable but inert.
- **Yes** — gather:

  | Field | Default | Notes |
  |---|---|---|
  | `docs_pr_branch_prefix` | `docs/state-post-` | Branch name; ticket-or-PR slug appended at run time. |
  | `docs_pr_commit_prefix` | `docs(state):` | Commit message header. |
  | `auto_merge_carve_out_path` | `.claude/rules/` | Diff entirely under this dir is auto-merge-eligible. |
  | `state_refresh_authority` | `null` | Path to the rule file owning the post-merge policy (e.g. `.claude/rules/METHODOLOGIES.md`). Ask if such a file exists. |
  | `audit_doc` | `null` | See below. |

  **Optional `audit_doc`** — ask: *"Is there a secondary doc (e.g. architecture doc, pipeline walkthrough) that needs auditing on certain merges?"* If yes, gather:

  - `path` — file path.
  - `trigger_checklist_section` — section name in that doc listing the files whose changes warrant an audit.
  - `structural_criteria_section` — section name listing the structural-change criteria.

  If no, bind `audit_doc: null`. The wrap-up skill skips step 5 cleanly when null.

### 8. Write PROJECT.md

Render the template at the bottom of this file, substituting the values gathered. Comment out the unused tracker block (Linear-configured → comment out `github:` and vice versa) so the file stays self-documenting.

```bash
cat > .claude/rules/PROJECT.md <<'EOF'
<rendered template>
EOF
```

Show the rendered file in chat. Ask: *"Looks good?"* If the user wants tweaks, edit before finishing.

### 9. Confirm and exit

Tell the user:

- PROJECT.md is now at `.claude/rules/PROJECT.md`.
- The `daily-stand-up` and `wrap-up` skills will pick it up automatically.
- If invoked from another skill, hand control back so the caller can resume from where it paused.

## Workflow — edit mode

If invoked explicitly while PROJECT.md *already exists*:

1. Read it; render the current YAML frontmatter in a digestible form (tracker, state file path, audit-doc status, etc.).
2. Ask which section to edit: `tracker`, `linear` / `github`, `state_file`, `standup`, `wrapup`, `audit_doc`, or `regenerate from scratch`.
3. Walk through just that section using the create-mode steps as a template.
4. Show before/after diff; confirm before writing.

**Do not silently regenerate** — always confirm, even when the user explicitly asked for regeneration.

## Schema reference (canonical)

PROJECT.md uses a YAML frontmatter followed by markdown prose. The frontmatter is what skills consume; the prose is for human readers.

### Top-level fields

| Field | Type | Required | Notes |
|---|---|---|---|
| `tracker` | `linear` \| `github` | yes | Skills branch on this. |
| `linear` | object | when `tracker: linear` | See Linear block below. |
| `github` | object | when `tracker: github` | See GitHub block below. |
| `state_file` | object | yes (`path` may be `null`) | See State-file block. |
| `standup` | object | yes (when daily-stand-up used) | See Stand-up block. |
| `wrapup` | object | yes (when wrap-up used) | See Wrap-up block. |
| `agent_sync` | object | no | Consumed by `~/.claude/skills/agent-sync`. Omit when the project has no rules-sync script. |

### Linear block

```yaml
linear:
  workspace: <slug>                 # linear.app/<workspace>
  team_prefix: <PREFIX>             # uppercase
  assignee_id: <uuid>
  state_uuids:                      # optional but recommended
    in_progress: <uuid>
    in_review:   <uuid>
    done:        <uuid>
```

### GitHub block

```yaml
github:
  owner: <gh-org-or-user>
  repo:  <repo-name>
  assignee: <gh-login>
```

### State-file block

```yaml
state_file:
  path: <file-path>                 # or null to disable T discovery + step-4/6/7 of wrap-up
  next_up_patterns:                 # array of patterns; first match wins
    - <pattern with {ID} placeholder>
    - ...
```

### Stand-up block

```yaml
standup:
  no_blockers_sentinel: <string>    # emitted verbatim, no normalisation
```

### Wrap-up block

```yaml
wrapup:
  docs_pr_branch_prefix: <prefix>           # ticket-or-PR slug appended at run time
  docs_pr_commit_prefix: <prefix>           # commit message header
  auto_merge_carve_out_path: <dir-path>     # diff under this dir is auto-merge-eligible
  state_refresh_authority: <file-path> | null
  audit_doc:                                # optional; null when not configured
    path: <file-path>
    trigger_checklist_section: <section-name>
    structural_criteria_section: <section-name>
```

### Agent-sync block (optional)

Consumed by `~/.claude/skills/agent-sync` — runs the project's rules-sync script (e.g. `.claude/rules/*.md` → `.cursor/rules/*.mdc`). Omit the whole block when the project has no such script; the agent-sync skill falls back to auto-detection.

```yaml
agent_sync:
  script: <repo-relative-path>              # e.g. scripts/agent-sync.sh; run from project root
```

## PROJECT.md template

Substitute values during step 8. Comment-out the unused tracker block.

```markdown
---
# Project skill bindings — consumed by ~/.claude/skills/daily-stand-up and ~/.claude/skills/wrap-up.
# Hand-edited rule file; the portable skills are project-agnostic, all the per-project values live here.
# Schema source of truth: ~/.claude/skills/bootstrap-project/SKILL.md

tracker: <linear|github>

# Linear bindings (required when tracker: linear; ignored otherwise).
linear:
  workspace: <slug>
  team_prefix: <PREFIX>
  assignee_id: <uuid>
  state_uuids:
    in_progress: <uuid>
    in_review:   <uuid>
    done:        <uuid>

# GitHub bindings (required when tracker: github; ignored otherwise).
# github:
#   owner: <gh-org-or-user>
#   repo:  <repo-name>
#   assignee: <gh-login>

# Project state file consumed by daily-stand-up (T discovery) and wrap-up (step-4 refresh).
# Set state_file.path to null to disable both behaviours.
state_file:
  path: <path-or-null>
  next_up_patterns:
    - "**Next: {ID}**"
    - "**next up: {ID}**"
    - "Next up in Phase N: {ID}"

# Stand-up-only settings.
standup:
  no_blockers_sentinel: ":none:"

# Wrap-up-only settings.
wrapup:
  docs_pr_branch_prefix: docs/state-post-
  docs_pr_commit_prefix: "docs(state):"
  auto_merge_carve_out_path: .claude/rules/
  state_refresh_authority: null
  audit_doc: null
---

# Project bindings — <project-name>

Free-form prose narrative. Document anything the skills should know about that doesn't fit the YAML above — auth rules, branch conventions, edge cases, references to other rule files, history of past calibration choices.
```

## See also

- `~/.claude/skills/daily-stand-up/SKILL.md` — consumes PROJECT.md for tracker + state-file + standup bindings.
- `~/.claude/skills/wrap-up/SKILL.md` — consumes PROJECT.md for tracker + state-file + wrapup bindings.
