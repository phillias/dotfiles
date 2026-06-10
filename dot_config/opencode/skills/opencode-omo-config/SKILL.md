# OpenCode/Oh-My-OpenAgent Configuration Skill

## Purpose
This skill documents the research, decisions, and priorities behind the OpenCode and Oh-My-OpenAgent (OmO) configuration for both Go-pool and no-Go setups.

## Architecture Overview

### Two-Config Strategy
- **Go config** (`oh-my-openagent.json`): Uses opencode-go pool models as primary for quality. For when the $12/5hr Go subscription is active.
- **No-Go config** (`oh-my-openagent-nogo.json`): Uses free OpenRouter + other free providers. For when Go pool is exhausted or unavailable.
- **Switching**: `go-pool-switch.sh go|nogo|status` toggles between configs.

### Provider Stack (11 providers, 57 models)

| Provider | Models | Cost | Role |
|---|---|---|---|
| **OpenCode Go** | 12 (K2.6, DS-V4-Pro, MiMo, etc.) | $10/mo | Quality primary (Go config) |
| **Groq** | 5 (GPT-OSS 120B/20B, Llama 3.3/4, Qwen3) | Free (14.4K req/day) | Fast primary (LPU, 394-1000 t/s) |
| **OpenRouter** | 22 (DS-V4-Flash, Qwen3-Coder, GLM-5, etc.) | Free/Paid | Broadest model selection |
| **OpenCode Zen** | 3 (Big Pickle, MiMo, Nemtron) | Free (limited) | Big Pickle for Docker admin; DS-V4-Flash Free removed — no longer available for no-Go |
| **Cerebras** | 2 (Llama 3.3 70B, GPT-OSS 120B) | Free (1M tok/day) | Fast 70B backup |
| **Mistral** | 1 (Mistral Large) | Free (1 req/s) | Reasoning, multilingual |
| **SambaNova** | 1 (Llama 3.3 70B) | Free | Fast 70B option |
| **Google** | 1 (Gemini 2.0 Flash) | Free (1500 req/day) | Vision, 1M ctx |
| **Together** | 1 (DeepSeek R1) | Free tier | Reasoning specialist |
| **Kilo Gateway** | 4 (auto-router, Nemotron, Grok Code, Trinity) | Free (200 req/hr) | Auto-router, fast code |
| **HuggingFace** | 5 (R1-0528, Qwen3-Coder-480B, Qwen3-235B, QwQ-32B, Gemma 4 12B) | Free | Reasoning, coding, multimodal |

### Model Selection Priorities

**Sisyphus (Orchestrator)**:
- Go: `opencode-go/kimi-k2.6` (frontier reasoning, SWE-Bench 80.2%)
- No-Go: `opencode-zen/big-pickle` (Docker admin specialist, 200K ctx)
- Ultrawork (turbo): `groq/gpt-oss-120b xhigh` or `opencode-go/deepseek-v4-pro xhigh`

**Hephaestus (Autonomous Project Work)**:
- Go: `opencode-go/deepseek-v4-pro` (principle-driven autonomous work)
- No-Go: `groq/gpt-oss-120b` → `opencode-zen/big-pickle` (Docker/compose tasks)

**Multimodal-Looker (PDFs, Images, Diagrams)**:
- No-Go: `huggingface/google/gemma-4-12b-it` (encoder-free multimodal, 256K ctx, Apache 2.0)

**Quick/Unspecified-Low (Trivial Tasks)**:
- No-Go: `groq/gpt-oss-20b` (1000 t/s) → `cerebras/llama3.3-70b` → `huggingface/google/gemma-4-12b-it` → `sambanova/Meta-Llama-3.3-70B-Instruct` → `openrouter/owl-alpha` (last resort)

### Key Decisions

1. **Big Pickle as Sisyphus primary (no-Go)**: User testing showed excellent Docker administration capabilities. 200K context, tool calling, reasoning, structured output. Free on OpenCode Zen (limited time).

2. **Owl Alpha demoted to last resort**: Repeated 502 provider errors and poor quality outputs. Kept only as final fallback in librarian and unspecified-low chains.

3. **Gemma 4 12B for Multimodal-Looker**: Encoder-free architecture (text+image+audio in single transformer), 256K context, beats Gemma 3 27B at half the size. Apache 2.0.

4. **GLM-5 on OpenRouter**: 744B MoE (40B active), SWE-bench 77.8%, GPQA 86.0%. Frontier open model, comparable to Claude Opus 4.5.

5. **DeepCoder-14B**: Matches o3-mini on LiveCodeBench (60.6%) at 14B params. Available on OpenRouter.

6. **Free-first fallback philosophy**: Every agent's fallback chain starts with free models, escalates to paid only when necessary. Go pool models are last resort in no-Go config.

7. **MoE preference**: All selected models use Mixture of Experts for efficiency — fewer active parameters per token = faster inference at lower cost.

8. **DeepSeek V4 Flash Free removed from no-Go**: The `opencode-zen/deepseek-v4-flash-free` model is no longer available for the no-Go design. The no-Go config (`oh-my-openagent-nogo.json`) has never depended on it — it relies on Groq LPU models (1000 t/s) as primary with Cerebras, SambaNova, Mistral, Google, Together, and HuggingFace as fallbacks. The Go config still uses `opencode-go/deepseek-v4-flash` (Go pool paid version) as a primary for Atlas, unspecified-high, and writing, and `openrouter/deepseek/deepseek-v4-flash:free` (OpenRouter free tier, different endpoint) extensively in fallback chains — neither of those is affected.

### Compaction Configuration
```json
{
  "auto": true,
  "prune": true,
  "reserved": 50000,
  "tail_turns": 40
}
```
- `reserved: 50000`: Only triggers compaction on real volume, not retry noise
- `tail_turns: 40`: Preserves more post-compaction context
- `small_model`: `groq/llama-3.3-70b-versatile` (394 t/s for fast compaction)

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
| `opencode.json` | Main OpenCode config (providers, compaction, MCP, plugins) |
| `oh-my-openagent.json` | Go pool config (active) |
| `oh-my-openagent-go.json` | Go pool config (backup) |
| `oh-my-openagent-nogo.json` | No-Go config (free-only) |
| `opencode-nocodemem.json` | Standalone config |
| `tui.json` | Theme selector |
| `scripts/go-pool-switch.sh` | Toggle Go/no-Go configs |
| `themes/solarized-dark.json` | Custom Solarized Dark theme |
