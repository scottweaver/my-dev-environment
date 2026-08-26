---
name: daily-stand-up
description: Generates a YTB (Yesterday / Today / Blockers) daily stand-up status update by reading project bindings from `.claude/rules/PROJECT.md`, autodiscovering tickets from the configured tracker (Linear or GitHub), walking through commentary, copying the result to the clipboard, and (when `standup.email_to` is bound) offering to email it. Triggers on phrases like "create my status update", "daily stand-up", "standup", "YTB", "what's my status", or "scrum update".
---

# Daily stand-up

Builds a YTB-formatted status update the user can paste into stand-up. Reads tracker + project bindings from `.claude/rules/PROJECT.md`, autodiscovers tickets, walks the user through commentary, prompts for blockers, then emits the final block.

## Workflow

Follow these steps in order. Wait for each reply before moving on — don't batch the prompts.

### 0. Read project bindings

Look for `.claude/rules/PROJECT.md` in the current project. Required YAML-frontmatter fields:

- `tracker`: `linear`, `github`, or `none`
- **If Linear**: `linear.workspace`, `linear.team_prefix`, `linear.assignee_id`
- **If GitHub**: `github.owner`, `github.repo`, `github.assignee`
- **If none**: no tracker bindings — steps 2 and 3 use their no-tracker branches
- `state_file.path` and `state_file.next_up_patterns`
- `standup.no_blockers_sentinel`

Optional fields:

- `standup.email_to` — when present, step 6 offers email delivery to
  this address. Absent → step 6 is skipped silently.

**If PROJECT.md is missing**, defer to the `bootstrap-project` skill — read `~/.claude/skills/bootstrap-project/SKILL.md` and run its create-mode walkthrough. After PROJECT.md is written, resume this skill from step 1.

`bootstrap-project` is the single source of truth for the PROJECT.md schema, template, and the interactive Linear/GitHub bootstrap walkthrough. Don't re-derive any of that here.

### 1. Compute the "yesterday" window

"Yesterday" = the last working day (Mon stand-up → Friday's work). Concretely:

- Tue–Fri stand-up: yesterday = previous calendar day at 00:00 local time.
- Mon stand-up: yesterday = the previous Friday at 00:00 local time.
- Sat/Sun stand-up: yesterday = the previous Friday at 00:00 local time.

Convert to UTC ISO-8601 (`YYYY-MM-DDTHH:MM:SSZ`).

### 2. Discover Y tickets

Branch on `tracker`.

#### Linear branch

Query Linear for issues assigned to `linear.assignee_id` that **transitioned** into `In Progress`, `In Review`, or `Done` inside the window. Use `LINEAR_API_KEY` from env — load per-machine secrets first (`for f in ~/.secrets/*; do [ -f "$f" ] && . "$f"; done`; never read or print those files); if the key isn't set after loading, stop and tell the user.

**Network heads-up:** `api.linear.app` is not in the default shell sandbox allowlist. The first `curl` of a session needs elevated network permissions; request them up front rather than retrying on a `403 CONNECT tunnel` error.

The query asks for issue `history` so we can filter on *state-change events* inside the window — not just any field update (the issue's `updatedAt` bumps for comments, labels, cycle moves, auto-merge metadata, etc., which produces false positives).

```bash
for f in ~/.secrets/*; do [ -f "$f" ] && . "$f"; done
SINCE="<UTC ISO start of last working day>"
ASSIGNEE="<linear.assignee_id from PROJECT.md>"

QUERY='query($since: DateTimeOrDuration!, $assignee: ID!) {
  issues(filter: {
    assignee: { id: { eq: $assignee } }
    updatedAt: { gte: $since }
  }) {
    nodes {
      identifier
      title
      description
      state { name }
      history(first: 20) {
        nodes { createdAt toState { name } }
      }
    }
  }
}'

curl -sS https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" -H "Content-Type: application/json" \
  -d "$(jq -n --arg q "$QUERY" --arg s "$SINCE" --arg a "$ASSIGNEE" \
        '{query:$q, variables:{since:$s, assignee:$a}}')" | jq .
```

Post-filter the result set: **keep an issue iff at least one `history.nodes[]` entry has `createdAt >= $since` AND `toState.name` ∈ {`In Progress`, `In Review`, `Done`}**. Drop everything else (housekeeping updates — labels, comments, slug regenerations).

**Do not use any `url` field Linear returns** — it embeds a title slug that breaks the format rule below. Construct URLs from the identifier directly: `https://linear.app/<workspace>/issue/<identifier>`.

#### GitHub branch

Query GitHub for issues assigned to `github.assignee` that closed inside the window. Use the `gh` CLI:

```bash
SINCE="<UTC ISO start of last working day, YYYY-MM-DD form is fine>"
ASSIGNEE="<github.assignee from PROJECT.md>"
OWNER="<github.owner>"
REPO="<github.repo>"

gh issue list \
  --repo "$OWNER/$REPO" \
  --assignee "$ASSIGNEE" \
  --state closed \
  --search "closed:>=$SINCE" \
  --json number,title,body,state,closedAt
```

Every returned issue counts as Y — `gh issue list` already filters to closed-in-window-and-assigned. Construct URLs from owner/repo/number directly: `https://github.com/<owner>/<repo>/issues/<number>`.

#### No-tracker branch (`tracker: none`)

Nothing to query. Draft Y candidates from what's observable locally: `git log --since="<window start>" --oneline` when the project is a git repo, plus the recent-progress section of the state file (when `state_file.path` is bound). Present the draft and let the user edit, add, or remove — with no tracker, the user is the source of truth for Y. Items are plain bullets (no identifier, no link); each still gets a goal summary per step 3.5.

### 3. Discover T tickets

Read the file at `state_file.path`. Search for each pattern in `state_file.next_up_patterns`, substituting `{ID}` with the tracker-appropriate identifier shape:

- Linear: `<team_prefix>-\d+` (e.g., `OSS-385`)
- GitHub: `#\d+` (e.g., `#42`)
- None: free text to the end of the line — the task name itself

Pull the next-up ticket(s) from the first matching pattern. Usually one ticket; occasionally more.

Fetch each T ticket's title and description from the tracker (Linear: query by identifier; GitHub: `gh issue view <number> --json title,body`) — the goal summaries in the next step need them. With `tracker: none` there is nothing to fetch — the matched state-file line plus its surrounding context stands in for the description.

If a ticket appears in both Y (state moved inside the window) AND is still the current focus (in-progress), put it under T — Y is for past activity, T is for what's actively being worked.

### 3.5 Generate goal summaries and section themes

Two generated layers ride on the discovered tickets — both drafted here, both user-editable in the walkthrough:

- **Per-ticket goal summary.** For every ticket in Y and T, distill the ticket's *goal* from its title + description into one clause, ≤ 12 words, plain language a non-engineer skims in a second. State the outcome the ticket exists for, not the mechanism ("split storage so clients sync only subscribed channels", not "introduce PartitionId newtype and per-doc export"). No ticket-ese, no acronym soup, no trailing period. It renders after the ticket link, joined by a plain ASCII hyphen (` - `) — never an em/en dash, which render corrupted in the user's Slack.
- **Per-section theme.** For Y and for T separately, one `Theme:` line naming the through-line across that section's tickets in ≤ 15 words — the "what is this stretch of work about" a reader takes away without opening anything. Draw on the tickets' summaries plus the state file's workstream context. With a single ticket in the section, the theme still earns its place only when it adds altitude (the parent arc, the milestone it serves); if it would just restate the one ticket's summary, omit it.

### 4. Walk through the draft

Present the discovered tickets and walk this exact order. Wait for each reply. Each draft list is shown **with its goal summaries and theme line already in place** — a correction to a summary or theme in any reply replaces the draft text; commentary lines are additive.

1. Show the draft Y list (links + goal summaries + theme). Ask: *"Any additional Y commentary?"* Skip if reply is negative; otherwise add each line in the reply as a bulleted item under Y.
2. Show the draft T list (links + goal summaries + theme). Ask: *"Any additional T commentary?"* Skip if reply is negative; otherwise add each line as a bulleted item under T.
3. Ask: *"Any blockers?"* If reply is negative, the B line uses `standup.no_blockers_sentinel` from PROJECT.md verbatim.

### 5. Emit the final formatted block

Print the block in chat AND copy the text to the macOS clipboard via `pbcopy`. Pipe the heredoc straight into `pbcopy` — don't write to a tmp file.

**Paste-guard — required.** Many stand-up paste targets (Slack, Teams, Google Chat and other rich editors) silently swallow the *first* pasted line. To survive that, the clipboard payload gets **one sacrificial leading blank line** before `Y:`. The blank line is what the target eats; `Y:` arrives intact. Note the blank line on the first line of the heredoc below:

```bash
pbcopy <<'EOF'

Y:
- [<IDENT>](<URL>) - <goal summary>
- {additional Y commentary lines, if any}
- Theme: {Y theme line, when present}
T:
- [<IDENT>](<URL>) - <goal summary>
- {additional T commentary lines, if any}
- Theme: {T theme line, when present}
B: {blocker text, or the configured sentinel if none}
EOF
```

After `pbcopy` succeeds, print the block in chat inside a fenced code block — **without** the leading blank line, so the user sees the clean YTB output. Confirm with a short line like *"Copied to clipboard (with a leading blank line so the first line survives pasting)."*

### 6. Offer email delivery (only when `standup.email_to` is bound)

Skip this step silently when PROJECT.md has no `standup.email_to`.
When it's bound, ask: *"Email this YTB to `<standup.email_to>`?"* and
wait for the reply. On a negative reply, stop — the clipboard copy is
the deliverable.

On yes, derive the **email variant** of the block (see Format rules —
email variant) and hand it to the default mail client as a prefilled
compose window via a `mailto:` URL — the user reviews and presses
Send, keeping the actual send a human act:

```bash
python3 - <<'PYEOF'
import subprocess, urllib.parse
body = """<email-variant YTB block>"""
url = "mailto:<standup.email_to>?" + urllib.parse.urlencode(
    {"subject": "YTB stand-up - <YYYY-MM-DD>", "body": body},
    quote_via=urllib.parse.quote)
subprocess.run(["open", url], check=True)
PYEOF
```

Then confirm: *"Compose window opened — review and hit Send."*

**Why mailto, not direct send:** on current macOS, Mail.app's
AppleScript surface no longer accepts `make new outgoing message`
(error -2710), so scripted silent sending via Mail is off the table.
If a Gmail/Outlook send tool is connected in the session (check
ToolSearch for an email send tool before falling back), prefer it —
send directly with the same subject/body and confirm with the message
id — and note the mailto path remains the offline fallback.

## Format rules

- **Linear identifier**: uppercase `<TEAM_PREFIX>-NNN`. Lowercase commonly breaks GitHub→Linear auto-flip integrations and is the wrong canonical form regardless.
- **GitHub identifier**: `#NNN` (same-repo).
- **No-tracker items** (`tracker: none`): plain bullets — no bracketed identifier, no URL. `- <goal summary>`, optionally prefixed by a short task name and a spaced ASCII hyphen. Every other rule (goal summaries, themes, ASCII dashes, sentinel) applies unchanged.
- **URL**: canonical short form. Linear: `https://linear.app/<workspace>/issue/<identifier>` (no trailing slug — strip any slug the API returns). GitHub: `https://github.com/<owner>/<repo>/issues/<number>`.
- **Bracketed link label**: identifier only — no title, no status suffix. The goal summary lives *outside* the brackets, joined by a spaced ASCII hyphen: `- [OSS-385](url) - split storage so clients sync only subscribed channels`.
- **Goal summary**: ≤ 12 words, outcome-focused, plain language, no trailing period. Every ticket line in Y and T carries one.
- **ASCII dashes only, everywhere in the block**: no em/en dashes (`—`/`–`) in summaries, themes, or commentary — they render corrupted in the user's Slack. Use `-`, `:`, `;`, or a comma instead.
- **Theme line**: `- Theme: <text>` as the **last** bullet of its section (after any commentary), ≤ 15 words, at most one per section, omitted when it would only restate a lone ticket's summary.
- **No-blockers sentinel**: emit `standup.no_blockers_sentinel` verbatim (no colons stripped, no substitution, no quote-wrapping).
- **Clipboard and chat block match byte-for-byte except for the paste-guard** — no quoting, escaping, or surrounding prose to either copy. The *only* permitted difference is the single sacrificial leading blank line in the clipboard payload (see step 5); the chat block omits it.

### Email variant (step 6 only)

The email body is the same block with exactly three transformations —
email clients don't render markdown or Slack emoji, and a raw
markdown link reads as noise in plain text:

- **Links flatten**: `- [IDENT](url) - summary` becomes
  `- IDENT (url) - summary`.
- **Slack-only sentinel flattens**: when `no_blockers_sentinel` is a
  Slack emoji code (`:something:`), the email's B line is `B: none`
  instead. A plain-text sentinel passes through verbatim.
- **No paste-guard**: the email body starts directly at `Y:` — the
  sacrificial blank line is a rich-editor workaround, not part of the
  content.

Subject: `YTB stand-up - <YYYY-MM-DD>` (stand-up date, ASCII hyphen).
Everything else — ordering, commentary, themes, ASCII-dashes-only —
carries over unchanged.

## Example — Linear-configured project

Tuesday stand-up after OSS-384 transitioned to Done Monday and OSS-385 is the named next-up ticket:

```
Y:
- [OSS-384](https://linear.app/kunai/issue/OSS-384) - land the tag hierarchy behind the storage boundary
- Refreshed STATE.md after the merge
- Theme: finishing the data-model substrate the MVP features build on
T:
- [OSS-385](https://linear.app/kunai/issue/OSS-385) - split storage so clients sync only subscribed channels
B: :none_nun:
```

(T has one ticket and its summary already says what the day is about, so no T theme line.)

## Example — GitHub-configured project

Tuesday stand-up after issue #42 closed Monday and #45 is the named next-up ticket:

```
Y:
- [#42](https://github.com/owner/repo/issues/42) - stop the importer double-counting retried uploads
T:
- [#45](https://github.com/owner/repo/issues/45) - let users export their history as CSV
B: none
```

## See also

- `~/.claude/skills/bootstrap-project/SKILL.md` — owns the PROJECT.md schema, template, and interactive bootstrap walkthrough. Invoked automatically when PROJECT.md is missing; also directly invokable for new projects or to edit existing bindings.
- `~/.claude/skills/wrap-up/SKILL.md` — companion post-merge skill consuming the same PROJECT.md.
