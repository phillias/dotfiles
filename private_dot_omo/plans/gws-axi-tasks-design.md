# gws-axi Tasks — Implementation Plan

## Overview

Add Google Tasks (`tasks.googleapis.com`) as the 7th service in `gws-axi`. The design spec below is **frozen** — ready for implementation when scheduled. Converted from `~/.agents/skills/gws-axi/TASKS-DESIGN.md` into a tracked plan.

- Status: **spec frozen** — ready for implementation when scheduled
- Scope: add Google Tasks (`tasks.googleapis.com`) as the 7th service in `gws-axi`
- Source repo: `github.com/JarvusInnovations/gws-axi` (MIT, TypeScript, published to npm as `gws-axi`)
- Skill doc: `~/.agents/skills/gws-axi/SKILL.md` (chezmoi-synced from `~/.local/share/chezmoi/dot_agents/skills/gws-axi/SKILL.md`)
- Target runtime: hermes agent server (separate host from the dev box)

## Context

`gws-axi` is an agent-ergonomic CLI for Google Workspace, built to the AXI standard: TOON-formatted output (~40% fewer tokens than JSON), contextual next-step suggestions, idempotent mutations, multi-account write-protection. Today it covers six services (Gmail, Calendar, Docs, Drive, Slides, Sheets). Google Tasks is the natural 7th — same OAuth model, same `googleapis` Node client, lower API surface complexity than any existing service.

The actual `gws-axi` binary is a compiled TypeScript package installed globally via npm. The skill file under `~/.agents/skills/gws-axi/SKILL.md` is **documentation only** — it describes the installed binary's surface to agents. Adding Tasks means changing the source repo and shipping a new binary; the SKILL.md update lands last, only after the new binary is live on the runtime host.

**No `gcloud` alternative exists.** `gcloud tasks` (where it exists) refers to Cloud Tasks, GCP's async work-queue product — an entirely different service. Consumer Google Tasks (the to-do lists in Gmail's sidebar) is reachable only via the REST API at `tasks.googleapis.com` or the `googleapis` Node client. `gws-axi` already uses `googleapis`, so a `tasksClient(email)` is a one-liner mirror of `slidesClient` / `sheetsClient`. The agent-token-efficiency goal of AXI is preserved: `gws-axi tasks list` runs as a host Node process; the model only sees the TOON output.

## Decisions (frozen)

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Write surface scope | Ship list/get/lists + create/update/delete + complete/uncomplete + list-create as ✅. Defer `clear`, `move`, `list-update`, `list-delete` as 🚧 NOT_IMPLEMENTED | Tasks CRUD is simple. Defer only the bulk-destructive (`clear`) and reorder-semantics (`move`) ops, plus destructive list-management — match the existing per-service write-rollout cadence |
| 2 | Default `tasks list` view | Bare `tasks list` shows task-lists table; `tasks list --list <name\|id>` narrows to one list's tasks | Tasks has no API-surfaced "primary" list. Showing lists first is content-dense and lets the agent pick |
| 3 | Subtask + completed behavior | Open tasks only by default; flat minimal table (no indentation, no parent column); `--include-completed` flag only | Subtasks are rare in practice. Flat table is most token-efficient; `tasks get` surfaces `parent` in the detail block when needed |
| 4 | Calendar enrichment | `--with-calendar` flag on `tasks list`; primary calendar by default, `--calendars primary,work@x.com` to extend; emits a `calendar_overlap[K]{...}` block | First cross-service flag in gws-axi. Read-only enrichment, no new mutation surface |
| 5 | Due date format | `--due YYYY-MM-DD` date-only; reject datetimes with VALIDATION_ERROR pointing at the format | Tasks API `due` field is date-only. Inheriting ISO datetime shape would mislead users into thinking time matters |
| 6 | Complete action shape | `tasks complete <id>` and `tasks uncomplete <id>` verbs (aliases) **plus** `tasks update <id> --status completed\|needsAction` canonical | Verb form is ~4 tokens shorter and maps 1:1 to natural-language agent prompts — reduces LLM mis-translation risk |
| 7 | Task-list management | Ship `tasks lists` (read) + `tasks list-create --title <text>` (non-destructive). Defer `list-update` / `list-delete` | Matches the "read-first for the long tail" pattern. List-create covers the plausible agent use case (scaffold a project's task list); destructive ops can wait |
| 8 | Task identification | Full IDs returned by `list`; no fuzzy lookup, no slug | Parity with `calendar get <event-id>` / `gmail read <thread-id>`. IDs are transient tokens the agent pipes forward, not memorized |
| 9 | Pagination | Single fetch `maxResults=100`; surface `next_page` field + suggest `--page <token>` if truncated (gmail-search pattern) | Matches `gmail search`. Most lists have <100 tasks; power users get a clean continuation cue |
| 10 | Output shape | Minimal TOON table per `calendar events` precedent | Highest-traffic read; shape sets the agent's mental model of task state |
| 11 | Subtask column | All tasks flat, **no parent_id column**; parent surfacing only in `tasks get <id>` detail block | Subtasks rare per interview; relationship recoverable via `get` when it matters. Saves tokens in the common case |
| 12 | Distribution | Public GitHub fork + tarball-URL install on hermes server | Free GitHub tier suffices (upstream is MIT and public). One fork doubles as upstream-PR source. Tarball URL form is npm-native and needs no `git` in PATH on hermes |
| 13 | Auth scope | Add `tasks` to `SERVICE_SCOPES` + `tasks.googleapis.com` to `REQUIRED_APIS` (Sensitive tier) | Matches how `sheets` was added. Existing accounts re-auth once via existing SCOPE_MISSING error path — no new mechanism needed |

## API reference (Google Tasks v1)

Endpoint: `https://tasks.googleapis.com/tasks/v1/`
Scope (read+write): `https://www.googleapis.com/auth/tasks`
Scope (read-only, **not used here**): `https://www.googleapis.com/auth/tasks.readonly`
Classification: **Sensitive** (per Google's OAuth verification tiers — same tier as Calendar, lighter than Gmail/Drive which are Restricted)

Resources:
- `tasklists` — collection of task-lists (`My Tasks`, `Work`, `Groceries`, etc.)
  - `list` — `GET /users/@me/lists` — `maxResults` (default 20, max 100), `pageToken`
  - `get` — `GET /users/@me/lists/{tasklist}`
  - `insert` — `POST /users/@me/lists` — body: `{title}`
  - `update` — `PUT /users/@me/lists/{tasklist}` — body: `{title}`
  - `delete` — `DELETE /users/@me/lists/{tasklist}` (recursively destroys all tasks in the list)
- `tasks` — collection of tasks within a task-list
  - `list` — `GET /lists/{tasklist}/tasks` — params: `showCompleted` (default true), `showDeleted` (default false), `showHidden` (default false), `showAssigned` (default false), `completedMax/Min`, `dueMax/Min`, `updatedMin`, `maxResults` (default 20, max 100), `pageToken`. Returns a flat `items[]`; subtask relationships live in each item's `parent` field
  - `get` — `GET /lists/{tasklist}/tasks/{task}`
  - `insert` — `POST /lists/{tasklist}/tasks` — body: `{title, notes, due, status, parent (for subtasks)}`
  - `update` — `PUT /lists/{tasklist}/tasks/{task}` — body: any subset of `{title, notes, due, status, parent}`
  - `delete` — `DELETE /lists/{tasklist}/tasks/{task}`
  - `clear` — `POST /lists/{tasklist}/clear` — marks all completed tasks as hidden (bulk, not undoable via API)
  - `move` — `POST /lists/{tasklist}/tasks/{task}/move` — params: `parent`, `previous` — reorder/reparent

Limits (per Google's docs):
- 20,000 non-hidden tasks per list
- 100,000 tasks in total per user
- `maxResults` capped at 100 on both `tasklists.list` and `tasks.list`

**Every task mutation requires a `tasklist` path param** — there is no account-wide "modify task X" operation. This is why `--list <id>` is required on every per-task mutation, not optional.

## Command surface

```
tasks lists                                       # list task-lists
tasks list                                        # alias for above (bare call)
tasks list --list <name|id>                       # tasks within one list
tasks list --list <id> --include-completed
tasks list --list <id> --with-calendar
tasks list --list <id> --with-calendar --calendars primary,work@x.com
tasks list --list <id> --page <token>
tasks get --list <id> <task-id>                   # single task detail (incl. parent field)

tasks create --list <id> --title <text>           # new task
tasks create --list <id> --title <text> --notes <text>
tasks create --list <id> --title <text> --due 2026-04-22
tasks create --list <id> --title <text> --parent <task-id>   # subtask

tasks update --list <id> <task-id> --title <text>
tasks update --list <id> <task-id> --due 2026-04-22
tasks update --list <id> <task-id> --status completed|needsAction
tasks complete --list <id> <task-id>              # alias for update --status completed
tasks uncomplete --list <id> <task-id>            # alias for update --status needsAction

tasks list-create --title <text>                  # create a new task-list
tasks delete --list <id> <task-id>                # idempotent (404/410 → noop)

# Scaffolded as 🚧 NOT_IMPLEMENTED:
tasks clear --list <id>                           # bulk: complete → hidden
tasks move --list <id> <task-id>                  # reorder/reparent
tasks list-update <list-id> --title <text>
tasks list-delete <list-id>                       # recursively destructive
```

**All write operations require `--account <email>` when 2+ accounts are authenticated.** (Standard gws-axi invariant — handled by the dispatcher's `resolveAccount`, no per-command code needed.)

**`--list <id>` is required on every per-task operation**, because the Tasks API path itself requires a `tasklist` segment. The CLI should accept either a list ID or a list title (matched against a short `tasklists.list` call for title→ID resolution — but see decision 8: full IDs only, title matching is *not* in scope for v1, so keep this strict: IDs only, title-match returns VALIDATION_ERROR pointing at `tasks lists` for the ID).

### Sample TOON output — `tasks list --list <list-id>`

```
account: chris@jarv.us
task_list: Work
count: 3
tasks[3]{id,title,due,status}:
  dGFTN3lYa0E0Y3JvVEdGA,Submit Q2 report,2026-04-22,needsAction
  aHJza2plN3p0d2xQR1ZQ,Review PR #847,2026-04-23,needsAction
  bklMNGpIRXNwbXB0ZU5z,Pick milk on way home,,needsAction
help[2]:
  Run `gws-axi tasks get --list <list-id> <task-id>` for full task details
  Run `gws-axi tasks complete --list <list-id> <task-id>` to mark a task done
```

### Sample TOON output — `tasks list --list <id> --with-calendar` (overlap block)

```
account: chris@jarv.us
task_list: Work
count: 3
tasks[3]{id,title,due,status}:
  ...
calendar_overlap[1]{task,event,start,end}:
  dGFTN3lYa0E0Y3JvVEdGA,Team sync,2026-04-22T14:00:00,2026-04-22T15:00:00
help[1]:
  Run `gws-axi calendar get <event-id>` for the conflicting event details
```

## Implementation work breakdown

For each touchpoint: file path (relative to repo root), what changes, parities to match.

### A. `src/auth/scopes.js`

Changes:
- Add `tasks: "https://www.googleapis.com/auth/tasks"` to `SERVICE_SCOPES`
- Add `tasks: "tasks.googleapis.com"` to `REQUIRED_APIS`
- Add `"tasks"` to the `SERVICES` array

No entry in `ADDITIONAL_SCOPE_INFO` — Tasks has no extra capabilities beyond the base scope.

### B. `src/google/client.js`

Add one function, mirroring `slidesClient` / `sheetsClient`:

```ts
export async function tasksClient(email) {
  const auth = await oauthClientForAccount(email);
  return google.tasks({ version: "v1", auth });
}
```

No changes to `translateGoogleError` or `runGoogleApi` — they're service-agnostic.

### C. `src/google/probe.js`

Add `probeTasks(ctx)`:

```ts
async function probeTasks(ctx) {
  const service = "tasks";
  if (!hasScope(ctx.tokens, SERVICE_SCOPES.tasks)) {
    return { service, status: "fail", detail: "scope not granted" };
  }
  // tasklists.list is a cheap direct probe — unlike docs/slides/sheets which
  // rely on the drive probe as a proxy. Returns total task-list count.
  const { status, body } = await gfetch(
    "https://tasks.googleapis.com/tasks/v1/users/@me/lists?maxResults=1&fields=nextPageToken",
    ctx.accessToken,
  );
  if (status === 200) {
    // If nextPageToken is present, there are more than 1 page (>20 lists);
    // otherwise we know the exact count would need a follow-up call.
    // Cheapest honest report: "≥1 task list" for now, refine only if needed.
    return { service, status: "ok", detail: "task lists accessible" };
  }
  return classifyError(service, status, body);
}
```

Wire `probeTasks(ctx)` into the `Promise.all` parallel batch in `probeAccount(email)` (alongside gmail/calendar/drive) — Tasks does not depend on the drive probe, unlike docs/slides/sheets.

Append `"tasks"` to the failure-mode services array in `probeAccount`'s catch block (the line listing `["gmail", "calendar", "docs", "drive", "slides", "sheets"]`).

### D. `src/commands/tasks.js` + `src/commands/tasks/` directory

Top-level dispatcher (`src/commands/tasks.js`) mirrors `src/commands/slides.js` exactly:
- Import each subcommand handler + HELP constant
- Define `SUBCOMMANDS` array with `{ name, mutation, help, handler }` entries
- `parseAccountFlag` helper (copy verbatim from slides.js)
- `tasksCommand(args)` exports: help / route / NOT_IMPLEMENTED for scaffolded commands

Subcommand files, each mirroring its slides/`calendar equivalent:

| File | Parity | Notes |
|---|---|---|
| `tasks/lists.js` | `calendar/calendars.js` (read pattern) | Emits `task_lists[N]{id,title,updated}`. This is the bare `tasks list` view |
| `tasks/list.js` | `gmail/search.js` (pagination pattern) | Requires `--list <id>`. Emits `tasks[N]{id,title,due,status}` table. Optional `--include-completed`, `--with-calendar` (+ `--calendars`), `--page <token>` |
| `tasks/get.js` | `slides/get.js` (single-resource detail) | Requires `--list <id> <task-id>`. Detail block includes `parent` (when set), `notes`, `due`, `status`, `links` (when title/selfLink present) |
| `tasks/create.js` | `calendar/create.js` (write pattern) | Requires `--list <id> --title <text>`. Optional `--notes`, `--due YYYY-MM-DD` (date-only validator), `--parent <task-id>` (subtask) |
| `tasks/update.js` | `calendar/update.js` | Requires `--list <id> <task-id>`. Accepts `--title`, `--notes`, `--due`, `--status completed\|needsAction`. Rejects `--status` values outside those two with VALIDATION_ERROR |
| `tasks/complete.js` + `tasks/uncomplete.js` | `calendar/respond.js` (alias-over-update pattern) | Thin wrappers that call `tasksUpdateCommand` with status pre-set. Same return shape |
| `tasks/delete.js` | `calendar/delete.js` (idempotent) | 404/410 → noop. Returns `deleted: <id>` on success, `not_found: <id> (already gone)` on noop |
| `tasks/list-create.js` | `gmail/label-create.js` (non-destructive create) | Requires `--title <text>`. Returns the new list's `{id, title}` |
| `tasks/clear.js` | — | HELP text only, no handler. `NOT_IMPLEMENTED` with planned surface |
| `tasks/move.js` | — | HELP text only, no handler. `NOT_IMPLEMENTED` with planned surface (reorder/reparent) |
| `tasks/list-update.js` | — | HELP text only. `NOT_IMPLEMENTED` |
| `tasks/list-delete.js` | — | HELP text only. `NOT_IMPLEMENTED` (recursively destructive) |

### E. `src/cli.js`

- Import `tasksCommand` from `./commands/tasks.js`
- Add `tasks: tasksCommand` to the `commands` map in `main()`
- Bump `commands[10]` → `commands[11]` in `TOP_HELP`
- Update `DESCRIPTION` string: append `, and Tasks` (or rephrase to include Tasks)

### F. `SKILL.md` (`~/.agents/skills/gws-axi/SKILL.md`)

**Update only after the new binary is live on hermes** — never before. Agents reading SKILL.md must never see commands their binary doesn't have.

Changes:
1. Frontmatter `description`: add `, Google Tasks` to the list of services; add `google tasks` to the trigger phrases
2. Quick Reference block: insert after the Sheets section
   ```
   # Tasks
   gws-axi tasks lists                         # list task-lists
   gws-axi tasks list --list <id>              # list tasks in a task-list
   gws-axi tasks list --list <id> --with-calendar   # show calendar conflicts
   gws-axi tasks complete --list <id> <task-id>     # mark task done
   ```
3. Service Coverage table: insert row
   ```
   | **Tasks** | ✅ list · get · lists · complete · uncomplete | ✅ create · update · delete · list-create &nbsp;·&nbsp; 🚧 clear · list-update · list-delete · move |
   ```
4. Add a new "When to Use" trigger phrase: `User asks to manage a to-do list, complete a task, or check what tasks are due`

After editing the local copy, run `chezmoi re-add ~/.agents/skills/gws-axi/SKILL.md` so the chezmoi source updates and `chezmoi apply` syncs it to other machines.

### G. `README.md` (in fork source, then upstream PR)

Mirror SKILL.md changes in the README's coverage table and status section. Add a `### Tasks` usage section between `### Sheets` and `### Multi-account with write protection`, documenting the full command surface. Add to "Known issues & roadmap": defer `clear` / `move`, plus a callout about subtask rarity and the `tasks get` path for parent detail.

### H. chezmoi source sync

`~/.local/share/chezmoi/dot_agents/skills/gws-axi/SKILL.md` is the chezmoi-managed source of the SKILL.md file. After editing the working copy, run `chezmoi re-add` to refresh the source, then `chezmoi apply` on any other machines to propagate.

## Distribution strategy

### Dev box (your machine)

1. `gh repo fork JarvusInnovations/gws-axi --clone` → fork appears at `github.com/<you>/gws-axi` with your work in `~/projects/gws-axi` (or wherever `gh repo fork --clone` lands it)
2. `git switch -c feat/tasks` from the upstream `main`
3. Implement across all touchpoints (see implementation work breakdown)
4. `npm run build && npm test` — must pass; `npm link` locally to dogfood
5. Commit, push to your fork's `feat/tasks` branch
6. `gh pr create --repo JarvusInnovations/gws-axi --base main --head <you>:feat/tasks` for the upstream PR
7. Cut a GitHub Release **on your fork** tagged `v0.17.0-tasks` (or whatever version bump is appropriate) — attach `npm pack` tarball as a release asset, OR rely on the automatic tarball URL form GitHub exposes for any branch/tag

### Hermes server (runtime host — separate machine)

Install via the npm-native tarball URL form — **no `git` in PATH required**, no `gh` required:

```bash
# From a branch:
npm install -g https://github.com/<you>/gws-axi/tarball/feat-tasks

# Or from a tag (preferred for reproducibility):
npm install -g https://github.com/<you>/gws-axi/tarball/v0.17.0-tasks
```

This requires the fork to be **public** (upstream `gws-axi` is MIT and public, so a public fork is the natural posture — no private-registry overhead). No npm publish, no GitHub Package Registry, no auth on the consumer side.

**Switch back to upstream once merged:** when JarvusInnovations merges the PR and publishes a new `gws-axi` to npm, run `npm install -g gws-axi@latest` on hermes. The branch-tarball pin in package-lock (if you've pinned it there) gets replaced by the registry semver. The fork stays alive as the PR source.

### Why NOT `npm install -g github:<you>/gws-axi#feat-tasks`

That form requires `git` in PATH on hermes (npm shells out to `git ls-remote` and friends — not reimplemented in pure JS per npm's own docs and the long-standing issue `npm/npm#10894`). The tarball URL form is pure HTTPS fetch and works without git.

### Pinning in hermes's own package-lock

If hermes pins `gws-axi` somewhere, the lockfile entry for the tarball-URL form looks like:
```json
"gws-axi": "https://github.com/<you>/gws-axi/tarball/v0.17.0-tasks"
```
Or, if installed globally without a project lockfile, just the direct `npm install -g` invocation is the pin. Either is valid; prefer the tag-pinned form for reproducibility.

## Auth posture + re-auth nudge

The `tasks` scope is classified **Sensitive** by Google — same tier as `calendar`, lighter than `gmail.modify` and `drive` (both Restricted). Practical consequences:

1. **Existing authenticated accounts** must re-run `gws-axi auth login --account <email>` **once** to consent to the new scope. First `tasks` call without re-auth → `SCOPE_MISSING` (403). The existing `translateGoogleError` path already emits the right suggestion ("Run `gws-axi auth login --account <email>` to re-consent"). No new error-handling code needed.

2. **`auth setup` walkthrough** must add Tasks API enablement. Adding `tasks.googleapis.com` to `REQUIRED_APIS` makes the existing walkthrough auto-pick it up — the walkthrough reads from that table. No new setup-step code.

3. **OAuth consent screen**'s scopes page in GCP Console will show one more Sensitive scope. No verification submission needed (only Restricted scopes trigger verification requirement).

4. **SKILL.md + README** must include a callout matching the existing sheets scope note:
   > The `tasks` scope means existing accounts must `gws-axi auth login --account <email>` once.

## Open questions (deferred to implementation time)

These are tactical details the implementer should resolve while writing code — not blocking the spec:

- **Calendar overlap window semantics.** `--with-calendar` fetches `calendar.events.list` for the [min_due, max_due] span across the listed tasks. If a task has no `due`, it's excluded from overlap consideration. Implementer decides: one fetch for the union span (cheap, may surface non-conflicting events) vs per-task fetch (precise, N calls). Recommend union span with a per-task filter post-fetch.

- **Validation error code for datetime in `--due`.** Align with whatever `calendar create`'s pattern uses for invalid `--start` formats. Likely `VALIDATION_ERROR` with suggestions pointing at `YYYY-MM-DD`.

- **Help text wording for `--with-calendar`.** Needs to make clear this is a read-only enrichment flag, not a mutation, and that it adds one extra Calendar API call per invocation.

- **Test coverage.** Mirror the existing `*.test.ts` pattern — one test file per subcommand. Calendar's test file is the closest structural model since it covers read+write.

- **`tasks lists` precedence vs `tasks list`.** The bare `tasks list` command (no args) should produce the same output as `tasks lists`. Either implement `list` as an alias that detects the missing `--list` flag and dispatches to `lists`, or have the dispatcher route `list` with no flags to the `lists` handler. The latter keeps the surface cleaner in `--help`.

- **Versioning of the fork release tag.** Upstream `gws-axi` is at `0.16.2`. A Tasks feature in a fork should not collide with upstream version numbers. Suggest `0.17.0-tasks.1` (prerelease tag) to signal non-final, or `0.0.0-fork.<date>` if you prefer clear non-canonicality. Upstream merge → publish `0.17.0` from the merged PR.

## Non-goals (explicitly out of scope)

- **No `gcloud` shell-out.** Verified: no consumer-Tasks surface in `gcloud`; only Cloud Tasks (work-queue product) lives there. All Tasks access goes through the `googleapis` Node client.
- **No fuzzy task lookup by title.** Full IDs only (decision 8). Title→ID lookup would introduce ambiguity and failure modes the agent doesn't need.
- **No `tasks send` / cross-service writes.** The `--with-calendar` flag is read-only enrichment. No `email-to-task` command in this PR.
- **No `clear` / `move` / `list-update` / `list-delete` implementation.** Scaffolded as `NOT_IMPLEMENTED` with planned surface in their `--help` text (decision 1).
- **No change to existing services' behavior.** Touchpoint A (scopes.js) adds to the scope set; all existing scopes remain in place, so no existing account loses access.
- **No SKILL.md update before the new binary is live.** Agents reading the skill doc must never see commands their installed binary can't run — that's a silent failure mode this spec refuses to introduce.

---

*Plan created: 2026-08-03*
*Last updated: 2026-08-03*
*Converted from: `~/.agents/skills/gws-axi/TASKS-DESIGN.md`*
