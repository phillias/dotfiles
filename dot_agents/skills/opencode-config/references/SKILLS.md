# Skills

CE skills and dispatch coordination relevant to OpenCode config work. The compound-engineering plugin installs skills at `~/.agents/skills/ce-*`; firstmate loads its own skills from `.agents/skills/` (metadata.internal=true).

## CE skill stagger dispatch map

Parallel dispatch sites for large CE flows — stagger to avoid hammering a single provider/concurrency pool.

| Dispatch site | Parallel agents |
|---|---|
| ce-code-review Stage 4 | ~18 |
| ce-code-review Stage 5b | ~15 |
| ce-agent-native-audit | 8 |
| ce-doc-review | 7 |
| ce-ideate Phase 2 | 6 |
| ce-compound Phase 3 | 6 |
| (remaining sites) | smaller fan-outs |

Recommendation: 5-10s jitter between parallel dispatches. CE sub-agents are pinned to budget-optimized models (never override); session model is used for skill entry points only.

## Related skill pointers

- **bootstrap-diagnostics** — actionable session-start diagnostic lines (MISSING/MISSING_MANUAL/NEEDS_GH_AUTH/TANGLE/CREW_DISPATCH/FLEET_SYNC/...)
- **harness-adapters** — load before spawn/recovery/trust handling
- **stuck-crewmate-recovery** — stale/looping/unresponsive workers
- **firstmate-coding-guidelines** — load before changing firstmate shared tracked material
- **axi** — TOON output discipline (the design standard for this skill's references)
