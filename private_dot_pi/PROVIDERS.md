# Pi Provider & Model Catalog (pi-specific)

Live provider + model reference for pi agent (`~/.pi/agent/models.json` + `~/.pi/fallback-chains.json`). The opencode-wide catalog lives in `~/.agents/skills/opencode-config/references/PROVIDERS.md`; this file covers only what pi uses. All providers route through Cloudflare AI Gateway `opencode`.

## Fallback chain — `gate` (paid-first, 13 steps)

| # | Provider / model | Lane |
|---|---|---|
| 1 | opencode-zen / big-pickle | paid (Zen sub) |
| 2 | opencode-go / kimi-k2.6 | paid (GO sub) |
| 3 | opencode-go / deepseek-v4-flash | paid (GO sub) |
| 4 | commandcode / moonshotai/Kimi-K2.6 | paid (GOAT) |
| 5 | commandcode / deepseek/deepseek-v4-flash | paid (GOAT) |
| 6 | zai-coding / glm-5.2 | paid (credits) |
| 7 | cloudflare / @cf/moonshotai/kimi-k2.7-code | Workers AI (free tier) |
| 8 | cloudflare / @cf/zai-org/glm-4.7-flash | Workers AI (free tier) |
| 9 | openrouter / z-ai/glm-5 | pay-per-token overflow |
| 10 | opencode-zen / deepseek-v4-flash-free | free pool |
| 11 | opencode-zen / nemotron-3-ultra-free | free pool |
| 12 | phoenixgrove / glm-5.3-flash | free pool |
| 13 | phoenixgrove / deepseek-v4-flash | free pool |

## Gateway routing (BYOK)

All baseUrls sit under `https://gateway.ai.cloudflare.com/v1/a7fa198dd5b359a187c671064fe6b36e/opencode/…` with header `cf-aig-gateway-id: opencode` and apiKey `$CF_AI_GATEWAY_TOKEN` (exported from `~/.zshenv`, reading `~/.config/opencode/.cf-ai-gw-token`).

| Provider | URL segment | Notes |
|---|---|---|
| opencode-zen | `custom-opencode-zen/v1` | |
| opencode-go | `custom-opencode-go/v1` | |
| commandcode | `custom-commandcode/v1` | |
| zai-coding | `custom-zai-coding/v4` | `/v4`, not `/v1` |
| cloudflare | `custom-cloudflare/v1` | @cf lane |
| openrouter | `openrouter/v1` | native passthrough slug, NOT `custom-` |
| phoenixgrove | `custom-phoenixgrove/v1` | |

BYOK keys live in the gateway dashboard (alias `default`); pi authenticates with the gateway token only, which the gateway does not forward upstream.

## Retry semantics (pi-fallback-provider)

Non-retryable: 400/401/403. Retryable: 429/5xx/timeout. Provider cooldown after failure: 5 min. Per-request timeout: 10 s. Chains are referenced as `fallback/<name>` in `~/.pi/agent/settings.json` (pi-fallback-provider package).

Known live statuses (2026-08-30): big-pickle → FreeUsageLimitError (falls through); zai-coding → 429, weekly reset 2026-09-02.
