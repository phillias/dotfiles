# Plan: Agent-Products Core — zero-patch, human-graspable, token-efficient

**Status**: active · **Created**: 2026-08-04 · **Type**: strategy/roadmap (living)
**Owner**: phillias + Sisyphus (big-pickle@InspironOne)
**Origin**: pivot from "merge CE skills into OmO" → "develop agent products on OmO's built-in agents"

## Context

The original direction (merge grill-with-docs + finding-unknowns-skills into ce-brainstorm, then into "the OmO design") was superseded after the discovery that:
1. Upstream CE (`EveryInc/compound-engineering-plugin`) already absorbed blindspot-pass and unified brainstorm→plan into one artifact (`artifact_readiness`) — the local port was a stale, stripped snapshot (delta manifest: **0/32 identical**, 15 stripped, 7 modified, 10 dropped, 14 customs).
2. Skills are token-heavy in the enumeration (paragraph descriptions, model-loadable) vs agents (one-line description, prompt loads only on delegation).
3. The user wants: **no patching, manual oversight, no looping, token economy, AXI/TOON, self-improving** — satisfied by agents + memory, not a skill pipeline.

## Design Priorities (binding)

1. **No patching** — stock opencode/OmO stay untouched; all drops in overlay dirs read by default.
2. **Manual oversight** — every phase gated; no autonomous loops.
3. **No looping** — phases with gates; the only "loop" is cross-session memory compounding.
4. **Token economy** — agents over skills; prune via `disabled_agents`/`disabled_skills`.
5. **AXI/TOON** — TOON output contracts, minimal schemas, aggregates, definitive empty states.
6. **Self-improving** — agents are the product; axi-memory read at start, write at end, `mem dedup` clean.

## The 4-Gate Core

```
Metis (brainstorm — ALWAYS first step) → [GATE] → plan (built-in) → [GATE] → build/Sisyphus-Junior → [GATE] → verify (ce-* personas / pro/reviewer)
```

Design folds into Metis-plan. Brainstorming is always the first step of the Metis-plan agent.

## Progress Log

| Date | Item | State |
|---|---|---|
| 2026-08-04 | MVP drop: 8 pro-workflow agents (`agents/pro/*`, opencode-tailored), 11 fu- skills, 8 pro- skills, MVP-README (design priorities + provenance + teams reference) | ✅ PR #164 commit 1 |
| 2026-08-04 | MVP-README: team-mode activation + 3 canonical team schemas (refactor-squad, hyperplan, security-research) | ✅ PR #164 commit 2 |
| 2026-08-04 | CE delta manifest (0/32 identical triage + attribution table) | ✅ PR #164 commit 3 + `docs/plans/CE-DELTA-MANIFEST.md` |
| 2026-08-04 | CF Workers catalog refresh in opencode-omo-config (34 LLM of 77, 7 new models flagged) | ✅ PR #164 |
| 2026-08-04 | 10 dropped CE skills installed as reference material (lfg + 9) | ✅ PR #164 commit 4 |
| 2026-08-04 | Team research: config-gated activation (`team_create` by lead in main session), single-shot lifecycle, WAIT directives, owner='lead' | ✅ in README + memory |
| 2026-08-04 | Firstmate direction: OmO team ≈ firstmate crewmate (single worker, free model, concise prompt) | 🔶 deepening (librarian) |

## Teams (OmO team mode) — reference

- Activation: `team_mode.enabled` (already on) → restart → define `~/.omo/teams/{name}/config.json` → lead calls `team_create`. Initiation is **LLM-driven** (tool call); mechanics (spawning, mailboxes, task state, tmux) are plugin code.
- Capability transfer: each member gets its `prompt` (or the referenced agent's prompt) as system prompt + the 12 `team_*` tools injected.
- Canonical schemas: refactor-squad (4 workers), hyperplan (5 adversarial), security-research (3 hunters + 2 PoC).
- Oversight stance: a team run = ONE gated unit (approve run, review mailbox). Teams only for parallelizable work; the 4-gate core stays sequential.

## Firstmate Direction (from README; deepening pending)

[kunchenguid/firstmate](https://github.com/kunchenguid/firstmate) (2.8K★, MIT, active — 329 commits, 899 forks): an **agent distro**, not a model/harness/CLI — "Talk to one agent. Ship with a crew."
- **Roles**: captain (you) → first mate (single liaison agent) → crewmates (autonomous agents, one per tmux window/herdr/zellij tab, each in a treehouse git worktree).
- **Two task shapes**: ship (deliver PRs/approved local merges) / scout (investigation reports).
- **Project modes**: no-mistakes / direct-PR / local-only, optional `+yolo`.
- **Zero-token supervision**: bash watcher sleeps on the fleet, wakes the first mate only when needed (turn-end guard backstop).
- **OpenCode is a verified primary harness** (TUI plugin).
- **Stack connection**: dispatch-rules birth commit `a6e88f9` = "port firstmate-style supervision as a thin wrapper around Sisyphus" — the fleet-state-writer/scripts already implement the watcher idea.

**Working hypothesis**: an OmO team = a firstmate-style crew where each crewmate = one OmO team member — single worker, free model, concise token-saving (TOON) prompt; autonomy contained within one gated team run.

## Open Decisions (awaiting user greenlight)

1. Apply config proposals: pro-agent model pins (free-tier CF first), new CF models in chains, `disabled_*` pruning.
2. dispatch-rules.json re-routing toward the 4-gate core.
3. CE rebase of the 15 stripped skills onto upstream `6a2a0f9` (manifest is the prerequisite — done).
4. Firstmate adoption path: full firstmate distro as a crew backend vs firstmate *patterns* (crewmate prompts, dispatch, supervision) translated into OmO teams.
5. `design-pass` team creation (activation documented).

## Attribution Discipline (standing)

Every absorbed skill/agent gets provenance (prefix + README/ADR credit). Counter-pattern to upstream's silent absorption of finding-unknowns' blindspot-pass.
