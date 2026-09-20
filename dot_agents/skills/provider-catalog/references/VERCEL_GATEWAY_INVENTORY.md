# Vercel AI Gateway Model Inventory

**Updated:** 2026-09-20
**Base URL:** `https://ai-gateway.vercel.sh/v1` (OpenAI-compat) / `https://ai-gateway.vercel.sh` (Anthropic Messages)
**Authentication:** `Authorization: Bearer $AI_GATEWAY_API_KEY` or `x-api-key` header
**Key file:** `~/.agents/keys/default/.vercel-gateway-key` (loaded by `load-keys.sh`)
**Total Models:** 376 (16 Anthropic, 20 Grok/xAI, 4 free-tier)
**Providers:** 47 (alibaba, anthropic, azure, bedrock, cerebras, deepseek, google, groq, mistral, moonshotai, openai, togetherai, xai, zai, and more)
**Markup:** Zero (all requests, including system credentials and BYOK)

## Key capabilities (2026-09-20 research)

### BYOK
- Team-level: dashboard-only (manual UI). No REST API for adding credentials.
- Request-scoped: programmatic via `providerOptions.gateway.byok` per-request.
- BYOK has zero markup. Available only on the paid tier and requires purchased AI Gateway Credits.
- Fallback: if BYOK fails, system credentials used (billed against credits).
- BYOK spend does NOT count toward budgets.

### Virtual Models (dynamic route equivalent)
- Custom slugs (`vmc/<slug>`) with fallback chains, provider ordering, sort-by-cost, service tiers.
- CLI-managed: `vercel ai-gateway virtual-models create/list/inspect/edit/remove/restore`.
- More powerful than CF dynamic routes (per-slug settings, CLI management, archive/restore).
- Routing rules (separate): CLI-managed (`vercel ai-gateway rules add`) for team-wide model rewrites/denies.

### Harness surfaces (dedicated endpoints)
- Claude Code: `https://ai-gateway.vercel.sh/claude-code`
- Codex: `https://ai-gateway.vercel.sh/codex/v1`
- Cursor: `https://ai-gateway.vercel.sh/cursor/v1` (normalizes non-spec bodies)
- OpenCode: provider entry in opencode.json
- Kimi CLI: provider entry in config.toml
- Generic coding agent: `https://ai-gateway.vercel.sh/coding-agent/v1`

### Provider options (per-request)
- `order`: provider try order
- `only`: restrict to specific providers
- `sort`: `cost` | `ttft` | `tps`
- `models`: fallback model chain
- `byok`: request-scoped credentials
- `providerTimeouts`: per-provider timeouts
- `serviceTier`: `flex` | `priority` | `fast` (`fast` aliases `priority`)
- `zeroDataRetention`: route to ZDR providers only
- `tags`: observability tags for spend tracking
- `caching`: `auto` for automatic prompt caching

## Evaluation Models

| Model ID | Context | Input Price | Output Price | ZDR | Notes |
|----------|---------|-------------|--------------|-----|-------|
| `typesafe-ai/jev` | 32K | $0.042/MTok | FREE | Yes | System One decisions — immediate access (no waitlist) |

## Daily Driver Standouts (TUI Route)

Fast, cheap, >=128K context, tool-use:

| Model | Context | Reasoning | Tools | Input | Output | Notes |
|-------|---------|-----------|-------|-------|--------|-------|
| `alibaba/qwen3.7-flash` | 991K | Yes | Yes | $0.03/MTok | $0.13/MTok | Best value — near-1M context |
| `deepseek/deepseek-v4-flash-0731` | 1M | Yes | Yes | $0.076/MTok | $0.153/MTok | Full 1M, reasoning |
| `zai/glm-5.3-flash` | 1M | Yes | Yes | $0.15/MTok | $0.50/MTok | 1M context, reasoning |
| `google/gemini-2.5-flash-lite` | 1M | Yes | Yes | $0.10/MTok | $0.40/MTok | 1M context |
| `openai/gpt-5-nano` | 400K | Yes | Yes | $0.05/MTok | $0.40/MTok | Reasoning, small |
| `openai/gpt-4o-mini` | 128K | No | Yes | $0.15/MTok | $0.60/MTok | Proven workhorse |

## Anthropic Models (native Anthropic Messages API)

| Model ID | Context | Input | Output | Notes |
|----------|---------|-------|--------|-------|
| `anthropic/claude-sonnet-5` | 1M | $2/MTok | $10/MTok | Balanced reviewer |
| `anthropic/claude-opus-5` | 1M | $5/MTok | $25/MTok | Flagship |
| `anthropic/claude-fable-5` | 1M | $10/MTok | $50/MTok | 1M context, premium |
| `anthropic/claude-3-haiku` | 200K | $0.25/MTok | $1.25/MTok | Fastest |
| `anthropic/claude-haiku-4.5` | 200K | $0.10/MTok | $0.50/MTok | Budget |
| `anthropic/claude-opus-4.8` | 1M | $5/MTok | $25/MTok | 1M context |

## Grok/xAI Models (Cursor-family)

| Model ID | Context | Notes |
|----------|---------|-------|
| `spacexai/grok-4.1-fast-reasoning` | 1M | $0.20/$0.50 MTok |
| `spacexai/grok-4.20-multi-agent` | 2M | Multi-agent |
| `spacexai/grok-4.20-non-reasoning` | 2M | Non-reasoning |

## High Reasoning Standouts (PR-Reviewer, Gate)

| Model | Context | Input | Output | Notes |
|-------|---------|-------|--------|-------|
| `openai/gpt-5.6-luna` | 1.05M | $0.20/MTok | $1.20/MTok | Flagship — 1M reasoning |
| `anthropic/claude-sonnet-5` | 1M | $2/MTok | $10/MTok | Proven reviewer |
| `deepseek/deepseek-v4-pro` | 1M | $0.66/MTok | $1.98/MTok | Deep 1M reasoning |
| `alibaba/qwen3.7-plus` | 1M | $0.40/MTok | $1.60/MTok | Strong Qwen reasoning |
| `openai/gpt-5.4-mini` | 400K | $0.20/MTok | $1.25/MTok | Reasoning budget option |
| `zai/glm-5.3-flashx` | 1M | $0.37/MTok | $1.25/MTok | GLM reasoning |

## No-Mistakes Gate Candidates

| Model | Context | Reasoning | Input | Output |
|-------|---------|-----------|-------|--------|
| `anthropic/claude-opus-5` | 1M | Yes | $5/MTok | $25/MTok |
| `openai/gpt-5.6-terra` | 1.05M | Yes | $1.00/MTok | $5.00/MTok |
| `anthropic/claude-fable-5` | 1M | Yes | $10/MTok | $50/MTok |
| `deepseek/deepseek-v4-pro` | 1M | Yes | $0.66/MTok | $1.98/MTok |

## Free Tier Models

| Model | Context | Reasoning | Tools | Notes |
|-------|---------|-----------|-------|-------|
| `inclusionai/ling-3.0-flash-fin-free` | 256K | Yes | Yes | Financial domain |
| `inclusionai/ling-3.0-flash-sante-free` | 256K | Yes | Yes | Health domain |
| `inclusionai/ling-3.0-flash-vl-free` | 256K | Yes | Yes | Vision-language |
| `poolside/laguna-s-2.1-free` | 256K | Yes | Yes | Coding model |

## Cost Tracking API

- `GET /v1/credits` — balance and total spend
- `GET /v1/generation?id={id}` — per-request cost, latency, tokens, provider
- `GET /v1/report?start_date=...&end_date=...&group_by=...` — aggregated spend
  (group by: day, user, model, tag, provider, credential_type, ZDR, api_key_name)
- `GET /v1/models/{creator}/{model}/endpoints` — per-provider pricing, uptime, latency

## CF AI GW Weaknesses Solved by Vercel

1. Anthropic model paths — native Anthropic Messages API (CF compat layer breaks)
2. Cursor support — dedicated Cursor surface (CF has none)
3. Cost-based routing — `sort: 'cost'` (CF has none)
4. Budget management — multi-scope budgets (CF's $50/30d failed on custom traffic)
5. Error handling — proper provider failover (CF treats 200-wrapped errors as success)
6. Per-request fallbacks — `models` array (CF is route-level only)
7. Dynamic route management — CLI-managed virtual models (CF custom providers dashboard-only)
8. Spend tracking — `GET /v1/generation` + `GET /v1/report` (CF has no cost API)
9. Cache TTL — proper caching with invalidation (CF serves cached failures for 1800s)
10. Body conditions — per-request options eliminate need (CF only matches metadata.*)

## CF AI GW Weaknesses NOT Solved by Vercel

1. opencode-go — Vercel has no opencode.ai provider; subsidized pool can't ride Vercel
2. opencode-go headers — `x-opencode-session` remains CF-specific

## Implementation plan (for ship task)

1. Install Vercel CLI: `mise install` (pinned at vercel@59.23.2 in mise config)
2. Authenticate CLI: `vercel login` or pass `--token` for CI/automation
3. Refresh API key (current `vck_` key returns auth errors)
4. Create virtual models mirroring CF dynamic routes:
   - `vmc/tui` — daily driver GLM ladder
   - `vmc/high` — high reasoning
   - `vmc/pr-gate` — gate/background
   - `vmc/pr-reviewer` — review second-set-of-eyes
   - `vmc/claude` — Claude family
   - `vmc/codex` — Codex family
   - `vmc/grok` — Grok family
   - `vmc/kimi` — Kimi family
   - `vmc/muse` — Muse family
   - `vmc/cursor` — Cursor family
5. Wire Vercel as fallback in all harness configs:
   - opencode: `vercel` provider entry in opencode.json
   - pi: `vercel` provider in models.json
   - codex: `vercel` provider in config.toml
    - claude: `ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN` (map from `AI_GATEWAY_API_KEY`), `ANTHROPIC_API_KEY` set empty to avoid direct-key preference
   - kimi: `vercel` provider in config.toml
   - muse: (rides Meta directly, not through gateway)
6. Ship via dotfiles PR
