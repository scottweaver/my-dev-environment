# Linear ticket management

How to create and manage tickets for this project in Linear. The user
prefers tickets be drafted in chat first, approved, then created via
the GraphQL API.

## Auth

`LINEAR_API_KEY` is exported from a file under `~/.secrets/` (sourced
by the shell). Always run `source ~/.zshrc` before any `curl` to the
Linear API — bash invocations don't inherit the interactive shell.

```bash
source ~/.zshrc
curl -sS https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '...'
```

If the key isn't in env after sourcing, stop and tell the user —
don't try to find it elsewhere or hard-code it.

## Workspace constants

Probed {{DATE}}. Re-probe via API if a request 404s — labels/states
get renamed.

| Thing | Value |
|---|---|
| Workspace | `linear.app/{{WORKSPACE}}` |
| Team **{{TEAM_NAME}}** (`{{TEAM_PREFIX}}`) | `{{TEAM_UUID}}` |
| Project **{{PROJECT_NAME}}** | `{{PROJECT_UUID}}` |
| State **Backlog** | `{{STATE_BACKLOG_UUID}}` |
| State **In Progress** | `{{STATE_IN_PROGRESS_UUID}}` |
| State **In Review** | `{{STATE_IN_REVIEW_UUID}}` |
| State **Done** | `{{STATE_DONE_UUID}}` |
{{LABEL_ROWS}}

Re-probe recipe:

```bash
source ~/.zshrc
curl -sS https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" -H "Content-Type: application/json" \
  -d '{"query":"{ team(id:\"{{TEAM_UUID}}\") { projects { nodes { id name } } states { nodes { id name type } } labels { nodes { id name } } } }"}'
```

## Default conventions

When the user asks for a ticket without specifying labels/state/
project:

- Default project: `{{PROJECT_NAME}}`; default team: `{{TEAM_NAME}}`.
- Tech-debt tickets (refactors, code-smell cleanup, instrumentation):
  set state to `Backlog`{{TECH_DEBT_LABEL_NOTE}}.

If the user specifies different values, follow them.

## Assignment on "In Progress" transitions

When creating a ticket directly in `In Progress`, or moving one
there, run `id -un` first:

- If it returns `{{LOCAL_USERNAME}}`, include
  `assigneeId: {{ASSIGNEE_UUID}}` in the mutation input.
- For any other local user, do NOT auto-assign — leave it unassigned
  and let the human decide.

Other states get no auto-assignment. Don't override an explicit
assignee the user has named.

Rationale: an unassigned `In Progress` ticket is ambiguous about
ownership; the `id -un` check confirms the assistant is running as
the project owner rather than a teammate or CI runner.

## Ticket references in commits and PR titles

Uppercase `{{TEAM_PREFIX}}-123`-style references in PR titles, commit
headers, and PR bodies are the convention — for readability and
grep-ability. Do not assume a GitHub→Linear integration will
auto-transition tickets on merge; verify ticket state manually as
part of the post-merge routine (METHODOLOGIES.md) unless/until an
integration is confirmed installed on this repo. (Hard-won lesson:
three rewrites of a casing rule chasing an auto-flip parser that
turned out not to exist.)

Recommended forms: `feat({{TEAM_PREFIX}}-123): ...` headers;
`Closes {{TEAM_PREFIX}}-123.` or `Refs: {{TEAM_PREFIX}}-123.` in
bodies.

## Workflow

1. **Draft in chat first.** Show full title + description (markdown)
   for every ticket before creating. Include labels, state, project,
   and parent/sub structure if applicable.
2. **Confirm before creating.** Wait for explicit approval. Don't
   bundle creation with the draft message.
3. **Create.** Use the API recipe below. Show the response
   (identifier + URL) for each created issue.
4. **Cleanup.** Remove any temp draft files (`/tmp/linear-issues/*`)
   after success.

## Drafting hints

- For >2 related tickets, propose **parent + sub-issues** structure.
- Titles imperative + scannable ("Surface X", "Audit Y"), not
  declarative ("There is a problem with...").
- Markdown tables for site lists (file + line + function).
- Acceptance criteria as a checkbox list, at least one verifiable
  item per ticket.

## Recipe: create issues with markdown bodies

Markdown often contains characters that break inline JSON escaping.
Always write descriptions to files and use `jq --rawfile` to embed
them safely.

```bash
mkdir -p /tmp/linear-issues
# write descriptions to /tmp/linear-issues/<name>.md per issue

source ~/.zshrc
TEAM={{TEAM_UUID}}
PROJECT={{PROJECT_UUID}}
STATE_BACKLOG={{STATE_BACKLOG_UUID}}

QUERY='mutation IssueCreate($input: IssueCreateInput!){
  issueCreate(input:$input){ success issue{ id identifier title url } }
}'

INPUT=$(jq -n \
  --arg teamId "$TEAM" --arg projectId "$PROJECT" --arg stateId "$STATE_BACKLOG" \
  --arg title "Issue title goes here" \
  --rawfile description /tmp/linear-issues/body.md \
  '{input:{teamId:$teamId, projectId:$projectId, stateId:$stateId,
           title:$title, description:$description}}')

REQ=$(jq -n --arg q "$QUERY" --argjson v "$INPUT" '{query:$q, variables:$v}')

curl -sS https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" -H "Content-Type: application/json" \
  -d "$REQ" | jq .
```

For a **sub-issue**, add `parentId: <parent-uuid>` to the `input`
object, capturing the parent's `id` from its create response first.

Other mutations (`issueUpdate`, `commentCreate`, `issueArchive`/
`issueDelete`) — probe Linear's GraphQL schema docs when first
needed. Archive/delete never run without explicit user approval.

## Don'ts

- Don't create issues silently — always draft + confirm.
- Don't put the API key in committed code, scripts, or temp files.
- Don't archive/delete/close issues without explicit approval.
- Don't paste long descriptions inline into GraphQL JSON — use
  `--rawfile`.
- Don't assume label/state UUIDs are stable indefinitely — re-probe
  on 404.
