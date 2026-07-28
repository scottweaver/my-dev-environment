# Architecture constraints

Decided, binding architecture facts. STATE.md answers "what is in
flight"; this file answers "what must remain true." Every constraint
here was decided in a design dialog or by a hard external fact — a
change to any of them is a design decision requiring its own dialog
and a PR that updates this file in the same change (see
METHODOLOGIES.md "Refactors that change documented architecture").

The intuition: STATE.md is a working artifact you update aggressively;
this file is a contract you update deliberately.

Established {{DATE}} ({{how: bootstrap dialog / initial design
session}}).

{{SECTIONS: one `##` section per architectural domain this project
actually has. Common domains — keep only what applies, add what
doesn't appear here:

## Source of truth
Where authoritative state lives; what is derived/cache.

## Module / crate / package layering
The dependency DAG between the project's units, and which direction
imports are allowed to flow.

## Data flow / pipeline shape
The phases work moves through and what each phase may know about.

## External boundaries
APIs, wire protocols, storage formats, third-party services — and
which types guard each boundary.

## Security and identity
Who holds credentials, what is signed/encrypted, where secrets live
(never in this repo — see the secrets policy).

Each constraint: one falsifiable, dated statement plus (optionally)
the one-line reason it was decided.}}

## Audit triggers

Files whose changes warrant re-checking this doc during post-merge
cleanup:

- {{path/glob — e.g. src/core/**, crates/*/Cargo.toml, the entry
  point, any boundary module}}
- {{...}}

## Structural criteria

Structural (this doc must change in the same PR): {{a change to any
layering rule above; a new external service or transport; a change to
who holds authoritative state; a change to a boundary contract;
replacing a core engine/framework}}.

Not structural (no update needed): {{API additions/renames that keep
the boundaries intact; test changes; implementation details behind an
unchanged surface}}.

## Maintenance

Update when a constraint above is deliberately renegotiated (design
dialog + PR updating this file), or when a recorded TBD is resolved.
Never for in-flight status — that's STATE.md. Keep constraints
falsifiable and dated. Secrets never enter this doc.
