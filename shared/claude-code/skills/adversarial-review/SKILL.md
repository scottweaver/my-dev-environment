---
name: adversarial-review
description: Spawn two isolated, context-blind adversarial agents — a Falsifier hunting concrete failure scenarios and an Auditor hunting violations of documented contracts — to review a diff in parallel git worktrees, then arbitrate their findings with evidence and report verdicts to the human. Invoke explicitly with `/adversarial-review [PR# | branch | diff-range]`, or organically on phrases like "adversarial review", "red team this PR", "get me a blind review", "have fresh eyes review this branch", or before human review of a meaty PR when the project has bound this into its PR flow.
---

# adversarial-review — two blind adversaries and an arbiter

The implementing session is the worst-placed reviewer of its own
change: it knows what the code is *supposed* to do, and that
knowledge papers over what the code *actually* does. This skill buys
independence through isolation — subagents launched with the Agent
tool inherit **no conversation context**, so they cannot absorb the
implementer's assumptions. Two agents with *opposed charters* attack
the same diff from different directions; the implementing session
then arbitrates their findings as a named conflict of interest,
refuting with evidence or conceding.

## When to run

- Before human review of any meaty PR (a project may bind this into
  its PR/methodology flow — see "Project wiring").
- On request, against any diff, branch, or PR — including code the
  session did not write.
- Not for trivial diffs (docs-only, mechanical renames): two deep
  reviews cost real tokens; say so and offer a single-agent pass
  instead.

## Target resolution

1. Explicit argument wins: a PR number (`gh pr diff <n>`, `gh pr
   view <n>` for recorded intent), a branch, or an explicit range.
2. Default: the current branch against the repo's main branch —
   `git diff main...HEAD` — plus the PR description when one exists.
3. Uncommitted work: reviewable (`git diff` in the worktree won't
   see it — pass the diff inline or stage it first); prefer
   reviewing committed state so the agents' worktrees reproduce it.

## The two charters

Launch both with the Agent tool, `subagent_type: "general-purpose"`,
`isolation: "worktree"`, **in one message** so they run in parallel.
Each prompt contains ONLY: the shared preamble, the target refs, the
charter, and the output contract. See "Blindness rules" for what must
never enter the prompt.

**Shared preamble (both agents):** You are an independent,
adversarial code reviewer with no relationship to the change's
author; you inherit no context — everything you conclude must come
from the repository and its recorded artifacts (code, commits, PR
description, project docs). You work in an isolated git worktree;
never commit or push. You may build and run anything there (test
suite, lints, doc tests) and write throwaway repro tests to check a
hypothesis. Assume the diff contains at least one real problem
review is meant to catch; your success is measured by finding what
the author missed, never by agreeing with them.

**Agent F — the Falsifier (correctness adversary).** Charter: prove
the diff defective with concrete failure scenarios only —
concurrency and interleaving (cancellation safety, channel-close
races, task lifecycle), protocol/state-machine holes (partial
failure between sequence steps, loss *during* recovery paths), data
lost/duplicated/reordered as observable by a user, reachable panics
in library code, resource leaks across repeated cycles, boundary
conditions on error paths. Every finding needs inputs/interleaving →
wrong observable outcome. No style findings of any kind.

**Agent A — the Auditor (contract adversary).** Charter: prove the
diff violates a documented constraint. Authorities: the project's
rules layer (`.claude/rules/*`, `CLAUDE.md`/`AGENTS.md`), READMEs
and architecture docs whose described shapes the diff touches, and
the rustdoc/docstring contracts in and around the diff itself. Hunt
invariant violations, doc drift (docs describing what the diff
changed, or missing what it added), public-API contract holes,
coverage gaps (claimed behavior no test pins), layering violations,
and conventions the rules files make *binding* (those are not style
nits). Every finding cites the violated constraint verbatim with its
source file.

**Output contract (both):** findings capped at 8, ranked most severe
first, each with severity (critical/major/minor), `file:line`, a
falsifiable one-sentence claim, the scenario or violated constraint,
confidence, and how it was validated (read / ran / wrote repro).
Then a **"Probed and held"** list — surfaces genuinely attacked that
resisted. The negative results are part of the deliverable: they are
the coverage map of the review. No praise, no change summary.

## Blindness rules

- The prompts must never contain the implementation narrative:
  design rationale, "what I was trying to do", known-weak spots, or
  anything from the implementing conversation. Blindness is the
  point — a reviewer told where to look stops looking elsewhere.
- Repo artifacts are fair game (commits, PR body, rules docs): they
  are the durable record, and drift between them and the code is
  itself a finding.
- A one-line neutral statement of the change's *claimed* purpose
  (as recorded in the PR title/description) is allowed so agents
  orient fast; copy it from the artifact, don't paraphrase from
  memory.
- Fully-blind knob: when the PR prose itself might anchor the
  reviewer (it was written by the implementer too), tell one agent
  to skip the PR description and derive intent from code and tests
  alone.

## Arbitration — the implementing session's job

The arbiter has a named conflict of interest: it wrote the code. The
discipline that keeps it honest is *refutation with evidence*:

1. For each finding, attempt to refute it — read the actual code
   path, run the cited test, write the repro the agent described.
2. Verdict per finding: **CONFIRMED** (with the evidence),
   **REFUTED** (with the evidence — an assertion is not evidence),
   or **UNCERTAIN** (the human rules).
3. Both agents independently reporting the same defect is
   independent rediscovery: treat as confirmed-unless-refuted.
4. Never silently drop a finding. Every one appears in the report
   with its verdict.

## Report to the human

One table: `# | sev | finding (file:line) | source (F/A/both) |
verdict | evidence`. Below it: dispositions — confirmed findings get
fixed on the branch or ticketed (severity decides; the human picks
when it isn't obvious), uncertain ones get the human's ruling,
refuted ones stay recorded with their refutation. Append both
"Probed and held" lists as the coverage signal. Findings are never
auto-fixed before the human has seen the table — the human is the
court of appeal, and silent fixes hide the review.

## Cost and calibration

Default is two agents, one pass each — roughly two deep independent
reviews' worth of tokens. Scale only on explicit request: a third
bespoke charter (security, performance, migration safety) when the
diff warrants it, or a re-run after fixes land. Don't loop
automatically; adversarial review is a gate, not a daemon.

## Operational notes

- Background agents do not survive a harness reload (`/reload-skills`,
  window/session restart): the task registry drops them mid-run and
  no completion notification ever fires. Symptoms: `ListAgents` and
  `TaskOutput` no longer know the IDs, and the agents' worktrees sit
  orphaned under `.claude/worktrees/agent-*` (a clean completion
  auto-removes an unchanged worktree). Recovery: check the orphaned
  worktrees are clean (`git -C <worktree> status --short`), remove
  them (`git worktree remove`), relaunch the pair. Avoid reloading
  skills or restarting the session while a review pair is in flight.

## Project wiring (optional)

A project may bind this into its flow: a line in its methodology doc
(e.g. "meaty PRs get an adversarial pass before human review") and,
in its `PROJECT.md` bindings, per-project extras — additional
authorities for the Auditor, a standing third charter, or a
different default target branch. Absent bindings, the defaults above
apply as-is.
