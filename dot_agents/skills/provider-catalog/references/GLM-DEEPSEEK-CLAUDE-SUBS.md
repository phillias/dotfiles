# Flat-rate subscription survey — GLM 5.x / DeepSeek V4.x / Claude 5.x (2026-11-08 scan)

Companion to `CODING-PLANS.md` (which holds the in-fleet coding-plan lanes). This file answers: *which flat-rate plans anywhere grant GLM, DeepSeek, or Claude 5.x models, and are they worth adding?* Verified pages are marked; single-source claims are flagged.

## TL;DR

No cheap flat plan covers all three families. Best GLM+DeepSeek value: **NanoGPT PRO $12** and **Synthetic.new** tiers; best multi-family: **DevPass** (ban-risk, verify first); the only flat **Claude** lane is **Anthropic's own Max**. **Chutes subs are discontinued** (see `CHUTES.md`). **NaraRouter** = BYNara gateway; its subs cover only its own free-tier models, not GLM/DeepSeek/Claude.

## NaraRouter (router.bynara.id) — verified from live /api/plans

Indonesian multi-model gateway (PT. NARA PEMECUT DIGITAL), OpenAI + Anthropic endpoints, `sk-nry-` keys, 44+ models. The catalog's existing "NaraRoute free lane" (7M tok/day, 15 RPM) is this provider's Free tier. Subscription tiers are **daily/weekly Rupiah passes** covering only its own lightweight models (Laguna S 2.1, Step 5 Preview, GPT 5.6 Luna class): Free Rp0/7M tok/day; Freemium Rp5K/day (~$0.28)/25M tok; Freemium Max Rp10K/day/60M; GPT Fams Rp20K/day; Freemium Ultra Rp30K/day/200M. **GLM/DeepSeek/Claude are PAYG-only here** (GLM-5.3 $0.41/$1.28, DeepSeek V4 Flash $0.02/$0.05, Sonnet 5 $0.59/$2.97, Opus 5 $1.47/$7.33 per 1M in/out). Quirks: ZDR by default, a "Publisher" program reselling users' idle subscriptions (elevated ToS/ban surface), tiers shown "out of stock", daily reset 07:00 WIB. A second site (`router.naraya.ai`, Rp15K–49K/day tier classes) was unreachable — operator relationship unknown; treat as unverified. **Verdict: no new sub value for the three target families.**

## New flat-rate value (not already in fleet)

| Provider | Plan | $/mo | Grants | GLM 5.x | DeepSeek | Claude | Ext. API | Caveats |
|---|---|---|---|---|---|---|---|---|
| NanoGPT | PRO | **$12** | 60M input tok/**week** + free output on included open models (~315–331 models) | ✅ GLM-5.3 (1×), GLM-5.2 (2×) | ✅ V4.x + R-line variants | ❌ | ✅ OpenAI + Anthropic wire, Batch API | **Personal/non-commercial ToS** (fleet use gray), 10 concurrent, no provider pinning on sub. Verified via 4 consistent sources; vendor page not fetched this session |
| Synthetic.new | Go/Standard/Big | **$9/$30/$90** | Weekly regenerating credits at discounted rates; Big adds Fast (2×) + **Infinite mode** (unmetered slow DeepSeek V4.1 Flash) | ✅ GLM-5.3 (beta), 5.3-Flash | ✅ V4.1-Flash-1017 | ❌ | ✅ OpenAI + Anthropic; Claude Code/OpenCode documented | **1 concurrent request per model**; reprice from $30-pack → tiers means old quota numbers are stale. Vendor page verified |
| Ollama Cloud | Pro/Max/Team | **$20/$100/$500** | $60/$300/$1,000 usage credits at list (3×); off-peak ≈50% off → up to ~6× effective | ✅ 5.3/5.2/5.3-flash | ✅ V4.1-flash, V4-pro | ❌ | ✅ OpenAI + Anthropic subset | Credits **don't roll over**; 3 concurrent (Pro). Vendor page verified |
| DevPass | Lite/Pro/Max | **$29/$79/$179** | 2× face value ($58/$158/$358) at provider list rates, 200+ models | ✅ | ✅ | ✅ **only cheap all-three plan** | ✅ OpenAI + Anthropic | ⚠️ **2026-10-15: coding-agent whitelist only; API/automation use can get banned**; 24h cap 8–10% of monthly; multiplier cut 3×→2×. **Single-source (competitor comparison page) — probe with a throwaway account first** |
| Kilo | Pass Starter/Pro/Expert | $19/$49/$199 | List-rate credits + ramping bonus (total ≈ 1.27–1.4× effective) | ✅ | ✅ | ✅ (500+ models) | ⚠️ Kilo Gateway (OpenAI-format) only | 5% fee; bonus expires monthly. Vendor page verified |
| Standard Compute | Starter→Pro | $19–$249 | $1-for-$1 budget, no windows, no overage (402 at cap) | ✅ | ✅ | ✅ | ✅ OpenAI + Anthropic | **1× value, no discount** — pay-for-budgeting/lane-priority only |
| Z.AI | Pro/Max (Lite in fleet) | $80/$168 | 12K/28K credits per 5h + 60K/140K weekly, off-peak half rate | ✅ GLM only | ❌ | ❌ | ⚠️ coding tools only | Pure GLM-5.3 volume upgrade over Lite |
| Anthropic | Claude Pro/Max | $20/$100/$200 | Claude 5.x in Claude Code + Anthropic apps; Max reportedly adds $100/$200 API credits/mo | ❌ | ❌ | ✅ **the only flat Claude lane** | ⚠️ OAuth locked to first-party apps; third-party routing = ban vector | API-credit inclusion unverified (single-source) |
| Cerebras Code | Pro/Max | $50/$200 | 24M/120M tok/day, ~1,000 tok/s | ⚠️ GLM-**4.7 only** (older gen) | ❌ | ❌ | ✅ | **Both tiers sold out as of 2026-11-01**; TPM figures conflict |

## PAYG-only (surveyed, no flat plan)

OpenRouter (free `:free` = 50 req/day, 1,000/day after $10 top-up), NVIDIA NIM (free lane: DeepSeek V4.1-Flash, GLM-5.3/5.3-Flash, Kimi K3 on one `nvapi-` key, ~40 RPM; GLM free envelope degrades under load), Together, Fireworks, DeepSeek official, Friendli (GLM-5.3 $1.26/$3.96; **DeepSeek V3.2 deprecated 2026-10-24**, no V4 listing), AIHubMix (GLM discount lanes + free coding-GLM variants), SiliconFlow (13 free models, 1K RPM), Novita, DeepInfra (silent 200-concurrency cap), Hyperbolic, Nebius, Lambda, Groq, Baseten, Parasail, GMI, Targon, MiniMax M Plan (own models only), Kimi Code (own models), BytePlus/ModelArk (via Kilo).

## Ranked recommendations

1. **NanoGPT PRO $12** — cheapest $/input-token (~$0.05/M with free output), GLM-5.3 counts 1×. Risk: personal-use ToS.
2. **Synthetic.new Standard $30** — exact GLM-5.3 + DeepSeek-V4.1-Flash class behind OpenAI+Anthropic endpoints; Big $90's Infinite mode is unique for background agent loops. Risk: 1-concurrency-per-model serialization.
3. **Ollama Cloud Pro $20** — 3× credits + off-peak half-rate ≈ 6× effective if batch runs schedule nights/weekends. Risk: no rollover.
4. **DevPass Lite $29** — only cheap plan touching GLM+DeepSeek+**Claude**; ban-risk terms + single-source data → throwaway-account probe before any fleet dependency.
5. **Claude Max $100** — the only flat-rate Claude 5.x lane; pair with 1–3 for open models. Confirm Max's API-credit inclusion on anthropic.com first.

Bubbling under: Kilo Starter $19 (weakest multiplier), Standard Compute $19 (budgeting only), Z.AI Pro $80 (GLM volume), Alibaba Qwen Coding Plan $50 (includes GLM-5 — older gen; Lite tier closed Mar 2026; competitor-sourced numbers).
