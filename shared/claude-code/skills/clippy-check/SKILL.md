---
name: clippy-check
description: Run the workspace clippy gate (`cargo clippy --all-targets -- -D warnings`) and present every warning/error as a readable, deduplicated report with clickable workspace-relative file:line links. Invoke explicitly with `/clippy-check [extra cargo args]` (e.g. `/clippy-check -p my-crate`), or organically on phrases like "run clippy", "clippy check", "is clippy clean", "lint check", "show me the clippy warnings", or before opening a PR in a Rust project whose CI gates on clippy.
---

# clippy-check — the clippy gate as a readable report

Runs the standard workspace gate — `cargo clippy --all-targets -- -D warnings` — and renders each diagnostic once (deduplicated across lib/bin/test targets) with a workspace-relative `file:line` link, the offending source line, and clippy's first `help:` suggestion.

## How to run

From the **workspace root** (links come out workspace-relative, which is what makes them clickable in IDE contexts):

```bash
python3 ~/.claude/skills/clippy-check/clippy_report.py [extra cargo args]
```

- No args → whole workspace.
- Scope to a crate: `python3 ~/.claude/skills/clippy-check/clippy_report.py -p some-crate`.
- Any args are passed to `cargo clippy` before the `--`; the `-D warnings` gate is always applied.

Exit code 0 = clean, 1 = issues found. A non-zero cargo exit with no parsed diagnostics (broken build, missing Cargo.toml) appends cargo's stderr tail to the report.

## How to present the result

- The script's stdout **is** the report — already markdown with links. Relay it to the user as-is (do not re-run clippy separately, do not reformat the links).
- If the session's display context requires a different link style than `[file.rs:12](path/to/file.rs#L12)`, rewrite only the link syntax, never the content.
- When the report is clean, say so in one line; don't pad it.

## Fallback

If the script is missing on this machine (skill not installed via the dev-environment repo), run `cargo clippy --all-targets -- -D warnings` directly and hand-format the same shape: one bullet per unique diagnostic — level icon, **lint name**, `file:line` link, message, offending line, first help suggestion — grouped under per-file headings, deduplicated across targets.
