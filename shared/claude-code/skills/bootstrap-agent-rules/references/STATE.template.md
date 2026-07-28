# Project State

The rehydration document. Any agent starting a session reads this
first to learn where the project stands right now. It answers "where
are we" — never "how does this work" (that's ARCHITECTURE.md and the
code) and never "how should we work" (that's METHODOLOGIES.md).

Last updated: {{DATE}}

## Active workstream

{{One dense narrative paragraph: what is being worked on right now,
what phase it is in, what just closed, what decisions are binding.
Written for an agent with zero session history.}}

## Branches in flight

| Branch | Purpose | Status |
|---|---|---|
| `main` | trunk | {{short state, e.g. "at <sha>, N tests green"}} |

## Next up

1. {{Most imminent task}}
2. {{Second}}
3. {{Third}}

## Most recent meaningful progress

- **{{DATE}} — {{headline}}.** {{What happened.}} Why: {{why it
  mattered}}. Risk: {{what could bite later, or "none noted"}}.

## Blocked / waiting

- *(nothing)*

## Maintenance

- **Refresh trigger:** any merge or milestone that changes what an
  incoming agent needs to know: workstream shifts, a branch opens or
  closes, "Next up" changes, something lands. Wired into
  METHODOLOGIES.md's post-merge routine (step 4).
- **Always update:** "Last updated"; "Branches in flight"; prepend a
  progress entry (what / why / risk voice — a judgment edit, not a
  paste of the PR description).
- **As applicable:** "Active workstream" paragraph, "Next up",
  "Blocked / waiting".
- **Trim policy:** progress log holds at most 10 entries — drop the
  oldest when adding. Anything stable graduates out of this file
  into the appropriate rules doc; this file stays small because
  every agent loads it every turn.
- **Edit policy:** STATE.md is authored on feature branches,
  propagates through merges, and is refreshed (not deleted) on new
  branches. Never edit it directly on `main`; docs-only diffs under
  `.claude/rules/` ride the METHODOLOGIES.md step-5 carve-out.
- **Keep entries short:** each progress entry is a pointer — date,
  PR #, ticket, a sentence or two of judgment. If you're tempted to
  write more, the detail belongs in the PR, commit, or ticket.
