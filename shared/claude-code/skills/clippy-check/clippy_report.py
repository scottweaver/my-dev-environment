#!/usr/bin/env python3
"""Report every diagnostic the `cargo clippy --all-targets -- -D warnings`
gate would reject, as markdown with workspace-relative file:line links.

Lints WITHOUT `-D warnings` so no target fails early and every target
gets linted in one pass; the gate semantic lives in the exit code.

Usage: clippy_report.py [extra cargo args, e.g. -p some-crate]
Run from the workspace root so paths come out workspace-relative.
Exits 0 when clean, 1 when any warning or error is reported.
"""

import json
import subprocess
import sys

MAX_SOURCE_LEN = 120


def parse_issues(stdout: str) -> list[dict]:
    issues: dict[tuple, dict] = {}
    for line in stdout.splitlines():
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        if record.get("reason") != "compiler-message":
            continue
        message = record.get("message") or {}
        if message.get("level") not in ("warning", "error"):
            continue
        spans = message.get("spans") or []
        primary = next((s for s in spans if s.get("is_primary")), None)
        if primary is None:
            continue  # skip the "N warnings emitted" summaries
        code = (message.get("code") or {}).get("code") or message["level"]
        key = (code, primary["file_name"], primary["line_start"], message.get("message"))
        if key in issues:
            continue  # same lint reported for lib/bin/test targets
        helps = [
            child.get("message")
            for child in message.get("children", [])
            if child.get("level") == "help" and child.get("message")
        ]
        text = primary.get("text") or []
        source = text[0].get("text", "").strip() if text else ""
        if len(source) > MAX_SOURCE_LEN:
            source = source[: MAX_SOURCE_LEN - 1] + "…"
        issues[key] = {
            "level": message["level"],
            "code": code,
            "file": primary["file_name"],
            "line": primary["line_start"],
            "message": message.get("message", ""),
            "source": source,
            "help": helps[0] if helps else None,
        }
    return sorted(issues.values(), key=lambda i: (i["file"], i["line"], i["code"]))


def render(issues: list[dict]) -> str:
    if not issues:
        return "✅ Clippy clean — `cargo clippy --all-targets -- -D warnings` passes."
    errors = sum(1 for i in issues if i["level"] == "error")
    warnings = len(issues) - errors
    lines = [f"## Clippy: {len(issues)} issue(s) — {errors} error(s), {warnings} warning(s)", ""]
    current_file = None
    for issue in issues:
        if issue["file"] != current_file:
            if current_file is not None:
                lines.append("")
            current_file = issue["file"]
            lines.append(f"### `{current_file}`")
            lines.append("")
        icon = "❌" if issue["level"] == "error" else "⚠️"
        basename = issue["file"].rsplit("/", 1)[-1]
        link = f"[{basename}:{issue['line']}]({issue['file']}#L{issue['line']})"
        lines.append(f"- {icon} **{issue['code']}** {link} — {issue['message']}")
        if issue["source"]:
            lines.append(f"  - `{issue['source']}`")
        if issue["help"]:
            lines.append(f"  - help: {issue['help']}")
    return "\n".join(lines)


def main() -> int:
    cmd = ["cargo", "clippy", "--all-targets", "--message-format=json", *sys.argv[1:]]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    issues = parse_issues(proc.stdout)
    print(render(issues))
    if not issues and proc.returncode != 0:
        print("\n⚠️ cargo exited non-zero without span-bearing diagnostics; stderr tail:")
        print("```")
        print("\n".join(proc.stderr.splitlines()[-15:]))
        print("```")
        return proc.returncode
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
