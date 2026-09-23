# Provider & Model Catalog (agent-agnostic)

Shared reference for every agent that routes through Cloudflare AI Gateway `opencode` (BYOK). Per-agent chain design lives in that agent's config, not here. Live quota: use `quota-axi`.

## Chain preference (captain's standing directive — superseded 2026-09-01)

The historical "Lead PGS free band → paid-first through zen → go → GOAT → Z.AI → CF → OpenRouter → Zen → free tail" directive is **superseded for interactive chains** as of 2026-09-01 (decision A v5). The live ladders per agent live in each agent's own config:

- Opencode interactive chains — `~/.config/opencode/opencode-fallback.jsonc` (owner). Two-path architecture (captain decision 2026-09-19, PRs #327 + #330): utility chains are `dynamic/TUI` (gateway cascading GLM ladder) → `opencode-go/glm-5.1` → `opencode-go/deepseek-v4-flash` (session-gated direct-client tail); specialized agents/categories keep pinned chains.
- Pi default chain — `~/.pi/fallback-chains.json` → `default` key (added 2026-09-01). Same GLM-5.1 ladder; activates via `fallback/default` model string.
- Pi GATE chain — `~/.pi/fallback-chains.json` → `gate` key. Current shape: `CfAiGw/dynamic/pr-gate` → `opencode-go-gw/deepseek-v4-flash` (see the Gate chain section; the 2026-09-01 gate-chain v4 record was superseded when the openrouter `:free` trio was removed after no-mistakes run deaths — that lane class is documented in the pr-gate entry).

Reasoning effort stays low for targeted, well-understood work (e.g. no-mistakes review/fix steps); high reasoning is reserved for ambiguous investigation or design.

**no-mistakes reviewer pin (deterministic):** the pi model pin lives in `~/.no-mistakes/config.yaml` (tracked here as `dot_no-mistakes/config.yaml`) — `agent_config.pi.model` for all steps and `review_agents.reviewer.model` for the reviewer both pin `opencode-go-gw/deepseek-v4-flash` (1M context, session-gated subsidized pool, riding pi via the opencode-go-gw static header). The pin moved out of `agent_args_override` on 2026-09-14: native argv always wins over the same knob, which silently nullified the reviewer pin and left review riding `fallback/gate` → dynamic/pr-gate (see the config's prose). The `fallback/gate` 1M ladder string in `~/.pi/fallback-chains.json` remains for manual pi use; pi-fallback-provider semantics there: 429/5xx/timeout retryable, 400/401/403 non-retryable with 5-min provider cooldown.

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

**Token:** `$CF_AI_GATEWAY_TOKEN` (exported from `~/.zshenv`, reading `.cf-ai-gw` from the default keys profile — `~/.agents/keys/$(readlink ~/.agents/keys/default)/.cf-ai-gw`). The token covers both the `/ai/*` (Workers AI REST) and `/ai-gateway/*` planes. BYOK upstream keys live in the gateway dashboard (alias `default`); clients authenticate with the gateway token only, which the gateway does not forward upstream.

| Provider | URL segment | Notes |
|---|---|---|
| opencode-zen | `custom-opencode-zen/v1` | primary quality (big-pickle) + free tier |
| opencode-go | `custom-opencode-go/v1` | subsidized pool (kimi-k2.6, deepseek-v4-flash). **Session-gated 2026-09-08**: requests require a per-conversation `x-opencode-session` header; a static config header cannot satisfy it. Direct-client use only (opencode/pi send it natively) — EXCLUDES opencode-go models from gateway dynamic routes and any static-header custom-provider hop. Clean 400 `MissingSessionID` otherwise. |
| commandcode | `custom-commandcode/v1` | GOAT paid pool (Kimi-K2.6, DS-V4-Flash) |
| zai-coding | `custom-zai-coding/v4` | Z.AI Coding Plan Lite; **`/v4`, not `/v1`** |
| phoenixgrove | `custom-phoenixgrove/v1` | GLM-5.3-flash, deepseek-v4-flash |
| openrouter | `openrouter/v1` | native passthrough slug, **NOT `custom-`** |
| cloudflare | `custom-cloudflare/v1` | @cf lane (Workers AI, free tier) |
| abliteration-ai | `custom-abliteration-ai/v1` | unrestricted reasoning models (abliterated-model, abliterated-model-large) |

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
| typesafe-ai | System One evaluation (Jev) — fast structured decisions | $0.042/MTok input, output free |
| abliteration-ai | unrestricted reasoning models | $1–$3/MTok input, $3–$5/MTok output |
| tsfm-ai | Hosted time-series foundation models (54 models, 16 families) — not a chat provider | $0.00025/forecast (flat) |

## Model ids

Model ids are the upstream API model names sent through the gateway verbatim — never rename them. Display names may carry a `· CF GW` marker (pi), but pi's picker shows `id [provider]` regardless.

## TypeSafe Jev (System One evaluation model)

**Provider:** `typesafe-ai` — native provider for Jev evaluation model

**Access:**
- Direct API: `POST https://api.typesafe.ai/v1/systemone` with `TYPESAFE_API_KEY` (waitlist)
- Vercel AI Gateway: Model ID `typesafe-ai/jev` with `AI_GATEWAY_API_KEY` (immediate, no waitlist)
- CF AI Gateway: Custom provider (dashboard BYOK setup, base URL `api.typesafe.ai/v1`)

**Pricing:** $0.042/MTok input, output free (too cheap to meter)

**Model IDs:**
- `jev-latest` — stable alias (SDK default)
- `jev-preview` — preview builds
- `jev-1.13.0` — pin for production (response includes versioned ID)

**Status (2026-09-18):** Vercel AI Gateway provides immediate access. Direct TypeSafe API requires waitlist acceptance.

**Capabilities:**
- Question types: Choice (pick from list), Score (rubric), Boolean (probability)
- Parallel evaluation: all questions in single call
- Calibrated confidence: probability distributions match outcomes (RLCD training)
- Speed: 70–500ms end-to-end, ~100ms typical
- Context: 32K input budget (documented 32,768 tokens)

**Limitations:**
- Cannot generate prose, code, or explanations
- Output is strictly structured (cannot invent values outside schema)
- No image input
- No chat interface

**Use cases:**
- Task routing and classification
- Finding triage (severity, auto-fixable, needs-human)
- Mention classification (spam, mention_type, safe_to_reply)
- Escalation decisions (genuinely_ambiguous, blast_radius)
- Guardrail verification (policy violations, jailbreak detection)
- Model selection routing (reasoning needed, profile fit)

**Integration pattern (cascade):**
```
Jev (fast, cheap) → Classify/route
   ↓ (low confidence cases)
Frontier model (slow, expensive) → Handle ambiguous cases
   ↓ (needs prose)
LLM (text generation) → Write output
```

**Example request (direct API):**
```bash
curl -X POST https://api.typesafe.ai/v1/systemone \
  -H "Authorization: Bearer $TYPESAFE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "jev-latest",
    "state": "The support agent issued a full refund to the customer.",
    "questions": {
      "refunded": { "type": "boolean", "instructions": "Was a refund issued?" },
      "severity": { "type": "choice", "instructions": "Severity level",
        "criteria": { "critical": "Breaks build/tests", "warning": "Style/best-practice", "info": "Nitpick" }},
      "needs_human": { "type": "boolean", "instructions": "Requires human judgment?" }
    }
  }'
```

**Response structure:**
```json
{
  "model": "jev-1.13.0",
  "answers": {
    "refunded": { "type": "boolean", "noul": 0.99 },
    "severity": { "type": "choice", "choice": "warning", "confidence": 0.95 },
    "needs_human": { "type": "boolean", "noul": 0.12 }
  }
}
```

## Abliteration AI — unrestricted reasoning models (2026-09-18)

**Provider:** `abliteration-ai` — native provider for unrestricted reasoning models

**Access:**
- Direct API: `POST https://api.abliteration.ai/v1/chat/completions` with `ABLITERATION_API_KEY` (starts with `ak_`)
- CF AI Gateway: Custom provider (dashboard BYOK setup, base URL `api.abliteration.ai/v1`)
- OpenAI SDK compatible: Set `baseURL: "https://api.abliteration.ai/v1"`

**Model IDs:**
- `abliterated-model` — general-purpose, multimodal (text + image), 256K context, bf16 quantization
- `abliterated-model-large` — frontier-scale reasoning, text-only, 1M context, fp8 quantization
- `abliterated-model-large-v2` — updated large variant (2026-09-18), same specs as large

**Pricing:**
- `abliterated-model`: $1/MTok input, $3/MTok output, $0.10/MTok cached read
- `abliterated-model-large`: $3/MTok input, $5/MTok output, $0.30/MTok cached read
- Same pricing for `abliterated-model-large-v2`

**Context & Limits:**
| Model | Context | Max Output | Modalities |
|---|---|---|---|
| `abliterated-model` | 262,144 | 262,134 | text, image |
| `abliterated-model-large` | 1,000,000 | 999,990 | text |
| `abliterated-model-large-v2` | 1,000,000 | 999,990 | text |

**Supported Features:**
- Tools (function calling)
- JSON mode & structured outputs
- Logprobs
- Web search
- Reasoning tokens
- Streaming (SSE)
- Prompt caching

**Sampling Parameters:**
- `temperature`: 0–2 (large: 0–1)
- `top_p`: 0–1
- `top_k`, `min_p`: supported
- `frequency_penalty`, `presence_penalty`, `repetition_penalty`
- `stop`, `seed`, `max_tokens`, `logit_bias`

**Status (2026-09-18):** Live API with immediate access via API key. Credit-based billing with remaining_credits field in response.

**Use Cases:**
- Hard reasoning workloads requiring frontier-scale compute
- Evaluation tasks needing 1M context
- Multimodal inference (abliterated-model only)
- Scenarios requiring unrestricted model behavior

**Example request:**
```bash
curl https://api.abliteration.ai/v1/chat/completions \
  -H "Authorization: Bearer $ABLITERATION_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "abliterated-model",
    "messages": [{"role": "user", "content": "Explain quantum computing in one sentence"}],
    "max_tokens": 128,
    "temperature": 0.7
  }'
```

**Response structure:**
```json
{
  "id": "chatcmpl-abc123",
  "object": "chat.completion",
  "created": 1781324687,
  "model": "abliterated-model",
  "choices": [{
    "index": 0,
    "message": {
      "role": "assistant",
      "content": "Quantum computing leverages superposition and entanglement..."
    },
    "finish_reason": "stop"
  }],
  "usage": {
    "prompt_tokens": 12,
    "completion_tokens": 28,
    "total_tokens": 40
  },
  "remaining_credits": 48,
  "estimated_credits_used": 1,
  "estimated_cost_usd": 0.000105
}
```

## TSFM.ai — Time Series Foundation Model inference (2026-09-18)

**Provider:** `tsfm-ai` — hosted inference for 54 time-series foundation models across 16 families.

**Not a chat/completions provider** — TSFM.ai serves a dedicated `/v1/forecast` endpoint for zero-shot time-series forecasting. It does NOT route through the CF AI Gateway (different API shape). Use directly.

**Access:**
- Endpoint: `POST https://api.tsfm.ai/v1/forecast`
- Auth: `Bearer $TSFM_API_KEY` (key at `~/.agents/keys/default/.tsfm-key`, loaded in both `.bashrc` and `.zshrc`)
- Model catalog: `GET https://api.tsfm.ai/api/models` (54 models, all $0.00025/forecast)
- OpenAI-compat model list: `GET https://api.tsfm.ai/v1/models`
- No GPU provisioning required — fully hosted, autoscaling, 99.9% uptime SLA

**Verified (2026-09-18):** API key works. Live forecast test on `google/timesfm-2.5-200m-pytorch` returned 21-step forecast with 9 quantile levels in 27ms (790 tokens, $0.00025).

**Pricing:** Flat $0.00025 per forecast request, regardless of model. No per-token billing. Free tier included (no credit card required for signup).

**Request format (canonical):**
```json
{
  "model": "google/timesfm-2.5-200m-pytorch",
  "inputs": [{
    "start": "2025-01-01T00:00:00Z",
    "target": [[450.0], [451.2], [449.8], ...],
    "metadata": {"item_id": "SPY"}
  }],
  "parameters": {
    "prediction_length": 21,
    "frequency": "B",
    "quantile_levels": [0.1, 0.5, 0.9]
  }
}
```

Key format detail: `target` is **always 2D** — `[[val], [val], ...]` (outer=time, inner=channels). Univariate uses length-1 inner arrays. Passing 1D arrays returns 422.

**Response format:**
```json
{
  "id": "...", "object": "forecast", "model": "google/timesfm-2.5-200m-pytorch",
  "horizon": 21, "prediction_length": 21,
  "quantile_levels": [0.1, 0.5, 0.9],
  "input_points": 252,
  "outputs": [{
    "mean": [[482.05], [482.82], ...],
    "quantile_predictions": [
      {"level": 0.1, "values": [[481.70], ...]},
      {"level": 0.5, "values": [[480.43], ...]},
      {"level": 0.9, "values": [[487.68], ...]}
    ],
    "timestamps": ["2025-12-29T00:00:00Z", ...],
    "metadata": {"item_id": "SPY"}
  }],
  "usage": {"input_tokens": 706, "output_tokens": 84, "total_tokens": 790},
  "latency_ms": 27
}
```

**TimesFM model availability (2026-09-18):**

| Model ID | Params | Context | Max Context | GPU | Status |
|---|---|---|---|---|---|
| `google/timesfm-2.0-500m-pytorch` | 500M | 2,048 | 2,048 | T4 | available |
| `google/timesfm-2.5-200m-pytorch` | 200M | 16,384 | 16,384 | T4 | available |
| `google/timesfm-3.0-pytorch` | 330M | 16,384 | 16,384 | — | **NOT hosted** |

TimesFM-3 is NOT available on any hosted inference provider. The weights are non-commercial license (`timesfm-non-commercial-license-v1.0`), which blocks commercial hosting. TSFM.ai has a blog post analyzing TimesFM-3 but confirmed via live API query: zero TimesFM-3 models in catalog. Google's BigQuery integration for TimesFM-3 is announced "in coming weeks" — that may provide a commercial path.

**Best models for financial time-series (Gambit use case):**

| Model ID | Family | Params | Context | Why |
|---|---|---|---|---|
| `google/timesfm-2.5-200m-pytorch` | TimesFM | 200M | 16,384 | Longest context, quantile support, covariates |
| `google/timesfm-2.0-500m-pytorch` | TimesFM | 500M | 2,048 | Higher capacity, shorter context |
| `Salesforce/moirai-1.1-R-large` | Moirai | 311M | 8,192 | Native multivariate (Any-Variate Attention) |
| `Salesforce/moirai-1.1-R-base` | Moirai | 91M | 8,192 | Balanced multivariate quality/cost |
| `amazon/chronos-2` | Chronos | — | 8,192 | Strong zero-shot, Apache-2.0 licensed |
| `NX-AI/TiRex-2` | TiRex | — | 8,192 | Multivariate xLSTM with covariates, streaming state |

For Gambit's multivariate alpha forecasting: `Salesforce/moirai-1.1-R-large` is the best commercially-licensed, natively multivariate option. Use `google/timesfm-2.5-200m-pytorch` for long-context univariate forecasting (16K points = ~64 trading days of minute data or ~65 years of daily data).

**Full model catalog (54 models, 16 families):**
Chronos (6), Cisco TSM (1), Granite FlowState (2), Granite PatchTST (2), Granite TTM (2), Kairos (3), Kronos (3), Lag-Llama (1), MOMENT (3), Moirai (9), Sundial (1), TEMPO (1), TiRex (3), TimeMoE (2), Timer (1), Timer-S1 (1), TimesFM (2), TinyTimeMixer (1), Toto (6), YingLong (4). All $0.00025/forecast.

**Key env var:** `TSFM_API_KEY` — set in `~/.zshrc` from `~/.agents/keys/default/.tsfm-key`

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
- GPT routing (opencode): `opencode/gpt-5.x` works · `opencode-go/gpt-5.x` fails "Model not supported" · `opencode-zen/gpt-5.x` historically returned HTTP 400 (chat/completions, not `/v1/responses`); re-verified 2026-09-14 via `custom-opencode-zen/v1` compat: `gpt-5.6-luna` and `gpt-5.5` fail with HTTP 500 "Internal server error" — still broken; gateway dynamic routes ride `openrouter/openai/gpt-5.x` (or GOAT `custom-commandcode/gpt-5.x`) instead.

## pi retry semantics (pi-fallback-provider)

Non-retryable: 400/401/403. Retryable: 429/5xx/timeout. Provider cooldown after failure: 5 min. Per-request timeout: 10 s. Chains referenced as `fallback/<name>` in `~/.pi/agent/settings.json`.

## Live statuses (dated; verify with quota-axi)

- 2026-08-30: big-pickle → FreeUsageLimitError (falls through); zai-coding → 429, weekly reset 2026-09-02.
- 2026-09-14 (corrected same day, captain-confirmed): PGS is **Coding-Plan-only — the PAYG balance is intentionally exhausted**. Any phoenixgrove request outside plan coverage (model not on the plan list at that moment, or plan window exhausted) returns 402 `insufficient_quota` and falls through; that fallthrough is expected, not a fault. The plan key serves `glm-5.3-flash` and `deepseek-v4-flash-0731` (200) while plan-covered, and the gateway BYOK key IS the plan key — no dashboard swap needed. Phoenixgrove lanes therefore breathe: plan-covered periods serve, otherwise the ladder falls through one hop (~4 s tax). Watch coverage via `/v1/usage` percent windows (weekly 17.9%, daily 59.6% at 2026-09-14 morning).

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

Chain order is owned by `private_dot_pi/fallback-chains.json` and summarized in `dot_no-mistakes/config.yaml`. 2026-09-15 shape: `CfAiGw/dynamic/pr-gate` (the gateway's linear free-first ladder) → `opencode-go/deepseek-v4-flash` (1M, subsidized pool — **session-gated, rides pi directly, never a gateway route**). kimi-k2.6 excluded (262K < the gate's 1M bar). CF @cf excluded (no 1M models). opencode-zen gemini-3.5-flash is PAID (zen free tier is sub-1M only). Inkling was dropped from the chain 2026-09-15: OpenRouter's routing funnel rejected pi-shaped gate requests unreliably (403 non-agentic in production), the free endpoint logs all traffic for TM training, and confidential data is barred — the `openrouter-direct` pi provider entry remains for personal agentic experiments only. Harness-recognition reality (2026-09-15 live probes): the funnel checks **OpenRouter app-listing attribution**, not harness self-claims — codex-cli is rejected (403 "plug into an app listed on openrouter.ai/apps"; TM's announcement named Codex the OpenAI product, not the CLI), and codex-cli 0.153.4 is Responses-wire-only, which the gateway compat plane also rejects (code 2019) — so codex cannot ride inkling:free OR pr-gate. The codex→inkling path exists only via the PAID tier ($0.95/$4.05, no gate, no logging). Impersonating a listed app's attribution is off the table.

## Dynamic routes on the `opencode` gateway (2026-09-04)

The gateway runs named dynamic routes (CF "dynamic routing", OpenAI-compatible
endpoint `…/opencode/compat/chat/completions`, model string `dynamic/<name>`).
Route contents will churn — this catalog records *purpose*, not lane lists:

- `TUI` — daily-driver, budget GLM ladder (captain directive 2026-09-19):
  **Free → Subsidized → PAYG**, GLM 5.1 → 5.2 → 5.3-flash within tiers,
  NO opencode-go (session-gated — harness connections only, cannot be a
  gateway route node). Ladder (version `d7fcd73f`, deployed 2026-09-19):
  `custom-opencode-zen/glm-5.1` → `custom-opencode-zen/glm-5.2` →
  `custom-opencode-zen/glm-5.3-flash` → `custom-commandcode/zai-org/GLM-5.1`
  → `custom-phoenixgrove/glm-5.2` → `custom-commandcode/zai-org/GLM-5.2` →
  `custom-commandcode/z-ai/glm-5.3-flash` → `custom-phoenixgrove/glm-5.3-flash`
  → `openrouter/z-ai/glm-5.1` (PAYG tail). PGS nodes currently 402
  insufficient-credits (plan window) — they fall through until the plan
  resets; the ladder stays correct either way. Supersedes the 2026-09-09
  phoenixgrove-head order and the aihubmix tail (bare-name nodes were
  dead anyway).
- `high` — latest-version models (`GLM-5.3` class, fable, astra when a lane
  appears) from reliable providers; aihubmix GLM discount lane sits top
  (caution 2026-09-08: aihubmix began 200-wrapped 404s — verify before
  trusting that head lane).
- `pr-gate` — gate/background ladder, **linear** (conditionals removed
  2026-09-14 version `6ed05d99`; **openrouter `:free` lanes removed version
  `91701376`** after three no-mistakes run deaths): openrouter free lanes
  200-wrap Nvidia-pool overload errors ("Service temporarily overloaded") —
  the route's success edge passes the error body verbatim, killing runs
  exactly when the pool is loaded.   2026-09-20 status: **no-mistakes gate agent rides this route via pi
  `fallback/gate` chain** (dotfiles PR #343 restored the chain, previously
  pinned opencode-go-gw/deepseek-v4-flash directly after free NEMO head
  200-wrapped overload errors 6/6 nights runs). Review agent rides the
  separate `fallback/review` chain (CfAiGw/dynamic/pr-reviewer →
  vercel/vmc/pr-reviewer → opencode-go-gw/deepseek-v4-flash). The route
  serves gate, probe, and external traffic.
  Actual active ladder (version `91701376`, verified via versions API
  2026-09-20 — the earlier "GOAT nodes" wording in this file was a mislabel,
  those lanes are commandcode): `custom-nvidia-nim/nvidia/nemotron-3-super-120b-a12b` →
  `custom-opencode-zen/nemotron-3-ultra-free` →
  `openrouter/openai/gpt-5.6-luna` → `custom-commandcode/zai-org/GLM-5.2` →
  `custom-commandcode/moonshotai/Kimi-K3` →
  `custom-commandcode/nvidia/nemotron-3-ultra-550b-a55b` →
  `custom-commandcode/deepseek/deepseek-v4-flash` →
  `custom-phoenixgrove/deepseek-v4-flash-0731` → `google-ai-studio/gemini-2.5-flash`.
  Never add opencode-go nodes to any route: the upstream
  mandates x-opencode-session, which route nodes cannot send.
- `vision` — image-capable chat lanes (GLM-4.5V via together, gemini-2.5-flash
  via google-ai-studio, zen/openrouter gemini variants).
- `pr-reviewer` — no-mistakes review second-set-of-eyes ladder; the pi reviewer
  rides `CfAiGw/dynamic/pr-reviewer` via `review_agents.reviewer`
  (dotfiles PR #297). Budget-ranked, JSON discipline first (rebuilt 2026-09-14):
  `custom-nvidia-nim/deepseek-ai/deepseek-v4-flash-0731` →
  `openrouter/openai/gpt-5.6-luna` →
  `openrouter/nvidia/nemotron-3-ultra-550b-a55b:free` →
  `custom-opencode-zen/glm-5.2`. 2026-09-22: review rides this route again via
  the separate `fallback/review` chain (pi fallback-chains.json), with Vercel
  `vmc/pr-reviewer` as second rung and opencode-go as tail.
- Harness family routes (2026-09-19 build, captain directive — house models
  per family across providers, openrouter PAYG + plan lanes). 2026-09-20
  less-wrong pass (captain order, route versions deployed and probed 200):
  removed `kimi`'s bare `opencode-go/kimi-k2.6` node (opencode-go can never be
  a route node — upstream mandates x-opencode-session) plus its bare
  `opencode-zen` tail, and the bare `opencode-zen` heads on `claude`/`codex`/
  `grok` (zen no longer serves claude-sonnet-4, gpt-5.1, or grok-build-0.1 —
  probed 400/503); renamed `high`'s bare `aihubmix` nodes to `custom-aihubmix`
  (the documented bare-name rule). Live ladders: `claude` =
  `openrouter/anthropic/claude-sonnet-4`; `codex` =
  `custom-commandcode/gpt-5.6-luna` → `openrouter/openai/gpt-4o`; `grok` =
  `custom-commandcode/xai/grok-4.5` → `openrouter/x-ai/grok-4.5`; `kimi` =
  `custom-commandcode/moonshotai/Kimi-K2.6` →
  `openrouter/moonshotai/kimi-k2.6`; `high` = `custom-aihubmix/coding-glm-5.3`
  → `custom-aihubmix/claude-fable-5-1` → `custom-aihubmix/glm-5.3` →
  `custom-together` → `openrouter` → `custom-phoenixgrove` → `custom-friendli`
  → `custom-deepinfra` (GLM-5.3 lanes). `muse` =
  `custom-commandcode/meta/muse-spark-1.2` → `openrouter/meta-llama/llama-3.1-70b-instruct`.
  `cursor` is deployed **empty** (no model nodes) —
  blocked on the captain's cursor seat decision.
- `muse` rides Meta's Model API directly (api.meta.ai) as of muse 1.3.0:
  The orphaned `dynamic/muse` route and its pi catalog row were removed
  because they only served a Bedrock fallback tail, not actual muse traffic.
  Re-evaluate on every muse release.

Owner defaults (2026-09-04): pi `default` chain = `CfAiGw/dynamic/TUI`
exactly; pi `gate` chain = `CfAiGw/dynamic/pr-gate` exactly;
opencode.json `model` = `CfAiGw/dynamic/TUI` with the legacy local
ladder remaining as the fallback tail.

### Route management via REST — dynamic routes ARE token-manageable (2026-09-09)

Contrary to the earlier "dashboard-only" note for *custom providers*, dynamic
ROUTE graphs are fully token-manageable:

- `POST /accounts/{acc}/ai-gateway/gateways/{gw}/versions`
  (`{'elements': [...]}`) → new draft version.
- `POST …/routes/{route_id}/deployments` (`{'version_id': …}`) → deploys it
  live (instant rollback = deploy an older version_id).
- Verified 2026-09-09 by repairing the TUI route (poisoned head node, below).
- Every `model` node requires an explicit `outputs.fallback` (validation
  rejects the last node falling through implicitly — chain it to `END`).
- Probe route health with header `cf-aig-skip-cache: true` first — the
  gateway serves cached failed responses for `cache_ttl` (ours 1800s), so
  unburst errors look instantly healthy/dead.

**Head-node poisoning failure mode (observed 2026-09-08):** an upstream that
returns HTTP 200 wrapping an error JSON (aihubmix style, `{"code":500,"msg":"404
NOT_FOUND"}`) is treated by the route as a *successful stream*. The node's
`success` edge fires, fallback never runs, and `END` passes the error body
verbatim. A single 200-wrapped-error head node kills the whole ladder. Fix:
broken or suspicious providers go LAST in the chain, healthy named first; the
error surfaces only when the real head is healthy.
Corollary: an opencode agent loop fed this error spins ~1 step/1.5s (1,300+
steps, 71min CPU before SIGINT on kali) — runaway `loop step=` growth in
`~/.local/share/opencode/log/opencode.log` is the signature.

### Route-graph facts (2026-09-14, pr-reviewer rebuild)

Empirical facts from rebuilding `dynamic/pr-reviewer` (versions deployed, probed with `cf-aig-skip-cache: true`):

- **NIM end-of-life rows — snapshot was stale:** `deepseek-ai/deepseek-v4-flash` EOL 2026-08-07 and `z-ai/glm-5.2` EOL 2026-08-21 (both 410 Gone on `custom-nvidia-nim`). Live NIM replacements from `/v1/models`: `deepseek-ai/deepseek-v4-flash-0731` (snapshot row now `-0731`, family-band price $0.14/$0.28 carried, not independently verified) and `z-ai/glm-5.3-flash` (price unverified, no snapshot row).
- **Provider naming in route graphs:** bare custom-provider names are dead — the pr-reviewer head fell through with provider `nvidia-nim`; `custom-nvidia-nim` serves. The custom- prefix rule above is empirically confirmed. The rename is now applied: pr-gate's bare `nvidia-nim` head became `custom-nvidia-nim/nvidia/nemotron-3-super-120b-a12b` in the 2026-09-20 less-wrong pass, and the ladder was verified via the versions API (see the pr-gate entry above).
- **END is implicit:** route-version `elements` must NOT include a literal END element (validation fails `elements[n].outputs Required`); the last model node's `outputs.fallback` targets the string `"END"`.
- **zen `glm-5.2`:** free lane confirmed live ($0/$0 row; probes 200 with real content). Thinking model consumes small `max_tokens` budgets before emitting content — probe with ≥500.
- **openrouter `nvidia/nemotron-3-ultra-550b-a55b:free`:** real but transiently "Upstream error from Nvidia: Service temporarily overloaded" — the budget-lane flakiness matches historical parse-failure windows.
- **Conditional conditions match `metadata.*` only (empirical 2026-09-14):** body-referencing condition paths (`body.*`, `messages.*`) VALIDATE cleanly but never evaluate — unresolvable paths are truthy (both branches saw the true-node serve regardless of content), and `$regex` on them errors the request outright (null response, no fallback). Only `metadata.*` conditions dispatch reliably; pi/no-mistakes send static `cf-aig-metadata`, so per-phase body-content branching has no working zero-patch path. Keep route conditions metadata-only until CF ships body matching.

### Custom providers (gateway BYOK, dashboard-only management)

REST `/ai-gateway/...` surfaces routes/logs only — **custom providers are
dashboard-edited**, not token-manageable. URL segment beats shared rules:
`custom-<name>/<version-tag>` where `<version-tag>` must be re-supplied in the
URL (e.g. `custom-zai-coding/v4`) — the gateway strips trailing version-like
segments from the base_url. Confirmed segments: `custom-aihubmix/v1`,
`custom-together/v1`, `custom-deepinfra/v1` (upstream 404s on all shapes — base
URL suspect), `custom-friendli/v1`, `custom-zai-coding/(v4 or /api/coding)`,
`custom-commandcode/v1`, `custom-nvidia-nim/v1`, `custom-phoenixgrove/v1`,
`custom-opencode-zen/v1`, plus native `openrouter/` + `google-ai-studio/`.
DYNAMIC-route caveat: model nodes naming bare custom-provider names
(`aihubmix`, `deepinfra`, `friendli`) error `Provider not found` — use the
`custom-` prefix form.

### In2.5 discounts / billing states (2026-09-04)

- aihubmix: glm-5.3 discount — keep lane 1 in `high`.
- friendli: BYOK key repaired; credits live on team `fndycazh1NMA` but the
  stored key needs to be a **team-scoped** key (dashboard) before billing
  succeeds.
- deepinfra: `$10 credits` exist, but the provider 404s everywhere; base URL
  correction pending captain.
- opencode-zen: confirmed flaky (`500/401` intermittent) on gemini lanes.
- commandcode: healthy; monthly limit resets Sept 12.
- openrouter `thinkingmachines/inkling:free`: agentic-harness-gated upstream —
  excluded from all gateway dynamic routes (kept in pi's local chain).
- together: `$10` credit added; catalog confirmed cheap (glm-5.3 $1.4/$4.4,
  glm-5.3-Flash $0.15/$0.50, FP8/FP4 rate $0) — lane usable once credits clear.

## pi + opencode wiring for dynamic routes

- pi (`private_dot_pi/private_agent/models.json`): provider `CfAiGw`
  with baseUrl `…/opencode/compat`, `api: openai-completions`, gateway token,
  `cf-aig-gateway-id` header, and model keys `dynamic/TUI|dynamic/high|dynamic/pr-gate|dynamic/vision`.
- pi (`~/.pi/fallback-chains.json`): `default` ⇒ single `CfAiGw/dynamic/TUI`;
  `gate` ⇒ single `CfAiGw/dynamic/pr-gate`.
- opencode (`dot_config/opencode/opencode.json`): provider `CfAiGw`
  with the four dynamic-route model keys; top-level `model` = `CfAiGw/dynamic/TUI`;
  agent/category chains unchanged (fallback jsonc tail unchanged).

## Gateway route node types beyond the linear ladder (2026-09-05)

RouterModule nodes beyond `model`/`start`/`end`, from the CF dynamic-routing
reference:

- `percent` — probabilistic split across outputs (A/B, gradual rollout).
  Stateless per request. The valuable shapes for the fleet: canarying a
  cheaper lane on 5–10% of TUI traffic before re-ordering the ladder
  (evidence over paper prices), and splitting shared account-wide rate pools
  (e.g. the ~40 RPM nvidia-nim nemotron family) across two key entries.
- `conditional` — if/else on expressions over the request body, headers, or
  custom metadata (e.g. `user_plan == "paid"`). The high-value node for us:
  attach metadata like `crew=firstmate` / `crew=mybrain` / `class=gate` at the
  harness layer and ONE route can dispatch firstmate interactive → high,
  secondmate/telegram → TUI, review/gate traffic → pr-gate — no new provider
  entries per agent. Conditions on model ids (e.g. starts-with
  `claude-fable`) also let one route serve multiple lane families by name.
- `rate_limit` / `budget_limit` — enforce per-key/per-period request or cost
  quotas whose breach walks the node's fallback edge instead of failing:
  self-limiting guardrails on subsidized lanes so a runaway agent can never
  drain a plan window faster than the chain can re-route.

## Budget-access playbook (2026-09-05 pricing facts)

Ranked cheapest-first for accessing openai/anthropic/xai/kimi-class traffic
without the $100+/mo native-subscription seats:

- **OpenRouter PAYG + `:free` trio**: 5.5% platform fee on credit purchases
  ($0.80 min per purchase), zero token markup — provider list rates pass
  through. Free-model ceiling 50 req/day, **1,000/day after a $10 deposit**
  (one-time, never expires) at 20 RPM. Separate 1M-requests/mo PAYG band
  before a 5% per-request fee. `openrouter/free` router picks arbitrary free
  models; `:floor` routes to the cheapest provider for a chosen model;
  `max_price` caps spend per call. Below ~$15/mo the $0.80 floor dominates
  (5–25% effective tax); above ~$50/mo single-provider, a direct key beats
  OpenRouter by the 5.5%; above ~$5k/mo, negotiated enterprise tiers win.
- **Direct provider credits** (OpenAI $5 min, Anthropic $5 min, xAI, Kimi
  API): per-token, no platform fee, no subscription. Right choice above
  ~$50/mo per provider.
- **Plan/subsidized lanes already in the chains**: z.ai Coding Lite ($18/mo),
  opencode-zen console free (~200/day), PGS coding-tester plan (glm-5.3-flash
  + deepseek-v4-flash-0731 plan-subsidized — verified 2026-09-01), GOAT
  monthly pool (resets Sept 12), aihubmix glm-5.3 discount (TUI lane 1),
  together `$0` FP8/FP4 quantized GLM items, nvidia-nim nemotron (free, 40
  RPM account-wide), cerebras paygo ($5 + card, big TPM small RPM).
- **Google AI Studio**: $5 min via AI Studio, then $0.15/$0.50 MTok flash —
  strongest budget agentic lane (1M ctx), reachable natively through pi's
  `google-generative-ai` api type.
- **Cursor: has no BYOK/per-token bridge.** Seat-based subscription,
  workstation-scoped identity, machine-locked; wire it at most as a paid TUI
  lane, never a model lane.

## Auth-shape clarifications (2026-09-05)

- **pi-signed** is not a different harness: it is the signed wrapper identity
  of the pi coding agent (exact `pi-signed` wrapper parent around the Pi
  binary, foreground name `pi-launcher`). Firstmate records the identity as
 -is and refuses rather than silently falling back when the wrapper is
  missing. The signed wrapper is what keeps the launch provenance legitimate;
  there is no separate provider behind it.
- **OpenRouter PAYG vs subscriptions**: OpenRouter gives *API-key pass-through
  list pricing*, which is NOT the same as a harness subscription rate — you
  pay the provider's listed per-token price (their $186/mo-example is
  identical either way) plus OpenRouter's 5.5%. Harness/OAuth subscriptions
  (Claude Code 5-hour windows, Codex/Cursor seats) are different accounting
  systems with their own subsidized lanes and can be *cheaper per hour of
  agent use* than PAYG when the model is subscription-exclusive. They are a
  per-seat recurring fixed cost; our budget goal is to stay per-token and let
  `TUI`'s plan-subsidized lanes absorb interactive volume.
- **Harness-recognition gates** are a real auth-shape class to watch:
  openrouter gate-checks the calling harness before honoring some price bands
  (verified: `thinkingmachines/inkling:free` 403s through the gateway because
  the harness signature doesn't survive the hop; same model works from pi
  directly, or from Ori Harness). Budget implication: harness-gated models can
  only be reached via their recognized client, so "one harness for everything"
  is not a pricing win — per-(harness, provider) headphones stay necessary
  where the gate exists.
- **Inkling free endpoint = a TM research program, not a free tier
  (2026-09-14 production data):** OpenRouter's routing funnel admits only
  requests it classifies as agentic harnesses (TM's announcement names Claude
  Code, Codex, Hermes Agent, Ori — criteria undocumented; pi passed a live
  one-shot smoke but no-mistakes' shaped gate request got `403: inkling:free
  is only available on agentic harnesses — OpenRouter's routing funnel
  rejects pi as non-agentic`, so the verdict is not reliably controllable
  from client signature alone). The free endpoint's terms also log all
  prompts/outputs (disassociated) for TM model improvement and forbid
  confidential/personal data — repository diffs and review content must
  never ride it. Verdict: unsuitable for no-mistakes gate traffic even when
  the funnel accepts a request; personal agentic experiments via pi direct
  only, paid tier ($0.95/$4.05) for anything sensitive or
  production-facing. Honest attribution headers (pi provider entry
  `headers`) are untested; impersonating a recognized harness (e.g. Ori) to
  pass the funnel is off the table.

## Harness fleet admin cost (2026-09-05)

Verified-shape notes for standing up each additional TUI in the fleet,
roughly uniform: install once (npm/curl), login once (browser/OAuth or key
paste into its native provider dir), then quota-axi picks headroom up
automatically from its local auth dir (claude/codex/opencode/grok/kimi/
cursor providers are all already-read). Recurring maintenance is version
upgrades plus trust-dialog acceptance on fresh worktrees; no recurring
provider-edit work is added per harness (all harnesses point at the same
`CfAiGw` provider entry, so dynamic-route lane changes stay
config-free).
## Deterministic dynamic-route audit (2026-09-06)

`~/.config/opencode/scripts/dynamic-audit.mjs` (source: dotfiles
`dot_config/opencode/scripts/executable_dynamic-audit.mjs`) is the scheduled,
fully deterministic audit of the `CfAiGw` routes — no LLM step exists;
LLM interpretation happens only when the captain interrogates it, reading the
audit log rather than re-probing the gateway.

**Why the tests exist:**

1. `config-drift` compares the route keys declared in
   `dot_config/opencode/opencode.json`, `~/.pi/agent/models.json`, and the
   `default`/`gate` chain entries in `~/.pi/fallback-chains.json` against the
   purpose list in "Dynamic routes" above. Catches route renames made
   dashboard-side, stale agent configs, unresolved merges in the chains file,
   and purpose entries dropped from the catalog without a code change.
2. `route-probe` sends one fixed 4-token completion (`dynamic/<route>`) per
   route and logs HTTP code, latency, the upstream model id each route served,
   and `retry-after` / `cf-aig-status` headers on 429/5xx. 429/5xx/timeout is
   recorded as *routing evidence*, never a tool failure — repeated
   `status":"limited"` on a route is a lane-health fact, not a broken audit.

**Log (the interrogation substrate):** append-only JSONL at
`~/.local/state/opencode-fleet/dynamic-audit.jsonl`:

```
{"ts":"…","test":"route_probe","route":"dynamic/high","status":"ok","http":200,"latency_ms":589,"served_model":"z-ai/glm-5.3"}
```

`served_model` history is ground truth for which upstream each route currently
maps to; diff it against the "Dynamic routes" purpose definitions when
rebuilding routes. `config_drift` events name the exact file and key so a
rebuild starts from the diff.

**Usage:**
- Scheduled: hourly cron (`node ~/.config/opencode/scripts/dynamic-audit.mjs`), exits 0 clean / 1 drift / 2 machinery failure — transient 429/5xx/timeout never fails the tool, they're evidence the skill reads.
- `tail -F ~/.local/state/opencode-fleet/dynamic-audit.jsonl` to follow.
- Interrogation (captain-triggered, interactive): aggregate `route_probe` events per route — `served_model` counts, latency percentiles, 429/limited frequency/retry-after rate — and check the ladder against the purpose definitions in "Dynamic routes" above.
- **LLM proposals are interactive-only:** the captain triggers them on request ("interrogate the audit"); there is no scheduled LLM step. Any LLM run reads
  these logs — never re-probes the gateway on its own authority.

### Why the tests exist (design rationale)

The catalog reacts to invisible churn: dynamic-route contents change dashboard-side only, provider windows exhaust silently, and the last human-visible signal is often a failed chain somewhere. Recording each route's served_model per test run plus the provider availability aggregate gives every lane a *replayable history* of when the route healthy and who served it — the same ground truth `quota-axi` provides for quota, here for route/availability identity.

### Test 3: `provider_window` — the availability probe

`dot_local/bin/big-pickle-watch.sh` (source: `~/.local/bin/big-pickle-watch.sh`, cron-entry: * per-minute, both direct zen route + gateway BYOK lane, CSV). It is the design template the audit extends:

| Column | Curl response dependency |
|---|---|
| ts | wall-clock test start (ISO-8601) |
| route | direct | gateway which of two parallel lanes |
| http_code | probe return code (000 = never connected) |
| result | ok | limited | error | timeout (the four cardinal outcomes, categorizing every curl exit) |
| latency_ms | curl `%{time_total}` |
| err_type | upstream's own error.type field — the direct route's canonical exhaustion signal (`FreeUsageLimitError`) |
| retry_after_s | the strongest server-side signal, `Retry-After` from 429s |
| rate_headers | ratelimit/exhaustion headers preserved for trend reading |

The audit (`executable_dynamic-audit.mjs`, Test 3) folds this CSV into a
`provider_window` log event per route every hour with 24h ok/limited/timeout
aggregates: a single JSONL record per route telling a reviewing agent what the
last day of lane health actually looked like without reading the raw minutes.

Design principles (applies to both):
- **Write everything down, decide nothing.** The scheduled layer never mutates
  the gateway, routes, or provider config; scheduled logs are committed to disk
  for later review.
- **LLM proposals only on manual interrogation:** the captain (or the agent
  reading the skill after captain's request, via structured review) examines
  the logs and drives route-adjustment edits; any LLM formulation is a read of
  the record, and then proposes for human confirmation.
- **Both logs are cheap and structure-stable:** the audit log is JSONL keyed by
  `test` (`route_probe` / `config_drift` / `provider_window`); the CSV has a
  fixed 10-column header (see script header), published as a stable format
  others can parse.

## Failure signatures & diagnostic queries (2026-09-19)

When investigating provider/gateway failures, recognize these signatures:

### Known failure patterns

| Signature | Meaning | Action |
|---|---|---|
| **Fixed-duration ~274s timeout** | Gateway/edge cutoff (CF AI Gateway limit) | Route failed upstream; check provider window |
| **Prose output before JSON fence** | Model contract fragility (gemini-2.5-flash) | Retry; documented quirk, not a lane change |
| **`model` column NULL in agent_invocations** | Historical gap (pre-no-mistakes v1.72) | Model attribution unavailable; step, provider, error_type, and failure counts remain usable |

### Diagnostic query process (pull-based)

When diagnosing step failures with unknown model attribution:

1. **Query no-mistakes state for failed invocations with timestamp window:**
   ```sql
   SELECT
       step,
       model,
       provider,
       error_type,
       MIN(ts) as earliest_failure,
       MAX(ts) as latest_failure,
       COUNT(*) as failures
   FROM agent_invocations
   WHERE status = 'failed'
     AND ts > datetime('now', '-60 minutes')
   GROUP BY step, model, provider, error_type
   ORDER BY failures DESC;
   ```
   Use the `earliest_failure` and `latest_failure` timestamps in Step 2.

2. **Cross-reference with dynamic-audit for route attribution:**
   ```bash
   # Two-pass query: attributed (exact model match) + unattributed (non-ok, no model)
   # Labeled separately so unattributed failures are not falsely attributed to the model
   model_id="<model-id-from-step-1>"
   earliest="<earliest-failure-ts>"
   latest="<latest-failure-ts>"
   
    # Pass 1: Model-correlated — exact model match
    jq -c --arg model "$model_id" --arg earliest "$earliest" --arg latest "$latest" '
      select(.test == "route_probe") |
      select(.ts >= $earliest and .ts <= $latest) |
      select(.served_model == $model) |
      {ts, route, served_model, status, http, cf_aig_status, retry_after_s, evidence: "model_correlated"}
    ' ~/.local/state/opencode-fleet/dynamic-audit.jsonl
   
   # Pass 2: Unattributed — non-ok status with no served_model, labeled as such
   jq -c --arg earliest "$earliest" --arg latest "$latest" '
     select(.test == "route_probe") |
     select(.ts >= $earliest and .ts <= $latest) |
     select(.served_model == null and .status != "ok") |
     {ts, route, served_model, status, http, cf_aig_status, retry_after_s, evidence: "unattributed"}
   ' ~/.local/state/opencode-fleet/dynamic-audit.jsonl
   ```
   Note: Unattributed records (null `served_model`, non-ok status) may include failures from unrelated routes. Do not interpret them as model-specific evidence. Use them only as ancillary signals after consulting `provider_window` aggregates and correlating with route-to-model mappings if available.

3. **Interpret:**
   - **Model-correlated records:** If `served_model` matches the requested model, these identify route behavior for that model. Invocation/provider attribution requires a verified provider-to-route mapping.
   - **Unattributed records:** Non-ok status without `served_model` — may belong to any route. Correlate by timestamp with other evidence, or discard if no mapping exists.
   - If route status was `limited` (HTTP 429) or retry evidence present → rate limit or routing constraint; verify provider window before concluding exhaustion.
   - If route status was `error` alone → route failed, but not proof of provider exhaustion.
   - If NULL model in invocations → model attribution unavailable; rely on model-correlated audit records plus any unattributed signals you can correlate.

**Read-only constraint:** Never modify no-mistakes state. These queries only read existing diagnostic data.

## Vercel AI Gateway (2026-09-20)

Vercel AI Gateway is a **zero-markup** multi-provider gateway with 376+ models
from 47 providers. It serves as the fallback to Cloudflare AI Gateway, solving
several CF weaknesses (Anthropic paths, Cursor support, cost-based routing,
proper error handling). The `AI_GATEWAY_API_KEY` env var authenticates all
inference and management requests; the model catalog endpoint (`GET /v1/models`)
requires no auth.

**Base URLs by API surface:**

| API | Base URL | Use case |
|---|---|---|
| OpenAI Chat Completions | `https://ai-gateway.vercel.sh/v1` | General OpenAI-compat |
| OpenAI Responses | `https://ai-gateway.vercel.sh/v1` | Responses API |
| Anthropic Messages | `https://ai-gateway.vercel.sh` | Claude/Anthropic native |
| OpenResponses | `https://ai-gateway.vercel.sh/v1` | Provider-agnostic REST |

**Dedicated harness surfaces** (set up via `vercel ai-gateway` CLI one-command
config — each gets its own endpoint shape):

| Harness | URL | Why |
|---|---|---|
| Claude Code | `https://ai-gateway.vercel.sh/claude-code` | Anthropic-compat with Claude Code model catalog |
| Codex | `https://ai-gateway.vercel.sh/codex/v1` | OpenAI-compat + `/codex/v1/models` shape |
| Cursor | `https://ai-gateway.vercel.sh/cursor/v1` | Normalizes non-spec Cursor bodies |
| OpenCode | `https://ai-gateway.vercel.sh/v1` (provider entry) | OpenAI-compat |
| Kimi CLI | `https://ai-gateway.vercel.sh/v1` (provider entry) | OpenAI-compat |
| Coding agent (generic) | `https://ai-gateway.vercel.sh/coding-agent/v1` | Aider, Continue, gptme, Grok Build, etc. |

**Token:** `$AI_GATEWAY_API_KEY` (from `~/.agents/keys/default/.vercel-gateway-key`,
loaded by `load-keys.sh`). Auth via `Authorization: Bearer <key>` or `x-api-key`
header. OIDC tokens work on Vercel deployments (`VERCEL_OIDC_TOKEN`).

### BYOK (Bring Your Own Key)

Two BYOK modes:

1. **Team-level (dashboard only):** Provider credentials added in the Vercel
   dashboard → AI Gateway → BYOK section. No REST API for adding BYOK keys.
   Scoped to the team; works across all projects. BYOK requests have **zero
   markup**. Requires paid tier (purchased AI Gateway credits). If BYOK fails,
   the gateway falls back to system credentials (billed against credits).
2. **Request-scoped (programmatic):** Pass credentials per-request via
   `providerOptions.gateway.byok`:
   ```json
   "providerOptions": { "gateway": { "byok": { "anthropic": [{ "apiKey": "..." }] } } }
   ```
   Multiple credentials per provider (tried in order); multiple providers in
   one request. Bypasses dashboard-configured BYOK for that request.

**BYOK spend is metered separately and does NOT count toward budgets.** To
limit BYOK spend, enforce limits in your own code. Monitor via `GET /v1/report`
with `group_by=credential_type`.

Supported BYOK providers: Anthropic `{ apiKey }`, OpenAI `{ apiKey }`, Azure
`{ apiKey, resourceName }`, Google Vertex `{ project, location, googleCredentials }`,
Amazon Bedrock `{ accessKeyId, secretAccessKey, region? }`.

### Virtual Models (dynamic route equivalent)

Virtual Models (`vmc/<slug>`) are Vercel's equivalent to CF dynamic routes —
**CLI-managed** custom slugs that bundle a model with provider routing,
fallback behavior, observability tags, and more. More powerful than CF dynamic
routes because they support per-slug provider ordering, sort-by-cost, service
tiers, compliance, and per-provider options.

**Management:** `vercel ai-gateway virtual-models create/list/inspect/edit/remove/restore`
(CLI) or dashboard. The slug is immutable; all other settings are editable.

**Per-virtual-model settings:**

| Setting | Description | Request override |
|---|---|---|
| Provider order (`order`) | Ordered provider list to try | Virtual model wins |
| Provider restriction (`only`) | Restrict to specific providers | Virtual model wins |
| Model fallbacks (`models`) | Fallback chain | Virtual model wins, replaces request's chain |
| Sort (`sort`) | `cost`, `ttft`, or `tps` | Virtual model wins |
| Service tier (`serviceTier`) | `flex`, `priority`, or `fast` (aliases `priority`) | Virtual model wins |
| Prompt caching (`caching`) | `auto` or explicit | Virtual model wins |
| Provider timeouts | Per-provider timeout in ms | Virtual model wins |
| Required capabilities | `implicit_caching`, `vision` | Virtual model wins (replaces) |
| Compliance (ZDR, HIPAA) | Restrict to compliant providers | Tightens (either side on → on) |
| Provider options | Per-provider AI SDK options | Merges per option |
| Observability tags | Tags for spend attribution | Virtual model wins |

**Usage:** Call `vmc/<slug>` as the model string in any API surface (AI SDK,
Chat Completions, Responses, Anthropic Messages). Example: `"model": "vmc/tui"`
in a chat completions request routes through the virtual model's configuration.

**Routing rules** (separate from virtual models): Team-wide model rewrites and
denies, managed via REST API (`GET/POST/PATCH/DELETE /v1/ai-gateway/rules`) or
CLI (`vercel ai-gateway rules add/list/edit/remove`). Rewrites apply before
virtual model resolution. Deny rules block models everywhere including inside
virtual models.

### Provider Options (per-request routing)

All options ride `providerOptions.gateway` in the request body:

| Option | Type | Description |
|---|---|---|
| `order` | `string[]` | Provider try order (e.g. `['bedrock', 'anthropic']`) |
| `only` | `string[]` | Restrict to these providers only |
| `sort` | `'cost'\|'ttft'\|'tps'` | Rank providers by cost, latency, or throughput |
| `models` | `string[]` | Fallback model chain |
| `byok` | `Record<string, Array>` | Request-scoped BYOK credentials |
| `providerTimeouts` | `{ byok: Record<string, number> }` | Per-provider timeout in ms |
| `serviceTier` | `'flex'\|'priority'\|'fast'` | Service tier intent (`fast` aliases `priority`) |
| `zeroDataRetention` | `boolean` | Route only to ZDR providers |
| `tags` | `string[]` | Observability tags for spend tracking |
| `user` | `string` | End user ID for spend attribution |
| `caching` | `'auto'` | Automatic prompt caching |

### Anthropic on Vercel (solves CF weakness)

Vercel has **native Anthropic Messages API** support — no compat layer needed.
Dedicated Claude Code surface at `https://ai-gateway.vercel.sh/claude-code`.
The Anthropic SDK appends `/v1/messages` itself, so the base URL has no `/v1`.

16 Anthropic models available (2026-09-20), including:
- `anthropic/claude-sonnet-5` — 1M ctx, $2/$10 MTok
- `anthropic/claude-opus-5` — 1M ctx, $5/$25 MTok
- `anthropic/claude-fable-5` — 1M ctx, $10/$50 MTok
- `anthropic/claude-3-haiku` — 200K ctx, $0.25/$1.25 MTok
- `anthropic/claude-haiku-4.5` — 200K ctx, $0.10/$0.50 MTok

Prompt caching (`cache_control`) is passed through to Anthropic, Vertex AI
Anthropic, and Bedrock Anthropic. `CLAUDE_CODE_EXTRA_BODY` env var can inject
`providerOptions` into Claude Code requests.

### Cursor on Vercel (solves CF weakness)

Vercel has a **dedicated Cursor surface** at `https://ai-gateway.vercel.sh/cursor/v1`
that normalizes the non-spec bodies Cursor's base URL override sends to
`/chat/completions`. This is a major advantage — CF AI Gateway has no
Cursor-specific surface. The `vercel ai-gateway` CLI can set up Cursor
natively with one command.

20 Grok/xAI models available (2026-09-20), including:
- `spacexai/grok-4.1-fast-reasoning` — 1M ctx, $0.20/$0.50 MTok
- `spacexai/grok-4.20-multi-agent` — 2M ctx

### opencode-go on Vercel (limitation)

Vercel does **NOT** list opencode.ai as a provider. The opencode-go subsidized
pool cannot ride Vercel — the `x-opencode-session` header issue remains
CF-specific. However, custom headers CAN be passed via `createGateway({ headers })`
on the AI SDK provider instance for other providers that need them. The
OpenCode CLI itself can point at Vercel via a `vercel` provider entry in
`opencode.json` (the `vercel ai-gateway` CLI sets this up).

### Cost tracking and credits

- `GET /v1/credits` — team's credit balance and total spend
- `GET /v1/generation?id={id}` — per-request cost, latency, token usage, provider
- `GET /v1/report?start_date=...&end_date=...&group_by=...` — aggregated spend
  (group by: day, user, model, tag, provider, credential_type, ZDR, api_key_name)
- `GET /v1/models/{creator}/{model}/endpoints` — per-provider pricing, uptime,
  throughput, latency for a specific model

### Free tier models (2026-09-20)

| Model | Context | Notes |
|---|---|---|
| `inclusionai/ling-3.0-flash-fin-free` | 256K | Financial domain |
| `inclusionai/ling-3.0-flash-sante-free` | 256K | Health domain |
| `inclusionai/ling-3.0-flash-vl-free` | 256K | Vision-language |
| `poolside/laguna-s-2.1-free` | 256K | Coding model |

### Key differences from CF AI Gateway

| Capability | CF AI Gateway | Vercel AI Gateway |
|---|---|---|
| Dynamic routes | Route graphs (REST API for routes, dashboard for providers) | Virtual models (CLI-managed) + routing rules (REST API) |
| Custom providers | Dashboard-only BYOK | Dashboard BYOK + request-scoped BYOK |
| Anthropic | Compat layer (breaks on some models) | Native Anthropic Messages API + Claude Code surface |
| Cursor | No dedicated surface | Dedicated Cursor surface (normalizes non-spec bodies) |
| Cost-based routing | Not available | `sort: 'cost'` auto-picks cheapest provider |
| Per-request fallbacks | Route-level only | Per-request `models` array |
| Budget management | Failed on custom-provider traffic (403 code 2040) | Team/project/key/member level, separate from BYOK |
| Error handling | 200-wrapped errors treated as success | Proper provider failover with timeouts |
| Spend tracking | No per-request cost API | `GET /v1/generation` + `GET /v1/report` |
| Markup | Zero (BYOK) | Zero (all, including system credentials) |
| Body conditions | metadata.* only (body paths never match) | Not needed (per-request options) |
| Cache TTL | Serves cached failed responses (1800s) | Proper caching with invalidation |
| opencode-go | BYOK works (with header workaround) | Not available (no opencode provider) |
| Service tiers | Not available | `flex` (cheaper) and `priority` (faster) |
| ZDR | Not available | Per-request and team-wide ZDR |
| CLI management | None | `vercel ai-gateway` CLI for all resources |

### Known limitations

- **No opencode.ai provider** — the subsidized pool (opencode-go) cannot ride
  Vercel. The `x-opencode-session` header issue remains CF-specific.
- **BYOK dashboard-only** — no REST API for adding team-level BYOK credentials.
  Request-scoped BYOK is the programmatic alternative.
- **Paid tier required for BYOK** — must purchase AI Gateway credits.
- **BYOK fallback billing** — if BYOK fails, system credential fallback is
  billed against credits.
- **API key currently needs refresh** — the existing `vck_` key returns auth
  errors on all authenticated endpoints (2026-09-20). Captain needs to refresh.

## Cost Metrics & Provider Comparison (2026-09-20)

Reference for evaluating cost across the three gateway/provider options. Live
quota comes from `quota-axi`; rates here are reference facts verified against
provider documentation.

### Gateway markup comparison

| Gateway | Markup | Platform fee | BYOK fee | Notes |
|---|---|---|---|---|
| **CF AI Gateway** | Zero (BYOK) | None | Zero | Custom providers dashboard-only; budget limits failed on custom traffic |
| **Vercel AI Gateway** | **Zero (all)** | None | Zero | System credentials also zero-markup; credits-based |
| **OpenRouter** | 5.5% on credits | $0.80 min/purchase | N/A | List-rate passthrough; free-tier 50/day (1000/day after $10 deposit) |

### Per-token pricing access

| Source | Method | Auth required |
|---|---|---|
| CF AI Gateway | Dashboard or probe | Gateway token |
| Vercel AI Gateway | `GET /v1/models` (catalog) or `GET /v1/models/{creator}/{model}/endpoints` (per-provider) | No auth for catalog; key for endpoints |
| OpenRouter | `GET /v1/models` | API key |

### Cost-based routing

| Gateway | Capability | How |
|---|---|---|
| CF AI Gateway | Not available | Must manually order route nodes by cost |
| **Vercel AI Gateway** | **`sort: 'cost'`** | Auto-picks cheapest provider per model, per-request or per-virtual-model |
| OpenRouter | `:floor` suffix | Routes to cheapest provider for a chosen model |

### Budget management

| Gateway | Scope | Behavior |
|---|---|---|
| CF AI Gateway | Per-key spend limit | **Failed** on custom-provider traffic (403 code 2040 for unpriceable requests) |
| **Vercel AI Gateway** | Team, project, API key, team member | BYOK spend excluded; system-credential spend capped |
| OpenRouter | Per-key | $10 deposit raises free tier from 50 to 1000/day |

### Service tiers

| Gateway | Tiers | Savings |
|---|---|---|
| CF AI Gateway | None | N/A |
| **Vercel AI Gateway** | `flex` (cheaper), `priority` (faster) | Flex tier reduces cost at latency expense |
| OpenRouter | None | N/A |

### Free tier comparison

| Gateway | Free models | Rate limits | Notes |
|---|---|---|---|
| CF AI Gateway | @cf Workers AI (metered, not truly free) | 10K Neurons/day | Evaporates on 120B-class traffic |
| **Vercel AI Gateway** | 4 models (ling-3.0-flash-*-free, laguna-s-2.1-free) | Per-model rate limits | Credits-based; free tier subset of catalog |
| OpenRouter | `:free` models | 50/day (1000/day after $10) | Shared free-tier bucket |

### Spend tracking

| Gateway | Method | Granularity |
|---|---|---|
| CF AI Gateway | Gateway logs (dashboard) | Per-request, no API |
| **Vercel AI Gateway** | `GET /v1/generation` + `GET /v1/report` | Per-request cost/latency/tokens; aggregated by day/user/model/tag/provider/credential_type |
| OpenRouter | Dashboard | Per-request, limited API |

### BYOK economics

| Factor | CF AI Gateway | Vercel AI Gateway | OpenRouter |
|---|---|---|---|
| Markup on BYOK | Zero | Zero | N/A (no BYOK) |
| Request-scoped BYOK | Not available | **Available** (per-request credentials) | N/A |
| Fallback on BYOK failure | Route-level fallback | System credentials (billed) | N/A |
| Multiple credentials per provider | Not available | **Available** (tried in order) | N/A |
| Provider timeout control | Gateway-level | **Per-provider** (`providerTimeouts.byok`) | N/A |

### Cheapest-qualified-lane dispatch (updated 2026-09-20)

The existing cheapest-qualified-lane rule (see above) applies to initial dispatch
only. Vercel does not participate in initial dispatch; it is used only after the
CF AI Gateway fallback ladder is exhausted or degraded. The ranking remains by
blended tokens-per-dollar from `models.snapshot.json`, with Vercel's
zero-markup system credentials as a baseline and BYOK for zero-fee access to
existing provider credits.

### Volume discounts

- **Vercel**: Custom discounts available for volume token spend
  (`/docs/ai-gateway/pricing/discounts`). Enterprise teams can pay by invoice
  (no payment processing fees).
- **CF AI Gateway**: No volume discount documented.
- **OpenRouter**: 5.5% platform fee dominates below ~$15/mo; above ~$5k/mo,
  negotiated enterprise tiers win.
