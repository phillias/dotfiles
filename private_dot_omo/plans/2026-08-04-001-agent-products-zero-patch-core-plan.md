---
title: "Agent-Products Core — zero-patch, human-graspable, token-efficient"
type: roadmap
created: 2026-08-04
status: active
origin: session synthesis — pivot from CE-skill merging to agent products on OmO built-ins
---

# Agent-Products Core

## Problem Frame

The original direction (merge grill-with-docs + finding-unknowns-skills into ce-brainstorm, then into "the OmO design") was superseded by three findings:
1. Upstream CE (`EveryInc/compound-engineering-plugin`) already absorbed blindspot-pass and unified brainstorm→plan into one artifact — the local port was a stale, stripped snapshot (delta manifest: **0/32 identical**, 15 stripped, 7 modified, 10 dropped, 14 customs).
2. Skills are token-heavy in the enumeration (paragraph descriptions, model-loadable) vs agents (one-line description, prompt loads only on delegation).
3. Requirements: **no patching, manual oversight, no looping, token economy, AXI/TOON, self-improving** — satisfied by agents + memory, not a skill pipeline.

## Design Priorities (binding)

- [x] **No patching** — stock opencode/OmO untouched; all drops in overlay dirs read by default
- [x] **Manual oversight** — every phase gated; no autonomous loops
- [x] **No looping** — phases with gates; the only "loop" is cross-session memory compounding
- [x] **Token economy** — agents over skills; prune via `disabled_agents`/`disabled_skills`
- [x] **AXI/TOON** — TOON output contracts, minimal schemas, aggregates, definitive empty states
- [x] **Self-improving** — agents are the product; axi-memory read at start, write at end, `mem dedup` clean

## The 4-Gate Core

```
Metis (brainstorm — ALWAYS first step) → [GATE] → plan (built-in) → [GATE] → build/Sisyphus-Junior → [GATE] → verify (ce-* personas / pro/reviewer)
```

Design folds into Metis-plan. Brainstorming is always the first step of the Metis-plan agent.

## Progress Log (verified)

- [x] MVP drop: 8 pro-workflow agents (`agents/pro/*`, opencode-tailored), 11 fu- skills, 8 pro- skills, MVP-README (design priorities + provenance + teams reference) — PR #164
- [x] MVP-README: team-mode activation + 3 canonical team schemas (refactor-squad, hyperplan, security-research)
- [x] CE delta manifest (0/32 identical triage + attribution table) — triage preserved in axi-memory (`d-2026-08-04-ce-delta-manifest-0-32-identical-15-stri`); doc removed 2026-08-04
- [x] CF Workers catalog refresh in opencode-omo-config (34 LLM of 77, 7 new models flagged)
- [x] 10 dropped CE skills installed as reference material (lfg + 9)
- [x] Team research: config-gated activation (`team_create` by lead in main session), single-shot lifecycle, WAIT directives, owner='lead'
- [x] Firstmate research: member≈crewmate mapping, single-shot autonomy gap, 5 stealable patterns (dispatch profiles, TOON briefs, delivery modes, wake classification, state separation)

## Open Decisions (awaiting captain greenlight)

- [ ] Apply config proposals: pro-agent model pins (free-tier CF first), new CF models (`kimi-k2.5`, `qwq-32b`) in fallback chains, `disabled_*` pruning
- [ ] dispatch-rules.json re-routing toward the 4-gate core
- [ ] CE rebase of the 15 stripped skills onto upstream `6a2a0f9` (delta manifest is the prerequisite — done)
- [ ] Firstmate adoption path: translate patterns into OmO teams (adapt — consistent with `a6e88f9`) vs adopt the distro (OpenCode is a verified primary harness)
- [ ] Prototype one scout team (single member, free model, TOON prompt) to validate bounded OmO autonomy
- [ ] `design-pass` team creation (activation documented)

## OmO Teams — reference

- Activation: `team_mode.enabled` (already on) → restart → define `~/.omo/teams/{name}/config.json` → lead calls `team_create`. Initiation is **LLM-driven** (tool call); mechanics (spawning, mailboxes, task state, tmux) are plugin code.
- Capability transfer: each member gets its `prompt` (or the referenced agent's prompt) as system prompt + the 12 `team_*` tools injected.
- Canonical schemas: refactor-squad (4 workers), hyperplan (5 adversarial), security-research (3 hunters + 2 PoC).
- Oversight stance: a team run = ONE gated unit (approve run, review mailbox). Teams only for parallelizable work; the 4-gate core stays sequential.

## Firstmate Direction (deepened 2026-08-04)

[kunchenguid/firstmate](https://github.com/kunchenguid/firstmate) (2.8K★, MIT, active): an **agent distro** — "Talk to one agent. Ship with a crew." Captain (you) → first mate (single liaison) → crewmates (autonomous agents, one per tmux/herdr/zellij/orca/cmux session, each in a treehouse worktree). OpenCode is a **verified primary harness** (TUI plugin). Stack connection: dispatch-rules birth commit `a6e88f9` = "port firstmate-style supervision as a thin wrapper around Sisyphus".

**Mapping**: one OmO team member ≈ one firstmate crewmate spawn; one OmO team lifecycle ≈ one dispatch+supervise cycle. **Correction**: OmO members are single-shot task() calls — bounded autonomy; firstmate crewmates are full-session agents with zero-token bash watcher supervision. OmO teams approximate firstmate **dispatch**, not firstmate **autonomy**.

**Stealable patterns**: (1) dispatch profile schema (NL rules → {harness, model, effort}, quota-balanced arrays), (2) TOON task briefs (project, ship/scout, delivery posture, yolo, worktree, in/out scope, outcome contract; crewmate reports only via lead), (3) project delivery modes (no-mistakes/direct-PR/local-only + yolo), (4) event-driven wake classification in shell (working/paused/merged/failed), (5) state separation (append-only wake events vs current-state snapshot).

## Attribution Discipline (standing)

Every absorbed skill/agent gets provenance (prefix + README/ADR credit). Counter-pattern to upstream's silent absorption of finding-unknowns' blindspot-pass.
