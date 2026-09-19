---
name: pr-review-loop
description: Loop on a PR, addressing bot review comments (CodeRabbit, Greptile, etc.) until nothing actionable remains, then merge. Drives the pr-ready-check tool for all detection and verdicts. Use when asked to iterate on a PR until bot approval or to merge when all bots are satisfied.
user-invocable: true
---

# pr-review-loop

Iterate a PR through bot review until nothing actionable remains, then merge.

## When to Use

- "Loop on PR#XXX until CodeRabbit approves"
- "Address bot comments and merge when ready"
- "Iterate on PR until all bots are satisfied"

## Ground rules (hard-won, PR#313 / PR#317)

1. **A `✅ Fixed` reply does not resolve the thread.** Replying only adds a comment. Thread resolution (`reviewThreads.isResolved`) is separate bookkeeping — a collaborator resolves it in the UI, or CodeRabbit auto-resolves on a later review. The loop therefore tracks *addressed* (fix reply posted) separately from *resolved* (thread state), and never blocks a merge on addressed-but-unresolved threads.

2. **CodeRabbit never submits APPROVED.** Its reviews stay `COMMENTED` forever, satisfied or not. Ignore review *state* entirely. The completion signal for the current head is the `CodeRabbit` row in `gh pr checks` flipping to `pass` ("Review completed").

3. **Checks + merge state are the authoritative merge signals.** `actionable=0` + all checks `pass` + `mergeStateStatus: CLEAN` means mergeable, even if stale threads remain unresolved. Merge plainly first, verify with `gh pr view --json state,mergedAt` (cached views lie), and only if refused retry once with `--admin`.

4. **Never hand-roll detection one-liners mid-loop.** Inline jq written from memory produced syntax errors twice in one session. Detection lives in exactly one tested place — `pr-ready-check` — and loops branch on its exit code instead of re-deriving readiness.

## The tool: pr-ready-check

```
pr-ready-check PR_NUMBER [REPO] [--strict]
```

Installed at `~/.local/bin/pr-ready-check` (chezmoi: `dot_local/bin/executable_pr-ready-check`). Single source of truth for merge readiness. Classifies every review thread (GraphQL, first 100 threads / 30 comments per thread — refuses to guess beyond that cap):

| kind | meaning |
|---|---|
| `actionable` | bot finding + no fix reply yet — **must fix** |
| `addressed` | bot finding + `✅` fix reply posted — advisory only |
| `resolved` | thread `isResolved` |
| `no-finding` | thread without a severity-marked bot comment |

A bot finding is a `[bot]`-authored comment whose body carries `🎯`, `🔴 Critical`, `🟠 Major`, or `🟡 Minor`. A fix reply is any non-bot comment containing `✅`.

Verdicts (exit codes):

| verdict | exit | meaning |
|---|---|---|
| `READY` | 0 | merge now |
| `ACTION` | 3 | actionable findings exist — fix, reply, push |
| `WAITING` | 1 | review or checks still in progress (or `--strict` with addressed threads outstanding) |
| `BLOCKED` | 1 | checks failing or merge state not CLEAN |
| `ERROR` | 2 | API failure |

`--strict` requires every thread actually resolved before READY — use only where branch protection or policy demands it.

## Workflow

Per check (poll every 5 minutes by default, capped by a timeout — 90 minutes unless the captain says otherwise):

1. Run `pr-ready-check $PR $REPO` and branch on the exit code:

2. **`ACTION` (3)** — for each finding in the tool output (it prints `path`, the finding `comment_id`, and an excerpt):
   - Fix the issue; commit with a message referencing the feedback.
   - Push to the PR branch (one push may address several findings).
   - Reply to each finding comment so its thread becomes *addressed*:
     ```bash
     gh api repos/$REPO/pulls/$PR/comments/$COMMENT_ID/replies \
       -X POST -f body="✅ Fixed in commit <short-sha>"
     ```
   - Continue the loop.

3. **`READY` (0)** — merge and verify:
   ```bash
   gh pr merge $PR --repo $REPO --merge
   gh pr view $PR --repo $REPO --json state,mergedAt
   ```
   If plain merge is refused (addressed-but-unresolved threads), retry once:
   ```bash
   gh pr merge $PR --repo $REPO --admin --merge
   ```
   Never delete branches or force anything in the process. After merge, pull the base branch and confirm the merge commit landed.

4. **`WAITING`/`BLOCKED` (1)** — sleep the poll interval and loop. Report nothing to the captain for WAITING; escalate BLOCKED only if it persists past the timeout.

5. **`ERROR` (2)** — report to the captain and stop.

## Timeout handling

Cap the loop. On timeout:
- READY-but-unmerged → ask the captain: merge now?
- actionable findings remain → report which ones and stop.

## Bot notes

### CodeRabbit
- Severity markers: `🔴 Critical`, `🟠 Major`, `🟡 Minor`, plus `🎯`-tagged findings.
- Reviews stay `COMMENTED`; never wait for an APPROVED review state.
- Completion signal: the `CodeRabbit` check row = `pass` ("Review completed").
- "Analysis chain" comments are evidence, not findings — nothing to fix there.

### Greptile
- Plain-text comments; trial accounts hit a 50-credit ceiling and it silently stops reviewing. Absence of a Greptile review is not a blocker.

## Example session (real PR#317 flow)

```bash
$ pr-ready-check 317 phillias/dotfiles
pr_ready:
  verdict: ACTION
  actionable: 2
  ...
findings[2]{path,comment_id,excerpt}:
  dot_local/bin/executable_pr-ready-check (comment 4052007869) — 🟠 Major ...
  dot_agents/skills/pr-review-loop/SKILL.md (comment 4052007859) — 🟠 Major ...

# fix both, commit, push
$ git push

# reply to each finding id — thread flips to addressed
$ gh api repos/phillias/dotfiles/pulls/317/comments/4052007869/replies \
    -X POST -f body="✅ Fixed in commit 0102df3"

$ pr-ready-check 317 phillias/dotfiles
pr_ready:
  verdict: READY
  actionable: 0
  addressed: 5   # advisory — thread bookkeeping, not blockers
  checks: pass (coderabbit: pass)
  mergeable: MERGEABLE CLEAN
merge_hint: addressed threads remain unresolved — if plain merge is refused, retry once with --admin

$ gh pr merge 317 --repo phillias/dotfiles --merge
$ gh pr view 317 --repo phillias/dotfiles --json state,mergedAt
{"mergedAt":"2026-09-19T03:50:19Z","state":"MERGED"}
```

## Integration with no-mistakes

- `no-mistakes`: code → validation → PR creation
- `pr-review-loop`: PR → bot feedback → fixes → merge
