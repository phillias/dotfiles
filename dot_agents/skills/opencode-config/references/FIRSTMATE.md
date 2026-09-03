# Firstmate (first-class agent distro)

Firstmate is the captain-facing agent distro standardized on this OpenCode design. It runs ON opencode, consumes the fallback chains in `opencode-fallback.jsonc`, and delegates project work to crewmates. This brief is the OpenCode-config view; the authoritative operating contract is the firstmate repo's own `AGENTS.md` (`~/firstmate/AGENTS.md`).

## Positioning

- Firstmate is the captain's single point of contact for all software work across all projects; crewmates and secondmates never address the captain directly.
- Project work is delegated, never done by firstmate directly — except hard-rule-1's concrete captain-approved project operation exception.
- Every session starts by running `bin/fm-session-start.sh` once (lock → bootstrap → wake queue → supervision instructions → fleet digest → network checks → context digest).

## Features & capabilities

- **Session start digest** — one-shot recovery/startup input: lock, bootstrap, wake drain, supervision block, fleet-state digest, context digest.
- **Backlog contract** — `data/backlog.md` via tasks-axi; tracks work items only, never agents; secondmate work lives in the secondmate home's own backlog.
- **Project management** — `project-management` skill owns add/create/clone/remove/initialization/registry/delivery-mode. Projects are read-only to firstmate; crewmates change them.
- **Supervision** — one live supervision cycle whenever work is under way; wake handling is drain-first; guards are harness-aware backstops.
- **Recovery** — `stuck-crewmate-recovery` for stale/looping/unresponsive workers; secondmate recovery is per-secondmate only.
- **Self-update** — `/updatefirstmate` performs guarded fast-forward updates of firstmate + registered secondmate homes; never touches `projects/`.
- **Relay** — public-mention integration (FMX_*); opt-in via `.env` pairing token; public replies are durable state, never conversation memory.
- **Knowledge routing** — `/stow` sweeps session knowledge to its durable owner (captain.md, learnings.md, project AGENTS.md, skills).

## Delivery modes & no-mistakes

Projects carry a standing delivery posture from the registry:

- **no-mistakes** — full pipeline through a PR, waits for configured merge authority; owns review/fixes/tests/push/PR/CI.
- **direct-PR** — push + open PR without the no-mistakes pipeline.
- **local-only** — worker stops with a clean ready branch; firstmate uses the guarded fast-forward merge path.

`yolo` is orthogonal to delivery mode. With `yolo` on, firstmate decides routine gates and merges only green work. **Never merge a red PR.** Merges use `bin/fm-pr-merge.sh` (metadata recorded) or `bin/fm-merge-local.sh`. Hard rule: never merge without explicit captain word except standing `yolo`.

## Slash commands

- `/afk` — away-mode supervision daemon; durable flag `state/.afk`; escalates only captain-relevant events as batched digests; exits on any real unmarked message.
- `/stow` — knowledge sweep + startup-memory curation before context reset.
- `/bearings` / `/ahoy` — fleet status recaps.
- `/updatefirstmate` — self-update.

## Agent architecture

- **Crewmates** — ephemeral task workers spawned via `bin/fm-spawn.sh` into isolated worktrees (worktree-isolation assertion in every brief); briefed via `bin/fm-brief.sh`.
- **Scouts** — knowledge-producing tasks (report.md), never a PR; promotion via `bin/fm-promote.sh`.
- **Secondmates** — persistent isolated `FM_HOME`s with chartered scope; idle by default; act only on work routed by the main firstmate.
- **Steering** — `bin/fm-send.sh` (fail-closed unless FM_HOME explicit); lifecycle via `bin/fm-control.sh` (never text-plane lifecycle).
- **Dispatch profiles** — `config/crew-dispatch.json` + `quota-axi`/`quota-array-dispatch` select harness/model/effort at intake; routing precedence: explicit captain override → matched rule → default → static crewmate harness.

## Token economy talent (AXI)

Firstmate brings the AXI standard to the OpenCode config surface:

- **AXI** (Agent eXperience Interface) — ergonomic standards for agent-facing CLIs: TOON output, minimal schemas, content truncation, pre-computed aggregates, definitive empty states, structured errors, ambient context, content-first, contextual disclosure, consistent help.
- **TOON output** — 3-4 fields, not 10; truncate with size hints; fail with structure, not noise.
- Applied to this skill: the fallback-status tool, fleet-digest.sh, session-start digest, and this reference-file restructure all follow AXI discipline.
- Token budget is a first-class design constraint — firstmate prefers the leanest end-to-end path (no wrappers/control planes unless a concrete blocker justifies them).

## Files & state

- `FM_HOME` (default `~/firstmate`) selects instance-private `data/`, `state/`, `config/`, `projects/`.
- Durable: `data/captain.md`, `data/learnings.md`, `data/backlog.md`, `data/projects.md`, `data/secondmates.md`.
- Volatile: `state/<id>.status` (wake events), `state/<id>.meta` (task records).
- Shared tracked: `AGENTS.md`, `README.md`, `bin/`, `.agents/skills/`, `skills/`, `.tasks.toml`, `.github/workflows/`.
