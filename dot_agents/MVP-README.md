# MVP — Zero-Patch Agent/Skill Trial

A drop-in trial of three external skill/agent suites, placed in overlay directories that opencode+OmO read by default. **No stock config patched.** The purpose is to judge what works, inform placement, and feed the self-improving loop — not to ship a final system.

## Design Priorities (in order)

1. **No patching** — stock opencode, OmO, and oh-my-openagent stay untouched. All drops live in overlay dirs that are read by default. Upstream updates flow without merge conflicts. No local fork to version or maintain.
2. **Manual oversight** — the orchestrator (Sisyphus) gates every phase. No skill or agent acts without an explicit delegation. Approval gates are structural, not optional.
3. **No looping** — zero dependence on ralph-loop / ulw-loop / continuation machinery. The design loop is **phases with gates**, not autonomous cycles. The only "loop" is cross-session compounding via memory (see #6).
4. **Token economy** — agents over skills for the core (one-line description standing cost vs paragraph + model-loadable body). Curate what loads; prune noise via `disabled_skills`/`disabled_agents` in `omo.jsonc` (one line, own overlay file, no upstream conflict). AXI discipline on every description.
5. **AXI / TOON** — every agent product and skill output observes the 10 AXI principles: TOON-format output (~40% fewer tokens than JSON), minimal default schemas (3-4 fields), content truncation with size hints, pre-computed aggregates, definitive empty states, structured errors to stdout, content-first (no args = live data), contextual disclosure, consistent help.
6. **Self-improving** — the agents themselves are the product. Each session's phases read `axi-memory` at start (past decisions/failures) and write at end (what was decided, what failed). `mem dedup` keeps it clean. The loop is amortized across sessions, not burned in-session. No autonomous loops; memory IS the loop substitute.

## The 4-Gate Core (what the drops feed into)

```
Metis (brainstorm — always first) → [GATE] → plan (built-in) → [GATE] → build/Sisyphus-Junior → [GATE] → verify (ce-* personas or pro/reviewer)
```

Design folds into Metis+plan (brainstorm is always the first step of the Metis-plan agent). Four named phases, four approval stops. No loops.

## What's Dropped Where

| Suite | Provenance | Placement | Count | IDs |
|---|---|---|---|---|
| **pro-workflow agents** | [rohitg00/pro-workflow](https://github.com/rohitg00/pro-workflow) (MIT) | `~/.config/opencode/agents/pro/` | 8 | `pro/scout`, `pro/planner`, `pro/reviewer`, `pro/orchestrator`, `pro/context-engineer`, `pro/cost-analyst`, `pro/permission-analyst`, `pro/debugger` |
| **finding-unknowns skills** | [Neeeophytee/finding-unknowns-skills](https://github.com/Neeeophytee/finding-unknowns-skills) (MIT) | `~/.agents/skills/fu-*/` | 11 | `fu-blindspot-pass`, `fu-interview-me`, `fu-reference-hunt`, `fu-implementation-plan`, `fu-implementation-notes`, `fu-brainstorm-prototypes`, `fu-pitch-packager`, `fu-change-quiz`, `fu-context-audit`, `fu-agent-interface-design`, `fu-progressive-disclosure` |
| **pro-workflow skills (curated)** | rohitg00/pro-workflow (MIT) | `~/.agents/skills/pro-*/` | 8 | `pro-token-efficiency`, `pro-compact-guard`, `pro-cost-tracker`, `pro-tdd`, `pro-design-engineering`, `pro-plan-interrogate`, `pro-skill-router`, `pro-thoroughness-scoring` |
| **CE personas** | [EveryInc/compound-engineering-plugin](https://github.com/EveryInc/compound-engineering-plugin) (MIT) | `~/.config/opencode/agents/` (already installed, flat) | 49 | `ce-correctness-reviewer`, `ce-security-sentinel`, etc. |

**Full pro-workflow skill set (41) is NOT dropped** — only the 8 token-economy / TDD / design / interrogation skills. The rest (wiki-*, batch-orchestration, parallel-worktrees, llm-council, orchestrate) are loop/parallel machinery that violates design priority #3. Available upstream if a later stage wants them.

## Provenance & Attribution

| Source | License | Credit |
|---|---|---|
| EveryInc/compound-engineering-plugin | MIT | Upstream; 49 personas already installed via plugin |
| rohitg00/pro-workflow | MIT | Rohit G. — independent CE-inspired suite, 41 skills + 8 agents |
| Neeeophytee/finding-unknowns-skills | MIT | Neeeophytee — distillation of Thariq Shihipar's "Finding Your Unknowns" essay |

**Attribution note**: upstream CE silently absorbed `blindspot-pass` from finding-unknowns into `ce-brainstorm/references/blindspot-pass.md` (commit `6a2a0f9`, 2026-08-03) with zero credit. This MVP does the counter-pattern: every dropped skill carries its source prefix (`fu-`, `pro-`) and this README records provenance. The self-improving loop should maintain this discipline for all future absorptions (ADR per absorbed skill).

## How to Trial

1. **Agents** — invoke directly: `task(subagent_type="pro/scout", prompt="...")`. The 8 pro agents appear in the task tool's enumeration as `pro/*` IDs.
2. **Skills** — invoke via `load_skills=["fu-blindspot-pass"]` in a task call, or model-invoked by description match.
3. **Judge**: Does `pro/scout` add value over `explore`? Does `fu-blindspot-pass` surface real unknowns before Metis? Does `pro/cost-analyst` actually constrain token spend? Which descriptions are noise?

## How to Prune (token economy lever)

In `~/.omo/omo.jsonc` (your overlay file — not stock):

```jsonc
"[opencode]": {
  "disabled_skills": ["fu-progressive-disclosure", "fu-agent-interface-design", /* ...noise... */],
  "disabled_agents": ["pro/orchestrator", "pro/debugger" /* if unused */]
}
```

The plugin filters the list at load: `skills.filter(s => !disabledSkills.has(s.name))`. One line each, no file deletion, no upstream conflict.

## Caveats (what this trial will surface)

1. **pro-workflow frontmatter**: pro agents carry Claude-Code-specific fields (`background`, `isolation: worktree`, `omitClaudeMd`) that opencode ignores. Their `model: opus` may not resolve — opencode uses `provider/model` format. If an agent fails to load, adjust its frontmatter `model` to a valid opencode model (e.g. `opencode-zen/big-pickle`). This is expected MVP signal.
2. **fu- skill `name` field**: finding-unknowns skills keep their original `name:` frontmatter (e.g. `blindspot-pass`), so the registered skill name may be `blindspot-pass` not `fu-blindspot-pass`. The directory is prefixed; the frontmatter is not. Resolve by editing the `name:` field if the prefix matters for invocation.
3. **pro-token-efficiency** embeds a full opencode skills preamble as content (pro-workflow's templated design) — noisy but harmless for trial.
4. **Nested pro/ agent IDs**: opencode resolves `~/.config/opencode/agents/pro/scout.md` → agent ID `pro/scout`. If the file's `name: scout` field overrides the path, the ID may be just `scout` (collision risk). Verify via `task` tool enumeration after reload.

## `.omo/teams` Schema Reference (for later stages)

Teams are **team compositions** (not agent definitions). Stored as `~/.omo/teams/{name}/config.json`. Members have two variants:

- `kind: "category"` — composes a model tier (category) + custom behavior (prompt) + instance name. **This is the abstraction layer**: behavior decoupled from model tier from identity.
- `kind: "subagent_type"` — reuses an existing opencode agent (from `~/.config/opencode/agents/`), with optional prompt override.

Not used in this MVP (the 4-gate core doesn't need parallel team_mode). Add later if parallel execution is wanted — members would reference the `pro/*` and `ce-*` agents defined above.

## Token Economy of Agents (reference)

Agents surface in the orchestrator's context as **one-line descriptions** in the `task` tool's enumeration ("Available agent types and the tools they have access to: ..."). The full agent prompt loads **only on delegation**. Standing cost ≈ N agents × 1 line. Skills, by contrast, surface as paragraph descriptions AND are model-loadable (heavier standing cost + double-load risk). This is why the core is agents, not skills, and why pruning (`disabled_agents`) matters.

---

**MVP date**: 2026-08-04
**Trial goal**: judge placement (overlay dirs vs `.omo/teams` vs `.omo/skills`) and per-piece value.
**Next stage**: based on trial signal, either expand drops, write the `design`/`verify` agent products, or formalize the 4-gate routing in `dispatch-rules.json`.
