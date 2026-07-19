# OpenCode/Oh-My-OpenAgent Configuration Skill

## Purpose

This skill documents the architecture, decisions, and maintenance procedures for the OpenCode and Oh-My-OpenAgent (OmO) configuration across all profiles.

## Architecture Overview

### Two-Layer Config System

Opencode merges a **global config** with a **profile config**. The global config provides defaults; the profile config overrides them.

```
~/.config/opencode/
├── opencode.json                              # Global defaults (providers, MCPs, compaction)
├── opencode-fallback.jsonc                    # Global fallback chain (free-tier, for opencode-runtime-fallback)
├── profiles/
│   ├── free/opencode.json                     # Free profile config
│   ├── free/oh-my-openagent.json              # Free OmO agent/category config
│   ├── team/opencode.json                     # Team profile config (Go pool merged in)
│   ├── team/oh-my-openagent.jsonc             # Team OmO config (JSONC — multi-user, comments)
│   ├── team/tui.json                          # Team theme override
│   ├── web/opencode.json                      # Web profile config (no OmO)
│   ├── web/opencode-serve.service             # Web systemd service
│   ├── web/service.env                        # Web service environment
│   ├── desk/opencode.json                     # Desk profile (no OmO, lightweight)
│   └── pure/opencode.json                     # Pure profile (no OmO plugin)
├── plugins/
│   ├── better-compaction.ts                   # Auto-loaded: todo tracking, skill generation, codemem
│   ├── go-pool-fallback.ts                    # Auto-loaded: Go pool exhaustion detection
│   └── go-pool-guard.ts                       # Auto-loaded: redirect to free when Go exhausted
├── AGENTS.md                                  # Agent behavioral rules
├── .cerebras-key, ...                           # API key files (secret)
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
3. **Profile configs are self-contained for `mcp` and `provider`.** Since opencode doesn't deep-merge nested keys, each profile must declare its full `mcp` block (including the 4 global baseline MCPs) and `provider` block with all models it uses.
4. **Three plugin profiles exist:** OmO (free, team), opencode-runtime-fallback (desk, web), and none (pure, test).
5. **`opencode-runtime-fallback` uses per-agent `fallback_models`** in `opencode.json` `agent` blocks. The global `opencode-fallback.jsonc` provides a default chain (first-match-wins per location, not merge).
6. **Auto-loaded plugins** in `~/.config/opencode/plugins/` (better-compaction.ts, go-pool-fallback.ts, go-pool-guard.ts) load for ALL profiles regardless of profile config.

### Profile Switching

```bash
# Launch a profile (sets OPENCODE_CONFIG_DIR and loads API keys)
oc free         # Free providers only (default)
oc desk         # Desktop — no OmO, opencode-runtime-fallback + codemem
oc team         # Team mode + tmux (Go pool merged in)
oc go           # Alias for team
oc web          # Google-provider focus — no OmO, opencode-runtime-fallback
oc pure         # Vanilla opencode, no plugins
oc test         # Experimental models, no plugins

# The team profile also exports TMUX_CONF
oc team / oc go # → also sets TMUX_CONF=~/.config/opencode/.tmux-OmOTeam.conf
```

### Profile Matrix

| Profile | Plugin(s) | Compaction `auto` | MCPs beyond global | Special |
|---|---|---|---|---|
| **free** | `oh-my-openagent@latest` | true | netdata-bylocalhost, chrome-devtools, codemem | Default |
| **desk** | `opencode-runtime-fallback` | true | chrome-devtools, codemem | Desktop — no OmO, no netdata |
| **team** | `oh-my-openagent@latest` | **false** | netdata-bylocalhost, chrome-devtools, codemem | Team mode + tmux, Go pool merged in |
| **web** | `opencode-runtime-fallback` | true | netdata-bylocalhost, chrome-devtools, codemem, google-workspace | Google focus — no OmO |
| **pure** | none | true | netdata-bylocalhost, chrome-devtools, codemem | Vanilla, no plugins |
| **test** | none | true | netdata-bylocalhost, chrome-devtools, codemem | Experimental models |

### Provider Stack (10 providers)

| Provider | Models | Cost | Role |
|---|---|---|---|
| **OpenCode Zen** | 49+ (GPT-5.x, Claude-4.x, Gemini-3.x, DS-V4, GLM-5, Big Pickle, free tier) | Zen sub | Quality primary |
| **OpenCode Go** | 24 (K2.6/2.7, DS-V4-Pro/Flash, GPT-5.x, Claude-4.x, Qwen3.x, etc.) | $10/mo | Quality pool, merged into team profile |
| **OpenRouter** | 22+ (DS-V4-Flash, Qwen3-Coder, GLM-5, etc.) | Free/Paid | Broadest model selection |
| **Cloudflare** | 16 (`@cf/...` Workers AI models: Llama 3.3, GPT-OSS 120B, Kimi K2.6/K2.7, GLM 5.2, Qwen 3, Nemotron 3, Gemma 4, etc.) | Free tier | Free-tier leader in fallback chains |
| **Mistral** | 1 (Mistral Large) | Free (1 req/s) | Reasoning, multilingual |
| **SambaNova** | 1 (Llama 3.3 70B) | Free | Fast 70B option |
| **Google** | 1 (Gemini 2.0 Flash) | Free (1500 req/day) | Vision, 1M ctx, pay-tier last resort |
| **Together** | 1 (DeepSeek R1) | Free tier | Reasoning specialist |
| **Kilo Gateway** | 4 (auto-router, Nemotron, Grok Code, Trinity) | Free (200 req/hr) | Auto-router, fast code |
| **HuggingFace** | 5 (R1-0528, Qwen3-Coder-480B, Qwen3-235B, QwQ-32B, Gemma 4 12B) | Free | Reasoning, coding, multimodal |

### Defunct Providers (removed 2026-07-18)

| Provider | Removed because | Date | Cleanup scope |
|---|---|---|---|
| **Groq** | Groq free-tier TPM limits (12K/8K) were chronically hitting rate limits on agentic workloads. Eliminated from all configs; `.groq-key` deleted; no functional replacement needed (Cloudflare has identical GPT-OSS and Llama 3.3 70B models at higher concurrency) | 2026-07-18 | Provider block + fallback chain entries + team/web/free/desk profiles (all 8 profiles removed entirely) |
| **Cerebras** | Account lacked model access despite valid `.cerebras-key`. Verified empirically: every retry attempt returned `Not Found: Model does not exist or you do not have access to it` against `cerebras/llama3.3-70b` and `cerebras/gpt-oss-120b` (observed 3× consecutive failures this session). Dormant provider block retained in `opencode.json` for potential re-enablement, but no agent references it. | 2026-07-18 | Stripped from 8 fallback chains in `oh-my-openagent.jsonc` (sisyphus, prometheus, ultrabrain, deep, artistry, quick, unspecified-high, writing). Provider block + `.cerebras-key` retained as dormant. |

Verification of these removals: schema audit of upstream opencode JSON schema (`https://opencode.ai/config.json` `$defs`) confirmed zero native `fallback` or `retry` keywords. All fallback handling is an OmO-feature, parsed by the OmO plugin, not by opencode core. Free→subsidized→pay progression is enforced by OmO at request-failure time.

For Groq-equivalent and Cerebras-equivalent free-tier capacity, see **Cloudflare Workers AI** in the provider stack above — it now leads every fallback chain via `opencode-fallback.jsonc` (10-entry progressive chain).

### API Key Management

All keys stored in `~/.config/opencode/.*-key` files, loaded by two mechanisms:

**1. `oc` launcher** (`~/.local/bin/oc`) — loads at opencode startup only:
```
.cerebras-key          → CEREBRAS_API_KEY        # DEFUNCT — see Defunct Providers section
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

`~/.config/opencode/opencode-fallback.jsonc` provides the global fallback chain for profiles using `opencode-runtime-fallback`:

- Free-tier fallback chain: cloudflare free → openrouter free → opencode-zen free → opencode-go deepseek-v4-flash → google/gemini-2.0-flash (10 entries total — progressive free→subsidized→pay in `opencode-fallback.jsonc`)
- Only applies to agents without per-agent `fallback_models` in their profile's `opencode.json`
- First-match-wins resolution: `.opencode/opencode-fallback.jsonc` (project) > `~/.config/opencode/opencode-fallback.jsonc` (global)

### Global MCP Servers

| MCP | Type | URL / Command | Purpose |
|---|---|---|---|
| **context7** | remote | `https://mcp.context7.com/mcp` | Library documentation lookup |
| **grep_app** | remote | `https://mcp.grep.app` | Code search across GitHub |
| **websearch** | remote | `https://mcp.exa.ai/mcp` (oauth: false, `x-api-key: {env:EXA_API_KEY}`) | Web search (Exa) |
| **mcp_everything** | local | `npx -y @modelcontextprotocol/server-everything` | Test/debug MCP |

### Profile-Specific MCP Servers

These are declared in profile configs, not global:

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
| **Multimodal-Looker** | `huggingface/google/gemma-4-12b-it` | Vision-specific, encoder-free multimodal |
| **Artistry** | `huggingface/google/gemma-4-12b-it` | Non-conventional, creative approaches |
| **Writing** | `cloudflare/llama-3.3-70b` | Fast, good prose, no Go dependency |

## Key Decisions

1. **Big Pickle as Sisyphus primary**: 200K context, tool calling, reasoning, structured output. Free on OpenCode Zen (limited time).
2. **Gemma 4 12B for Multimodal-Looker**: Encoder-free architecture, 256K context, beats Gemma 3 27B at half the size.
3. **Free→subsidized→pay global fallback**: The global `opencode-fallback.jsonc` chain has 10 entries in progressive order: cloudflare Workers AI free (`@cf/meta/llama-3.3-70b`, `@cf/openai/gpt-oss-20b`, `@cf/zai-org/glm-4.7-flash`) → openrouter free (`nvidia/nemotron-3-super-120b-a12b:free`, `nvidia/nemotron-3-nano-30b-a3b:free`) → opencode-zen free (`nemotron-3-ultra-free`, `deepseek-v4-flash-free`, `mimo-v2.5-free`) → subsidized opencode-go (`deepseek-v4-flash`) → pay-tier last resort `google/gemini-2.0-flash`. Free tier is exhausted first by OmO's failure-driven fallback; pays last.
4. **Lightweight profiles use `opencode-runtime-fallback`** (desk, web) instead of OmO to save ~204 lines of system prompt overhead. Model fallback is preserved; agent routing, concurrency management, and hooks are not. Skills from `~/.config/opencode/skills/` are still available — they're loaded by OpenCode core, not by OmO.
5. **Go pool merged into team profile** (Jun 2026): The `go` and `zen` profiles were consolidated into `team`. `oc go` is now an alias for `oc team`. Team gets 24 Go pool models, Zen-aligned critics (gpt-5.4), and the `no-hephaestus-non-gpt` hook.
6. **MoE preference**: All selected models use Mixture of Experts for efficiency.
7. **Auto-compaction varies by profile**: `team` has `auto: false` (manual compaction only). All others have `auto: true`.
8. **Global config layer**: Root `opencode.json` provides provider defaults and baseline MCPs. Profiles override as needed. Since opencode doesn't deep-merge, profiles must still declare full `provider` and `mcp` blocks.
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

OmO configs are loaded in layers. **Project-level configs override profile-level configs:**

1. **Team profile**: `~/.config/opencode/profiles/team/oh-my-openagent.jsonc` — read as `.jsonc` (with `parseJsonc`)
2. **Project-level**: `<project>/.opencode/oh-my-openagent.jsonc` — **overrides team profile**. THIS is where project-specific agent tuning goes.
3. The OmO plugin's `omoConfig` path resolves to `{configDir}/oh-my-openagent.json` — but the runtime reads `.jsonc` via `parseJsonc`.

**Key lessons learned:**
- Editing the team profile `.jsonc` alone is NOT enough — the project-level `.opencode/oh-my-openagent.jsonc` overrides it.
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
| `~/.config/opencode/opencode-fallback.jsonc` | Global fallback chain for opencode-runtime-fallback | chezmoi |
| `~/.config/opencode/profiles/<name>/opencode.json` | Profile-specific opencode config | chezmoi |
| `~/.config/opencode/profiles/<name>/oh-my-openagent.json` | Profile OmO agent/category config (free) | chezmoi |
| `~/.config/opencode/profiles/<name>/oh-my-openagent.jsonc` | Profile OmO config (team — JSONC with comments) | chezmoi |
| `~/.config/opencode/AGENTS.md` | Agent behavioral rules | chezmoi |
| `~/.config/opencode/plugins/*.ts` | Auto-loaded global plugins (better-compaction, go-pool-*) | chezmoi |
| `~/.config/opencode/.*-key` | API key files (secret) | chezmoi (some encrypted with age) |
| `~/.local/bin/oc` | Profile launcher script | chezmoi (`dot_local/bin/executable_oc`) |
| `~/.config/opencode/.tmux-OmOTeam.conf` | tmux layout for team profile | chezmoi |
| `~/.config/opencode/skills/` | OpenCode skills directory | chezmoi |
