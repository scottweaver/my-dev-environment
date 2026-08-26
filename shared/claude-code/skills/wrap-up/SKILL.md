---
name: wrap-up
description: Run the standard post-merge cleanup routine after a PR lands on the project's default branch. Reads project bindings from `.claude/rules/PROJECT.md` and supports Linear or GitHub issues as the tracker. Invoke explicitly with `/wrap-up [PR#]`, or organically when the user signals completion of a merged PR with phrases like "wrap it up", "ship it", "do the wrap-up", "standard wrap-up", "post-merge cleanup", or "finish the PR". The routine syncs the default branch, deletes the merged branch (local + remote), verifies the tracker ticket is done/closed, refreshes the project state file, optionally audits a secondary doc, opens a docs-only PR with auto-merge per the configured carve-out, and resyncs the default branch afterward.
---

# wrap-up — standard post-merge cleanup routine

Codifies the "After a PR merges" routine. Run this **immediately after a PR's commits land on the project's default branch**, before moving on to the next task. The routine propagates the merge to the parts of the project that don't update themselves: the local repo, the remote, the issue tracker, and the project state file. Skipping any step creates drift.

Project-specific bindings (state file path, branch/commit conventions, auto-merge carve-out, optional audit doc) come from `.claude/rules/PROJECT.md`. If that file is missing, defer to the `bootstrap-project` skill (`~/.claude/skills/bootstrap-project/SKILL.md`) and run its create-mode walkthrough first.

## When to invoke

- Explicit: `/wrap-up` or `/wrap-up <PR#>` after a merge.
- Organic: when the user signals completion ("wrap it up", "ship it", "standard wrap-up", "do the post-merge cleanup", "finish the PR"). Skill-matcher should auto-fire on these.
- **Do not invoke** for closed-without-merge PRs — that has a different cleanup (tracker ticket → Cancelled or back to Backlog, no state refresh). If the user says "wrap up" for a closed-not-merged PR, ask first.

## Input handling

- **With explicit PR#** (`/wrap-up 87`): use that PR.
- **Without argument**: run `gh pr list --state merged --limit 3 --json number,title,mergedAt,headRefName` and pick the most recently merged. If the most recent is older than ~1 hour or ambiguous (multiple recent merges), confirm with the user before proceeding.
- **Tracker ticket ID**: derive from the PR title/body or commit message. If ambiguous, ask. With `tracker: none` there is no ticket — use the PR number for slugs and skip step 3.

## The 8 steps

Run sequentially. Each step is short; the whole routine takes a couple of minutes.

### 0. Read project bindings

Look for `.claude/rules/PROJECT.md`. Required YAML-frontmatter fields:

- `tracker`: `linear`, `github`, or `none`
- Tracker-specific bindings (Linear: workspace, team_prefix, assignee_id, state_uuids; GitHub: owner, repo, assignee; none: no bindings — step 3 is skipped)
- `state_file.path` (may be `null` to disable steps 4 + 6 + 7)
- `wrapup.docs_pr_branch_prefix`, `wrapup.docs_pr_commit_prefix`, `wrapup.auto_merge_carve_out_path`
- `wrapup.state_refresh_authority` (optional — the rule file that owns the post-merge policy)
- `wrapup.audit_doc` (optional — if present, drives step 5)

**If PROJECT.md is missing**, defer to the `bootstrap-project` skill — read `~/.claude/skills/bootstrap-project/SKILL.md` and run its create-mode walkthrough. After PROJECT.md is written, resume this skill from step 1.

### 1. Pull the default branch and switch off the merged branch

```bash
DEFAULT=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)
git checkout "$DEFAULT" && git pull --ff-only
```

Capture the new head SHA — you'll need it in step 4. If `git pull` reports "Already up to date" but you expected new commits, the merge may have been to a different remote or branch; verify with `git log --oneline -5`.

### 2. Delete the merged branch — local and remote

```bash
git branch -d <branch-name>
git push origin --delete <branch-name>
```

**Guardrails:**

- Use `-d`, not `-D`. If `-d` refuses, the branch isn't actually merged — investigate before forcing.
- Squash-merged PRs may produce a warning like *"deleting branch ... merged to refs/remotes/origin/... but not yet merged to HEAD"* — expected; deletion proceeds.
- If `gh pr merge --delete-branch` was used at merge time, the remote branch is already gone — the local `git branch -d` may also have been auto-cleaned. Either of these returning "not found" is fine; don't treat it as an error.
- The local branch deletion is the only destructive step. If acting unprompted (rare; this skill is usually invoked explicitly), confirm before running.

### 3. Verify the tracker ticket is done/closed

Branch on `tracker`. **If `tracker: none`**: skip this step — there is no ticket to verify. Record "no tracker configured — skipped" in the outcomes table's step-3 row and continue to step 4.

#### Linear branch

Check the ticket's current state. If a GitHub→Linear integration is installed for the project, it *may* have auto-flipped the ticket on PR merge — but that's project-dependent; don't assume.

```bash
source ~/.zshrc
TICKET="<identifier from PR title/body>"
curl -sS https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" -H "Content-Type: application/json" \
  -d "$(jq -n --arg id "$TICKET" '{query:"query($id:String!){ issue(id:$id){ identifier state{ name } } }", variables:{id:$id}}')" | jq .
```

If still `In Review` or `In Progress` (or any non-done state), flip manually using the `issueUpdate` mutation with `linear.state_uuids.done` from PROJECT.md (or probe via the project's LINEAR.md recipe if uuids aren't bound). For projects without the integration, manual flip is the *expected* path, not a fallback — record it as ✅ in the outcomes table, not ⚠️. For projects with the integration, a manual-flip step *is* worth flagging in the table since it usually means the PR title/body convention slipped (project-specific guidance in the project's LINEAR.md).

#### GitHub branch

GitHub doesn't have an auto-flip equivalent, but PR descriptions containing "Closes #N" / "Fixes #N" / "Resolves #N" auto-close the referenced issue on merge. Verify:

```bash
gh issue view <NN> --json state,closedAt
```

If still `OPEN`, the PR body probably didn't reference the issue with a closing keyword. Close manually:

```bash
gh issue close <NN> --comment "Closed via PR #<PR>"
```

### 4. Refresh the project state file

The judgment step — don't over-automate. **Skip this step entirely if `state_file.path` is null** in PROJECT.md (and skip steps 6 + 7 below too; emit a compact outcomes table).

Branch off the default branch using the configured prefix:

```bash
git checkout -b <wrapup.docs_pr_branch_prefix><ticket-or-pr-short-slug>
```

Read the state file. **If the file has its own Maintenance / Conventions section, that section is authoritative** — honor it before applying the generic rules below.

Generic always-do edits:

- Bump the `Last updated:` date + one-line summary at the top (if the file has one).
- Update default-branch head-SHA references (if tracked).
- Update test/measurement baselines (if tracked and they changed).
- Remove the merged branch from any "Branches in flight" or equivalent table.
- Prepend an entry to the project's "Recent progress" / "Changelog" / "Most recent" section with the date, ticket ID + PR#, and a 2-4 sentence summary describing **what / why / risk** in the established voice. Match the style of existing entries.
- Trim the oldest entry if the list overflows the project's configured limit.

As-applicable edits depend on the project — re-read the state file's Maintenance section.

**Don't:**

- Edit the state file on the default branch directly if the file's Maintenance section forbids it (most do — STATE-style files are usually branch-scoped).
- Mechanically copy the PR description into the progress entry — re-summarize in the established voice. The entry is a memory aid for future readers, not a changelog.

**Gotcha — long single-line entries (>~1 KB):** Some state files pack a whole paragraph or table row onto a single physical line (e.g. a STATE.md "Last updated:" prose paragraph, or a "Branches in flight" `main` row with several KB of inlined detail). For those, **do not** use the `Edit` tool with a leading prefix match to replace them — `Edit` only replaces what its `old_string` matches, and the rest of the long line stays concatenated after your new content. The result is a single line with [new prefix] + [leftover old suffix], no closing delimiter, and a broken Markdown table or doubled-up prose.

Use **index-based whole-line replacement** instead:

```bash
python3 - <<'PYEOF'
from pathlib import Path
p = Path('<state_file.path>')
lines = p.read_text().split('\n')
# 0-indexed; e.g. lines[4] = "Last updated: <new prose>"
lines[<line_idx>] = '<new full line content>'
p.write_text('\n'.join(lines))
PYEOF
```

Or `sed -i` with an explicit line address (`sed -i '' '5c\<new line>' file`). The check after writing: count delimiters on the rewritten line. For a 5-column table row, expect exactly 6 `|` characters (`awk 'NR==<n> {print gsub(/\|/, "|")}'`). Any other count means leftover concatenation — fix before continuing.

Pattern recognition: if a single line in the state file is >1000 characters wide, reach for index-based replacement preemptively. `Edit` with prefix matching is safe on short lines and on multi-line blocks; it's the long-single-line case specifically where it silently leaves garbage.

### 5. Audit the secondary doc (optional)

**Skip this step if `wrapup.audit_doc` is null** in PROJECT.md.

When configured, the audit doc has:

- `path`: file path of the doc to audit
- `trigger_checklist_section`: section name listing files whose changes warrant a doc update
- `structural_criteria_section`: section name listing what counts as a structural change

**Get the merged PR's file list:**

```bash
gh pr view <PR#> --json files --jq '.files[].path'
```

**Cross-reference against the trigger checklist** in the audit doc. If the PR touched any checklist file AND did not already update the audit doc in the merge:

1. Read the audit doc's `structural_criteria_section`. Type-internal changes (renames, signature widening, brand propagation, helper extraction) typically don't qualify. Structural changes (phase added/removed, new convention name introduced, removed section, file:line drift past the project's threshold, replaced worked example) typically do.
2. Audit specifically against each criterion in the section.
3. **If yes — update the audit doc on the same docs branch** and fold the edits into the same commit as the state-file refresh (both ride the configured auto-merge carve-out). Edit conservatively; match the existing voice and density.
4. **If no — note "audit doc: no update needed" in the outcomes table** and continue. Don't write a non-substantive change.

If the PR touched no checklist file: skip; note "audit doc: non-trigger-touching, skipped".
If the audit doc was already updated in the merged PR: skip; note "audit doc: already updated in PR".

### 6. Commit + push + open a docs-only PR with auto-merge

Commit-message header: `<wrapup.docs_pr_commit_prefix> refresh post PR #N merged — <ticket-id> closed; <one-line context>`. If the audit doc was also updated in step 5, mention it in the body (e.g. `+ <audit_doc.path> updated for <reason>`). Body explains the merge in 2-4 lines + cites the head SHA.

```bash
git add <state_file.path>   # + <audit_doc.path> if step 5 produced edits
git commit -m "..."  # via HEREDOC per shell-tool conventions
git push -u origin <wrapup.docs_pr_branch_prefix><slug>
```

Create the PR:

```bash
gh pr create --title "<wrapup.docs_pr_commit_prefix> ..." --body "$(cat <<'EOF'
## Summary
- <bullets>

## Test plan
- [x] Documentation-only edit under <wrapup.auto_merge_carve_out_path> per project convention
- [x] No source-code changes; CI gate will pass trivially
EOF
)"
```

**Auto-merge** per the carve-out — applies when the *entire* diff is under `wrapup.auto_merge_carve_out_path`. If the diff includes any file outside that path (source, tests, workflows), do not auto-merge; surface for review.

```bash
gh pr merge <N> --auto --squash --delete-branch
```

The CI gate runs even on docs-only PRs; auto-merge fires when CI passes. May fire instantly if a baseline-update workflow recently re-ran.

### 7. Sync local default branch after auto-merge fires

```bash
git checkout "$DEFAULT" && git pull --ff-only && git log --oneline -3
```

Verify the state-file refresh + any baseline-update commit landed. The local branch should auto-delete; if not:

```bash
git branch -d <wrapup.docs_pr_branch_prefix><slug>
```

### 8. Emit the outcomes table

After step 7 completes, **always** emit a markdown summary table with three columns: `Step | Outcome | Notes`. This is the user-facing receipt of what the routine actually did. Required even when every step succeeds — the table is the deterministic signal that the routine ran end-to-end, and it surfaces edge cases (manual tracker flip, branch already gone, auto-merge instant, baseline already absorbed, audit-doc update folded in, etc.) in one glance.

Format:

```markdown
| Step | Outcome | Notes |
|---|---|---|
| 1 — Pull <default-branch> | ✅ at `<sha>` | <one-line observation, e.g. "baseline auto-update already absorbed"> |
| 2 — Delete branch | ✅ local + remote gone | <deviation, e.g. "remote already deleted by --delete-branch"; otherwise "clean"> |
| 3 — Tracker <TICKET> → done/closed | ✅ <auto-flipped \| manual flip via `issueUpdate`> | <one-line context, e.g. "no integration on this repo — manual is expected" or "auto-flip missed: <reason>"> |
| 4 — State file refresh | ✅ judgment-call edits | <what specifically changed, e.g. "head SHA, branches+measurements tables, progress log prepend + trim"> |
| 5 — Audit doc | ✅ <no update needed \| folded in \| already in PR \| not configured \| non-trigger-touching, skipped> | <one-line reason> |
| 6 — PR #<N> + auto-merge | ✅ carve-out applied | <e.g. "fired instantly because baseline workflow already current"> |
| 7 — Sync default branch | ✅ at `<sha>` | <e.g. "local branch auto-deleted" or "deleted manually"> |
```

Use ✅ for success, ⚠️ for partial / non-blocking deviation (e.g. "tracker ticket not found — skipped step 3"), ❌ for failure (and stop the routine to investigate before emitting; this column should rarely show ❌).

Follow the table with one or two sentences of forward context: which tracker ticket is next, whether anything in this run flagged a follow-up worth filing, and any open observations about the skill itself (e.g. a failure mode that's becoming a pattern and could be hardened).

## Don'ts

- **Don't auto-delete the merged branch without confirming** when running unattended. Confirmation is implicit when this skill is invoked explicitly; if running organically and any branch state looks unusual (uncommitted changes, non-fast-forward default, etc.), stop and ask.
- **Don't edit the state file on the default branch directly.** Always go through the configured docs branch.
- **Don't extend the auto-merge carve-out beyond `wrapup.auto_merge_carve_out_path`.** If the diff touches any file outside that path (source, tests, workflows), go through normal review.
- **Don't cite "auto-merge fine" for PRs that aren't pure carve-out-path edits.** Re-check the diff before invoking `gh pr merge --auto`.
- **Don't write a non-substantive audit-doc edit** just because the audit fired. If the change is type-internal (renames, branding, signature widening, helper extraction), "no update needed" is the right answer — say so in the outcomes table and skip the write.

## What this skill replaces

Nothing — it's an encoded version of the project's post-merge policy (typically `wrapup.state_refresh_authority` if configured). The policy rule file remains authoritative; this skill is the executable form. If the two ever drift, the policy file wins; update this skill (or PROJECT.md) to match.

## Edge cases worth recognising

- **PR closed without merge** — different routine; not this skill.
- **Several PRs merged at once** — wrap up each individually; state-file refresh can batch the progress-log entries if they're tightly related (same track, same day).
- **Tracker ticket not found** — investigate before flipping anything; may be that the PR had no ticket ref by design (e.g. tiny tech-debt chores), in which case skip step 3.
- **No tracker configured** (`tracker: none`) — skip step 3; note "no tracker configured — skipped" in the outcomes table. The PR/branch steps still apply when the repo is hosted on GitHub.
- **State file already up-to-date** (race: someone else refreshed it) — skip steps 4-7; verify and move on.
- **No state file configured** (`state_file.path: null`) — skip steps 4-7 entirely; emit a compact outcomes table covering steps 1-3 + 8.
- **No audit doc configured** (`wrapup.audit_doc: null`) — skip step 5; note "not configured" in the outcomes table.
- **Baseline workflow already absorbed the merge** — fine; auto-merge of the docs PR fast-forwards through it.
- **Long single-line state-file entries** — see the Gotcha block in step 4. State files that pack paragraphs/table rows onto single physical lines (>~1 KB) need index-based replacement (Python or `sed`), not the `Edit` tool's prefix matching, which silently leaves the rest of the old line concatenated.

## See also

- `.claude/rules/PROJECT.md` — project bindings consumed by this skill.
- `~/.claude/skills/bootstrap-project/SKILL.md` — owns the PROJECT.md schema, template, and interactive bootstrap walkthrough. Invoked automatically when PROJECT.md is missing; also directly invokable for new projects or to edit existing bindings.
- `~/.claude/skills/daily-stand-up/SKILL.md` — companion stand-up skill consuming the same PROJECT.md.
- The project's state file's own Maintenance section — authoritative for step-4 conventions.
- The project's `wrapup.state_refresh_authority` rule file (if configured) — authoritative for the post-merge routine policy.
