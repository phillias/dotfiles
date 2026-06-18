# OpenCode/Oh-My-OpenAgent Configuration Skill

## Purpose

This skill documents the architecture, decisions, and maintenance procedures for the OpenCode and Oh-My-OpenAgent (OmO) configuration across all profiles.

## Architecture Overview

### Two-Layer Config System

Opencode merges a **global config** with a **profile config**. The global config provides defaults; the profile config overrides them.

```
~/.config/opencode/
├── opencode.json                              # Global defaults (providers, MCPs, compaction)
├── profiles/
│   ├── free/opencode.json                     # Free profile config
│   ├── free/oh-my-openagent.json              # Free OmO agent/category config
│   ├── zen/opencode.json                      # Zen profile config
│   ├── zen/oh-my-openagent.json               # Zen OmO agent/category config
│   ├── go/opencode.json                       # Go profile config
│   ├── go/oh-my-openagent.json                # Go OmO agent/category config (JSONC with comments)
│   ├── team/opencode.json                     # Team profile config
│   ├── team/oh-my-openagent.jsonc             # Team OmO config (JSONC — multi-user, comments)
│   ├── team/tui.json                          # Team theme override
│   ├── web/opencode.json                      # Web profile config
│   ├── web/oh-my-openagent.json               # Web OmO config
│   ├── web/opencode-serve.service             # Web systemd service
│   ├── web/service.env                        # Web service environment
│   ├── desk/opencode.json                     # Desk profile (alias for free)
│   ├── desk/oh-my-openagent.json              # Desk OmO config
│   └── pure/opencode.json                     # Pure profile (no OmO plugin)
├── AGENTS.md                                  # Agent behavioral rules
├── .groq-key, .cerebras-key, ...             # API key files (secret)
├── .tmux-OmOTeam.conf                        # tmux layout for team profile
└── skills/                                    # OpenCode skills directory
```

### How Profiles Work

The `~/.local/bin/oc` launcher sets `OPENCODE_CONFIG_DIR` to point at a profile directory. Opencode merges `~/.config/opencode/opencode.json` (global) with that profile's `opencode.json`. **Profile configs override global defaults** — they do NOT deep-merge nested keys.

This means:
- **Global config** defines all 11 providers (with API keys), baseline MCPs, compaction defaults, and no plugins
- **Profile configs** re-declare providers with their model lists, override compaction settings, add profile-specific MCPs, and declare plugins

### Critical Rules

1. **Never symlink.** Profile switching is done via `oc <profile>`, which sets `OPENCODE_CONFIG_DIR`. There are no symlinks involved.
2. **Global config has empty model lists.** Profiles fill in the models they need. The global config only provides provider connection details (baseURL, apiKey) so profiles don't have to repeat them.
3. **Profile configs are self-contained.** Since opencode doesn't deep-merge, each profile must declare its full `provider` block with all models it uses.
4. **`pure` profile has no oh-my-openagent config.** It runs vanilla opencode without the OmO plugin.

### Profile Switching

```bash
# Launch a profile (sets OPENCODE_CONFIG_DIR and loads API keys)
oc zen          # Zen subscription as primary
oc free         # Free providers only (default)
oc go           # Go subscription as primary
oc team         # Team mode with tmux layout
oc web          # Google-provider focus
oc desk         # Alias for free
oc pure         # Vanilla opencode, no OmO plugin

# The team profile also exports TMUX_CONF
oc team         # → also sets TMUX_CONF=~/.config/opencode/.tmux-OmOTeam.conf
```

### Profile Matrix

| Profile | OmO Plugin | Compaction `auto` | MCPs beyond global | Special |
|---|---|---|---|---|
| **free** | yes | true | codemem, google-workspace | Default |
| **desk** | yes | true | google-workspace | Alias for free, different MCP set |
| **go** | yes | true | codemem | Go subscription primary |
| **zen** | yes | **false** | codemem, google-tasks-calendar | Zen primary, manual compaction |
| **team** | yes | **false** | codemem | Team mode + tmux, JSONC omo config |
| **web** | yes | true | codemem, google-workspace | Google focus |
| **pure** | no | true | codemem, google-workspace | Vanilla, no OmO |

### Provider Stack (11 providers)

| Provider | Models | Cost | Role |
|---|---|---|---|
| **OpenCode Zen** | 49+ (GPT-5.x, Claude-4.x, Gemini-3.x, DS-V4, GLM-5, Big Pickle, free tier) | Zen sub | Quality primary |
| **OpenCode Go** | 12 (K2.6, DS-V4-Pro, MiMo, etc.) | $10/mo | Fallback |
| **Groq** | 5 (GPT-OSS 120B/20B, Llama 3.3/4, Qwen3) | Free (14.4K req/day) | Fast fallback (LPU, 394-1000 t/s) |
| **OpenRouter** | 22+ (DS-V4-Flash, Qwen3-Coder, GLM-5, etc.) | Free/Paid | Broadest model selection |
| **Cerebras** | 2 (Llama 3.3 70B, GPT-OSS 120B) | Free (1M tok/day) | Fast 70B backup |
| **Mistral** | 1 (Mistral Large) | Free (1 req/s) | Reasoning, multilingual |
| **SambaNova** | 1 (Llama 3.3 70B) | Free | Fast 70B option |
| **Google** | 1 (Gemini 2.0 Flash) | Free (1500 req/day) | Vision, 1M ctx |
| **Together** | 1 (DeepSeek R1) | Free tier | Reasoning specialist |
| **Kilo Gateway** | 4 (auto-router, Nemotron, Grok Code, Trinity) | Free (200 req/hr) | Auto-router, fast code |
| **HuggingFace** | 5 (R1-0528, Qwen3-Coder-480B, Qwen3-235B, QwQ-32B, Gemma 4 12B) | Free | Reasoning, coding, multimodal |

### API Key Management

All keys stored in `~/.config/opencode/.*-key` files, loaded by two mechanisms:

**1. `oc` launcher** (`~/.local/bin/oc`) — loads at opencode startup only:
```
.groq-key              → GROQ_API_KEY
.cerebras-key          → CEREBRAS_API_KEY
.mistral-key           → MISTRAL_API_KEY
.sambanova-key         → SAMBANOVA_API_KEY
.google-key            → GOOGLE_API_KEY
.together-key          → TOGETHER_API_KEY
.zen-key               → OPENCODE_ZEN_API_KEY
.exa-key               → EXA_API_KEY
.google-client-id      → GOOGLE_CLIENT_ID
.google-client-secret  → GOOGLE_CLIENT_SECRET
```

**2. Shell profiles** (`dot_bashrc`, `dot_zshrc.tmpl`) — load at shell login for non-opencode use.

Both use the same key files. The `oc` launcher's `_load_key` function is the canonical source — shell profiles mirror it.

### Global Config Defaults

`~/.config/opencode/opencode.json` provides:

- **`small_model`**: `google/gemini-2.0-flash` (1M context)
- **`provider`**: All 11 providers with connection details and `{env:VAR}` key refs, empty model lists
- **`compaction`**: `{auto: false, prune: true, reserved: 50000, tail_turns: 40}` — profiles with `auto: true` override this
- **`mcp`**: Baseline MCPs (context7, grep_app, websearch, mcp_everything)
- **No `plugin`** field — profiles declare their own

### Global MCP Servers

| MCP | Type | URL / Command | Purpose |
|---|---|---|---|
| **context7** | http | `https://mcp.context7.com/mcp` | Library documentation lookup |
| **grep_app** | http | `https://mcp.grep.app` | Code search across GitHub |
| **websearch** | http | `https://mcp.websearch.exa.ai/mcp` | Web search (Exa, `{env:EXA_API_KEY}`) |
| **mcp_everything** | local | `npx -y @modelcontextprotocol/server-everything` | Test/debug MCP |

### Profile-Specific MCP Servers

These are declared in profile configs, not global:

| MCP | Type | Profiles | Purpose |
|---|---|---|---|
| **codemem** | local | free, go, pure, team, web, zen | Memory/context management for OmO |
| **netdata-bylocalhost** | remote | all | Server monitoring |
| **chrome-devtools** | local | all | Browser automation |
| **google-workspace** | local | desk, free, pure, web | Google Calendar/Docs/Tasks (`{env:GOOGLE_CLIENT_ID}`, `{env:GOOGLE_CLIENT_SECRET}`) |
| **google-tasks-calendar** | local | zen | Minimal Google Tasks MCP |

## Model Selection Priorities

### Tier 1 — Quality Agents (lower volume, frontier models)

| Agent | Primary (Zen) | Fallback Chain | Rationale |
|---|---|---|---|
| **Sisyphus** | `zen/big-pickle` | `zen/kimi-k2.6` → `go/kimi-k2.6` → cerebras → mistral → gemini | Docker admin specialist, 200K ctx |
| **Prometheus** | `zen/big-pickle` | `zen/kimi-k2.6` → `go/kimi-k2.6` → `go/deepseek-v4-pro` → cerebras | Planner needs strong reasoning |
| **Metis** | `zen/glm-5.1` | `zen/gpt-5.4` → `go/glm-5.1` → groq → cerebras → together | SWE-bench 77.8% |
| **Momus** (xhigh) | `zen/gpt-5.4` | `zen/claude-sonnet-4-6` → `go/kimi-k2.6` → cerebras → together | Critic needs frontier reasoning |
| **Oracle** (xhigh) | `zen/gpt-5.4` | `zen/claude-opus-4-5` → `zen/big-pickle` → `go/deepseek-v4-pro` → cerebras → mistral → together | Deep reasoning, xhigh variant |
| **Hephaestus** | `zen/gpt-5.5` | `zen/gpt-5.4` → `go/deepseek-v4-pro` → cerebras → together | Principle-driven autonomous work |
| **Ultrabrain** (xhigh) | `zen/gpt-5.4` | `zen/claude-opus-4-5` → `zen/big-pickle` → `go/deepseek-v4-pro` → cerebras → together | Hard logic category |
| **Visual-Engineering** | `zen/gpt-5.3-codex` | `zen/claude-sonnet-4-6` → `zen/kimi-k2.6` → `go/deepseek-v4-pro` → openrouter | Codex model for code work |

### Tier 2 — Cheap/High-Volume Agents (zen free → Go flash → zen paid → other free)

| Agent | Primary | Fallback Chain |
|---|---|---|
| **Sisyphus-Junior** | `zen/nemotron-3-ultra-free` | `go/deepseek-v4-flash` → `zen/big-pickle` → groq → cerebras → huggingface |
| **Atlas** | `zen/nemotron-3-ultra-free` | `go/deepseek-v4-flash` → `zen/big-pickle` → `go/kimi-k2.6` → groq → sambanova |
| **Explore** | `zen/nemotron-3-ultra-free` | `go/deepseek-v4-flash` → `zen/big-pickle` → groq → cerebras → huggingface |
| **Librarian** | `zen/nemotron-3-ultra-free` | `go/deepseek-v4-flash` → `zen/big-pickle` → groq → cerebras → gemini |
| **Quick** | `zen/nemotron-3-ultra-free` | `go/deepseek-v4-flash` → `zen/big-pickle` → groq → cerebras → huggingface |
| **Unspecified-Low** | `zen/nemotron-3-ultra-free` | `go/deepseek-v4-flash` → `zen/big-pickle` → groq → cerebras → huggingface → openrouter |

### Tier 3 — Specialized

| Agent | Primary | Rationale |
|---|---|---|
| **Multimodal-Looker** | `huggingface/google/gemma-4-12b-it` | Vision-specific, encoder-free multimodal |
| **Artistry** | `huggingface/google/gemma-4-12b-it` | Non-conventional, creative approaches |
| **Writing** | `groq/llama-3.3-70b-versatile` | Fast, good prose, no Go dependency |

## Key Decisions

1. **Big Pickle as Sisyphus primary**: 200K context, tool calling, reasoning, structured output. Free on OpenCode Zen (limited time).
2. **Owl Alpha demoted to last resort**: Repeated 502 provider errors and poor quality outputs.
3. **Gemma 4 12B for Multimodal-Looker**: Encoder-free architecture, 256K context, beats Gemma 3 27B at half the size.
4. **Free-first fallback philosophy**: Every agent's fallback chain starts with free models, escalates to paid only when necessary.
5. **MoE preference**: All selected models use Mixture of Experts for efficiency.
6. **Zen-primary migration (Jun 2026)**: All agents use `opencode-zen` as primary. Go models are fallback only.
7. **Auto-compaction varies by profile**: `team` and `zen` have `auto: false` (manual compaction only). All others have `auto: true`.
8. **Global config layer (Jun 2026)**: Root `opencode.json` provides provider defaults and baseline MCPs. Profiles override as needed. Since opencode doesn't deep-merge, profiles must still declare full `provider` and `mcp` blocks.

## Zen Provider Model Catalog (Live)

The `opencode-zen` provider (`https://opencode.ai/zen/v1`) serves 49+ models — far more than declared in config.

**Check for changes:**
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

## Compaction Configuration

Global default: `{auto: false, prune: true, reserved: 50000, tail_turns: 40}`

- `auto: false` (global default): Manual compaction only — triggers at task boundaries, not token thresholds. Profiles `free`, `go`, `desk`, `web`, `pure` override to `auto: true`.
- `prune: true`: Prunes invisible system messages
- `reserved: 50000`: Budget for manual compaction
- `tail_turns: 40`: Preserves post-compaction context
- `small_model`: `google/gemini-2.0-flash` (1M context — sees full session before compacting)

## Runtime Fallback

```json
{
  "enabled": true,
  "retry_on_errors": [401, 402, 429, 500, 502, 503, 504, 529],
  "max_fallback_attempts": 2,
  "cooldown_seconds": 120,
  "timeout_seconds": 180
}
```

## Provider Concurrency Limits

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

## TUI Theme
- Active: `tokyonight` (via `tui.json`)
- Alternative: `solarized-dark` (custom theme in `themes/`)

## Maintenance

### Updating Profile Configs

When modifying `~/.config/opencode/` files (profiles, keys, global config):

1. Make changes on disk
2. Verify with `chezmoi diff` to see what drifted
3. Capture changes with `chezmoi re-add <file>` or `chezmoi add <file>` (if new)
4. Commit and push using the **dotfiles skill** (`/dotfiles`) standard commit flow

### Updating the `oc` Launcher

The `oc` script at `~/.local/bin/oc` is chezmoi-managed as `dot_local/bin/executable_oc`. After editing it on disk:

1. Verify: `chezmoi diff ~/.local/bin/oc`
2. Capture: `chezmoi re-add ~/.local/bin/oc`
3. Commit and push via the **dotfiles skill** standard commit flow

### Adding a New API Key

1. Create key file: `echo -n '<key>' > ~/.config/opencode/.<provider>-key`
2. Add `_load_key` line to `~/.local/bin/oc`
3. Add `_load_key` line to `dot_bashrc` / `dot_zshrc.tmpl` in chezmoi source
4. If the key is referenced via `{env:VAR}` in config, ensure the env var name matches
5. Commit all changes via the **dotfiles skill** (`/dotfiles`)

### Adding a New Profile

1. Create `~/.config/opencode/profiles/<name>/` with `opencode.json` (and optionally `oh-my-openagent.json`)
2. Add the profile name to the `case` statement in `~/.local/bin/oc`
3. `chezmoi add` the new profile directory
4. Commit and push via the **dotfiles skill** (`/dotfiles`)

### Adding a New Global MCP

1. Add to `~/.config/opencode/opencode.json` under `mcp`
2. `chezmoi re-add ~/.config/opencode/opencode.json`
3. Commit and push via the **dotfiles skill** (`/dotfiles`)

Note: Profile configs override the global `mcp` block entirely. If a profile needs the new global MCP, add it to that profile's config as well.

## Files Reference

| File | Purpose | Managed by |
|---|---|---|
| `~/.config/opencode/opencode.json` | Global defaults (providers, MCPs, compaction) | chezmoi |
| `~/.config/opencode/profiles/<name>/opencode.json` | Profile-specific opencode config | chezmoi |
| `~/.config/opencode/profiles/<name>/oh-my-openagent.json` | Profile OmO agent/category config | chezmoi |
| `~/.config/opencode/profiles/<name>/oh-my-openagent.jsonc` | Team profile OmO config (JSONC with comments) | chezmoi |
| `~/.config/opencode/AGENTS.md` | Agent behavioral rules | chezmoi |
| `~/.config/opencode/.*-key` | API key files (secret) | chezmoi (some encrypted with age) |
| `~/.local/bin/oc` | Profile launcher script | chezmoi (`dot_local/bin/executable_oc`) |
| `~/.config/opencode/.tmux-OmOTeam.conf` | tmux layout for team profile | chezmoi |
| `~/.config/opencode/skills/` | OpenCode skills directory | chezmoi |
