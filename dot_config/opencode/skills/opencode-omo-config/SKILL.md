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
| HuggingFace | openai/gpt-oss-120b | 131K | 32K | 0.7 |
| HuggingFace | openai/gpt-oss-20b | 131K | 16K | 0.7 |
| HuggingFace | deepseek-ai/DeepSeek-V4-Flash | 1M | 16K | 0.7 |
| HuggingFace | Qwen/Qwen3-Coder-480B-A35B-Instruct | 262K | 32K | 0.7 |
| HuggingFace | Qwen/Qwen3-235B-A22B-Instruct-2507 | 262K | 8K | 0.7 |
| HuggingFace | Qwen/QwQ-32B | 131K | 8K | 1.0 |
| HuggingFace | google/gemma-4-26B-A4B-it | 262K | 16K | 0.7 |
| HuggingFace | meta-llama/Llama-3.3-70B-Instruct | 131K | 16K | 0.7 |
| HuggingFace | deepseek-ai/DeepSeek-R1-0528 | 131K | 8K | 1.0 |

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
├── .cloudflare-key, .zen-key, .google-key, .go-key, .together-key, .sambanova-key, .mistral-key, .hf-key, .agnes-key, .exa-key  # API keys (secret; .groq-key + any other defunct-key files removed)
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
├── .cloudflare-key, .zen-key, .google-key, .go-key, .together-key, .sambanova-key, .mistral-key, .hf-key, .kilo-key, .exa-key  # API keys (secret; .groq-key + any other defunct-key files removed)
├── .tmux-OmOTeam.conf                         # tmux layout for team mode
├── .google-client-id, .google-client-secret   # OAuth creds for Google Workspace MCP
└── skills/                                    # OpenCode skills directory (axi, ce-*, dotfiles, dotfiles-chezmoi, grill-with-docs, etc.)
```

### Critical Rules

1. **One config, not profiles.** `OPENCODE_CONFIG_DIR` is unset — root `~/.config/opencode/` is authoritative. No `oc <profile>` launcher, no `profiles/` subdirectory. To switch behavior, change `opencode.json` / `oh-my-openagent.jsonc` directly and chezmoi-track the change.
2. **Global config defines providers and MCPs.** `opencode.json` has all 11 live providers with connection details (baseURL, `{env:VAR}` key refs) and populated model lists. The dormant Cerebras provider block is retained in `opencode.json` for potential re-enablement; no agent references it.
3. **OmO owns agent + category routing.** `oh-my-openagent.jsonc` declares per-agent `model` + `fallback_models` arrays, per-category model variants, and `concurrency` limits. Per-agent `fallback_models` take priority over the global `opencode-fallback.jsonc` chain.
4. **`opencode-fallback.jsonc` is global default fallback.** First-match-wins resolution: `.opencode/opencode-fallback.jsonc` (project) > `~/.config/opencode/opencode-fallback.jsonc` (global). Used by the 11 agents that don't specify their own `fallback_models` arrays.
5. **Auto-loaded plugins.** Any `.ts` file in `~/.config/opencode/plugins/` loads for every opencode session regardless of config — currently: `better-compaction.ts`, `fleet-state-writer.ts`, `go-pool-fallback.ts`, `go-pool-guard.ts`, `tmux-patch-keeper.ts`. All run in-process with zero LLM cost on the write side.
6. **No symlinks, no env switching.** Environment homogeneity: every machine running this chezmoi-tracked config runs the same root config. Machine-specific differences live in chezmoi templates (`.tmpl` files) and per-machine `/etc/` overrides — not in opencode profile subdirs.

### Provider Stack (11 providers)

| Provider | Models | Cost | Role |
|---|---|---|---|
| **OpenCode Zen** | 49+ (GPT-5.x, Claude-4.x, Gemini-3.x, DS-V4, GLM-5, Big Pickle, free tier) | Zen sub | Quality primary |
| **OpenCode Go** | 24 (K2.6/2.7, DS-V4-Pro/Flash, GPT-5.x, Claude-4.x, Qwen3.x, etc.) | $10/mo | Quality pool, 24 models in routing |
| **OpenRouter** | 22+ (DS-V4-Flash, Qwen3-Coder, GLM-5, etc.) | Free/Paid | Broadest model selection |
| **Cloudflare** | 16 (`@cf/...` Workers AI models: Llama 3.3, GPT-OSS 120B, Kimi K2.6/K2.7, GLM 5.2, Qwen 3, Nemotron 3, Gemma 4, etc.) | Free tier | Free-tier leader in fallback chains |
| **Mistral** | 1 (Mistral Large) | Free (1 req/s) | Reasoning, multilingual |
| **SambaNova** | 1 (Llama 3.3 70B) | Free | Fast 70B option |
| **Google** | 1 (Gemini 2.0 Flash) | Free (1500 req/day) | Vision, 1M ctx, pay-tier last resort |
| **Together** | 1 (DeepSeek R1) | Free tier | Reasoning specialist |
| **HuggingFace** | 9 (GPT-OSS-120B, GPT-OSS-20B, DS-V4-Flash, Qwen3-Coder-480B, Qwen3-235B, QwQ-32B, Gemma-4-26B, Llama-3.3-70B, R1-0528) | Pass-through (HF router) | Coding, reasoning, multimodal |
| **Agnes AI** | 5 (video, image, flash models) | Free tier | Multimodal (video, image generation) |

### Defunct Providers (removed 2026-07-18)

| Provider | Removed because | Date | Cleanup scope |
|---|---|---|---|
| **Groq** | Groq free-tier TPM limits (12K/8K) were chronically hitting rate limits on agentic workloads. Eliminated from all configs; `.groq-key` deleted; no functional replacement needed (Cloudflare has identical GPT-OSS and Llama 3.3 70B models at higher concurrency) | 2026-07-18 | Provider block + all fallback chain entries (all 8 profile subdirs also deleted root-only config introduced same day) |
| **Cerebras** | Account lacked model access despite valid `.cerebras-key`. Verified empirically: every retry attempt returned `Not Found: Model does not exist or you do not have access to it` against `cerebras/llama3.3-70b` and `cerebras/gpt-oss-120b` (observed 3× consecutive failures this session). Dormant provider block retained in `opencode.json` for potential re-enablement, but no agent references it. | 2026-07-18 | Stripped from 8 fallback chains in `oh-my-openagent.jsonc` (sisyphus, prometheus, ultrabrain, deep, artistry, quick, unspecified-high, writing). Provider block + `.cerebras-key` retained as dormant. |

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
- `team` has `auto: false` (manual compaction only — preserves context for long code sessions)

## Global Fallback Config (`opencode-runtime-fallback`)

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

## HuggingFace Provider Reference

### Pricing Model

HF Inference Providers is a **pass-through router** at `https://router.huggingface.co/v1` routing to 17+ third-party providers (Groq, Together, DeepInfra, Cerebras, etc.). No HF markup — you pay provider rates.

| Tier | Monthly Cost | Credits | Notes |
|------|-------------|---------|-------|
| Free | $0 | $0.10/mo | Exhausts in ~100-200 agent turns |
| PRO | $9/mo | $2.00/mo | 20x credits |

### Rate Limits

- **Inference Providers**: No fixed per-minute limits. Billing by token against credit balance. 402 on exhaustion.
- **Legacy Serverless API**: ~10-20 req/min per IP, silent queuing (no 429), 10-30s cold starts. Do NOT use for agent work.
- **Provider auto-failover**: Use `:fastest` or `:cheapest` suffix for automatic provider routing around dead endpoints.

### HF Provider Models (9 models)

| Model | Context | Output | Temp | Tools | Best For |
|-------|---------|--------|------|-------|----------|
| openai/gpt-oss-120b | 131K | 32K | 0.7 | Yes | Best bang-for-buck coding |
| openai/gpt-oss-20b | 131K | 16K | 0.7 | Yes | Fast cheap subagent |
| deepseek-ai/DeepSeek-V4-Flash | 1M | 16K | 0.7 | Yes | Cheapest, huge context |
| Qwen/Qwen3-Coder-480B-A35B-Instruct | 262K | 32K | 0.7 | Yes | Dedicated code MoE |
| Qwen/Qwen3-235B-A22B-Instruct-2507 | 262K | 8K | 0.7 | Yes | Budget MoE |
| Qwen/QwQ-32B | 131K | 8K | 1.0 | No | Reasoning |
| google/gemma-4-26B-A4B-it | 262K | 16K | 0.7 | Yes | Vision/MoE, multimodal |
| meta-llama/Llama-3.3-70B-Instruct | 131K | 16K | 0.7 | Yes | Reliable all-rounder |
| deepseek-ai/DeepSeek-R1-0528 | 131K | 8K | 1.0 | No | Deep reasoning |

### Broken Models Replaced

| Old (broken) | New (working) | Reason |
|--------------|---------------|--------|
| `huggingface/google/gemma-4-12b-it` | `huggingface/google/gemma-4-26B-A4B-it` | 401 Unauthorized, gemma-4-12b deprecated |
| `opencode-zen/nemotron-3-super-free` (in fallback chains) | `opencode-zen/mimo-v2.5-free` | Model retired: "Did you mean nemotron-3-ultra-free?" |

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
