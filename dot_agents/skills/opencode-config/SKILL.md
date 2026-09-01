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
| OS dependencies (gh, bw, wrangler, sqlite, mise, ...) | `references/DEPENDENCIES.md` |
| Model snapshot (drift baseline) | `~/.agents/skills/provider-catalog/models.snapshot.json` |

## Critical rules

1. One config, no profiles; `OPENCODE_CONFIG_DIR` unset.
2. `~/.config/opencode/opencode.json` defines live providers + MCPs.
3. `opencode-fallback.jsonc` owns agent/category/global routing; `oh-my-openagent.jsonc` is a legacy orphan never read.
4. Global default fallback — project > global first-match-wins.
5. Plugins auto-load; retired plugins enforced-removed.
6. No symlinks, no env switching; machine diffs via chezmoi `.tmpl`, paths always `$HOME`/`%h` (never `/home/<user>`).

## Chain at a glance (paid-first, 2026-08-29)

`opencode-zen/big-pickle` → OpenCode Go (kimi-k2.6, ds-v4-flash) → Command Code GOAT (Kimi-K2.6, DS-V4-Flash) → **Z.AI Coding Plan Lite** (GLM-5.2, credits-based, 0.5× off-peak ET) → **Cloudflare** (REST `/ai/v1`, @cf lane; kimi-k2.7-code, glm-4.7-flash) → **OpenRouter** (cheapest GLM-5 per-token) → Zen free (deepseek-v4-flash-free, nemotron-3-ultra-free) → free providers (Phoenix Grove Everyday-band free: glm-5.3-flash, ds-v4-flash; nvidia, openrouter, baseten) → `google/gemini-2.5-flash`. Six providers (zen, go, commandcode, zai, openrouter, phoenixgrove) route through gateway `opencode` via BYOK — gateway token in `Authorization`, stored keys inject upstream. Full taxonomy + agent/category tables: `references/AGENTS.md`. Design rationale: `references/DESIGN.md` §2.6.

Provider/model facts (stack, gateway routing, BYOK, pricing, quotas, quirks) are owned by the `provider-catalog` skill (`references/PROVIDERS.md` is a stub pointer to it) — load `provider-catalog` when needed; opencode-specific provider mechanics live in `references/DESIGN.md` §8.

## Config defaults (live)

`small_model: opencode-zen/nemotron-3-ultra-free` · compaction `{auto:false, prune:true, reserved:50000, tail_turns:40}` · MCP baseline: context7, grep_app, websearch, mcp_everything · TUI theme tokyonight. Stale doc text in older copies says `google/gemini-2.0-flash` — live value wins.

## Key files

`opencode.json` (root) · `opencode-fallback.jsonc` (chain) · `dispatch-rules.json` (30 rules) · `plugins/opencode-runtime-fallback.ts` + `lib/opencode-runtime-fallback-core.ts` · `lib/opencode-rest-api-provider.test.ts` (contract: @cf lane + gateway-routed provider assertions) · `~/.local/state/opencode-fleet/fallback.json` (live state) · `scripts/catalog-drift.mjs` + `fm-drift-pr.sh` · systemd `catalog-drift.{service,timer}` · `~/.agents/skills/provider-catalog/models.snapshot.json` · `~/.agents/skills/` · `.cf-ai-gw-token` (gateway token — covers both `/ai/*` and `/ai-gateway/*` planes; `.cloudflare-key` has AI Gateway Edit/Run + Read, Read added 2026-08-29).

## Maintenance

- **Edit config** → `chezmoi diff` → `chezmoi re-add` → commit via `/dotfiles` (or drift-PR gate for chains).
- **Add API key** → key file → `{env:VAR}` match in opencode.json → shell profiles → `chezmoi add --encrypt`.
- **Add MCP** → opencode.json `mcp` → re-add → commit.
- **Chain edits** flow through `bin/fm-drift-pr.sh` (DRIFT gate = captain approval), never direct master writes.

## GPT model routing

`opencode/gpt-5.x` works · `opencode-go/gpt-5.x` fails "Model not supported" · `opencode-zen/gpt-5.x` HTTP 400 (chat/completions, not /v1/responses). Details: `provider-catalog` skill §Known quirks.

## Related skills

`bootstrap-diagnostics` (actionable session-start lines), `harness-adapters` (spawn/recovery), `stuck-crewmate-recovery`, `firstmate-coding-guidelines`, `axi` (TOON discipline). See `references/SKILLS.md`.
