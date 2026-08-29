# Provider & Model Catalog

Live provider + model reference for the OpenCode config. Chain design lives in `DESIGN.md`; agent/category routing lives in `AGENTS.md` and `~/.config/opencode/opencode-fallback.jsonc`. All prices USD per 1M tokens (input/output) unless noted; all limits verified against the live config or provider docs on the dated line.

## Provider stack (19 configured)

| Provider | Role | Cost |
|---|---|---|
| opencode-zen | primary quality (big-pickle) + free tier, gateway-routed | free ~200/day / paid |
| commandcode (GOAT) | paid-first ladder stage 2, gateway-routed | $10/mo → $70 usage (7×) |
| opencode-go | subsidized pool, ladder lead, gateway-routed | $5 first mo → $10/mo → $60 usage |
| zai-coding | Z.AI Coding Plan Lite, credits-based, gateway-routed | $18/mo |
| cloudflare | AI Gateway REST `/ai/v1` (@cf lane), analytics, $50/mo cap | $0 (Workers AI free tier) |
| nvidia | free ladder (40 RPM shared) | $0 |
| openrouter | free ladder (50/day) + cheapest GLM-5 overflow, gateway-routed | $0 / pay |
| together | free single-shot (Bonsai) | $0 |
| baseten | pay-per-token ($30 credits) | pay |
| google | pay last resort | pay |
| mistral, sambanova, kilocode, agnes, intern | spot/experimental | $0/mix |
| opencode | GPT-class models (built-in sub) | sub |
| groq | DORMANT (configured, manual-only) | — |
| cerebras | DORMANT (no model access) | — |
| huggingface | DORMANT (no free tier, 402 on exhaust) | — |
| pokee | DORMANT (10M-context specialty, no key yet) | pay |

**No `enabled:false` flag in opencode** — for configured providers, presence = available, chain-absence = never auto-used. Broken *built-in* providers are suppressed via the top-level `disabled_providers` array (live: `zai`, `zhipuai`, `zai-coding-plan`, `zhipuai-coding-plan` — built-in Z.AI/Zhipu endpoints that misbehave; the custom `zai-coding` provider above is unaffected). Schema audit confirmed zero native fallback/retry keywords in opencode core; all fallback is plugin-level.

## Gateway routing — AI Gateway BYOK (2026-08-29)

Five providers route through Cloudflare AI Gateway `opencode` via BYOK (bring-your-own-key): `opencode-zen`, `opencode-go`, `commandcode`, `zai-coding`, `openrouter`. The `cloudflare` @cf lane stays on the REST `/ai/v1` endpoint (unchanged from PR #230).

**BYOK mechanics:** provider keys are stored in the gateway dashboard (alias `default` on gateway `opencode`, all five present). OpenCode authenticates with the gateway token (`.cf-ai-gw-token`) in the `Authorization` header, which the gateway consumes as gateway auth and does **not** forward; the stored BYOK keys inject upstream. No per-provider key files appear in `opencode.json` — only the gateway token file indirection (`{file:~/.config/opencode/.cf-ai-gw-token}`). No `cf-aig-authorization` header is needed on these providers (unlike the §5a ship-now shape that used gateway `phillias-cloudflare-os-ai` with explicit keys).

**URL version-segment rule:** the gateway strips a trailing version-like segment from the custom provider's `base_url` before appending the request path. Carrying the version in the request URL restores correctness:
- `opencode-zen` → `…/opencode/custom-opencode-zen/v1`
- `opencode-go` → `…/opencode/custom-opencode-go/v1`
- `commandcode` → `…/opencode/custom-commandcode/v1`
- `zai-coding` → `…/opencode/custom-zai-coding/v4` (note: `/v4`, not `/v1`)
- `openrouter` → `…/opencode/openrouter/v1` (native passthrough slug, NOT `custom-openrouter`)

The openai-compatible SDK appends `/chat/completions` to each baseURL, producing the exact validated URLs. `{file:}` substitution works in any string value (not just `apiKey`).

**Spend-limit rule:** the $50/30d spend-limit rule on gateway `opencode` (provider filter `["universal"]`) was **deleted 2026-08-29** — it returned 403 code 2040 ("Model or provider could not be resolved for spend-limit enforcement") for every custom-provider and openrouter request, including priced models, because it could not price custom-provider traffic. A metadata-scoped replacement is the recommended future shape: `cf-aig-metadata` application key split-by-value, smoke-tested against one custom-slug request first because custom-provider pricing may be unknown to Cloudflare.

**Token scopes (corrected 2026-08-29):** `.cloudflare-key` now has AI Gateway Edit/Run + Read (Read added 2026-08-29); `.cf-ai-gw-token` covers both planes (Workers AI `/ai/*` + AI Gateway `/ai-gateway/*`).

## Free → subsidized → pay value analysis (priority ranking)

| Priority | Provider | Models | Cost | Limit |
|---|---|---|---|---|
| 1 | NVIDIA NIM | 48 | $0 | ~40 RPM shared |
| 2 | Cloudflare | 34 LLM | $0 | 300 RPM |
| 3 | OpenRouter | 6 free | $0 | 50/day |
| 4 | OpenCode Zen | 6 free | $0 | ~200/day |
| 5 | Together | 2 | $0 | 60 RPM |
| 6 | Baseten | 13 | $30 credits | 15/120 RPM |
| 7 | OpenCode Go | 19 | $5/$10→$60 | $12/$30/$60 |
| 8 | GOAT | 34 | $10→$70 | $14/$35/$70 |
| 9+ | Google, Together, CheapestInference, Cheaper Inference | pay | pay | — |

Key insight: **NVIDIA after Cloudflare, before OpenRouter** (DS-V4 free only on NIM + Zen). 2026-08-12 captain superseded this free-first ranking with paid-first (DESIGN.md §2.6).

## OpenCode Zen (primary, 44 models)

Gateway-routed through gateway `opencode` via BYOK (custom-slug `custom-opencode-zen/v1`). Model keys are bare upstream ids (e.g. `big-pickle`, `kimi-k2.6`).

Big Pickle is the primary session model: `opencode-zen/big-pickle` 200K ctx / 32K out / temp 0.7.

Key models: kimi-k2.6 (200K/32K), deepseek-v4-pro (131K/8K, temp 1.0), gpt-5.5 (128K/32K), claude-opus-4-8 (200K/32K), gemini-3.5-flash (1M/64K), nemotron-3-ultra-free (262K/8K), deepseek-v4-flash-free (131K/8K).

**Free tier:** nemotron-3-ultra-free, deepseek-v4-flash-free, mimo-v2.5-free — (pruned 2026-08-29: `north-mini-code-free`, `minimax-m3-free`, `x-preview-f-free` — "Model not supported" on BYOK key lane; `claude-opus-4-1` — not on BYOK key lane).

Live catalog check: `cat ~/.config/opencode/.zen-key; curl https://opencode.ai/zen/v1/models | jq`. BYOK keys get worse rate limits than the shared pool — do not BYOK unless needed.

## Cloudflare Workers AI (34 LLM of 77 catalog, free, 300 RPM)

Free-tier ladder leader since 2026-08-16 (DESIGN.md §2.6). Prefix `cloudflare/@cf/...` (routed through the AI Gateway **REST API** `https://api.cloudflare.com/client/v4/accounts/{account_id}/ai/v1` with the `cf-aig-gateway-id: opencode` header, migrated 2026-08-29 off the deprecated `/compat` endpoint — Workers AI ids are bare `@cf/` there; DESIGN.md §2.6). Key: `.cf-ai-gw-token` (covers both `/ai/*` and `/ai-gateway/*` planes; `.cloudflare-key` has AI Gateway Edit/Run + Read — Read added 2026-08-29).

Key models: llama-3.3-70b-instruct-fp8-fast (24K, free-leader but MUST sit at END of chains), llama-4-scout (131K), kimi-k2.6 (262K), **kimi-k2.7-code (262K, coding)**, **glm-4.7-flash (131K)**, glm-5.2 (262K), gemma-4-26b-a4b-it (256K, thinking), qwq-32b (131K, reasoning), gpt-oss-120b/20b (128K), qwen2.5-coder-32b (32K).

**Small-prompts-only constraint:** CF context windows are 131-262K; prompts must fit before CF is reached. The 24K llama must sit at the END of any chain (2026-07-31 global-chain gap fix: 24K llama mid-chain caused 5021 AiError overflow).

## Agnes (5 models)

agnes-1.5 / agnes-2.0-flash (131K), video-v2.0 + image (32K).

## OpenRouter (15 models, gateway-routed)

Gateway-routed through gateway `opencode` via native passthrough (`openrouter/v1`, NOT `custom-openrouter`). Model keys are vendor-prefixed upstream ids (e.g. `z-ai/glm-5`, `anthropic/claude-sonnet-4`). Pruned 2026-08-29: 10 dead/retired models removed (see gateway routing section). Free tier 50/day (fleet-shared, 1000/day at high-balance tier).

## OpenCode Go (12 models, gateway-routed, $5/$10 → $60 usage)

Gateway-routed through gateway `opencode` via BYOK (custom-slug `custom-opencode-go/v1`). Now has `npm: @ai-sdk/openai-compatible` and `options` (previously built-in with no options). **GPT-class models need `opencode/` prefix, NOT `opencode-go/`** (see DESIGN.md GPT routing).

| Model | Ctx | $ in | $ out | Allowance |
|---|---|---|---|---|
| DS V4 Flash | 1M | 0.14 | 0.28 | $60 |
| DS V4 Pro | 1M | 0.435 | 0.87 | $15 |
| GPT-5.6 Luna | 1M | 0.10 | 0.60 | $15 |
| Grok 4.5 | 500K | 2.00 | 6.00 | $15 |
| Kimi K3 | 1M | 3.00 | 15.00 | $15 |
| GLM-5.2 | 1M | 1.40 | 4.40 | — |
| MiniMax M3 | 1M | 0.60→0.30 | — | — |
| Kimi K2.7 Code | 262K | — | — | — |
| Kimi K2.6 | 262K | — | — | — |
| GLM-5.1 | 203K | — | — | — |
| Qwen3.7 Max / Qwen3.7 Plus | 1M | — | — | — |
| MiMo V2.5 | — | — | — | — |

Deprecated on Go: GLM-5, Kimi K2.5, Qwen3.5 Plus, MiMo V2 Pro, MiMo V2 Omni.

## Command Code GOAT (Langbase, $10/mo → $70 usage, 34 models, gateway-routed)

Gateway-routed through gateway `opencode` via BYOK (custom-slug `custom-commandcode/v1`). Key: `.cf-ai-gw-token` (gateway token; provider key stored as BYOK in dashboard, not in config).

Rolling limits $14/5h, $35/wk, $70/mo; on-demand credits never window-throttled. GOAT is stage 2 of the paid-first ladder (DESIGN.md §2.6); Go leads since 2026-08-25. Key: `~/.config/opencode/.command-code.key` → `COMMANDCODE_API_KEY`, chezmoi age-encrypted 2026-08-12 (`{file:...}`).

Per-model allowances: GLM-5.2 $70, GPT-5.6 Luna $70 (~51.8K req), Hy3 $70, DS V4 Flash $60, K2.7 Code $60, MiniMax M3 $47, Qwen Max/Plus $33, MiMo V2.5 $30; new/negotiating models 2× = $20. Free on GOAT: Laguna S 2.1, Ling 3.0 Flash.

**API ids are vendor-prefixed and case-sensitive** (`https://api.commandcode.ai/provider/v1`): zai-org/GLM-5.2 (1M), gpt-5.6-luna (1.05M), deepseek/deepseek-v4-flash (1M), moonshotai/Kimi-K2.7-Code (256K), moonshotai/Kimi-K3 (1M), Qwen3.7-Max (1M), MiniMax-M3 (1M), Tencent hy3-paid (262K), xai/grok-4.5/4.6 (500K), thinkingmachines/inkling (256K), nvidia/nemotron-3-ultra-550b-a55b (1M), xiaomi/mimo-v2.5 (1M), stepfun/Step-3.7-Flash (256K), poolside/laguna-s-2.1-free (256K), GLM-5.2-Fast (1M), K2.7-Code-Highspeed (262K).

**Premium NOT on GOAT:** claude-* (7), gpt-5.6-sol/terra, gpt-5.5, gpt-5.4, gpt-5.3-codex, gpt-5.4-mini, google/gemini-* (4), sakana/fugu-ultra, meta/muse-spark-1.1.

GOAT edge: bigger pool + closed-model access (Luna, Grok). Deals: DS V4 Pro 4× permanent; MiMo V2.5/Pro up to 99% off.

## Z.AI Coding Plan Lite ($18/mo, credits-based, 4 models, gateway-routed)

Gateway-routed through gateway `opencode` via BYOK (custom-slug `custom-zai-coding/v4` — note the `/v4` version segment). Key: `.cf-ai-gw-token` (gateway token; provider key stored as BYOK in dashboard).

**Models:** GLM-5.3 (262K/8K, exclusive to Coding Plan), GLM-5.2 (262K/8K), GLM-5-Turbo (262K/8K), GLM-4.7 (131K/8K).

**Metering:** credits-based with 0.5× off-peak during ET 7am–11pm operational hours. The Coding Plan endpoint is restricted to supported coding tools; OpenCode is supported. Sits between GOAT and Cloudflare in the paid-first ladder (DESIGN.md §2.6).

## Other providers (spot/experimental)

| Provider | Model | Ctx | Notes |
|---|---|---|---|
| Google | gemini-2.0-flash | 1M/8K | small_model text (LIVE: opencode-zen/nemotron-3-ultra-free) |
| Mistral | mistral-large-latest | 131K | 1 req/s |
| SambaNova | Llama-3.3-70B | 131K | — |
| Together | DeepSeek-R1 | 163K/163K | 60 RPM |
| Together | **Ternary-Bonsai-27B** | 262K | FREE, ⚠️ single-shot only — KNOWN FAILURE tool-loop repeated-call; NEVER primary for tool-loop agents |
| InternLM | intern-s2-preview-397b | 256K | free |
| HuggingFace | 9 models | — | DORMANT (see below) |
| MindLab | Macaron-V1-Preview-749B | 202K | NO API, HF weights only |

## NVIDIA NIM (118 models, 48 relevant, free prototyping, ~40 RPM shared)

No daily cap. Key: `.nvidia-key` → `NVIDIA_API_KEY`. Recommend `providerConcurrency.nvidia: 4`.

Flagship: nemotron-3-ultra-550b-a55b (202K), nemotron-3-super-120b-a12b (202K), deepseek-v4-pro (1024K), deepseek-v4-flash (131K), z-ai/glm-5.2 (524K), kimi-k2.6 (262K), qwen3.5-397b-a17b (262K), gpt-oss-120b (128K), thinkingmachines/inkling (1048K), gemma-4-31b-it (256K), minimax-m3 (128K). Utility/embedding: llama-nemotron-embed-1b-v2, nemotron-parse, safety guards. Production: $4,500/GPU/yr.

Chain placement: NIM models limited to 1-2 per chain (KTD6 constraint).

## Baseten (13 models, pay-per-token, $30 free credits)

Key: `.baseten-key` → `BASETEN_API_KEY`. Rate limits Basic 15 RPM / verified 120 RPM.

Best value: **gpt-oss-120b** (128K, $0.10/$0.50), Nemotron-120B-A12B (202K, $0.30/$0.75), inkling (1048K, $1.00/$4.05), GLM-5.2 (524K, $1.40/$4.40). Also: GLM-4.7 (200K), Kimi-K2.5 (262K), Kimi-K2.6 (262K, $0.95/$4.00), DS-V4-Pro (262K, $1.74/$3.48), GLM-5.2-Fast (524K, $2.10/$6.60).

## CheapestInference (flat-rate time-block subs — documented, NOT wired)

Flat-rate unlimited in-window: Flagship Kimi-K3 solo $149-165/mo; Frontier K2.7+GLM-5.2+MiniMax-M3 $57-61/mo; Core DS-V4-Flash+MiMo-v2.5 $14.99-19.99/mo; annual −15%. 1 concurrent req/key. Americas 8h UTC block recommended. Counterparty risk noted. Key `.cheapestinference-key` NOT created. Placement: high-volume low-parallelism agents.

## Cheaper Inference / Keak (discounted reseller — documented, NOT wired)

≤30% below list; serves proprietary Claude/GPT/Kimi-K3. Wallet $5 min +$10 bonus; per-key configurable RPM/concurrency/quota/budget; 402 = insufficient wallet. Endpoints api.cheaperinference.com/v1, keys `ir_live_`. Key `.cheaperinference-key` NOT created. Catalog: claude-opus-4.6, gpt-5.4 ($1.25/$10), kimi-k3 (reasoning low|high|max), nano-banana-pro, grok-imagine.

## Hetzner Inference (experimental — WATCH, NOT chain-placed)

Single Qwen/Qwen3.6-35B-A3B-FP8 (262K, free experimental). **NO SLA/DPA/rate-limits.** US signup 401 KYC gate (disable VPN/Private Relay, custom email, or passport/card preorder). GEX44 RTX4000SFF $211/mo; GEX131 RTXPRO6000 96GB $989/mo. Key NOT created.

## Recently added models

- **Z.AI Coding Plan Lite** — GLM-5.3 (exclusive), GLM-5.2, GLM-5-Turbo, GLM-4.7; credits-based metering with 0.5× off-peak ET 7am–11pm; $18/mo. Wired in live config 2026-08-25. Gateway-routed 2026-08-29.
- **~~Ox Alpha Free~~** — stealth model on Zen (`x-preview-f-free`), pruned 2026-08-29 ("Model not supported" on BYOK key lane).
- **Laguna S 2.1** — 118B MoE 8B active, 262K, free (`poolside/laguna-s-2.1:free`) / 1M paid; Terminal-Bench 2.1 70.2%, SWE 78.5%.
- **Intern-S2-Preview-397B** — 397B MoE ~120B active, 256K, free official API (chat.intern-ai.org.cn), Apache 2.0, multimodal.
- **Ternary Bonsai 27B** — 1.58-bit, Qwen3.6-27B base, 262K, Together FREE, ⚠️ single-shot only (reverted 2026-07-31 from Librarian). 8B/4B/1.7B self-host only.
- **Macaron-V1-Preview-749B** — GLM-5.1 base Mixture-of-LoRA l0-l4, 202K, MIT, Livingbench 75.2 #1, HF weights only (~1.49TB) NO API.

## Pending evaluation

- **Ling 3.0 Flash** — 124B MoE 5.1B active, 256K→1M, OpenRouter `inclusionai/ling-3.0-flash:free`, unverified, recheck 2026-08-03.

## Pokee (dormant, 10M-context specialty)

`pokee/pokee-isaac` — Pokee-Isaac 28B v0 (2026-08-04). ONLY model on pokee.ai. 10M ctx / 60K out, `temperature: true`, pricing $0.15/$1.00 (PROVISIONAL). Base URL `https://api.pokee.ai/v1`, key prefix `pk-`, OpenAI-compatible. 500 req/min, 20M tok/min, 10 concurrent (25 with any purchase); new accounts 300 free credits. `background: true` extension for >10min runs; bodies >16 MiB REQUIRE SSE; prompt can take ~7 min at 10M tokens → set ≥10min client timeout. NOT in any chain (no key; long TTFT; provisional pricing). Specialty: whole-repo ingestion / pre-compaction 1M+ reads. See Task 1 research summary for full benchmark/API detail.

## HuggingFace Provider Reference (DORMANT)

No free tier verified (2026-07-22); 402 on credit exhaustion. Pass-through router to 17+ providers (DeepInfra, Novita, ...). HF paid-only placement at END of chains. Gotchas: gemma-4 thinking `content=null`; llama-3.3 on Novita 5K ctx cap; R1 expensive; credits exhaust silently.

Models NOT on HF: QwQ-32B (400). Broken Models replaced: gemma-4-12b → cf gemma-4-26b; nemotron-3-super-free → zen mimo-v2.5-free; llama-3.3-70b-instruct-fp8-fast → zen deepseek-v4-flash-free. Global-chain gap fixed 2026-07-31 (24K llama at END of chains; 5021 AiError overflow).

## Provider concurrency (live config)

**Team Profile:** defaultConcurrency 8; providerConcurrency {opencode 15, opencode-zen 15, opencode-go 8, openrouter 6}; modelConcurrency {big-pickle 2, kimi-k2.6 3, ds-v4-pro 2, gpt-5.5 2, gpt-5.4 2, gpt-5.3-codex 2, glm-5.1 2, ds-v4-flash 15, zen/kimi-k2.6 2}.
**Free Profile:** default 5; provider {opencode 10, openrouter 5}; modelConcurrency {}.

## Provider rate limits & quotas (16 providers)

| Provider | Limit | omo # |
|---|---|---|
| Cloudflare | 300 req/min | 8 |
| OpenRouter free | 50/day | 4 |
| Zen free | ~200/day | 10 |
| Go | $12/$30/$60 | 6 |
| GOAT | $14/$35/$70 | planned |
| Z.AI Coding Plan | credits-based, 0.5× off-peak ET 7am–11pm | — |
| NVIDIA | ~40 RPM shared | 4 |
| Baseten | 15/120 RPM | 3 |
| Mistral | 1 req/s | — |
| Google | 1500/day | — |
| Together | 60 RPM / 60K TPM | 4 |
| SambaNova | — | — |
| Agnes | — | 3 |
| InternLM | — | 3 |
| CheapestInference | unlimited in-window, 1 concurrent/key | — |
| Cheaper Inference | per-key configurable (only one) | — |

## GPT model routing (three prefixes)

`opencode/gpt-5.x` ✅ (Go binary built-in subscription) · `opencode-go/gpt-5.x` ❌ "Model not supported" · `opencode-zen/gpt-5.x` ❌ HTTP 400 (Zen uses chat/completions, not /v1/responses). BYOK OpenAI key not needed — shared pool preferred.

## Intermittent OpenAI server errors

Transient `server_error` from opencode provider; handled by `retry_on_errors` (400 stays in list).
