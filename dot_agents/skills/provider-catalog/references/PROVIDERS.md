# Provider & Model Catalog (agent-agnostic)

Shared reference for every agent that routes through Cloudflare AI Gateway `opencode` (BYOK). Per-agent chain design lives in that agent's config, not here. Live quota: use `quota-axi`.

## Chain preference (captain's standing directive — superseded 2026-09-01)

The historical "Lead PGS free band → paid-first through zen → go → GOAT → Z.AI → CF → OpenRouter → Zen → free tail" directive is **superseded for interactive chains** as of 2026-09-01 (decision A v5). The live ladders per agent live in each agent's own config:

- Opencode interactive chains — `~/.config/opencode/opencode-fallback.jsonc` (owner). Now the GLM-5.1 ladder (`big-pickle → opencode-go/glm-5.1 → commandcode/zai-org/GLM-5.2 → openrouter/z-ai/glm-5 → opencode-zen/glm-5.1`) on every `agents.*` and `categories.*` entry; PGS, Cloudflare Workers, Z.AI Coding Plan, and the openrouter `:free` trio are dropped.
- Pi default chain — `~/.pi/fallback-chains.json` → `default` key (added 2026-09-01). Same GLM-5.1 ladder; activates via `fallback/default` model string.
- Pi GATE chain — `~/.pi/fallback-chains.json` → `gate` key (unchanged 2026-09-01, gate-chain v4: openrouter `:free` trio first, gemini-2.5-flash demoted, `phoenixgrove/glm-5.3-flash` kept as manual tail; CF `@cf` and opencode-go excluded: no 1M models in either pool).

Reasoning effort stays low for targeted, well-understood work (e.g. no-mistakes review/fix steps); high reasoning is reserved for ambiguous investigation or design.

**no-mistakes reviewer pin (deterministic):** no-mistakes launches its pi reviewer via `agent_args_override` in `~/.no-mistakes/config.yaml` (tracked here as `dot_no-mistakes/config.yaml`): `[--no-context-files, --model, "fallback/gate"]` — the 1M-only cost-ordered ladder in `~/.pi/fallback-chains.json` (current order documented in the config's prose; see `dot_no-mistakes/config.yaml`). pi-fallback-provider activates on the `fallback/gate` model string: 429/5xx/timeout retryable, 400/401/403 non-retryable with 5-min provider cooldown.

## Cheapest-qualified-lane dispatch rule (spawn selection)

- **Rule:** when a dispatch resolves to multiple *qualified* lanes — lanes that
  meet the task's reasoning-class, capability, and runway gates — prefer the
  cheapest qualified lane, ranked by blended tokens-per-dollar from the current
  catalog snapshot (`models.snapshot.json` in this skill; per-provider rates in
  `PROVIDERS.md` — never duplicated elsewhere).
- **Scope:** applies to dispatch-time selection among eligible lanes
  (unbound sessions and utility classes). Pinned classes keep their pins;
  cheapest-qualified never downgrades a reasoning-class requirement.
- **Relationship to the fallback ladder:** this rule picks the lane *before*
  work starts; the fallback ladder is reactive, stepping only after the active
  lane fails or exhausts. A cheapest-lane choice does not reorder the ladder.

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

## Gemini 2.5 Flash — limits surfaced live (2026-08-30)

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

## PGS coding tester plan (2026-09-01)

Captain holds a PGS coding tester plan covering `deepseek-v4-flash-0731` + `glm-5.3-flash`. Key: `~/.agents/keys/phillias/.phoenixgrove-coding-plan-key` (pgsk_…; deployed to the `phillias` keys profile). Verified plan behavior:

- baseURL unchanged (`https://api.pgsgrove.com/v1`) — zero client config changes; the key swap is a dashboard BYOK update on the gateway's custom-phoenixgrove upstream.
- `/v1/usage` (HTTP 200) returns percent-based windows: `weekly_used_percent`, `daily_used_percent`, `api_share_of_weekly_percent`, `weekly_resets_at` (2026-09-08T01:56Z). No bank/credits endpoint.
- Plan models complete while usage stays 0% → plan-subsidized, NOT per-token. The old PGS key bills per-token (insufficient-credits errors on 2026-08-31 were billing, not path/gateway).

## Free-model probe results (2026-08-31, via gateway)

- `opencode-zen/nemotron-3-ultra-free`: works, tool-calling verified (function call, finish=tool_calls) — best free agentic model.
- `opencode-zen/deepseek-v4-flash-free`: FreeUsageLimitError (busy, retryable).
- `opencode-zen/gemini-3-flash`: 500 via `custom-opencode-zen/v1` (opencode-zen passthrough slug = 400 Invalid provider).
- `custom-cloudflare` @cf lane: 502 code 2006 for both `@cf/zai-org/glm-4.7-flash` and `@cf/deepseek-ai/deepseek-v4-flash` (broken that day; recheck).
- phoenixgrove custom lane serves ~38 models (glm-4.7-flash, qwen-3.8-27b, gemma-4-31b respond); PGS bills per-token on the old key — treat PGS as paid except on the coding plan above.


## Free-lane probe results (2026-09-01, via gateway)

- `custom-nvidia-nim` (`https://integrate.api.nvidia.com/v1` upstream): `nvidia/nemotron-3-super-120b-a12b` 200 OK, 1M ctx. Whole nemotron-3 family on one free `nvapi-` key, BUT ~40 RPM is **account-wide** across all NIM models (shared pool, no SLA, increases never granted) — gate/aux lane, not workhorse. Catalog churns: `nemotron-3-nano-30b-a3b` hit end-of-life 2026-09-01; verify slugs at call time.
- `google-ai-studio` (native gateway provider, BYOK): works via the **native path only** — `/google-ai-studio/v1beta/models/gemini-3.6-flash:generateContent` → 200. The OpenAI-compat `/v1/chat/completions` on that route 404s. Free tier is `$0` tokens with no billing, but the hard wall is **20 requests/day/model/project** (see the Gemini limits section above) — light fallback only, never a pipeline primary.
- `cerebras` (native gateway provider, BYOK): works after paygo migration (+$5 credit, card linked). `gpt-oss-120b` → 200. Live envelope: **5 RPM / 150 per hour / 2,400 RPD, 30K TPM / 1M TPD** — low request rate, big token budget: large single completions, not tool loops. `zai-glm-4.7` is now `model_archived` — Cerebras free catalog is effectively gpt-oss-120b only and churns repeatedly; never hardcode a lone Cerebras model id.
- `custom-phoenixgrove` route verified 2026-09-01 (200) — phoenixgrove now transits the gateway (`custom-phoenixgrove/v1`) instead of direct `api.pgsgrove.com`.
- Workers AI GLM is **metered**, not free: `@cf/zai-org/glm-5.3` $1.40/$4.40 per M in/out, `glm-5.3-flash` $0.15/$0.50 (REST models/search pricing, verified 2026-09-01). The 10K Neurons/day free allowance evaporates instantly on 120B-class agent traffic — avoid GLM on Workers AI for free lanes.
- **GitHub Models: fully retired 2026-07-30** (changelog; live brownout 410 `github_models_retirement_brownout` confirmed 2026-09-01). Do not wire it anywhere.

## Gate chain (pi-fallback-provider)

Chain order is owned by `private_dot_pi/fallback-chains.json` and summarized in `dot_no-mistakes/config.yaml` (gate-chain v4: openrouter :free trio first, gemini-2.5-flash demoted after live performance issues, `phoenixgrove/glm-5.3-flash` kept as manual tail). CF @cf and opencode-go excluded: no 1M models in either pool. opencode-zen gemini-3.5-flash is PAID (zen free tier is sub-1M only).
