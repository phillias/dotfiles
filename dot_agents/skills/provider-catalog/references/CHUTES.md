# Chutes.ai — subscription analysis (2026-11-08 scan)

Companion to `CODING-PLANS.md`. Verified against chutes.ai/pricing, chutes.ai/news, chutes.ai/llms.txt, chutes.ai/terms, status.chutes.ai (2026-11-08).

## Headline: subscriptions are discontinued

Monthly plans (Base $3 / Plus $10 / Pro $20) were **retired 2026-10-26** ("subscriptions are no longer feasible" — GPU/compute market dynamics + new PayGo-only beta models); gone from the pricing page by 2026-10-29. PAYG is the only path for new users; existing plans run out their billing period and do not renew. The prior round-2 note ("Chutes $10 / $20, 2k/5k req/day capped at 5× PAYG value") is now historical.

## Historical plan facts (for the record)

- 5× PAYG-value cap was official (2026-02-27): Plus = $50, Pro = $100 of PAYG-equivalent usage/month.
- Published caps (from Sept 2026): Plus 2,000 req/day + ~$4.17 per 4h window; Pro 5,000/day + ~$8.33 per 4h. The 4h window + monthly cap bound first; req/day was cosmetic (Reddit 402s at 63/2000).
- TEE models excluded from subscriptions; new beta models (Qwen3.8 Max, DeepSeek V4.1 Pro) are PayGo-only.

## Current product shape

- **PAYG** (per-token, no minimum) — the sanctioned lane for agent fleets. Terms §5.4: large-scale automated inference must use PAYGO; multi-subscription circumvention = material breach.
- **Private Chutes** (self-serve TEE GPU): RTX Pro 6000 at $2.25/hr + $6.75 one-time deploy (raised from $1.80/$5.40 late Oct 2026).
- **Enterprise**: custom/volume via sales.
- OpenAI-compatible endpoint `https://llm.chutes.ai/v1` (Bearer `cpk_...`); **no Anthropic Messages endpoint**. Third-party use officially documented (Claude Code, Cursor, Cline, Aider, Codex, OpenClaw, MCP server).
- Catalog (2026-11-08, 18 open-weight models, no frontier): GLM-5.2/5.3/5.2-Fast, Kimi K2.6/K2.7-Code/K3, DeepSeek V3.2 / V4-Flash / V4.1-Flash / V4-Pro, Qwen3.8 (27B/Max/2.4T), Qwen3.5-397B, gemma-4-31B, Hy4. GLM-5.3 added 2026-11-07. Quantization varies (fp8/fp4/int4/mxfp4).
- Sample PAYG rates ($/M in/out): DeepSeek-V4.1-Flash 0.30/1.20 · Kimi K2.6 0.39/1.80 · GLM-5.1 0.90/2.90 · GLM-5.2 1.25/3.95 · Kimi-K3 1.85/9.50 (cut from 3/15 on 2026-10-14) · Qwen3.8-27B 0.039/1.25. Cached-input rates cheap (GLM-5.2 $0.125/M) but some cached-input overcharge complaints (r/chutesAI).

## Reliability

Status page self-reports 100% uptime (30/60/90d) as of 2026-11-08. But: Aug 2026 subscription-era threads report 15–20 TPS and 100% utilization (PAYG users fine); 2026 saw 4 term changes (free tier killed Mar 15, 5× cap Feb 27, Base closed May, subs retired Oct); model deprecations; capacity depends on Bittensor miner participation → multihost variance. OpenRouter-route uptime 86–100% by model.

## Fleet verdict

**Do not buy — nothing to buy.** As a PAYG overflow lane Chutes is genuinely cheap on DeepSeek-V4.1-Flash / Qwen3.8-27B / K2.6, but expect capacity variance and aggressive catalog/price churn. Flags: pseudonymous operator (Nevis-incorporated), crypto payments non-refundable.
