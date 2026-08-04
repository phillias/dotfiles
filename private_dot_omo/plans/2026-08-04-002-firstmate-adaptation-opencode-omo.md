# firstmate adaptation to opencode + OmO — crew orchestration without the distro

- **Date**: 2026-08-04
- **Status**: draft (needs Momus review before execution)
- **Owner**: Sisyphus
- **Trigger**: fleet-state was originally conceived as a firstmate-style aggressive-subagenting layer but drifted into a generic task tracker (hemma/chezmoi detour). firstmate (kunchenguid/firstmate) remains the reference for the intended model.

## Goal

Adapt firstmate's crew-orchestration *concepts* onto the existing opencode + OmO stack — captain/firstmate/crew hierarchy, visible crew, zero-token watcher, restart-proof reconciliation, ship/scout task shapes — **without** importing the firstmate distro (its AGENTS.md targets claude/grok/pi primaries; opencode is a secondary harness with supervision tradeoffs).

## Context (verified from firstmate README + local stack)

- firstmate = "agent distro": you talk to one first mate; it spawns crewmates (autonomous agents), each in its own tmux window (hard default), each in a disposable treehouse git worktree; supervises via an **event-driven zero-token bash watcher** that sleeps on the fleet and wakes the first mate only when needed; **restart-proof** (all state on disk; next session reconciles); two task shapes — **ship** (authorized changes → PR/local merge) and **scout** (investigation report); project modes `no-mistakes`/`direct-PR`/`local-only` (+ optional `+yolo`); optional **secondmates** (persistent agents in isolated FM_HOME, local or SSH host); built-ins `/afk` (away-mode escalation), `/bearings` (4-section fleet digest), `/stow`, `/ahoy`.
- Local stack already has: OmO `task()`/`background_task`/team-mode; `tmux-subagent-activator.ts` (placeholder panes → `opencode attach`); `fleet-state-writer.ts` sidecar (wake.log/state.json/digest.txt, zero LLM cost); `fleet-digest.sh` reader; `dispatch-rules.json` (26 rules); ntfy.sh plugin (error/idle pushes, verified live); go-pool fallback chain; codeburn federation (cross-server aggregation precedent).

## Design mapping (firstmate concept → opencode/OmO primitive)

| firstmate | Adaptation |
|---|---|
| Captain | User |
| First mate | Sisyphus (existing orchestrator role) |
| Crewmates | `task()` / `background_task` agents (existing) |
| Visible crew (tmux) | `tmux-subagent-activator` — extend: every dispatched bg task gets a pane streaming via `opencode attach` (activator already does this for placeholder panes) |
| Zero-token watcher | **fleet-state sidecar becomes the watcher state**: wake.log = event stream; a bash watcher (`fleet-digest.sh --watch`) sleeps (inotify/`sleep` loop) and surfaces ONLY state transitions idle/error/resulted — never per-message |
| Restart-proof reconciliation | fleet-state session-start reconcile: digest.txt read at boot; `gcStaleTasks` (already implemented) marks dead in-flight tasks failed; watcher re-arms |
| Ship / Scout | dispatch-rules: ship → `deep`/`unspecified-high`/`ultrabrain` (mutations allowed under guards); scout → `explore`/`librarian` (read-only, report to `data/<id>/report.md` equivalent = session digest) |
| Project modes | `dispatch-rules.json` extension: per-project `mode: no-mistakes|direct-pr|local-only` consumed at dispatch; no-mistakes → strict permission + PR-only; local-only → no PR push |
| Secondmates | Deferred: remote `opencode serve` + codeburn-style aggregation of remote fleet-state (existing federation precedent) |
| `/bearings` | `fleet-digest.sh v2`: 4-section digest (running tasks / resolved / unresolved decisions / PR status), injected at session start |
| `/afk` | Away-mode: watcher batches to ntfy; escalate only error + unresolved captain decision; `--watch --escalate` flag |
| Read-only captain / guards | Existing guardrails + opencode.json `permission` block (no new machinery) |

## Decisions

### D1. Reuse, don't rewrite
All crew dispatch stays on OmO `task()`/`background_task`/team-mode. The adaptation touches ONLY: fleet-state-writer (watcher semantics), fleet-digest.sh (v2 digest + watch mode), dispatch-rules.json (project modes + ship/scout), tmux-subagent-activator (pane naming). No new daemon, no new state files.

### D2. Watcher wake conditions (strict)
The watcher wakes Sisyphus (via session-start digest injection + ntfy) ONLY on: task terminal (idle/error/resulted), unresolved-captain-decision, or stale-task GC. Everything else stays silent. This is the anti-noise rule the current sidecar violates (65% session.status chatter in wake.log — see fleet evaluation 2026-08-04).

### D3. ship/scout is a dispatch-rules concern
No new agent types. Ship vs scout maps to existing categories; the rules file gains a `shape` field consumed at intent-gate time. Scout tasks never get permission to mutate (reuse existing permission config).

### D4. Project modes default `no-mistakes`
Conservative default; `direct-pr` and `local-only` opt-in per project via `dispatch-rules.json` or `<project>/.opencode/opencode.json` override.

### D5. No backlog/queue system in this phase
fleet-state stays append-only; a backlog is YAGNI until watcher semantics prove out (firstmate's backlog/briefs are built around its own route state).

## Phases

| Phase | Deliverables | Exit criteria |
|---|---|---|
| 1 (MVP) | Watcher: `fleet-digest.sh --watch` (transition-only wake, ntfy escalation); session-start digest injection (4 sections, ≤1 tool call); fleet-state-writer: suppress session.status/diff/updated rows from wake.log (noise fix, keeps idle/error/resulted/gc/fallback) | Forced-kill test: kill session mid-task → restart → state.json reconciles, digest shows the interrupted task; ntfy fires on error only |
| 2 | Dispatch: `shape: ship|scout` + `mode:` in dispatch-rules.json; tmux pane naming (`crew/<task-id>`); scout report convention (report digest to state.json `resulted` tasks) | 2 projects running different modes route correctly; a scout task makes zero mutations |
| 3 (optional) | Secondmates: remote opencode serve + remote fleet-state aggregation (codeburn pattern); /afk full away-mode | Remote task dispatched, watched, results aggregated on the primary |

## Risks

- **Watcher complexity creep** → inotify dependency: mitigate with plain `sleep`-loop + rotation-safe tail (existing wake.log rotation makes tail cheap); watcher is bash, zero LLM cost.
- **Session-start digest bloat** → hard cap: 8 lines / 4 sections, matches skills_review.tsv token bound.
- **Project-mode misrouting** → dispatch-rules evaluation order (explicit user > first match > default) already prioritizes explicit instructions; modes are advisory.
- **Firstmate divergence**: if firstmate later ships a first-class opencode backend, revisit adoption (this plan is the lower-cost equivalent, not a fork).

## Definition of done

Watcher wakes on transitions only (verified: no per-message wake); session-start digest readable in ≤1 tool call after any kill/restart; ship/scout routing proven with a scout zero-mutation test; ntfy error + escalation verified; project modes active for ≥2 projects; wake.log noise (session.status) eliminated from the reader's default view.

## Open questions

1. Does `direct-pr` mode mean auto-PR after passing `ce-code-review`, or after user approval? (default: after approval — firstmate's "captain approves" boundary is worth keeping)
2. Watcher as systemd user timer (5s interval) vs in-session background loop — systemd survives agent restarts; session loop is simpler. (lean: systemd timer)
