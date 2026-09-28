# Routing topology (D1-generated snapshot)

Snapshot generated 2026-09-28 from the shared D1 `provider-catalog` registry: 15 routes, 61 ladder steps, 53 model rows.
The underlying tables refresh daily at 05:00 ET via `d1-registry-refresh.mjs`; this document is a manual snapshot — regenerate after structural route changes.
Live quota truth is always `quota-axi`, never this file. Ladder truth is the gateway; D1 mirrors it.

## Flow 1 — firstmate → harnesses → (virtual) providers → models

```mermaid
flowchart TD
    captain[Captain]
    fm[Firstmate<br/>supervisor + briefs]
    captain --> fm
    subgraph crew[Crewmate workers ship/scout]
        h1[claude / codex / opencode / pi<br/>primary harnesses]
        h2[grok / kimi / cursor / gemini<br/>secondary harnesses]
        h3[muse / rovo / agy / omp<br/>scout-crew only]
    end
    fm --> crew
    subgraph cf[Cloudflare AI Gateway `opencode` — 12 dynamic routes]
        TUI["dynamic/TUI<br/>mimo-v2.5-free → glm ladder ×10"]
        HIGH["dynamic/high<br/>glm-5.3 ×8 providers"]
        GATE["dynamic/pr-gate<br/>nemotron-super ×9"]
        REV["dynamic/pr-reviewer<br/>deepseek-v4-flash ×4"]
        VIS["dynamic/vision<br/>gemini-2.5-flash ×4"]
        PERH["claude · codex · cursor · grok · kimi · muse · test<br/>single-purpose 1–2 model ladders"]
    end
    subgraph vg[Vercel AI Gateway — virtual models]
        VTUI["vmc/tui<br/>qwen3.7-flash → gpt-4o-mini ×6"]
    end
    subgraph direct[Direct providers in harness configs]
        OG[opencode-go-gw / opencode-zen<br/>zen free lane + omen-alpha]
        OTHERS[commandcode · zai-coding · phoenixgrove<br/>openrouter-direct · nvidia · cerebras …]
    end
    crew -->|stage 0 primary| cf
    crew -->|stage 1 fallback| vg
    crew -->|stage 2 / direct| direct
    cf --> models1[upstream provider/models<br/>per ladder below]
    vg --> models2[alibaba · deepseek · zai · openai · google]
    direct --> models3[per provider catalogs]
```

### Cloudflare `dynamic/*` ladders (position order, head first)

| Route | Ladder (provider/model, fallback order) |
|---|---|
| dynamic/TUI | opencode-zen/mimo-v2.5-free → glm-5.1 → glm-5.2 → glm-5.3-flash → commandcode/GLM-5.1 → phoenixgrove/glm-5.2 → commandcode/GLM-5.2 → commandcode/glm-5.3-flash → phoenixgrove/glm-5.3-flash → openrouter/z-ai/glm-5.1 |
| dynamic/high | aihubmix/coding-glm-5.3 → aihubmix/claude-fable-5-1 → aihubmix/glm-5.3 → together/GLM-5.3 → openrouter/glm-5.3 → phoenixgrove/glm-5.3 → friendli/GLM-5.3 → deepinfra/GLM-5.3 |
| dynamic/pr-gate | nvidia-nim/nemotron-3-super-120b → zen/nemotron-3-ultra-free → openrouter/gpt-5.6-luna → commandcode/GLM-5.2 → commandcode/Kimi-K3 → commandcode/nemotron-3-ultra-550b → commandcode/deepseek-v4-flash → phoenixgrove/deepseek-v4-flash-0731 → google-ai-studio/gemini-2.5-flash |
| dynamic/pr-reviewer | nvidia-nim/deepseek-v4-flash-0731 → openrouter/gpt-5.6-luna → openrouter/nemotron-3-ultra-550b:free → zen/glm-5.2 |
| dynamic/vision | google-ai-studio/gemini-2.5-flash → together/GLM-4.5V → zen/gemini-3.5-flash → openrouter/gemini-2.5-flash |
| dynamic/claude | openrouter/anthropic/claude-sonnet-4 |
| dynamic/codex | commandcode/gpt-5.6-luna → openrouter/gpt-4o |
| dynamic/cursor | _registered in D1; empty ladder — no models discovered yet_ |
| dynamic/grok | commandcode/xai/grok-4.5 → openrouter/x-ai/grok-4.5 |
| dynamic/kimi | commandcode/Kimi-K2.6 → openrouter/kimi-k2.6 |
| dynamic/muse | commandcode/meta/muse-spark-1.2 → openrouter/llama-3.1-70b |
| dynamic/test | zen/nemotron-3-ultra-free |

### Vercel virtual models

| Route | Ladder |
|---|---|
| vmc/tui | alibaba/qwen3.7-flash → deepseek/deepseek-v4-flash-0731 → zai/glm-5.3-flash → openai/gpt-5-nano → google/gemini-2.5-flash-lite → openai/gpt-4o-mini |
| vmc/pr-gate | deepseek/deepseek-v4-flash-0731 → nvidia/nemotron-3-super-120b-a12b → moonshotai/kimi-k3 → zai/glm-5.2 → openai/gpt-5.6-luna → google/gemini-2.5-flash |
| vmc/pr-reviewer | deepseek/deepseek-v4-flash-0731 → openai/gpt-5.6-luna → nvidia/nemotron-3-ultra-550b-a55b → zai/glm-5.2 |

**List-API workaround (resolved 2026-09-27):** Vercel's virtual-model list API returns empty (upstream quirk), so `vmc/pr-gate` and `vmc/pr-reviewer` were registered by one-time manual `routes` seed; the daily refresh walks their ladders from those rows. Any NEW Vercel virtual model needs the same one-time seed before the daily refresh discovers it.

## Flow 2 — no-mistakes → pi harness → (virtual) providers → models

```mermaid
flowchart TD
    fm[Firstmate ship task]
    nm["no-mistakes axi run<br/>intent → rebase → review → test → document → lint → push → pr → ci"]
    fm --> nm
    pi["pi — configured gate-validation agent<br/>~/.no-mistakes/config.yaml agent: pi"]
    nm -->|pipeline steps invoke| pi
    subgraph chains[pi fallback chains ~/.pi/fallback-chains.json]
        DEF["default<br/>CfAiGw/dynamic/TUI → vercel/vmc/tui"]
        GATEC["gate<br/>CfAiGw/dynamic/pr-gate → vercel/vmc/pr-gate → opencode-go-gw/deepseek-v4-flash"]
        REV2["review<br/>CfAiGw/dynamic/pr-reviewer → vercel/vmc/pr-reviewer → opencode-go-gw/deepseek-v4-flash"]
    end
    pi --> chains
    GATEC --> cfroute[CF dynamic/pr-gate ladder ×9]
    REV2 --> cfroute2[CF dynamic/pr-reviewer ladder ×4]
    DEF --> cfroute3[CF dynamic/TUI ladder ×10]
    GATEC -->|vercel seed| vg[vercel/vmc/pr-gate]
    REV2 -->|vercel seed| vr[vercel/vmc/pr-reviewer]
    GATEC -->|terminal| ogw[opencode-go-gw/deepseek-v4-flash]
    REV2 -->|terminal| ogw
```

## Free lanes, quota and limits

Provider-level headroom snapshot (quota-axi, 2026-09-27, kalione). Live values: run `quota-axi`.

| Provider / plane | Plan or auth | Free lane models | Headroom snapshot 2026-09-27 |
|---|---|---|---|
| opencode (zen + go) | OpenCode account | mimo-v2.5-free (client-gated, degraded), nemotron-3-ultra-free, deepseek-v4-flash-free | monthly 0% → resets 2026-09-30 21:14 UTC; 5h/weekly 100% |
| commandcode | individual-goat | poolside/laguna-s-2.1-free | weekly + monthly 0% → reset 2026-09-28 / 2026-10-12 |
| openrouter | credit balance | nemotron-3-super-120b-a12b:free, laguna-s-2.1:free, space-bunny-alpha (QUARANTINED) | balance ~6% |
| kilocode | free relay | kilo-auto/free, nemotron-3-nano-30b:free, grok-code-fast-1:free, trinity-large:free | not metered on this host |
| claude / codex / cursor / grok / kimi | per-harness auth | harness free tiers | unresolved on kalione (auth sources absent) |

Model status counts in D1: 50 unknown · 1 degraded (mimo) · 1 quarantined (space-bunny) · 1 ok. Per-model pricing/context: `models.snapshot.json`; D1 `models` table carries status + free_tier.

Quarantine reminder: `openrouter/stealth/space-bunny-alpha` stays out of every interactive-TUI chain (captain decision 2026-09-25); do not re-add without explicit captain approval.
