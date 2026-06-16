# OpenCode/Oh-My-OpenAgent Configuration Skill

## Purpose
This skill documents the research, decisions, and priorities behind the OpenCode and Oh-My-OpenAgent (OmO) configuration for both Go-pool and no-Go setups.

## Architecture Overview

### Profile System

Configs live in `~/.config/opencode/profiles/`. Each profile has:

- **Config files** (actual JSON): `opencode-{profile}.json`, `oh-my-openagent-{profile}.json`
- **Profile directory** (activation point): `profiles/{profile}/` with symlinks to config files

```
profiles/
├── opencode-free.json             # Free config (actual)
├── opencode-zen.json              # Zen config (actual)
├── opencode-go.json               # Go config (actual)
├── oh-my-openagent-free.json      # Free omo config (actual)
├── oh-my-openagent-zen.json       # Zen omo config (actual)
├── oh-my-openagent-go.json        # Go omo config (actual)
├── opencode.json → opencode-free.json           # Active opencode symlink (ALWAYS free)
├── oh-my-openagent.json → oh-my-openagent-free.json  # Default omo symlink (ALWAYS free)
├── free/
│   ├── opencode.json → ../opencode-free.json
│   └── oh-my-openagent.json → ../oh-my-openagent-free.json
├── zen/
│   ├── opencode.json → ../opencode-zen.json
│   └── oh-my-openagent.json → ../oh-my-openagent-zen.json
├── go/
│   ├── opencode.json → ../opencode-go.json
│   └── oh-my-openagent.json → ../oh-my-openagent-go.json
├── desk/
├── web/
└── team/
```

### Critical Rules

1. **`profiles/opencode.json`** and **`profiles/oh-my-openagent.json`** are the top-level "active" symlinks. They ALWAYS point to the **free** configs. Never change these symlinks.
2. **`opencode.json` uses only free providers** (opencode-zen free tier, Groq, OpenRouter free, etc.). It does NOT hold zen subscription models — those belong in oh-my-openagent config only.
3. **Only `*-zen.json` files are edited for zen configuration.** The zen profile is activated by symlinking `~/.config/opencode/oh-my-openagent.json` → `profiles/zen/oh-my-openagent.json` (and similarly for opencode.json).
4. **Switching profiles** means changing the HOME-LEVEL symlinks (`~/.config/opencode/`), not the `profiles/` level symlinks.

### Profile Descriptions

| Profile | Dir | opencode config | oh-my-openagent config | Use Case |
|---|---|---|---|---|
| **Free** | `profiles/free/` | `opencode-free.json` | `oh-my-openagent-free.json` | Default — free providers only |
| **Zen** | `profiles/zen/` | `opencode-zen.json` | `oh-my-openagent-zen.json` | Zen subscription as primary, Go as fallback |
| **Go** | `profiles/go/` | `opencode-go.json` | `oh-my-openagent-go.json` | Go pool as primary |

### Switching

```bash
# Activate zen profile
ln -sf profiles/zen/oh-my-openagent.json ~/.config/opencode/oh-my-openagent.json
ln -sf profiles/zen/opencode.json ~/.config/opencode/opencode.json

# Activate free profile (revert)
ln -sf profiles/free/oh-my-openagent.json ~/.config/opencode/oh-my-openagent.json
ln -sf profiles/free/opencode.json ~/.config/opencode/opencode.json
```

### Provider Stack (11 providers, 57+ models)

| Provider | Models | Cost | Role |
|---|---|---|---|
| **OpenCode Zen** | 16+ (GPT-5.x, Claude, Gemini, DS-V4, GLM-5, Big Pickle, free tier) | Zen sub | Quality primary — see catalog below |
| **OpenCode Go** | 12 (K2.6, DS-V4-Pro, MiMo, etc.) | $10/mo | Fallback only (zen config) |
| **Groq** | 5 (GPT-OSS 120B/20B, Llama 3.3/4, Qwen3) | Free (14.4K req/day) | Fast fallback (LPU, 394-1000 t/s) |
| **OpenRouter** | 22 (DS-V4-Flash, Qwen3-Coder, GLM-5, etc.) | Free/Paid | Broadest model selection |
| **Cerebras** | 2 (Llama 3.3 70B, GPT-OSS 120B) | Free (1M tok/day) | Fast 70B backup |
| **Mistral** | 1 (Mistral Large) | Free (1 req/s) | Reasoning, multilingual |
| **SambaNova** | 1 (Llama 3.3 70B) | Free | Fast 70B option |
| **Google** | 1 (Gemini 2.0 Flash) | Free (1500 req/day) | Vision, 1M ctx |
| **Together** | 1 (DeepSeek R1) | Free tier | Reasoning specialist |
| **Kilo Gateway** | 4 (auto-router, Nemotron, Grok Code, Trinity) | Free (200 req/hr) | Auto-router, fast code |
| **HuggingFace** | 5 (R1-0528, Qwen3-Coder-480B, Qwen3-235B, QwQ-32B, Gemma 4 12B) | Free | Reasoning, coding, multimodal |

### Model Selection Priorities (Zen Config)

**Tier 1 — Quality Agents** (lower volume, frontier models):

| Agent | Primary (Zen) | Fallback Chain | Rationale |
|---|---|---|---|
| **Sisyphus** | `zen/big-pickle` | `zen/kimi-k2.6` → `go/kimi-k2.6` → cerebras → mistral → gemini | Docker admin specialist, 200K ctx |
| **Prometheus** | `zen/big-pickle` | `zen/kimi-k2.6` → `go/kimi-k2.6` → `go/deepseek-v4-pro` → cerebras | Planner needs strong reasoning |
| **Metis** | `zen/glm-5.1` | `zen/gpt-5.4` → `go/glm-5.1` → groq → cerebras → together | Same model on Zen, SWE-bench 77.8% |
| **Momus** (xhigh) | `zen/gpt-5.4` | `zen/claude-sonnet-4-6` → `go/kimi-k2.6` → cerebras → together | Critic needs frontier reasoning |
| **Oracle** (xhigh) | `zen/gpt-5.4` | `zen/claude-opus-4-5` → `zen/big-pickle` → `go/deepseek-v4-pro` → cerebras → mistral → together | Deep reasoning, xhigh variant |
| **Hephaestus** | `zen/gpt-5.5` | `zen/gpt-5.4` → `go/deepseek-v4-pro` → cerebras → together | GPT variant, principle-driven autonomous work |
| **Ultrabrain** (xhigh) | `zen/gpt-5.4` | `zen/claude-opus-4-5` → `zen/big-pickle` → `go/deepseek-v4-pro` → cerebras → together | Deep reasoning category |
| **Visual-Engineering** | `zen/gpt-5.3-codex` | `zen/claude-sonnet-4-6` → `zen/kimi-k2.6` → `go/deepseek-v4-pro` → openrouter | Codex model for code work |

**Tier 2 — Cheap/High-Volume Agents** (zen free → Go flash → zen paid → other free):

| Agent | Primary (Zen) | Fallback Chain |
|---|---|---|
| **Sisyphus-Junior** | `zen/nemotron-3-ultra-free` | `go/deepseek-v4-flash` → `zen/big-pickle` → groq → cerebras → huggingface |
| **Atlas** | `zen/nemotron-3-ultra-free` | `go/deepseek-v4-flash` → `zen/big-pickle` → `go/kimi-k2.6` → groq → sambanova |
| **Explore** | `zen/nemotron-3-ultra-free` | `go/deepseek-v4-flash` → `zen/big-pickle` → groq → cerebras → huggingface |
| **Librarian** | `zen/nemotron-3-ultra-free` | `go/deepseek-v4-flash` → `zen/big-pickle` → groq → cerebras → gemini |
| **Quick** | `zen/nemotron-3-ultra-free` | `go/deepseek-v4-flash` → `zen/big-pickle` → groq → cerebras → huggingface |
| **Unspecified-Low** | `zen/nemotron-3-ultra-free` | `go/deepseek-v4-flash` → `zen/big-pickle` → groq → cerebras → huggingface → openrouter |

**Tier 3 — Specialized**:

| Agent | Primary | Rationale |
|---|---|---|
| **Multimodal-Looker** | `huggingface/google/gemma-4-12b-it` | Vision-specific, encoder-free multimodal |
| **Artistry** | `huggingface/google/gemma-4-12b-it` | Non-conventional, creative approaches |
| **Writing** | `groq/llama-3.3-70b-versatile` | Fast, good prose, no Go dependency |

### Key Decisions

1. **Big Pickle as Sisyphus primary (no-Go)**: User testing showed excellent Docker administration capabilities. 200K context, tool calling, reasoning, structured output. Free on OpenCode Zen (limited time).

2. **Owl Alpha demoted to last resort**: Repeated 502 provider errors and poor quality outputs. Kept only as final fallback in librarian and unspecified-low chains.

3. **Gemma 4 12B for Multimodal-Looker**: Encoder-free architecture (text+image+audio in single transformer), 256K context, beats Gemma 3 27B at half the size. Apache 2.0.

4. **GLM-5 on OpenRouter**: 744B MoE (40B active), SWE-bench 77.8%, GPQA 86.0%. Frontier open model, comparable to Claude Opus 4.5.

5. **DeepCoder-14B**: Matches o3-mini on LiveCodeBench (60.6%) at 14B params. Available on OpenRouter.

6. **Free-first fallback philosophy**: Every agent's fallback chain starts with free models, escalates to paid only when necessary. In the zen config, Go pool models are last-resort fallback (before escalations to zen paid).

7. **MoE preference**: All selected models use Mixture of Experts for efficiency — fewer active parameters per token = faster inference at lower cost.

8. **DeepSeek V4 Flash Free removed from no-Go**: The `opencode-zen/deepseek-v4-flash-free` model is no longer available for the no-Go design. The no-Go config (`oh-my-openagent-nogo.json`) has never depended on it — it relies on Groq LPU models (1000 t/s) as primary with Cerebras, SambaNova, Mistral, Google, Together, and HuggingFace as fallbacks. The Go config still uses `opencode-go/deepseek-v4-flash` (Go pool paid version) as a primary for Atlas, unspecified-high, and writing, and `openrouter/deepseek/deepseek-v4-flash:free` (OpenRouter free tier, different endpoint) extensively in fallback chains — neither of those is affected.

9. **Zen-primary migration (Jun 2026)**: The `oh-my-openagent-zen.json` config now uses `opencode-zen` provider as primary for all agents instead of `opencode-go`. Go models retained exclusively as fallback. The zen profile lives at `profiles/zen/` — activate via home-level symlinks (never change `profiles/oh-my-openagent.json` which always points to free). Key changes:
   - Full model catalog discovered at `https://opencode.ai/zen/v1/models` — 49+ models including GPT-5.x, Claude-4.x, Gemini-3.x, GLM-5.1, etc. — far beyond the 4 originally declared in config.
   - `groq/gpt-oss-120b` removed from all 16 agent/category fallback chains (model no longer accessible on Groq).
   - Auto-compaction disabled (`auto: false`) — manual compaction only.
   - Hephaestus now uses `opencode-zen/gpt-5.5` (GPT variant satisfied on Zen).
   - Cheap/high-volume agents follow: zen-free → Go flash → zen-paid → other free.

### Zen Provider Model Catalog (Live)

The `opencode-zen` provider (`https://opencode.ai/zen/v1`) serves 49+ models — far more than the 4 listed in config. The config only explicitly declares models used; the API returns the full available set.

**Check daily for changes:**
```bash
curl -s -H "Authorization: Bearer $(cat ~/.config/opencode/.zen-key)" \
  https://opencode.ai/zen/v1/models | jq '.data[].id' | sort
```

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

> **Note from Jun 15 2026**: The config previously only declared 4 models. The API returns all of the above. Add to `opencode-zen` provider definition as they're adopted. The `opencode-zen` provider supports all these with the same `opencode-zen/` prefix.

### Compaction Configuration
```json
{
  "auto": false,
  "prune": true,
  "reserved": 50000,
  "tail_turns": 40
}
```
- `auto: false`: Manual compaction only — triggers at task boundaries, not token thresholds
- `prune: true`: Still prunes invisible system messages
- `reserved: 50000`: Budget for manual compaction
- `tail_turns: 40`: Preserves more post-compaction context
- `small_model`: `google/gemini-2.0-flash` (1M context — sees full session before compacting, unlike 131K Groq)

### Runtime Fallback
```json
{
  "enabled": true,
  "retry_on_errors": [401, 402, 429, 500, 502, 503, 504, 529],
  "max_fallback_attempts": 2,
  "cooldown_seconds": 120,
  "timeout_seconds": 180
}
```
- Max 2 fallback attempts to prevent context runaway
- 120s cooldown between attempts
- 180s timeout before fallback (gives slow models time)

### MCP Servers

| MCP | Type | Purpose |
|---|---|---|
| **codemem** | Local | Memory/context management for OmO |
| **netdata-bylocalhost** | Remote | Server monitoring (host-specific) |
| **chrome-devtools** | Local | Browser automation |
| **mcp_everything** | Local | Test-only (removed from standalone) |

### Standalone Config (`opencode-nocodemem.json`)
For instances without codemem:
- No codemem MCP
- No mcp_everything (test-only)
- No netdata (host-specific)
- Minimal: chrome-devtools MCP only
- Same provider stack (groq + openrouter)

### API Key Management
All keys stored in `~/.config/opencode/.*-key` files, loaded via env vars:
- `GROQ_API_KEY` → `.groq-key`
- `CEREBRAS_API_KEY` → `.cerebras-key`
- `MISTRAL_API_KEY` → `.mistral-key`
- `SAMBANOVA_API_KEY` → `.sambanova-key`
- `GOOGLE_API_KEY` → `.google-key`
- `TOGETHER_API_KEY` → `.together-key`

Shell profiles (`dot_bashrc`, `dot_zshrc.tmpl`) load all keys at startup.

### Provider Concurrency Limits
```json
{
  "defaultConcurrency": 5,
  "providerConcurrency": {
    "opencode-go": 5,
    "opencode": 10,
    "openrouter": 5,
    "groq": 5
  },
  "modelConcurrency": {
    "opencode-go/kimi-k2.6": 2,
    "opencode-go/deepseek-v4-pro": 2,
    "opencode-go/deepseek-v4-flash": 10,
    "opencode-go/mimo-v2.5-pro": 3
  }
}
```

### TUI Theme
- Active: `tokyonight` (via `tui.json`)
- Alternative: `solarized-dark` (custom theme in `themes/`)

### Files
| File | Purpose |
|---|---|
| `profiles/opencode.json` → `opencode-free.json` | Active opencode symlink (ALWAYS free — opencode core uses free providers) |
| `profiles/oh-my-openagent.json` → `oh-my-openagent-free.json` | Default oh-my-openagent symlink (ALWAYS free by default) |
| `profiles/opencode-free.json` | Free opencode config (actual) |
| `profiles/opencode-zen.json` | Zen opencode config (full model catalog, no auto-compaction) |
| `profiles/opencode-go.json` | Go pool opencode config |
| `profiles/oh-my-openagent-free.json` | Free oh-my-openagent config (actual) |
| `profiles/oh-my-openagent-zen.json` | Zen oh-my-openagent config (zen-primary, Go as fallback) |
| `profiles/oh-my-openagent-go.json` | Go pool oh-my-openagent config |
| `profiles/oh-my-openagent-zen-team.jsonc` | Zen team variant (jsonc, multi-user) |
| `profiles/opencode-desk.json` | Desk profile opencode config |
| `profiles/opencode-web.json` | Web profile opencode config |
| `profiles/{free,zen,go,desk,web,team}/` | Profile directories — each has symlinks to activate that profile |
| `opencode.json` → `profiles/opencode-free.json` | Home-level opencode symlink (change this to switch profiles) |
| `oh-my-openagent.json` → `profiles/oh-my-openagent-free.json` | Home-level omo symlink (change this to switch profiles) |
| `tui.json` | Theme selector |
| `themes/solarized-dark.json` | Custom Solarized Dark theme |
