---
name: checkpoint
description: Saves session state to the project state file before the user clears context — surveys git/PR/tracker ground truth, harvests conversation-only context (decisions, open questions, loose ends), updates the state file via the docs carve-out, and confirms it's safe to /clear. Triggers on phrases like "checkpoint the session", "save state before clearing", "get ready to clear", "prep for the next session", "record state and clear", or "wrap the session without merging".
---

# Checkpoint

Captures everything the *next* session's agent needs before the user runs `/clear`. The state file is the rehydration document; this skill's job is making sure it tells the truth at the moment context is thrown away — especially the parts that live only in the conversation (decisions made, questions pending, review state) and would otherwise be lost.

Companion to `wrap-up`: wrap-up closes work that *merged*; checkpoint preserves work that's *in flight*. Running checkpoint never merges feature work, flips tickets, or deletes branches.

## Workflow

Follow the steps in order. The only user-blocking pause is the draft approval in step 3.

### 0. Read project bindings

Read `.claude/rules/PROJECT.md`. Required: `state_file.path` (if it's `null`, stop — tell the user this project has no state file to checkpoint into). Tracker bindings (`tracker`, `linear.*` / `github.*`) are used when present to verify ticket states; skip tracker verification without them.

**If PROJECT.md is missing**, defer to the `bootstrap-project` skill (see `~/.claude/skills/bootstrap-project/SKILL.md`), then resume.

### 1. Survey ground truth

Collect, in parallel where possible:

- `git status` + current branch. **If the working tree is dirty, stop and ask** — commit, stash, or leave is the user's call; never auto-commit. A checkpoint over uncommitted work is a checkpoint of a lie.
- Unpushed commits on the current branch (`git log @{u}..` — or an unpushed branch entirely). Offer to push: state saved to the state file is useless if the code it describes exists only on this machine.
- Open PRs for the repo's in-flight branches (`gh pr list --state open`) with review state.
- Tracker state for each ticket named by in-flight branches/PRs (Linear: see `.claude/rules/LINEAR.md` for auth; GitHub: `gh issue view`). Flag mismatches (e.g. PR open but ticket still In Progress) — fix only with user approval.

### 2. Harvest conversation-only context

From the current conversation, list what the repo and tracker *cannot* reconstruct:

- Decisions made this session (and where they got recorded — dialog rulings, doc updates in flight).
- Open questions awaiting the user (pending review hotspots, unanswered design choices).
- Loose ends and known drift noticed but deferred.
- The concrete next action the next session should start with.

Terse bullets, each self-contained. The test for inclusion: *would the next session's agent, reading only the repo + tracker + state file, miss this?* If the repo already records it, leave it out.

### 3. Draft the state-file delta and get approval

Update the file at `state_file.path` respecting its existing section structure and its own Maintenance rules. Typical updates:

- "Last updated" date.
- In-flight branches table/section: current branch, its PR, review status.
- Next-up section: reorder/reword if the session changed what's actually next.
- Blocked/waiting section: anything now waiting on a human.
- **`## Session handoff` section — owned by this skill.** Replace it wholesale each checkpoint (never append across sessions); it carries the step-2 harvest plus a "resume here" first line. It is transient by design: wrap-up or the next checkpoint deletes items that have landed. Add the section (with a one-line HTML comment `<!-- transient; owned by the checkpoint skill -->`) if it doesn't exist.

Show the full delta (or full new sections) in chat and **wait for approval** before landing anything.

### 4. Land it via the docs carve-out

The state file rides the project's docs-only carve-out (see METHODOLOGIES.md step 5 / PROJECT.md `wrapup` notes):

- Never commit the state-file edit onto the in-flight feature branch, and never edit directly on the default branch.
- Spawn a **background agent with worktree isolation** (feature work is in flight by definition here): branch `docs/checkpoint-<YYYY-MM-DD>` off the default branch, apply the approved delta, open a docs-only PR, merge directly per the carve-out policy (no CI wait where the project's policy says so).
- Commit/PR title prefix: `docs(state):`.

Local default-branch sync is *not* done now — the feature branch stays checked out; next session pulls.

### 5. Confirm ready-to-clear

When the docs PR merges, print a short exit summary:

- State file updated (PR link).
- Branch/PR/ticket status lines (all pushed, links).
- The "resume here" line the next session will see.

End with: safe to `/clear`. (The skill cannot clear for the user; `/clear` is theirs to run.)

## Guardrails

- No feature merges, no ticket transitions, no branch deletion — that's wrap-up's territory, post-merge only.
- Dirty working tree = hard stop until the user decides.
- The Session handoff section is replaced, not accumulated; if it grows stale entries the next checkpoint prunes them.
- State-file edit lands off the default branch via the carve-out, never on the feature branch (keeps PRs reviewable and the state file's history clean).

## See also

- `~/.claude/skills/wrap-up/SKILL.md` — post-merge closure; deletes handoff items that landed.
- `~/.claude/skills/daily-stand-up/SKILL.md` — consumes the same state file's next-up section for T discovery.
- `~/.claude/skills/bootstrap-project/SKILL.md` — PROJECT.md schema source of truth.
