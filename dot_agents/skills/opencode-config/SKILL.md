---
name: opencode-config
description: Architecture, decisions, and maintenance of the OpenCode config — provider stack, model catalog, fallback chains, drift pipeline, plugins, and the firstmate distro built on it. Load when editing opencode.json or fallback routing, wiring providers or keys, or debugging model routing.
---

# OpenCode Configuration Skill

Purpose: architecture, decisions, and maintenance of the OpenCode config — provider stack, model catalog, fallback system, drift pipeline, per-provider gotchas, and the firstmate distro built on it.

History: single-root config since 2026-07-18 (profiles phased out; `cloudflare/` vs `@cf/` prefix bug source — resolved 2026-08-29: the cloudflare provider targets the AI Gateway **REST API** (`.../ai/v1` baseURL + required `cf-aig-gateway-id: opencode` header), where Workers AI ids are bare `@cf/...`, so the Cloudflare model ids and every fallback/doc reference are `cloudflare/@cf/...`; the 2026-08-27 `workers-ai/` prefix scheme applied only to the deprecated `/compat` endpoint). OmO retired 2026-08-09 — the OmO plugin was purged from opencode.json + node_modules; `~/.omo/omo.jsonc` recovered config seeded `opencode-fallback.jsonc` and is **provenance only**. Renamed from opencode-omo-config.

## Reference files (load the section you need)

| Purpose | File |
|---|---|
| Design — 4 runtime systems + architecture overview | `references/DESIGN.md` |
| Agent & category routing (fallback chains) | `references/AGENTS.md` |
| Plugins — runtime fallback, fleet-state-writer, stack | `references/PLUGINS.md` |
| Skills — CE stagger dispatch, related skills | `references/SKILLS.md` |
| OmO-era archive (Model Selection Priorities, Config File Hierarchy) | `references/ARCHIVE-OMO.md` |
| Firstmate agent distro brief | `references/FIRSTMATE.md` |
| Fleet serve mesh (cross-node agent communication) | `references/DESIGN.md` §9 |
| OS dependencies (gh, bw, wrangler, sqlite, mise, ...) | `references/DEPENDENCIES.md` |
| Model snapshot (drift baseline) | `~/.agents/skills/provider-catalog/models.snapshot.json` |

## Critical rules

1. One config, no profiles; `OPENCODE_CONFIG_DIR` unset. The headless serve process reads the same `~/.config/opencode` tree as the TUI; its systemd unit does not override `XDG_CONFIG_HOME`.
2. `~/.config/opencode/opencode.json` defines live providers + MCPs (interactive TUI + headless runs without the serve unit).
3. `opencode-fallback.jsonc` owns agent/category/global routing; `oh-my-openagent.jsonc` is a legacy orphan never read.
4. Global default fallback — project > global first-match-wins.
5. Plugins auto-load; retired plugins enforced-removed.
6. No symlinks, machine diffs via chezmoi `.tmpl`, paths always `$HOME`/`%h` (never `/home/<user>`).

## Chain at a glance (paid-first, 2026-08-29)

`opencode-zen/big-pickle` → OpenCode Go (kimi-k2.6, ds-v4-flash) → Command Code GOAT (Kimi-K2.6, DS-V4-Flash) → **Z.AI Coding Plan** (`zai-coding`: DIRECT to `https://api.z.ai/api/coding/paas/v4` with `ZHIPU_API_KEY_PLAN` since 2026-10-25 — no gateway hop; Z.AI cannot be a gateway route element, its path is non-standard) → **Cloudflare** (REST `/ai/v1`, @cf lane; kimi-k2.7-code, glm-4.7-flash) → **OpenRouter** (cheapest GLM-5 per-token) → Zen free (deepseek-v4-flash-free, nemotron-3-ultra-free) → free providers (Phoenix Grove Everyday-band free: glm-5.3-flash, ds-v4-flash; nvidia, openrouter, baseten) → `google/gemini-2.5-flash`. Six providers (zen, go, commandcode, openrouter, phoenixgrove, zai-coding) — all but zai-coding route through gateway `opencode` via BYOK — gateway token in `Authorization`, stored keys inject upstream. Gateway dynamic routes bridge provider gaps via **Vercel indirection** (`custom-vercel/router/tui` GLM-only, `/router/high`) with openrouter as PAYG tail — live ladders: `provider-catalog` ROUTING_TOPOLOGY.md. Full taxonomy + agent/category tables: `references/AGENTS.md`. Design rationale: `references/DESIGN.md` §2.6.

Provider/model facts (stack, gateway routing, BYOK, pricing, quotas, quirks) are owned by the `provider-catalog` skill (`references/PROVIDERS.md` is a stub pointer to it) — load `provider-catalog` when needed; opencode-specific provider mechanics live in `references/DESIGN.md` §8.

## Config defaults (live)

`small_model: opencode-zen/nemotron-3-ultra-free` · compaction `{auto:false, prune:true, reserved:50000, tail_turns:40}` · MCP baseline: context7, grep_app, websearch, mcp_everything · TUI theme tokyonight. Stale doc text in older copies says `google/gemini-2.0-flash` — live value wins.

## Key files

`opencode.json` (root) · `opencode-fallback.jsonc` (chain) · `dispatch-rules.json` (30 rules) · `plugins/opencode-runtime-fallback.ts` + `lib/opencode-runtime-fallback-core.ts` · `lib/opencode-rest-api-provider.test.ts` (contract: @cf lane + gateway-routed provider assertions) · `~/.local/state/opencode-fleet/fallback.json` (live state) · `scripts/bws-exec.sh` (runtime secret loader for the two timer units) + `d1-registry-refresh.mjs` (daily) + `dynamic-audit.mjs` (hourly) · `fm-drift-pr.sh` · systemd `d1-registry-refresh.{service,timer}` + `dynamic-audit.{service,timer}` — both exec via `bws-exec.sh` (sources BWS `load-keys.sh`, maps `CLOUDFLARE_DEPLOY_TOKEN` → `CLOUDFLARE_API_TOKEN` for wrangler; PRs #480; never put a static `CF_AI_GATEWAY_TOKEN` in `provider-catalog.env` — stale copies shadow the vault token and caused the 2026-10-15→24 monitoring blind spot) (catalog-drift.mjs + its units retired 2026-09-28) · `~/.agents/skills/provider-catalog/models.snapshot.json` · `~/.agents/skills/` · gateway token via env `CF_AI_GATEWAY_TOKEN` (bws phillias env-shaped vault key, harvested at consumer start — `glm-free-lane-scan.sh` chain: env override → bws → age fallback only on failed vault fetch; successful-fetch-missing-key errors; covers both `/ai/*` and `/ai-gateway/*` planes; dot-key `.cf-ai-gw` and its age copy are fallback-only since Wave A2 2026-10-27 — use env-shaped `CLOUDFLARE_DEPLOY_TOKEN` for deploy).

## Maintenance

- **Edit config** → `chezmoi diff` → `chezmoi re-add` → commit via `/dotfiles` (or drift-PR gate for chains).
- **Add API key** → key file → `{env:VAR}` match in opencode.json → shell profiles → `chezmoi add --encrypt`.
- **Add MCP** → opencode.json `mcp` → re-add → commit.
- **Chain edits** flow through `bin/fm-drift-pr.sh` (DRIFT gate = captain approval), never direct master writes.

## GPT model routing

`opencode/gpt-5.x` works · `opencode-go/gpt-5.x` fails "Model not supported" · `opencode-zen/gpt-5.x` HTTP 400 (chat/completions, not /v1/responses). Details: `provider-catalog` skill §Known quirks.

## Related skills

`bootstrap-diagnostics` (actionable session-start lines), `harness-adapters` (spawn/recovery), `stuck-crewmate-recovery`, `firstmate-coding-guidelines`, `axi` (TOON discipline). See `references/SKILLS.md`.
