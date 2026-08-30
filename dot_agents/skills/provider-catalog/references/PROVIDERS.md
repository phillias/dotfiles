# Provider & Model Catalog (agent-agnostic)

Shared reference for every agent that routes through Cloudflare AI Gateway `opencode` (BYOK). Per-agent chain design lives in that agent's config, not here. Live quota: use `quota-axi`.

## Gateway routing (BYOK)

All baseUrls sit under `https://gateway.ai.cloudflare.com/v1/a7fa198dd5b359a187c671064fe6b36e/opencode/…` with header `cf-aig-gateway-id: opencode` and the gateway token.

**Token:** `$CF_AI_GATEWAY_TOKEN` (exported from `~/.zshenv`, reading `~/.config/opencode/.cf-ai-gw-token`). The token covers both the `/ai/*` (Workers AI REST) and `/ai-gateway/*` planes. BYOK upstream keys live in the gateway dashboard (alias `default`); clients authenticate with the gateway token only, which the gateway does not forward upstream.

| Provider | URL segment | Notes |
|---|---|---|
| opencode-zen | `custom-opencode-zen/v1` | primary quality (big-pickle) + free tier |
| opencode-go | `custom-opencode-go/v1` | subsidized pool (kimi-k2.6, deepseek-v4-flash) |
| commandcode | `custom-commandcode/v1` | GOAT paid pool (Kimi-K2.6, DS-V4-Flash) |
| zai-coding | `custom-zai-coding/v4` | Z.AI Coding Plan Lite; **`/v4`, not `/v1`** |
| phoenixgrove | `custom-phoenixgrove/v1` | GLM-5.3-flash, deepseek-v4-flash |
| openrouter | `openrouter/v1` | native passthrough slug, **NOT `custom-`** |
| cloudflare | `custom-cloudflare/v1` | @cf lane (Workers AI, free tier) |

**URL version-segment rule:** the gateway strips a trailing version-like segment from the custom provider's `base_url` before appending the request path; carrying the version in the request URL restores correctness.

## Provider roles

| Provider | Role | Cost |
|---|---|---|
| opencode-zen | primary quality (big-pickle) + free tier | free ~200/day / paid |
| opencode-go | subsidized pool | $5 first mo → $10/mo |
| commandcode (GOAT) | paid pool | $10/mo → usage |
| zai-coding | Z.AI Coding Plan Lite, credits-based | $18/mo |
| phoenixgrove | GLM-5.3 exclusive band, free + paid tiers | $4–$195/mo / $5+ per-token |
| cloudflare | Workers AI @cf lane, free tier | $0 |
| openrouter | GLM-5 overflow + free ladder | $0 / pay |

## Model ids

Model ids are the upstream API model names sent through the gateway verbatim — never rename them. Display names may carry a `· CF GW` marker (pi), but pi's picker shows `id [provider]` regardless.

## Known quirks

- `zai-coding` uses `/v4` in the gateway URL (all others `/v1`).
- `openrouter` keeps the native passthrough slug (`openrouter/`, not `custom-openrouter/`).
- GPT routing (opencode): `opencode/gpt-5.x` works · `opencode-go/gpt-5.x` fails "Model not supported" · `opencode-zen/gpt-5.x` HTTP 400 (chat/completions, not `/v1/responses`).

## pi retry semantics (pi-fallback-provider)

Non-retryable: 400/401/403. Retryable: 429/5xx/timeout. Provider cooldown after failure: 5 min. Per-request timeout: 10 s. Chains referenced as `fallback/<name>` in `~/.pi/agent/settings.json`.

## Live statuses (dated; verify with quota-axi)

- 2026-08-30: big-pickle → FreeUsageLimitError (falls through); zai-coding → 429, weekly reset 2026-09-02.
