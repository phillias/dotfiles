# Vercel AI Gateway Model Inventory

**Generated:** 2026-09-18  
**Base URL:** `https://ai-gateway.vercel.sh/v1`  
**Authentication:** `Authorization: Bearer $AI_GATEWAY_API_KEY`  
**Total Models:** 376 (209 high-context ≥128K)

## Evaluation Models

| Model ID | Context | Input Price | Output Price | ZDR | Notes |
|----------|---------|-------------|--------------|-----|-------|
| `typesafe-ai/jev` | N/A | $0.042/MTok | FREE | ✅ | System One decisions — choice/score/boolean |

## Daily Driver Standouts (TUI Route)

Fast, cheap, ≥128K context, tool-use:

| Model | Context | Reasoning | Tools | Input | Output | Notes |
|-------|---------|-----------|-------|-------|--------|-------|
| `alibaba/qwen3.7-flash` | 991K | ✅ | ✅ | $0.03/MTok | $0.13/MTok | **Best value** — near-1M context |
| `deepseek/deepseek-v4-flash-0731` | 1M | ✅ | ✅ | $0.076/MTok | $0.153/MTok | Full 1M, reasoning |
| `zai/glm-5.3-flash` | 1M | ✅ | ✅ | $0.15/MTok | $0.50/MTok | 1M context, reasoning |
| `google/gemini-2.5-flash-lite` | 1M | ✅ | ✅ | $0.10/MTok | $0.40/MTok | 1M context |
| `openai/gpt-5-nano` | 400K | ✅ | ✅ | $0.05/MTok | $0.40/MTok | Reasoning, small |
| `openai/gpt-4o-mini` | 128K | ❌ | ✅ | $0.15/MTok | $0.60/MTok | Proven workhorse |

## High Reasoning Standouts (PR-Reviewer, Gate)

Reasoning + ≥128K context + tool-use:

| Model | Context | Input | Output | Notes |
|-------|---------|-------|--------|-------|
| `openai/gpt-5.6-luna` | 1.05M | $0.20/MTok | $1.20/MTok | **Flagship** — 1M reasoning |
| `anthropic/claude-sonnet-5` | 200K | $0.30/MTok | $1.50/MTok | Proven reviewer |
| `deepseek/deepseek-v4-pro` | 1M | $0.66/MTok | $1.98/MTok | Deep 1M reasoning |
| `alibaba/qwen3.7-plus` | 1M | $0.40/MTok | $1.60/MTok | Strong Qwen reasoning |
| `openai/gpt-5.4-mini` | 400K | $0.20/MTok | $1.25/MTok | Reasoning budget option |
| `zai/glm-5.3-flashx` | 1M | $0.37/MTok | $1.25/MTok | GLM reasoning |
| `minimax/minimax-m3` | 512K | $0.30/MTok | $1.20/MTok | MiniMax reasoning |

## No-Mistakes Gate Candidates

Reasoning + reliability + good context:

| Model | Context | Reasoning | Input | Output |
|-------|---------|-----------|-------|--------|
| `anthropic/claude-opus-5` | 200K | ✅ | $1.50/MTok | $7.50/MTok |
| `openai/gpt-5.6-terra` | 1.05M | ✅ | $1.00/MTok | $5.00/MTok |
| `anthropic/claude-fable-5` | 200K | ✅ | $0.80/MTok | $4.00/MTok |
| `deepseek/deepseek-v4-pro` | 1M | ✅ | $0.66/MTok | $1.98/MTok |

## Free Tier Models

| Model | Context | Reasoning | Tools | Notes |
|-------|---------|-----------|-------|-------|
| `inclusionai/ling-3.0-flash-fin-free` | 256K | ✅ | ✅ | Financial domain |
| `inclusionai/ling-3.0-flash-sante-free` | 256K | ✅ | ✅ | Health domain |
| `inclusionai/ling-3.0-flash-vl-free` | 256K | ✅ | ✅ | Vision-language |
| `poolside/laguna-s-2.1-free` | 256K | ✅ | ✅ | Coding model |

## Agent Family Recommendations

### Codex Workers
Fast, tool-capable, good context:

1. `openai/gpt-5.1-codex-mini` — 400K context, reasoning, $0.25/$2.00/MTok
2. `openai/gpt-4o-mini` — Proven, tools, $0.15/$0.60/MTok
3. `alibaba/qwen3-coder-next` — Coding-focused, $0.50/$1.20/MTok

### Claude Workers
Anthropic-native:

1. `anthropic/claude-3-haiku` — Fastest, $0.25/$1.25/MTok
2. `anthropic/claude-sonnet-5` — Balanced, $0.30/$1.50/MTok

### Grok Workers
X.AI-native:

1. `spacexai/grok-4.1-fast-reasoning` — 1M context, $0.20/$0.50/MTok

### Kimi Workers
Moonshot-native:

1. `moonshotai/kimi-k2-thinking` — 216K context, $0.47/$2.00/MTok

## Integration Pattern

```typescript
import { gateway } from '@ai-sdk/gateway';
import { experimental_evaluate as evaluate } from 'ai';

// Daily driver
const tui = gateway('alibaba/qwen3.7-flash');

// High reasoning
const reviewer = gateway('openai/gpt-5.6-luna');

// Gate
const gate = gateway('anthropic/claude-opus-5');

// Evaluation (Jev) — experimental_evaluate with model string
const triage = await evaluate({
  model: 'typesafe-ai/jev',
  state: 'The support agent issued a full refund to the customer.',
  questions: {
    refunded: {
      type: 'boolean',
      instructions: 'Was a refund issued?',
    },
  },
});
```

## Cost Comparison vs CF AI Gateway

For 1M tokens daily (triage/classification workload):

| Provider | Daily Cost | Monthly Cost |
|----------|------------|--------------|
| Vercel (Jev) | $0.04 | $1.20 |
| CF Gateway (custom) | $0.04 + setup | $1.20 + BYOK |
| Direct TypeSafe | $0.04 (waitlist) | $1.20 |

**Recommendation:** Use Vercel AI Gateway for immediate Jev access. Equivalent pricing, zero markup.

## Next Steps

1. Add Vercel to Firstmate fallback configs (codex, claude, grok, kimi)
2. Create `config/crew-dispatch.json` profile for Jev-router
3. Test Jev triage against real finding data
4. Tune confidence thresholds per calibration run
