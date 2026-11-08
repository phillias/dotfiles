# Flat-rate coding-agent plan lanes (2026-11-07 scan)

Flat monthly-fee subscription lanes for open-weight / budget coding models, surveyed 2026-11-07 for the
firstmate worker + opencode fallback lanes. Live quota/headroom still comes from `quota-axi`; this file is
the stable contract of what exists, what it costs, and how it authenticates.

## In-comparison verified plans

| Plan | Price | Models | Limits | External use | Auth |
|---|---|---|---|---|---|
| ClinePass | $9.99/mo (single tier) | GLM 5.3/5.3-Flash, Kimi K3/K3.1 Pro, DeepSeek V4 Pro/V4.1 Flash, MiniMax M3/M3.1, MiMo V2.6, Qwen3.7/3.8 | 2–5× standard API rate; 5h/week/month windows (numeric caps unpublished) | **Yes** — OpenAI-compat `POST https://api.cline.bot/api/v1/chat/completions`, slug `cline-pass/<model>`, header `X-Response-Format: openai` (verified working 2026-10-30; docs endorse LiteLLM/scripts) | API key from app.cline.bot |
| OpenCode Go | $10/mo (Go Plus $40, Teams $20/member; launched 2026-10-28) | ~31 models incl. GLM-5.3(-Flash), Kimi K3/K3.1 Pro, DeepSeek V4.1 Flash/V4 Pro, MiniMax M3(.1), MiMo V2.5/2.6, Qwen3.7/3.8, Grok 4.7, GPT 5.6/6 Luna, Haiku 5.5, Gemini 4 Argon | Published $ allowances per model/mo ($15–$100 tiers); 5h = 20%, week = 50%, month = 100% | Policy unstated; API key via Console `/connect` | API key |
| CommandCode GOAT | $10/mo (Go $1, Pro $20, Max 10× $100 / 20× $200) | Per-model credits ($100 Ling 3.1 Flash / DeepSeek V4.1 Flash / GLM-5.3-Flash, $70 GLM-5.2, $20–47 others; Sonnet 5.5 + GPT-5.6 Sol at $10, Haiku 5.5 $20) | Exact windows: $20/5h, $50/week, $100/month; extra credits at model cost, roll over forever | API included on GOAT+ (OpenAI- + Anthropic-compatible) | `cmd login` browser authorize or API key |
| PhoenixGrove | Taster $3.99 (first month free, Flash-only ~18M tok/mo), Basic $12.95, Pro $24.95, Elite $50, Ultra $99, Canopy $195 | 17–22 open models (GLM 5.2/5.3, Kimi K3/K2.6, DeepSeek V4.x, MiniMax M3, MiMo, Qwen, Nemotron, Ling) | 5h rolling + weekly windows with usage banking (rolls up to 10 days) | **Only vendor advertising tool-agnostic endpoints as a feature** — OpenAI + Anthropic + Responses + Ollama-compatible | API key |
| Z.AI GLM Coding Plan | Lite $18, Pro $80, Max $168 | GLM-5.3 + GLM-5.3-Flash(FlashX) only | Credits 2K/5h + 10K/wk (Lite), 12K/60K (Pro), 28K/140K (Max); off-peak (peak = Mon–Fri 06:00–10:00 UTC) half price | Most locked-down: coding-only endpoints, strictly limited tool list, >3 violations → ban | API key |

**Fleet fit:** ClinePass is the best $/flexibility cheap open-weight worker lane (verified outside-Cline
API); PhoenixGrove is the runner-up when Anthropic-compat is required. Z.AI Lite is already in use.

## Unutilized flat-rate plans worth watching (2026-11-07 survey)

Cross-checked against the in-use catalog (opencode-zen, opencode-go, CommandCode GOAT, Z.AI Lite,
PhoenixGrove PGS tester, OpenRouter PAYG, NIM free, Cerebras PAYG, AI Studio free, Claude Pro OAuth +
ChatGPT codex seats are excluded as in-use).

| Provider | Plan | Price/mo | Grants | External use | Auth |
|---|---|---|---|---|---|
| NanoGPT | Subscribe | $12 | 60M input tokens/week on 300+ open models (output free); 100 img/day | Yes — OpenAI+Anthropic-compat; documented for Claude Code/Codex/OpenCode | API key |
| Kimi (Moonshot) | Membership Plus / Pro | $19 / $39 ($15/$31 annual) | Kimi Code + K3 (Pro: 1M ctx + HighSpeed); shared pool across CLI/devices/API | Yes — OpenAI+Anthropic-compat ride membership quota; shares pool with the kimi CLI the fleet already runs | API key |
| MiniMax | M Plan Go / Explore / Build | $22 / $55 / $132 | M3.1 Flash + image + audio (+video from Explore), 1×/3×/7.5× | Yes — OpenAI+Anthropic-compat (Claude Code, Codex, OpenCode, Hermes) | API key |
| Chutes | Plus / Pro | $10 / $20 | 2,000 / 5,000 req/day on TEE-hosted open models, capped 5× PAYG value; then −6%/−10% PAYG | Yes — OpenAI-compat only | API key |
| Synthetic.new | pack (stackable) | $30 | 500 req/5h + $24 API credit/week + 1 concurrent/model on Kimi K3, GLM-5.3, DeepSeek V4.1 Flash, Qwen3.8; "Infinite mode" background agents | Yes — OpenAI+Anthropic APIs | API key |
| Ollama Cloud | Pro / Max | $20 / $100 | $60/$300 usage credits/mo, open-weight only, 3/10 concurrent | Yes — OpenAI+Anthropic-compat subset | API key |
| Standard Compute | Economy→Max | $19 / $39 / $89 / $249 | Fixed monthly compute budget at per-token rates across Claude/GPT/Gemini + open models; **no 5h/weekly windows** | Yes — OpenAI+Anthropic APIs (Claude Code, Codex CLI, OpenCode, Cline, Hermes) | API key |
| X (xAI) | Premium / Super | $30 / $100 | Grok pool (4×/15× Plus, weekly refresh) across Grok Build CLI + Cursor + X Premium | Partial — rides Grok CLI OAuth; API billed separately | Device OAuth (CLI login) |
| Google | AI Pro | $19.99 | Boosts Antigravity CLI (agy) quota + AI Studio limits + 1,000 Flow credits (media) | Partial — rides agy CLI (already wired) | Google account (already signed in) |
| Freepik | Premium / Premium+ | ~$7.25/mo annual ($20 monthly) / $45 | 240k / 600k credits/year + API access + Magnific/Topaz upscalers (≈3,200 Nano Banana 2 imgs or ~307 Kling 3.0 Turbo vids) | Yes — credit-based API | API key |
| Kilo | Kilo Pass | $19 / $49 / $199 | List-price credits + bonus (≈$26.60/$68.60/$278.60 total); bonus expires monthly, 5% fee | Partial — Kilo Gateway API, built for Kilo Code/OpenClaw/Hermes | API key |
| DevPass | Starter/Pro/Max | $29 / $79 / $179 | 2× face value at provider rates on 200+ models incl. Claude/GPT/Gemini | Conditional — Anthropic+OpenAI compat but whitelisted coding tools only; automation can get banned | API key |
| BytePlus | Coding Plan Lite | $20/30d | Doubao Seed 2.0 Pro/Code, Kimi K2.5, GLM 5.1/5.2, DeepSeek V4 Flash/Pro, GPT-OSS-120B; ~1,900 req/5h, 12k/wk | Partial — sold via Kilo credits, Kilo Gateway | API key (via Kilo) |

Not flat-rate (PAYG only, no subscription found): DeepSeek, OpenRouter, Together, Fireworks, fal.ai,
Kie.ai, Replicate, WaveSpeed, Brave, Exa, Perplexity API. Seat-locked (no external use): GitHub Copilot,
Cursor, Devin/Windsurf editor, Higgsfield, Perplexity Pro.

## Top-5 unutilized recommendations

1. **ClinePass $9.99** — cheapest worker-quota lane; OpenAI-compat key plugs into gateway custom-provider + firstmate worker lanes directly.
2. **NanoGPT $12** — bulk background-worker lane: 60M input tokens/week, cheapest $/token envelope found.
3. **Kimi membership Plus $19** — fills the kimi harness quota lane; pool already shared with the installed kimi CLI (no new auth plumbing).
4. **Freepik Premium ~$7.25 annual** — media lane for Bench Studio overflow (fal/Kie/Replicate have no flat plans).
5. **X Premium $30** — grok lane: weekly-refresh Grok pool riding the already-authenticated grok CLI (OAuth).

Runner-up: **Google AI Pro $19.99** — direct quota boost to the already-wired agy Antigravity worker chain
plus Flow media credits. **Chutes $10** as an ultra-cheap overflow lane (OpenAI-compat only).
