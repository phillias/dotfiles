# Provider & Model Catalog (agent-agnostic)

Shared reference for every agent that routes through Cloudflare AI Gateway `opencode` (BYOK). Per-agent chain design lives in that agent's config, not here. Live quota: use `quota-axi`.

## Global chain preference (captain's standing directive)

Every agent constructs its fallback chain to match this ladder; implementation mechanics (chain files, retry semantics) stay agent-specific.

1. **Lead:** `phoenixgrove/glm-5.3-flash` (PGS free band, gateway-proxied) — preferred working model.
2. **Then paid-first:** `opencode-zen/big-pickle` → `opencode-go` models → commandcode (GOAT) → zai-coding → cloudflare @cf → openrouter GLM-5.
3. **Tail:** free pools (zen free, phoenixgrove) as last resort.

Reasoning effort stays low for targeted, well-understood work (e.g. no-mistakes review/fix steps); high reasoning is reserved for ambiguous investigation or design.

**no-mistakes reviewer pin (deterministic):** no-mistakes launches its pi reviewer via `agent_args_override` in `~/.no-mistakes/config.yaml` (tracked here as `dot_no-mistakes/config.yaml`): `[--no-context-files, --model, "fallback/gate"]` — the 1M-only cost-ordered ladder in `~/.pi/fallback-chains.json` (chain v2 below). pi-fallback-provider activates on the `fallback/gate` model string: 429/5xx/timeout retryable, 400/401/403 non-retryable with 5-min provider cooldown.

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

## Gemini as gate primary — limits surfaced live (2026-08-30)

**Model:** `gemini/gemini-2.5-flash` — Google Generative AI (AI Studio), native `google-generative-ai` API type in pi. Input 1,048,576 tok (real 1M), output 65,536, ~0.6 s latency. Key: `~/.config/opencode/.google-key` (AQ.* OAuth-derived token; captain handles rotation on expiry).

**pi wiring rule (verified):** the provider MUST declare `"api": "google-generative-ai"` with `baseUrl https://generativelanguage.googleapis.com/v1beta`. pi's `openai-completions` path 400s against Gemini's OpenAI-compat endpoint: pi (OpenAI SDK) sends OpenAI-only fields — `store: false`, `max_completion_tokens`, `stream_options` — that Gemini's compat layer rejects, and pi 0.84.2 has no compat flag to strip them. The native API type avoids the whole class.

**Surfaced limit (hard wall):** free tier is `GenerateRequestsPerDayPerProjectPerModel-FreeTier = 20 requests/day/model/project`. A no-mistakes run costs ~10–30 model calls across review/test/document/lint/PR agents → **one busy run exhausts the daily budget**. Gemini free tier cannot be a pipeline primary; use as light fallback, or move the Google key to AI Studio paid tier (removes the 20/day wall).

**Reliability quirk:** gemini-2.5-flash intermittently wraps its structured JSON in markdown code fences (```json …```), which pi's output parser rejects → step-level parse failures, nondeterministic (retries usually pass). Treat as a tax when it drives structured-output steps.

**Long-term free 1M-context candidates (ranked):**
1. **`opencode/gemini-3-flash`** via the opencode (zen Console) provider — 1M context, standing free tier (not a promo window), and Console free-tier limits are per-model, so it has its own window separate from big-pickle.
2. **Google AI Studio free** (native key, above) — 20/day wall.
3. **OpenRouter `:free` models with 1M ctx** (e.g. gemini-2.5-flash:free) — 1000/day shared free-tier bucket only while the account holds a $10+ credits balance ("high-balance" tier; our key is exhausted, so currently 50/day).

## Known quirks

- `zai-coding` uses `/v4` in the gateway URL (all others `/v1`).
- `openrouter` keeps the native passthrough slug (`openrouter/`, not `custom-openrouter/`).
- GPT routing (opencode): `opencode/gpt-5.x` works · `opencode-go/gpt-5.x` fails "Model not supported" · `opencode-zen/gpt-5.x` HTTP 400 (chat/completions, not `/v1/responses`).

## pi retry semantics (pi-fallback-provider)

Non-retryable: 400/401/403. Retryable: 429/5xx/timeout. Provider cooldown after failure: 5 min. Per-request timeout: 10 s. Chains referenced as `fallback/<name>` in `~/.pi/agent/settings.json`.

## Live statuses (dated; verify with quota-axi)

- 2026-08-30: big-pickle → FreeUsageLimitError (falls through); zai-coding → 429, weekly reset 2026-09-02.


## Gate chain v2 — 1M-only, cost-ordered (2026-08-30, captain-ordered)

`fallback/gate` chain (pi-fallback-provider): gemini-2.5-flash (AI Studio free) →
openrouter :free nemotron-3.5-lightning / minimax-m3 / inkling (1M, $0; 1000/day
bucket needs $10+ credits balance, else 50/day) → GOAT pool gpt-5.6-luna
($0.10/$0.60, cheapest paid 1M), GLM-5.2, nemotron-3-ultra, Kimi-K3,
deepseek-v4-flash → openrouter gpt-5.6-luna → zen gemini-3.5-flash (rate
unverified) → phoenixgrove glm-5.3-flash tail. CF @cf and opencode-go excluded:
no 1M models in either pool. opencode-zen gemini-3.5-flash is PAID (zen free
tier is sub-1M only). Model-registry entries added to pi models.json for every
chain id; openrouter :free ids verified live (429 with remaining:0 at vet time).
