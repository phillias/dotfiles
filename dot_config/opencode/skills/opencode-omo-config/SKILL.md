# OpenCode/Oh-My-OpenAgent Configuration Skill

## Purpose

This skill documents the architecture, decisions, and maintenance procedures for the OpenCode and Oh-My-OpenAgent (OmO) configuration. As of 2026-07-18, this is a single-root config — profiles were phased out after they were identified as the source of the `cloudflare/` vs `@cf/` prefix bug (root config was correct, profiles shadowed it with bare model names).

## Model Specifications

### OpenCode Zen (47 models)

| Model | Context | Output | Temp |
|-------|---------|--------|------|
| big-pickle | 200K | 32K | 0.7 |
| kimi-k2.6 | 200K | 32K | 0.7 |
| deepseek-v4-pro | 131K | 8K | 1.0 |
| deepseek-v4-flash | 131K | 8K | 0.7 |
| gpt-5.5 | 128K | 32K | 0.7 |
| gpt-5.4 | 128K | 32K | 0.7 |
| claude-opus-4-8 | 200K | 32K | 0.7 |
| gemini-3.5-flash | 1M | 64K | 0.7 |
| nemotron-3-ultra-free | 262K | 8K | 0.7 |
| deepseek-v4-flash-free | 131K | 8K | 0.7 |

### Cloudflare Workers AI (16 models)

| Model | Context | Output | Temp |
|-------|---------|--------|------|
| @cf/meta/llama-3.3-70b-instruct-fp8-fast | 24K | 8K | 0.7 |
| @cf/meta/llama-4-scout-17b-16e-instruct | 131K | 8K | 0.7 |
| @cf/deepseek-ai/deepseek-r1-distill-qwen-32b | 80K | 8K | 1.0 |
| @cf/qwen/qwen2.5-coder-32b-instruct | 32K | 8K | 0.7 |
| @cf/qwen/qwen3-30b-a3b-fp8 | 32K | 8K | 0.7 |
| @cf/openai/gpt-oss-120b | 128K | 8K | 0.7 |
| @cf/openai/gpt-oss-20b | 128K | 8K | 0.7 |
| @cf/moonshotai/kimi-k2.6 | 262K | 8K | 0.7 |
| @cf/moonshotai/kimi-k2.7-code | 262K | 8K | 0.7 |
| @cf/zai-org/glm-4.7-flash | 131K | 8K | 0.7 |
| @cf/zai-org/glm-5.2 | 262K | 8K | 0.7 |
| @cf/google/gemma-4-26b-a4b-it | 256K | 8K | 0.7 |
| @cf/nvidia/nemotron-3-120b-a12b | 256K | 8K | 0.7 |

### Agnes AI (5 models)

| Model | Context | Output | Temp |
|-------|---------|--------|------|
| agnes-1.5-flash | 131K | 8K | 0.7 |
| agnes-2.0-flash | 131K | 8K | 0.7 |
| agnes-video-v2.0 | 32K | 4K | 0.7 |
| agnes-image-2.1-flash | 32K | 4K | 0.7 |
| agnes-image-2.0-flash | 32K | 4K | 0.7 |

### OpenRouter (24 models)

| Model | Context | Output | Temp |
|-------|---------|--------|------|
| qwen/qwen3-coder:free | 131K | 8K | 0.7 |
| meta-llama/llama-3.3-70b-instruct:free | 131K | 8K | 0.7 |
| nvidia/nemotron-3-super-120b-a12b:free | 131K | 8K | 0.7 |
| openai/gpt-4o | 128K | 16K | 0.7 |
| google/gemini-2.5-flash | 1M | 64K | 0.7 |
| deepseek/deepseek-chat | 131K | 8K | 0.7 |

### OpenCode Go (12 models)

| Model | Context | Output | Temp |
|-------|---------|--------|------|
| kimi-k2.6 | 200K | 32K | 0.7 |
| deepseek-v4-pro | 131K | 8K | 1.0 |
| deepseek-v4-flash | 131K | 8K | 0.7 |
| glm-5.1 | 131K | 8K | 0.7 |

### Other Providers

| Provider | Model | Context | Output | Temp |
|----------|-------|---------|--------|------|
| Google | gemini-2.0-flash | 1M | 8K | 0.7 |
| Mistral | mistral-large-latest | 131K | 8K | 0.7 |
| SambaNova | Meta-Llama-3.3-70B-Instruct | 131K | 8K | 0.7 |
| Together | deepseek-ai/DeepSeek-R1 | 163K | 163K | 1.0 |
| HuggingFace | openai/gpt-oss-120b | 128K | 32K | 0.7 |
| HuggingFace | openai/gpt-oss-20b | 128K | 16K | 0.7 |
| HuggingFace | deepseek-ai/DeepSeek-V4-Flash | 1024K | 16K | 0.7 |
| HuggingFace | deepseek-ai/DeepSeek-V4-Pro | 1024K | 32K | 0.7 |
| HuggingFace | Qwen/Qwen3-Coder-480B-A35B-Instruct | 262K | 32K | 0.7 |
| HuggingFace | Qwen/Qwen3-235B-A22B-Instruct-2507 | 262K | 8K | 0.7 |
| HuggingFace | google/gemma-4-26B-A4B-it | 256K | 32K | 0.7 |
| HuggingFace | meta-llama/Llama-3.3-70B-Instruct | 128K | 16K | 0.7 |
| HuggingFace | deepseek-ai/DeepSeek-R1-0528 | 160K | 8K | 1.0 |

### NVIDIA NIM (118 models, 48 relevant — FREE for prototyping)

**Cost**: Free for prototyping via NVIDIA Developer Program. No per-token pricing published.
**Rate limit**: ~40 RPM shared across ALL models (community-acknowledged baseline, not published SLA). No daily token cap.
**Production**: NVIDIA AI Enterprise from $4,500/GPU/year. Free 90-day evaluation available.
**Key file**: `.nvidia-key` → `NVIDIA_API_KEY`
**Verified via API**: 2026-07-23, 118 total models on `integrate.api.nvidia.com/v1/models`

#### Flagship Models (free, highest value for fallback chains)

| Model ID | Category | Context | Notes |
|----------|----------|---------|-------|
| `nvidia/nemotron-3-ultra-550b-a55b` | Agentic/Reasoning | 202K | Flagship MoE, 550B total / 55B active |
| `nvidia/nemotron-3-super-120b-a12b` | Agentic/Coding | 202K | Strong coding + reasoning MoE |
| `nvidia/nemotron-3-nano-30b-a3b` | Lightweight | 202K | Edge-tier MoE, 30B total / 3B active |
| `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning` | Reasoning | 202K | Omni-modal reasoning variant |
| `deepseek-ai/deepseek-v4-pro` | Frontier Reasoning | 1024K | 1.6T MoE, 49B active |
| `deepseek-ai/deepseek-v4-flash` | Fast Coding | 131K | Speed-optimized variant |
| `z-ai/glm-5.2` | Agentic/Coding | 524K | SWE-bench leader |
| `moonshotai/kimi-k2.6` | Agentic/Coding | 262K | Long-horizon problem solving |
| `qwen/qwen3.5-397b-a17b` | Vision/Chat | 262K | MoE, vision-capable |
| `qwen/qwen3-next-80b-a3b-instruct` | Lightweight MoE | 128K | 80B total / 3B active |
| `openai/gpt-oss-120b` | General Purpose | 128K | OpenAI's open-source 120B |
| `openai/gpt-oss-20b` | Fast General | 128K | Lightweight open-source |
| `thinkingmachines/inkling` | 1M Context | 1048K | Multimodal, Apache 2.0 |
| `google/gemma-4-31b-it` | Vision | 256K | Multimodal MoE |
| `minimaxai/minimax-m2.7` | Reasoning | 128K | |
| `minimaxai/minimax-m3` | Reasoning | 128K | |
| `mistralai/mistral-nemotron` | Agentic/Coding | 128K | Mistral × NVIDIA collab |
| `meta/llama-4-maverick-17b-128e-instruct` | Chat | 128K | Meta MoE |

#### Utility/Embedding Models (free, specialized)

| Model ID | Category | Notes |
|----------|----------|-------|
| `nvidia/llama-nemotron-embed-1b-v2` | Embeddings | |
| `nvidia/llama-nemotron-embed-vl-1b-v2` | Vision Embeddings | |
| `nvidia/nemotron-3-embed-1b` | Embeddings | |
| `nvidia/nemotron-nano-12b-v2-vl` | Vision | |
| `nvidia/llama-3.1-nemotron-nano-vl-8b-v1` | Vision | |
| `nvidia/nemotron-parse` | Document parsing | |
| `nvidia/nemotron-3.5-content-safety` | Moderation | |
| `nvidia/llama-3.1-nemotron-safety-guard-8b-v3` | Safety | |

#### Rate Limit Details

- **Shared limit**: ~40 RPM across ALL models for a single API key
- **Not per-model**: All model calls combined cannot exceed the limit
- **Model-dependent ceiling**: Your exact limit is shown in build.nvidia.com account panel
- **No daily token cap**: Only RPM is limited
- **No SLA**: "Dependent on model, use-case and the amount of current overall traffic"
- **Recommendation**: Set `providerConcurrency.nvidia: 4` to stay well under 40 RPM with burst headroom

### Baseten (13 models — PAY-PER-TOKEN with $30 free credits)

**Cost**: Pay-per-token. $30 free credits for new workspaces (no credit card required).
**Rate limit**: 15 RPM (unverified) / 120 RPM (verified) per workspace.
**Startup program**: Up to $25,000 credits (Dedicated Inference) + $2,500 (Model APIs) for seed–Series A.
**Key file**: `.baseten-key` → `BASETEN_API_KEY`
**Verified via API**: 2026-07-23, 13 models on `inference.baseten.co/v1/models`

#### Full Model Catalog with Pricing

| Model ID | Name | Context | Max Output | In $/M | Out $/M | Cache $/M | Features |
|----------|------|---------|------------|--------|---------|-----------|----------|
| `openai/gpt-oss-120b` | GPT-OSS 120B | 128K | 128K | **$0.10** | **$0.50** | $0.10 | tools, reasoning, json_mode, structured_outputs |
| `nvidia/Nemotron-120B-A12B` | Nemotron Super | 202K | 202K | **$0.30** | **$0.75** | $0.06 | tools, json_mode, structured_outputs, reasoning |
| `zai-org/GLM-4.7` | GLM 4.7 | 200K | 200K | $0.60 | $2.20 | $0.12 | tools, json_mode, structured_outputs |
| `moonshotai/Kimi-K2.5` | Kimi K2.5 | 262K | 262K | $0.60 | $3.00 | $0.12 | tools, json_mode, structured_outputs, vision |
| `nvidia/NVIDIA-Nemotron-3-Ultra-550B-A55B` | Nemotron Ultra | 202K | 202K | $0.60 | $2.40 | $0.12 | tools, json_mode, structured_outputs, reasoning |
| `zai-org/GLM-5` | GLM 5 | 202K | 202K | $0.95 | $3.15 | $0.20 | tools, json_mode, structured_outputs |
| `moonshotai/Kimi-K2.6` | Kimi K2.6 | 262K | 262K | $0.95 | $4.00 | $0.16 | tools, json_mode, structured_outputs, reasoning |
| `moonshotai/Kimi-K2.7-Code` | Kimi K2.7 Code | 262K | 262K | $0.95 | $4.00 | $0.16 | tools, json_mode, structured_outputs, reasoning |
| `thinkingmachines/inkling` | Inkling | **1048K** | 32K | $1.00 | $4.05 | $0.17 | tools, json_mode, structured_outputs, reasoning |
| `zai-org/GLM-5.1` | GLM 5.1 | 202K | 202K | $1.30 | $4.30 | $0.26 | tools, json_mode, structured_outputs |
| `zai-org/GLM-5.2` | GLM 5.2 | **524K** | **524K** | $1.40 | $4.40 | $0.14 | tools, json_mode, structured_outputs, reasoning |
| `deepseek-ai/DeepSeek-V4-Pro` | DeepSeek V4 Pro | 262K | 262K | $1.74 | $3.48 | $0.14 | tools, json_mode, structured_outputs, reasoning |
| `zai-org/GLM-5.2-Fast` | GLM 5.2 Fast | **524K** | **524K** | $2.10 | $6.60 | $0.21 | tools, json_mode, structured_outputs, reasoning |

#### Rate Limit Details

| Account Type | RPM | TPM |
|---|---|---|
| Basic (unverified) | 15 | 100,000 |
| Basic (verified) | 120 | 500,000 |
| Pro | 120 | 1,000,000 |
| Enterprise | Custom | Custom |

#### Best Value Picks (for fallback chain placement)

1. **`openai/gpt-oss-120b`** — $0.10/$0.50 per 1M tokens. Cheapest general-purpose model. 128K context.
2. **`nvidia/Nemotron-120B-A12B`** — $0.30/$0.75. Strong coding + reasoning at budget price. 202K context.
3. **`thinkingmachines/inkling`** — $1.00/$4.05. **1M context window** — unique capability. Multimodal.
4. **`zai-org/GLM-5.2`** — $1.40/$4.40. **524K context**, reasoning. SWE-bench leader.

### Free→Subsidized→Pay Value Analysis

**Priority ranking for fallback chain placement (exhaust free → subsidized → pay):**

| Tier | Provider | Models | Cost | RPM | Best For |
|------|----------|--------|------|-----|----------|
| 🟢 **FREE** | NVIDIA NIM | 48 relevant | $0 | ~40 shared | Largest free catalog, 1M ctx (Inkling), reasoning (Nemotron Ultra) |
| 🟢 **FREE** | Cloudflare Workers AI | 16 | $0 | 300 req/min | Free-tier leader, GPT-OSS, Kimi K2.7, GLM 5.2 |
| 🟢 **FREE** | OpenRouter | 6 free | $0 | 50 req/day | Nemotron Super/Nano, Qwen3 Coder |
| 🟢 **FREE** | OpenCode Zen | 6 free | $0 | ~200 req/day | Nemotron Ultra, DeepSeek V4 Flash, MiMo |
| 🟡 **SUBSIDIZED** | Baseten | 13 | $30 credits | 15-120 | GPT-OSS 120B at $0.10/M, Inkling at 1M ctx |
| 🟡 **SUBSIDIZED** | OpenCode Go | 24 | $10/mo | — | Quality pool (K2.6, DS-V4, GLM-5.1) |
| 🔴 **PAY** | Google | 1 | Pay-per-token | 1500/day | Gemini 2.0 Flash, 1M ctx, last resort |
| 🔴 **PAY** | Together | 1 | Pay-per-token | 60+ | DeepSeek R1, reasoning specialist |

**Key insight**: NVIDIA NIM provides the **largest free model catalog** (48 relevant models at $0) with a shared ~40 RPM limit. This should be inserted into fallback chains **after** Cloudflare (which has higher RPM at 300 req/min) but **before** OpenRouter free (which has only 50 req/day). Baseten's $30 credits + $0.10/M GPT-OSS 120B provides a cheap subsidized tier between free and full-pay.

**DeepSeek V4 availability**: Only 2 providers offer DS-V4 for free — NVIDIA NIM (both Flash and Pro) and OpenCode Zen (Flash Free only). OpenRouter's `:free` listing is dead (endpoints: [], 0% availability). Add both NIM and Zen DS-V4 models to fallback chains for resilience — they have independent rate limits.

**Recommended fallback chain order**:
1. Cloudflare Workers AI (free, 300 RPM)
2. NVIDIA NIM (free, ~40 RPM shared — use 1-2 models max to stay under limit)
3. OpenRouter free (50 req/day)
4. OpenCode Zen free (200 req/day)
5. Baseten ($30 credits → $0.10/M GPT-OSS 120B)
6. OpenCode Go ($10/mo pool)
7. Google Gemini (pay, last resort)

## Architecture Overview

### Single-Root Config System

All config lives directly under `~/.config/opencode/`. No profile subdirectories. There is exactly one `opencode.json`, one `oh-my-openagent.jsonc`, one `opencode-fallback.jsonc` — each is the authoritative source for its concern.

```
~/.config/opencode/
├── opencode.json                              # Providers (Cloudflare, OpenRouter, OpenCode Zen, OpenCode Go, Agnes AI, Google, Mistral, SambaNova, Together, HuggingFace), MCPs, compaction defaults
├── oh-my-openagent.jsonc                      # OmO agent and category routing (sisyphus, prometheus, oracle, metis, momus, atlas, ultrabrain, deep, quick, writing, artistry, explore, librarian, sisyphus-junior, etc.) + fallback_models chains
├── opencode-fallback.jsonc                    # Global 11-entry free→subsidized→pay fallback chain (cloudflare Workers AI free → openrouter free → opencode-zen free → opencode-go flash → google gemini last resort)
├── dispatch-rules.json                        # 26 starter rules mapping task shape → task(category=..., load_skills=[...]) at Sisyphus intent-gate time
├── plugins/
│   ├── better-compaction.ts                   # Auto-loaded: todo tracking, skill generation, codemem
│   ├── fleet-state-writer.ts                  # Auto-loaded: zero-LLM-cost state wire (writes ~/.local/state/opencode-fleet/{state.json,wake.log,digest.txt})
│   ├── fleet-digest.sh                        # (in scripts/, not plugins/) — pure bash reader for fleet state
│   ├── go-pool-fallback.ts                    # Auto-loaded: Go pool exhaustion compaction note
│   ├── go-pool-guard.ts                       # Auto-loaded: redirect to free when Go exhausted (only safety net for bare-opencode runs; no-op when OmO loads)
│   └── tmux-patch-keeper.ts                   # Auto-loaded: re-applies tmux attach patch on session.created when upstream fingerprint detected
├── scripts/
│   ├── fleet-digest.sh                        # Pure bash reader for fleet state (terse TSV summary)
│   ├── go-pool-check.sh                       # Go pool usage probe helper
│   └── go-pool-switch.sh                      # Switch Go pool off if exhausted
├── AGENTS.md                                  # Agent behavioral rules (Dispatch Rules + Fleet State Comms sections appended 2026-07-18)
├── docs/plans/                                # Plan archive (not actively consumed at runtime)
├── .cloudflare-key, .zen-key, .google-key, .go-key, .together-key, .sambanova-key, .mistral-key, .hf-key, .agnes-key, .exa-key, .nvidia-key, .baseten-key  # API keys (secret; .groq-key + any other defunct-key files removed)
├── .tmux-OmOTeam.conf                         # tmux layout for team mode
├── .google-client-id, .google-client-secret   # OAuth creds for Google Workspace MCP
└── skills/                                    # OpenCode skills directory (axi, ce-*, dotfiles, dotfiles-chezmoi, grill-with-docs, etc.)
```
~/.config/opencode/
├── opencode.json                              # Providers (Cloudflare, OpenRouter, OpenCode Zen, OpenCode Go, Google, Mistral, SambaNova, Together, Kilo, HuggingFace), MCPs, compaction defaults
├── oh-my-openagent.jsonc                      # OmO agent and category routing (sisyphus, prometheus, oracle, metis, momus, atlas, ultrabrain, deep, quick, writing, artistry, explore, librarian, sisyphus-junior, etc.) + fallback_models chains
├── opencode-fallback.jsonc                    # Global 10-entry free→subsidized→pay fallback chain (cloudflare Workers AI free → openrouter free → opencode-zen free → opencode-go flash → google gemini last resort)
├── dispatch-rules.json                        # 26 starter rules mapping task shape → task(category=..., load_skills=[...]) at Sisyphus intent-gate time
├── plugins/
│   ├── better-compaction.ts                   # Auto-loaded: todo tracking, skill generation, codemem
│   ├── fleet-state-writer.ts                  # Auto-loaded: zero-LLM-cost state wire (writes ~/.local/state/opencode-fleet/{state.json,wake.log,digest.txt})
│   ├── fleet-digest.sh                        # (in scripts/, not plugins/) — pure bash reader for fleet state
│   ├── go-pool-fallback.ts                    # Auto-loaded: Go pool exhaustion compaction note
│   ├── go-pool-guard.ts                       # Auto-loaded: redirect to free when Go exhausted (only safety net for bare-opencode runs; no-op when OmO loads)
│   └── tmux-patch-keeper.ts                   # Auto-loaded: re-applies tmux attach patch on session.created when upstream fingerprint detected
├── scripts/
│   ├── fleet-digest.sh                        # Pure bash reader for fleet state (terse TSV summary)
│   ├── go-pool-check.sh                       # Go pool usage probe helper
│   └── go-pool-switch.sh                      # Switch Go pool off if exhausted
├── AGENTS.md                                  # Agent behavioral rules (Dispatch Rules + Fleet State Comms sections appended 2026-07-18)
├── docs/plans/                                # Plan archive (not actively consumed at runtime)
├── .cloudflare-key, .zen-key, .google-key, .go-key, .together-key, .sambanova-key, .mistral-key, .hf-key, .kilo-key, .exa-key, .nvidia-key, .baseten-key  # API keys (secret; .groq-key + any other defunct-key files removed)
├── .tmux-OmOTeam.conf                         # tmux layout for team mode
├── .google-client-id, .google-client-secret   # OAuth creds for Google Workspace MCP
└── skills/                                    # OpenCode skills directory (axi, ce-*, dotfiles, dotfiles-chezmoi, grill-with-docs, etc.)
```

### Critical Rules

1. **One config, not profiles.** `OPENCODE_CONFIG_DIR` is unset — root `~/.config/opencode/` is authoritative. No `oc <profile>` launcher, no `profiles/` subdirectory. To switch behavior, change `opencode.json` / `oh-my-openagent.jsonc` directly and chezmoi-track the change.
2. **Global config defines providers and MCPs.** `opencode.json` has all 13 live providers with connection details (baseURL, `{env:VAR}` key refs) and populated model lists. The dormant Cerebras provider block is retained in `opencode.json` for potential re-enablement; no agent references it.
3. **OmO owns agent + category routing.** `oh-my-openagent.jsonc` declares per-agent `model` + `fallback_models` arrays, per-category model variants, and `concurrency` limits. Per-agent `fallback_models` take priority over the global `opencode-fallback.jsonc` chain.
4. **`opencode-fallback.jsonc` is global default fallback.** First-match-wins resolution: `.opencode/opencode-fallback.jsonc` (project) > `~/.config/opencode/opencode-fallback.jsonc` (global). Used by the 11 agents that don't specify their own `fallback_models` arrays.
5. **Auto-loaded plugins.** Any `.ts` file in `~/.config/opencode/plugins/` loads for every opencode session regardless of config — currently: `better-compaction.ts`, `fleet-state-writer.ts`, `go-pool-fallback.ts`, `go-pool-guard.ts`, `tmux-patch-keeper.ts`. All run in-process with zero LLM cost on the write side.
6. **No symlinks, no env switching.** Environment homogeneity: every machine running this chezmoi-tracked config runs the same root config. Machine-specific differences live in chezmoi templates (`.tmpl` files) and per-machine `/etc/` overrides — not in opencode profile subdirs.

### Provider Stack (13 providers)

| Provider | Models | Cost | Role |
|---|---|---|---|
| **OpenCode Zen** | 49+ (GPT-5.x, Claude-4.x, Gemini-3.x, DS-V4, GLM-5, Big Pickle, free tier) | Zen sub | Quality primary |
| **OpenCode Go** | 24 (K2.6/2.7, DS-V4-Pro/Flash, GPT-5.x, Claude-4.x, Qwen3.x, etc.) | $10/mo | Quality pool, 24 models in routing |
| **OpenRouter** | 22+ (DS-V4-Flash, Qwen3-Coder, GLM-5, etc.) | Free/Paid | Broadest model selection |
| **Cloudflare** | 16 (`@cf/...` Workers AI models: Llama 3.3, GPT-OSS 120B, Kimi K2.6/K2.7, GLM 5.2, Qwen 3, Nemotron 3, Gemma 4, etc.) | Free tier | Free-tier leader in fallback chains (300 RPM) |
| **NVIDIA NIM** | 48 relevant of 118 total (Nemotron 3 Ultra/Super/Nano, DS-V4, GLM 5.2, Kimi K2.6, Qwen 3.5, GPT-OSS, Inkling, Gemma 4, MiniMax, etc.) | Free (prototyping) | **Largest free catalog** (~40 RPM shared), 1M ctx via Inkling |
| **Baseten** | 13 (GPT-OSS 120B, Nemotron Super/Ultra, GLM 4.7/5/5.1/5.2, Kimi K2.5/K2.6/K2.7, DS-V4-Pro, Inkling, GLM 5.2 Fast) | $30 free credits → pay-per-token | **Cheapest pay-per-token** ($0.10/M GPT-OSS 120B), 1M ctx Inkling |
| **Mistral** | 1 (Mistral Large) | Free (1 req/s) | Reasoning, multilingual |
| **SambaNova** | 1 (Llama 3.3 70B) | Free | Fast 70B option |
| **Google** | 1 (Gemini 2.0 Flash) | Free (1500 req/day) | Vision, 1M ctx, pay-tier last resort |
| **Together** | 1 (DeepSeek R1) | Free tier | Reasoning specialist |
| **HuggingFace** | 9 (GPT-OSS-120B, GPT-OSS-20B, DS-V4-Flash, DS-V4-Pro, Qwen3-Coder-480B, Qwen3-235B, Gemma-4-26B, Llama-3.3-70B, R1-0528) | Pass-through (HF router) | **DORMANT** — zero free models, paid-only. See Defunct Providers. |
| **Agnes AI** | 5 (video, image, flash models) | Free tier | Multimodal (video, image generation) |

### Defunct Providers (removed 2026-07-18)

| Provider | Removed because | Date | Cleanup scope |
|---|---|---|---|
| **Groq** | Groq free-tier TPM limits (12K/8K) were chronically hitting rate limits on agentic workloads. Eliminated from all configs; `.groq-key` deleted; no functional replacement needed (Cloudflare has identical GPT-OSS and Llama 3.3 70B models at higher concurrency) | 2026-07-18 | Provider block + all fallback chain entries (all 8 profile subdirs also deleted root-only config introduced same day) |
| **Cerebras** | Account lacked model access despite valid `.cerebras-key`. Verified empirically: every retry attempt returned `Not Found: Model does not exist or you do not have access to it` against `cerebras/llama3.3-70b` and `cerebras/gpt-oss-120b` (observed 3× consecutive failures this session). Dormant provider block retained in `opencode.json` for potential re-enablement, but no agent references it. | 2026-07-18 | Stripped from 8 fallback chains in `oh-my-openagent.jsonc` (sisyphus, prometheus, ultrabrain, deep, artistry, quick, unspecified-high, writing). Provider block + `.cerebras-key` retained as dormant. |
| **HuggingFace** | HF Inference Providers has **zero free models** — `is_free: false` on all 127 models across all 17 providers (verified via `/v1/models` API 2026-07-22). The `$0.10/mo` "free credits" is a one-time starting balance, not a renewable tier. Credits exhaust same-day → 402 on everything. Additional gotchas: Gemma 4 26B is a thinking model (content=null, reasoning tokens consume max_tokens); Llama 3.3 70B novita provider caps context at 5K (!). Provider block retained in `opencode.json` for manual/direct use; removed from all OmO agent/category fallback chains. | 2026-07-22 | Stripped from 6 fallback chains (explore, librarian, multimodal-looker, artistry, quick, writing). ProviderConcurrency entry removed. Provider block + `.hf-key` retained. |

Verification of these removals: schema audit of upstream opencode JSON schema (`https://opencode.ai/config.json` `$defs`) confirmed zero native `fallback` or `retry` keywords. All fallback handling is an OmO-feature, parsed by the OmO plugin, not by opencode core. Free→subsidized→pay progression is enforced by OmO at request-failure time.

For Groq-equivalent and Cerebras-equivalent free-tier capacity, see **Cloudflare Workers AI** in the provider stack above — it now leads every fallback chain via `opencode-fallback.jsonc` (11-entry progressive chain).

### API Key Management

All keys stored in `~/.config/opencode/.*-key` files, loaded by two mechanisms:

**1. `oc` alias** (`alias oc='opencode --port 42069'` in `.bashrc`/`.zshrc`) — loads at shell login:
```
.cerebras-key          → CEREBRAS_API_KEY        # DEFUNCT — see Defunct Providers section
.mistral-key           → MISTRAL_API_KEY
.sambanova-key         → SAMBANOVA_API_KEY
.google-key            → GOOGLE_API_KEY
.together-key          → TOGETHER_API_KEY
.zen-key               → OPENCODE_ZEN_API_KEY
.fireworks-key         → FIREWORKS_API_KEY
.exa-key               → EXA_API_KEY
.nvidia-key            → NVIDIA_API_KEY           # NVIDIA NIM — free prototyping, ~40 RPM shared
.baseten-key           → BASETEN_API_KEY          # Baseten — $30 free credits, pay-per-token after
.google-client-id      → GOOGLE_CLIENT_ID
.google-client-secret  → GOOGLE_CLIENT_SECRET
.composio-key          → COMPOSIO_API_KEY
```

**2. Shell profiles** (`dot_bashrc`, `dot_zshrc.tmpl`) — load at shell login for non-opencode use.

Both use the same key files. Shell profiles mirror the key files loaded by opencode core at startup.

> **Note:** The `~/.local/bin/oc` launcher script was deprecated in favor of the shell alias. The alias sets `--port 42069` for tmux subagent pane streaming compatibility.

### Config Defaults

`~/.config/opencode/opencode.json` provides:

- **`small_model`**: `google/gemini-2.0-flash` (1M context)
- **`provider`**: All 11 live providers (Cloudflare, OpenCode Zen, OpenCode Go, Agnes AI, OpenRouter, Mistral, SambaNova, Google, Together, HuggingFace) with connection details and `{env:VAR}` key refs. Plus the dormant Cerebras block (no agent references it).
- **`compaction`**: `{auto: false, prune: true, reserved: 50000, tail_turns: 40}`
- **`mcp`**: Baseline MCPs (context7, grep_app, websearch, mcp_everything)
- **`plugin`**: `["oh-my-openagent@latest"]` — the OmO plugin is loaded directly by root `opencode.json`

`~/.config/opencode/opencode-fallback.jsonc` provides the global fallback chain for agents without their own `fallback_models` array:

- Free→subsidized→pay chain: cloudflare Workers AI free → openrouter free → opencode-zen free → opencode-go deepseek-v4-flash → google/gemini-2.0-flash (10 entries total — progressive, exhausts free first, pays last via OmO's failure-driven fallback)
- First-match-wins resolution: `.opencode/opencode-fallback.jsonc` (project) > `~/.config/opencode/opencode-fallback.jsonc` (global)

### Global MCP Servers

| MCP | Type | URL / Command | Purpose |
|---|---|---|---|
| **context7** | remote | `https://mcp.context7.com/mcp` | Library documentation lookup |
| **grep_app** | remote | `https://mcp.grep.app` | Code search across GitHub |
| **websearch** | remote | `https://mcp.exa.ai/mcp` (oauth: false, `x-api-key: {env:EXA_API_KEY}`) | Web search (Exa) |
| **mcp_everything** | local | `npx -y @modelcontextprotocol/server-everything` | Test/debug MCP |

### Optional MCP Servers (declared in `opencode.json` directly)

These are declared in `opencode.json` directly (no profile indirection):

| MCP | Type | Profiles | Purpose |
|---|---|---|---|
| **netdata-bylocalhost** | remote | all except desk | Server monitoring |
| **chrome-devtools** | local | all | Browser automation |
| **codemem** | local | all except desk | Memory/context management (used by better-compaction.ts) |
| **google-workspace** | local | web | Google Calendar/Docs/Tasks (`{env:GOOGLE_CLIENT_ID}`, `{env:GOOGLE_CLIENT_SECRET}`) |
| **google-tasks-calendar** | local | mybrain project only | Minimal Google Tasks MCP — moved from zen to `~/mybrain/.opencode/` |

## Model Selection Priorities (Team Profile, merged with Go pool)

### Tier 1 — Quality Agents (lower volume, frontier models)

| Agent | Primary | Fallback Chain | Rationale |
|---|---|---|---|
| **Sisyphus** | `opencode-zen/big-pickle` | `opencode-go/kimi-k2.6` → `cloudflare/@cf/moonshotai/kimi-k2.7-code` → `mistral/mistral-large-latest` → `google/gemini-2.0-flash` | 200K ctx, tool calling, reasoning |
| **Prometheus** | `opencode-zen/big-pickle` | `opencode-go/kimi-k2.6` → `cloudflare/@cf/moonshotai/kimi-k2.7-code` → `opencode-go/deepseek-v4-pro` | Planner needs strong reasoning |
| **Metis** | `opencode-go/glm-5.1` | `cloudflare/@cf/zai-org/glm-5.2` → `opencode-zen/glm-5.1` → openrouter/nemotron:free → `opencode-zen/deepseek-v4-flash-free` → `opencode-go/deepseek-v4-flash` | SWE-bench 77.8% |
| **Momus** (xhigh) | `opencode/gpt-5.5` | `opencode-zen/gpt-5.5-pro` → `cloudflare/@cf/moonshotai/kimi-k2.7-code` → `opencode-zen/big-pickle` → `opencode/deepseek-v4-pro` → `opencode-zen/kimi-k2.6` | Critic needs frontier reasoning |
| **Oracle** (xhigh) | `opencode/gpt-5.5` | `opencode-zen/gpt-5.5-pro` → `cloudflare/@cf/nvidia/nemotron-3-120b-a12b` → `opencode-zen/big-pickle` → `opencode/deepseek-v4-pro` → together | Deep reasoning, xhigh variant |
| **Hephaestus** | `opencode/gpt-5.5` | `opencode-zen/gpt-5.5` → `opencode-zen/gpt-5.4` → `cloudflare/@cf/moonshotai/kimi-k2.7-code` → `opencode-zen/nemotron-3-ultra-free` → openrouter/qwen:free | Principle-driven autonomous work |
| **Ultrabrain** (xhigh) | `opencode-go/deepseek-v4-pro` | `cloudflare/@cf/deepseek-ai/deepseek-r1-distill-qwen-32b` → `opencode-zen/big-pickle` → `mistral/mistral-large-latest` → together | Hard logic category |
| **Visual-Engineering** | `opencode/gpt-5.3-codex` | `opencode-zen/gpt-5.3-codex` → openrouter/nemotron-nano:free → `opencode-zen/deepseek-v4-flash-free` → `opencode-go/deepseek-v4-flash` | Codex model for code work |

### Tier 2 — High-Volume Utility Agents (free primary, Go pool fallback)

| Agent | Primary | Fallback Chain |
|---|---|---|
| **Sisyphus-Junior** | `opencode-zen/nemotron-3-ultra-free` | `opencode-go/deepseek-v4-flash` → `zen/deepseek-v4-flash-free` → openrouter/qwen-free |
| **Atlas** | `opencode-go/deepseek-v4-flash` | `cloudflare/@cf/qwen/qwen2.5-coder-32b-instruct` → `opencode-go/kimi-k2.6` → sambanova |
| **Explore** | `cloudflare/@cf/meta/llama-3.3-70b-instruct-fp8-fast` | `cloudflare/@cf/google/gemma-4-26b-a4b-it` → openrouter/nemotron-3-super:free → `opencode-zen/deepseek-v4-flash-free` → `opencode-go/deepseek-v4-flash` |
| **Librarian** | `cloudflare/@cf/meta/llama-3.3-70b-instruct-fp8-fast` | `cloudflare/@cf/nvidia/nemotron-3-120b-a12b` → openrouter/nemotron-3-super:free → `opencode-zen/deepseek-v4-flash-free` → `opencode-go/qwen3.5-plus` → `opencode-go/deepseek-v4-flash` |
| **Quick** | `opencode-zen/nemotron-3-ultra-free` | `opencode-go/deepseek-v4-flash` → `zen/deepseek-v4-flash-free` → openrouter/qwen-free |
| **Unspecified-Low** | `opencode-zen/nemotron-3-ultra-free` | `opencode-go/deepseek-v4-flash` → `zen/deepseek-v4-flash-free` → openrouter/qwen-free |

### Tier 3 — Specialized

| Agent | Primary | Rationale |
|---|---|---|
| **Multimodal-Looker** | `huggingface/google/gemma-4-26B-A4B-it` | Vision-specific, MoE, 262K ctx, tools ✅ |
| **Artistry** | `huggingface/google/gemma-4-26B-A4B-it` | Non-conventional, creative approaches |
| **Writing** | `cloudflare/llama-3.3-70b` | Fast, good prose, no Go dependency |

## Key Decisions

1. **Big Pickle as Sisyphus primary**: 200K context, tool calling, reasoning, structured output. Free on OpenCode Zen (limited time).
2. **Gemma 4 12B for Multimodal-Looker**: Encoder-free architecture, 256K context, beats Gemma 3 27B at half the size.
3. **Free→subsidized→pay global fallback**: The global `opencode-fallback.jsonc` chain has 10 entries in progressive order: cloudflare Workers AI free (`@cf/meta/llama-3.3-70b`, `@cf/openai/gpt-oss-20b`, `@cf/zai-org/glm-4.7-flash`) → openrouter free (`nvidia/nemotron-3-super-120b-a12b:free`, `nvidia/nemotron-3-nano-30b-a3b:free`) → opencode-zen free (`nemotron-3-ultra-free`, `deepseek-v4-flash-free`, `mimo-v2.5-free`) → subsidized opencode-go (`deepseek-v4-flash`) → pay-tier last resort `google/gemini-2.0-flash`. Free tier is exhausted first by OmO's failure-driven fallback; pays last.
4. **OmO is the only plugin**: As of 2026-07-18, `opencode.json` declares `["oh-my-openagent@latest"]` as the sole plugin. Profile variants (`opencode-runtime-fallback` for desk/web, no-plugin for pure/test) are obsolete — deleted with the rest of `profiles/`. Skills from `~/.config/opencode/skills/` continue to load via OpenCode core, not OmO.
5. **Go pool merged in** (Jun 2026): The former `go` and `zen` profile variants were consolidated into root config. 24 Go pool models (K2.6/K2.7, DS-V4-Pro/Flash, GPT-5.x, Qwen3.x) and Zen-aligned critics (gpt-5.4) are all in `oh-my-openagent.jsonc` directly now.
6. **MoE preference**: All selected models use Mixture of Experts for efficiency.
7. **Auto-compaction**: `opencode.json` declares `{auto: false, prune: true, reserved: 50000, tail_turns: 40}` — manual compaction only. This avoids disrupting background-task `<system-reminder>` delivery on the `chat.message` hook chain, which was identified as a known failure mode in 2026-07. Project-level `<project>/.opencode/opencode.json` can override to `{auto: true}` if a specific project wants auto-compaction back.
8. **Single global config layer**: Root `opencode.json` is authoritative for providers and MCPs. No per-profile overrides. Machine differences via chezmoi templates and per-project `<project>/.opencode/` overrides only.
9. **GPT model routing** (Jun 2026): GPT-5.x models require the `opencode` provider prefix (Go binary built-in), NOT `opencode-go` or `opencode-zen`. See [GPT Model Routing](#gpt-model-routing) below for details.

## GPT Model Routing

GPT-5.x models have specific routing requirements that differ from other providers. Understanding these is critical for GPT agents to work.

### The Three GPT Provider Prefixes

| Prefix | Type | GPT Works? | Notes |
|---|---|---|---|
| `opencode/gpt-5.x` | Go binary built-in (subscription) | ✅ YES | Use this for all GPT agents. Routes through the opencode subscription pool. |
| `opencode-go/gpt-5.x` | Go binary built-in (separate provider) | ❌ "Model not supported" | Internal model validation rejects GPT names. Does NOT work for GPT models. |
| `opencode-zen/gpt-5.x` | Zen proxy (`@ai-sdk/openai-compatible`) | ❌ HTTP 400 | Routes to `/v1/chat/completions`, but GPT models need `/v1/responses` (Responses API). |

### Why `opencode-zen` Fails for GPT

The `opencode-zen` provider uses `@ai-sdk/openai-compatible` which only calls `/v1/chat/completions`. GPT-5.x models on opencode.ai require the OpenAI Responses API at `/v1/responses`. Switching the npm package to `@ai-sdk/openai` doesn't fix this — that SDK validates model names against its own registry and rejects `gpt-5.5` (an opencode alias, not an official OpenAI model ID).

### Why `opencode-go` Fails for GPT

The `opencode-go` provider is a separate built-in provider in the Go binary. Its internal model list does NOT include GPT model names. The binary rejects `gpt-5.5` with `AI_APICallError: Model gpt-5.5 is not supported`.

### BYOK vs Shared Pool

The `opencode-zen` proxy has two modes for GPT models:
1. **BYOK (Bring Your Own Key)**: If you've linked a personal OpenAI API key in your opencode.ai account, zen routes GPT requests through YOUR key. If your key has no balance, you get `insufficient_quota`.
2. **Shared pool**: If no BYOK is linked, zen uses the opencode subscription's shared OpenAI pool.

**Recommendation**: Remove any BYOK OpenAI key from your opencode.ai account settings. The shared pool has separate quota and works for all GPT variants via the Responses API.

### Correct GPT Agent Configuration

For agents that need GPT (Momus, Oracle, Hephaestus, Visual-Engineering):

```jsonc
"oracle": {
  "model": "opencode/gpt-5.5",           // ← opencode/ prefix (NOT opencode-go/)
  "variant": "xhigh",
  "fallback_models": [
    "opencode-zen/gpt-5.5-pro",          // ← zen as fallback (uses shared pool, responses API via curl)
    "opencode-zen/big-pickle",            // ← non-GPT fallback
    "opencode/deepseek-v4-pro",           // ← non-GPT subscription fallback
    "together/deepseek-ai/DeepSeek-R1"
  ]
}
```

### Config File Hierarchy (Critical)

OmO configs are loaded in two layers:

1. **Root**: `~/.config/opencode/oh-my-openagent.jsonc` — read as `.jsonc` (with `parseJsonc`). Authoritative for all agents and categories on this machine.
2. **Project-level**: `<project>/.opencode/oh-my-openagent.jsonc` — **overrides root**. THIS is where project-specific agent tuning goes.
3. The OmO plugin's `omoConfig` path resolves to `{configDir}/oh-my-openagent.json` — but the runtime reads `.jsonc` via `parseJsonc`.

**Key lessons learned:**
- Editing the root `.jsonc` is the global change; the project-level `.opencode/oh-my-openagent.jsonc` overrides it for that project only.
- The `.jsonc` file (with comments) is the source of truth. A stripped `.json` copy is also read but comments-stripping must preserve URLs and strings.
- Config changes require a **restart** to take effect (OmO caches config at process startup).
- `runtime_fallback.retry_on_errors` must include **400** (not just 500-series) for GPT fallback to trigger on zen's chat-completion 400s.

### Intermittent OpenAI Server Errors

The `opencode` provider (Go binary subscription) may return intermittent `server_error` from OpenAI. These are transient — the `server_error` comes from OpenAI's side, not from the routing or auth. Retry the request; it will usually succeed within 1-2 attempts.

The `runtime_fallback` config with `retry_on_errors: [400, 401, 402, 403, 429, 500, 502, 503, 504, 529]` handles this — failed requests automatically fall through to fallback models.

## Zen Provider Model Catalog (Live)

The `opencode-zen` provider (`https://opencode.ai/zen/v1`) serves 49+ models — far more than declared in config.

**Check for changes:**
```bash
curl -s -H "Authorization: Bearer $(cat ~/.config/opencode/.zen-key)" \
  https://opencode.ai/zen/v1/models | jq '.data[].id' | sort
```

**BYOK (Bring Your Own Key) — Important:** The zen proxy supports BYOK for OpenAI models. If you've linked a personal OpenAI API key in your opencode.ai account settings, zen routes GPT/Claude requests through YOUR key instead of the shared subscription pool. If your personal key has no balance, you'll get `insufficient_quota` errors. **Remove the BYOK key from your opencode.ai account to use the shared subscription pool instead.**

#### GPT Family
`gpt-5.5`, `gpt-5.5-pro`, `gpt-5.4`, `gpt-5.4-pro`, `gpt-5.4-mini`, `gpt-5.4-nano`, `gpt-5.3-codex-spark`, `gpt-5.3-codex`, `gpt-5.2`, `gpt-5.2-codex`, `gpt-5.1`, `gpt-5.1-codex-max`, `gpt-5.1-codex`, `gpt-5.1-codex-mini`, `gpt-5`, `gpt-5-codex`, `gpt-5-nano`

#### Claude Family
`claude-fable-5`, `claude-opus-4-8`, `claude-opus-4-7`, `claude-opus-4-6`, `claude-opus-4-5`, `claude-opus-4-1`, `claude-sonnet-4-6`, `claude-sonnet-4-5`, `claude-sonnet-4`, `claude-haiku-4-5`

#### Gemini
`gemini-3.5-flash`, `gemini-3.1-pro`, `gemini-3-flash`

#### Other Quality
`deepseek-v4-pro`, `deepseek-v4-flash`, `glm-5.1`, `glm-5`, `kimi-k2.6`, `kimi-k2.5`, `qwen3.6-plus`, `qwen3.5-plus`, `big-pickle`, `minimax-m2.7`, `minimax-m2.5`, `grok-build-0.1`

#### Free Tier
`nemotron-3-ultra-free`, `north-mini-code-free`, `deepseek-v4-flash-free`, `qwen3.6-plus-free`, `minimax-m3-free`, `mimo-v2.5-free`

## Compaction Configuration

Global default: `{auto: false, prune: true, reserved: 50000, tail_turns: 40}`

- `auto: false` (global default): Manual compaction only — triggers at task boundaries, not token thresholds. Profiles `free`, `desk`, `web`, `pure`, `test` override to `auto: true`.
- `prune: true`: Prunes invisible system messages
- `reserved: 50000`: Budget for manual compaction
- `tail_turns: 40`: Preserves post-compaction context
- `small_model`: `google/gemini-2.0-flash` (1M context — sees full session before compacting)
  - **Used for**: Compaction (session summarization) + title generation. NOT used for agentic tasks.
  - **Key constraint**: Must have ≥1M context to ingest full session history before summarizing.
  - **No tool calling required**: Compaction is plain text summarization.
  - **Best choices**: `google/gemini-2.0-flash` (current, free 1M), `nvidia/thinkingmachines/inkling` (free 1M on NIM, 32K output limit)
  - **Avoid**: Models with <500K context (can't see full sessions), reasoning models (overkill for summarization)
- `team` has `auto: false` (manual compaction only — preserves context for long code sessions)

## Global Fallback Config (`opencode-runtime-fallback`)

The global `opencode-fallback.jsonc` chain is used for:

1. **Non-agent model calls** — `small_model` (compaction/title gen), any ad-hoc model usage outside agent context
2. **Safety net** — when an agent's per-agent `fallback_models` chain is *also* exhausted
3. **Project-level overrides** — `.opencode/opencode-fallback.jsonc` can shadow the global chain per-project

Since all agents in `oh-my-openagent.jsonc` have their own `fallback_models`, the global chain primarily serves as the "last resort before failure" for any model call not routed through a specific agent.

Profiles using `opencode-runtime-fallback` (desk, web) get model fallback via the plugin. The global config at `~/.config/opencode/opencode-fallback.jsonc`:

```jsonc
{
  "enabled": true,
  "retry_on_errors": [400, 401, 402, 403, 429, 500, 502, 503, 504, 529],
  "max_fallback_attempts": 6,
  "cooldown_seconds": 60,
  "timeout_seconds": 120,
  "notify_on_fallback": true,
  "fallback_models": [
    "cloudflare/@cf/meta/llama-3.3-70b-instruct-fp8-fast",
    "cloudflare/@cf/openai/gpt-oss-20b",
    "cloudflare/@cf/zai-org/glm-4.7-flash",
    "openrouter/nvidia/nemotron-3-super-120b-a12b:free",
    "openrouter/nvidia/nemotron-3-nano-30b-a3b:free",
    "opencode-zen/nemotron-3-ultra-free",
    "opencode-zen/deepseek-v4-flash-free",
    "opencode-zen/mimo-v2.5-free",
    "opencode-go/deepseek-v4-flash",
    "google/gemini-2.0-flash"
  ]
}
```

**Resolution order** (first-match-wins):
1. `.opencode/opencode-fallback.jsonc` — project-local
2. `~/.config/opencode/opencode-fallback.jsonc` — global

Per-agent `fallback_models` in `opencode.json` `agent` blocks take priority over the global chain.

### OmO Runtime Fallback

Profiles with OmO (free, team) use OmO's built-in `runtime_fallback` in `oh-my-openagent.json` instead:

## Provider Concurrency Limits (Team Profile)

```json
{
  "defaultConcurrency": 8,
  "providerConcurrency": {
    "opencode": 15,
    "opencode-zen": 15,
    "opencode-go": 8,
    "openrouter": 6
  },
  "modelConcurrency": {
    "opencode-zen/big-pickle": 2,
    "opencode-go/kimi-k2.6": 3,
    "opencode-go/deepseek-v4-pro": 2,
    "opencode-go/gpt-5.5": 2,
    "opencode-go/gpt-5.4": 2,
    "opencode-go/gpt-5.3-codex": 2,
    "opencode-go/glm-5.1": 2,
    "opencode-go/deepseek-v4-flash": 15,
    "opencode-zen/kimi-k2.6": 2
  }
}
```

### Free Profile Concurrency

```json
{
  "defaultConcurrency": 5,
  "providerConcurrency": {
    "opencode": 10,
    "openrouter": 5
  },
  "modelConcurrency": {}
}
```

## TUI Theme
- Active: `tokyonight` (via `tui.json`)
- Alternative: `solarized-dark` (custom theme in `themes/`)

## Maintenance

### Updating OpenCode/OmO Config

When modifying `~/.config/opencode/` files (root config, OmO config, fallback chain, keys, plugins):

1. Make changes on disk
2. Verify with `chezmoi diff` to see what drifted
3. Capture changes with `chezmoi re-add <file>` or `chezmoi add <file>` (if new)
4. Commit and push using the **dotfiles skill** (`/dotfiles`) standard commit flow

### Updating the Root Config Layers

- `opencode.json` — providers, MCPs, compaction, `plugin` declaration
- `oh-my-openagent.jsonc` — per-agent `model` + `fallback_models` arrays, category routing, concurrency
- `opencode-fallback.jsonc` — global free→subsidized→pay fallback chain (10 entries)
- `dispatch-rules.json` — 26 starter rules consumed by Sisyphus at intent-gate time

All four are chezmoi-tracked. `chezmoi re-add` each after edits, then standard commit flow.

### Adding a New API Key

1. Create key file: `echo -n '<key>' > ~/.config/opencode/.<provider>-key`
2. If the key is referenced via `{env:VAR}` in `opencode.json`, ensure the env var name matches. Opencode core reads the `.*-key` files at startup and maps them to env vars based on provider convention.
3. The shell profiles (`dot_bashrc`, `dot_zshrc.tmpl`) mirror the key files for non-opencode use — add the new mapping there too.
4. `chezmoi add --encrypt ~/.config/opencode/.<provider>-key` (use `--encrypt` for secrets)
5. Commit all changes via the **dotfiles skill** (`/dotfiles`)

### Adding a New MCP

1. Add to `~/.config/opencode/opencode.json` under `mcp`
2. `chezmoi re-add ~/.config/opencode/opencode.json`
3. Commit and push via the **dotfiles skill** (`/dotfiles`)

This is the only step needed — root config is authoritative for MCPs (no profile indirection).

## Fleet State Writer Fixes (2026-07-22)

Root cause analysis of 24 subagent sessions stuck in "running" state:

### Root Causes Found

1. **`session.diff` / `session.updated` overwrite terminal states.** The event handler mapped unrecognized event types to `"running"`. `session.diff` fires ~8ms after `session.idle`, overwriting `"completed"` back to `"running"`.
2. **Error objects serialized as `[object Object]`.** `String(error)` on Error objects loses the message. Fixed to use `error?.message ?? String(error)`.
3. **No staleness detection.** Tasks stuck in `"running"` for days/weeks were never garbage collected.
4. **`session.status` events also overwrote terminal states.** Same fallthrough bug as `session.diff`.

### Fixes Applied

- **Terminal-state protection**: `updateTask()` now checks if the task is already in a terminal state (`completed`, `failed`, `cancelled`) and refuses to overwrite.
- **No-op event mapping**: `session.diff` and `session.updated` events are now skipped entirely in the event handler (they don't affect task status).
- **Staleness GC**: `loadState()` runs `gcStaleTasks()` on every read — any `"running"` task older than 4 hours is marked `"failed"` with `[gc: stale after Xh]` in the digest.
- **Error serialization**: Fixed to extract `error.message` from Error objects.
- **Fallback transition logging**: Chat messages containing fallback keywords are logged to `wake.log` as `fallback` events.
- **`HF_API_KEY` loading**: Added `export HF_API_KEY="$(cat $HOME/.config/opencode/.hf-key)"` to `.bashrc`.

### Runtime Fallback Changes

- `runtime_fallback.max_fallback_attempts`: 1 → 3 (more retries before giving up)
- `runtime_fallback.cooldown_seconds`: 30 (unchanged)
- `runtime_fallback.timeout_seconds`: 60 (unchanged)

## HuggingFace Provider Reference (Empirical, 2026-07-22) — DORMANT

> **DORMANT as of 2026-07-22.** Zero free models verified via API. Provider block retained in `opencode.json` for manual/direct use only. Removed from all OmO agent/category fallback chains. See Defunct Providers.

### Pricing Model — NO FREE TIER

HF Inference Providers is a **pass-through router** at `https://router.huggingface.co/v1` routing to 17+ third-party providers (DeepInfra, Novita, Together, Groq, Cerebras, etc.). No HF markup — you pay provider rates.

| Tier | Monthly Cost | Credits | Notes |
|------|-------------|---------|-------|
| Free | $0 | $0.10/mo starting balance | **NOT a free tier.** Once exhausted → 402 on ALL models. Exhausts in ~100-200 agent turns. |
| PRO | $9/mo | $2.00/mo | Still paid per-token after credits |

**Verified via API**: `is_free: false` on every model × every provider. The `$0.10/mo` is a one-time credit, not a renewable free tier.

### Rate Limits

- **Inference Providers**: No fixed per-minute limits. Billing by token against credit balance. **402 on exhaustion** (not 429).
- **Provider auto-failover**: Use `:fastest` or `:cheapest` suffix for automatic routing around dead endpoints.
- **Concurrency recommendation**: `providerConcurrency.huggingface: 2` — paid provider, credit-limited.

### HF Provider Models (9 models, verified via `/v1/models` API)

| Model | Cheapest Provider | Context | Output | In $/M | Out $/M | Tools | t/s | Notes |
|-------|------------------|---------|--------|--------|---------|-------|-----|-------|
| openai/gpt-oss-120b | DeepInfra | 128K | 32K | $0.04 | $0.17 | Yes | 48 | Best bang-for-buck |
| openai/gpt-oss-20b | DeepInfra | 128K | 16K | $0.03 | $0.14 | Yes | 80 | Fastest, cheapest |
| deepseek-ai/DeepSeek-V4-Flash | DeepInfra | 1024K | 16K | $0.09 | $0.18 | Yes | 25 | Huge context, cheap |
| deepseek-ai/DeepSeek-V4-Pro | DeepInfra | 1024K | 32K | $1.30 | $2.60 | Yes | 43 | Frontier quality |
| Qwen/Qwen3-Coder-480B-A35B | Novita | 256K | 32K | $0.38 | $1.55 | Yes | 59 | Dedicated code MoE |
| Qwen/Qwen3-235B-A22B-2507 | DeepInfra | 256K | 8K | $0.09 | $0.55 | Yes | 48 | Budget MoE |
| google/gemma-4-26B-A4B-it | DeepInfra | 256K | 32K | $0.07 | $0.34 | Yes | 24 | **THINKING MODEL** — content=null, reasoning tokens consume max_tokens |
| meta-llama/Llama-3.3-70B | Novita | 128K | 16K | $0.14 | $0.40 | Yes | 37 | ⚠️ novita caps at 5K ctx. Use `:groq` for 128K |
| deepseek-ai/DeepSeek-R1-0528 | DeepInfra | 160K | 8K | $0.50 | $2.15 | No | 21 | Reasoning model, no tool calling |

**Removed**: `Qwen/QwQ-32B` — returns 400 "model not supported" on HF router. Not available via Inference Providers.

### Gotchas (Verified Empirically)

1. **Gemma 4 26B is a thinking model**: `content: null`, reasoning tokens in `reasoning` field. Must set `max_tokens >= 200` to get actual output content. Reasoning tokens count toward output budget.
2. **Llama 3.3 70B novita context = 5K**: The novita provider caps context at 5K (!!) despite model supporting 128K. Use `meta-llama/Llama-3.3-70B-Instruct:groq` for full 128K.
3. **R1-0528 credits**: DeepSeek-R1 costs $0.50/M input — the most expensive model in our HF catalog. Use only for deep reasoning tasks.
4. **Credits exhaust silently**: No warning. First sign is 402 on every request across all models/providers.

### Fallback Chain Placement

**HF is paid-only.** It belongs at the **end** of fallback chains, after all free providers (Cloudflare, OpenRouter free, Zen free, Go flash) are exhausted.

Correct placement:
```
Primary: zen/cloudflare/openrouter (free)
  → Fallback 1-4: other free providers
    → Fallback 5: opencode-go flash (subsidized $10/mo)
      → Fallback 6: huggingface/* (PAID — last resort)
        → Fallback 7: google/gemini-2.0-flash (pay)
```

**Never** put HF models in primary or early fallback positions for high-volume agents (explore, librarian, quick).

### Models NOT on HF

| Model | Status | Alternative |
|-------|--------|-------------|
| Qwen/QwQ-32B | 400 "model not supported" | Use opencode-zen/qwq-32b or openrouter |
| Qwen/Qwen3-Coder-Next | Exists on HF router | Valid alternative to Coder-480B |
| nvidia/Nemotron-Ultra-550B | Exists on HF | Use opencode-zen/nemotron-3-ultra-free instead |

### Broken Models Replaced

| Old (broken) | New (working) | Reason |
|--------------|---------------|--------|
| `huggingface/google/gemma-4-12b-it` | `cloudflare/@cf/google/gemma-4-26b-a4b-it` (free) | 401 Unauthorized, gemma-4-12b deprecated on HF |
| `opencode-zen/nemotron-3-super-free` | `opencode-zen/mimo-v2.5-free` | Model retired: "Did you mean nemotron-3-ultra-free?" |
| `cloudflare/@cf/meta/llama-3.3-70b-instruct-fp8-fast` (explore/librarian/writing primary) | `opencode-zen/deepseek-v4-flash-free` | 24K context too small for ~40K token prompts |

## CE Skill Stagger Dispatch Map

14 parallel subagent dispatch sites across 10 SKILL.md files. Highest-risk thundering herds:

| Site | Max Agents | File | Lines |
|------|-----------|------|-------|
| ce-code-review Stage 4 | ~18 | ce-code-review/SKILL.md | 416-489 |
| ce-code-review Stage 5b | ~15 | ce-code-review/SKILL.md | 576 |
| ce-agent-native-audit | 8 | ce-agent-native-audit/SKILL.md | 38 |
| ce-doc-review | 7 | ce-doc-review/SKILL.md | 133-202 |
| ce-ideate Phase 2 | 6 | ce-ideate/SKILL.md | 340 |
| ce-compound Phase 3 | 6 | ce-compound/SKILL.md | 336-349 |
| ce-ideate Phase 1 | 5 | ce-ideate/SKILL.md | 237-268 |
| ce-compound Phase 1 | 4 | ce-compound/SKILL.md | 117-187 |
| ce-plan Phase 1.1 | 3 | ce-plan/SKILL.md | 240-256 |
| ce-simplify-code | 3 | ce-simplify-code/SKILL.md | 21-23 |
| ce-work | 3+ | ce-work/SKILL.md | 134-187 |
| ce-plan Phase 1.3 | 2 | ce-plan/SKILL.md | 308-313 |
| ce-optimize Phase 3.2 | N | ce-optimize/SKILL.md | 436 |
| ce-optimize Phase 3.3 | N | ce-optimize/SKILL.md | 494 |

**Stagger recommendation**: Add 5-10s jitter between dispatches at each site. `ce-code-review` (18+15 agents) is highest priority. Sites already using bounded parallelism (`ce-code-review`, `ce-doc-review`) benefit from stagger + queue combination.

## Files Reference

| File | Purpose | Managed by |
|---|---|---|
| `~/.config/opencode/opencode.json` | Root config (providers, MCPs, compaction, `plugin` declaration) | chezmoi |
| `~/.config/opencode/oh-my-openagent.jsonc` | OmO agent + category routing + fallback_models chains | chezmoi |
| `~/.config/opencode/opencode-fallback.jsonc` | Global free→subsidized→pay fallback chain (10 entries) | chezmoi |
| `~/.config/opencode/dispatch-rules.json` | 26 starter dispatch rules consumed by Sisyphus at intent gate | chezmoi |
| `~/.config/opencode/AGENTS.md` | Agent behavioral rules (Dispatch Rules + Fleet State Comms sections) | chezmoi |
| `~/.config/opencode/plugins/*.ts` | Auto-loaded TypeScript plugins (better-compaction, fleet-state-writer, go-pool-fallback, go-pool-guard, tmux-patch-keeper) | chezmoi |
| `~/.config/opencode/scripts/*.sh` | Bash reader scripts (fleet-digest.sh, go-pool-check.sh, go-pool-switch.sh) | chezmoi (executable bit preserved) |
| `~/.local/state/opencode-fleet/` | Fleet state tree (state.json + wake.log + digest.txt) — written by `fleet-state-writer.ts`, read by `fleet-digest.sh` | chezmoi tracks `.keep`; live files not tracked |
| `~/.config/opencode/.*-key` | API key files (secret) | chezmoi (encrypted with age) |
| `~/.config/opencode/.tmux-OmOTeam.conf` | tmux layout for team mode | chezmoi |
| `~/.config/opencode/skills/` | OpenCode skills directory (axi, ce-*, dotfiles, dotfiles-chezmoi, grill-with-docs, opencode-omo-config, etc.) | chezmoi |
