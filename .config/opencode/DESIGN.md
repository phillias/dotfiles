# Oh-My-OpenAgent & OpenCode Configuration Design

> **Date:** 2026-05-19
> **Author:** phillias
> **Repo:** [github.com/phillias/dotfiles](https://github.com/phillias/dotfiles) — `.config/opencode/`

---

## Table of Contents

- [Executive Summary](#executive-summary)
- [Problem Statement](#problem-statement)
- [Sources & Citations](#sources--citations)
- [Priorities & Constraints](#priorities--constraints)
- [Model Pools Available](#model-pools-available)
- [Agent Design Decisions](#agent-design-decisions)
  - [Sisyphus (Primary Orchestrator)](#sisyphus-primary-orchestrator)
  - [Sisyphus-Junior (Task Executor)](#sisyphus-junior-task-executor)
  - [Prometheus (Planner)](#prometheus-planner)
  - [Metis (Plan Consultant)](#metis-plan-consultant)
  - [Momus (Plan Reviewer)](#momus-plan-reviewer)
  - [Atlas (Execution Conductor)](#atlas-execution-conductor)
  - [Hephaestus (Builder)](#hephaestus-builder)
  - [Oracle (Architecture Consultant)](#oracle-architecture-consultant)
  - [Explore (Codebase Navigator)](#explore-codebase-navigator)
  - [Librarian (Research)](#librarian-research)
  - [Multimodal-Looker (Vision)](#multimodal-looker-vision)
- [Category Design Decisions](#category-design-decisions)
  - [visual-engineering](#visual-engineering)
  - [ultrabrain](#ultrabrain)
  - [deep](#deep)
  - [artistry](#artistry)
  - [quick](#quick)
  - [unspecified-low](#unspecified-low)
  - [unspecified-high](#unspecified-high)
  - [writing](#writing)
- [Settings & Properties](#settings--properties)
  - [model_fallback](#model_fallback)
  - [runtime_fallback](#runtime_fallback)
  - [ultrawork](#ultrawork)
  - [fallback_models](#fallback_models)
  - [background_task Concurrency](#background_task-concurrency)
  - [variant](#variant)
  - [opencode.json defaults (model, small_model)](#opencodejson-defaults-model-small_model)
- [Budget Analysis](#budget-analysis)
- [Risk Register](#risk-register)
- [Appendix: Model Specifications](#appendix-model-specifications)

---

## Executive Summary

This configuration migrates oh-my-openagent from relying on Anthropic Claude and OpenAI GPT models to a model pool that consists **only** of:

1. **OpenCode Go** — $10/month subscription with shared dollar limits ($12/5hr, $30/wk, $60/mo)
2. **OpenCode Zen Free** — Free models available through the OpenCode Zen platform (no subscription required)
3. **OpenRouter Free** — Free-tier models via OpenRouter (`:free` suffix)

Every agent and category is mapped using the [oh-my-openagent agent-model-matching guide](https://github.com/code-yeongyu/oh-my-openagent) framework, which classifies agents into four types: **Communicators**, **Dual-Prompt**, **Deep Specialists**, and **Utility Runners**. Free models handle high-volume, low-stakes roles; paid Go models are reserved for quality-critical roles where the token cost justifies the value.

---

## Problem Statement

oh-my-openagent was designed with Claude and GPT models as defaults. The canonical model assignments are:

| Agent | Canonical Model | Provider |
|-------|----------------|----------|
| Sisyphus | `claude-opus-4-7` | Anthropic |
| Oracle | `gpt-5.5` | OpenAI |
| Hephaestus | `gpt-5.5` | OpenAI |
| Librarian | `gpt-5.4-mini-fast` | OpenAI |
| Explore | `gpt-5.4-mini-fast` | OpenAI |

**None of these models are available** in the user's available pools (no Anthropic, no OpenAI). Every assignment is an override from the canonical defaults. The official oh-my-openagent guide categorizes overrides as either **Safe** (the model supports the agent's interaction style) or **Dangerous** (the model cannot replicate the agent's canonical behavior).

This configuration minimizes the number of Dangerous overrides and documents unavoidable ones.

---

## Sources & Citations

| # | Source | URL | Relevance |
|---|--------|-----|-----------|
| S1 | [Reddit: From Claude to opencode-go (byungsker)](https://www.reddit.com/r/opencodeCLI/comments/1stn08o/from_claude_to_opencodego_mapping_ohmyagents_to/) | Primary mapping inspiration. Agent-type classification, per-agent reasoning, community feedback on K2.6 loops and usage patterns. |
| S2 | [OpenCode Go Usage Limits](https://opencode.ai/docs/go/) | Official usage table: per-model request estimates within $12/5hr, $30/wk, $60/mo limits. |
| S3 | [oh-my-openagent Configuration Reference](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/configuration.md) | Agent options, category options, model resolution priority, fallback_models format, runtime_fallback, variant, reasoningEffort, textVerbosity. |
| S4 | [oh-my-openagent Agent-Model-Matching Guide](https://github.com/code-yeongyu/oh-my-openagent) | Agent type classification (Communicators, Dual-Prompt, Deep Specialists, Utility Runners). Sisyphus safe override list: "Kimi K2.5/GLM 5/Sonnet". |
| S5 | [oh-my-openagent Orchestration Guide](https://github.com/code-yeongyu/oh-my-openagent) | Three-layer architecture: Planning (Prometheus + Metis + Momus), Execution (Atlas), Worker (specialized agents). |
| S6 | [HuggingFace: Kimi K2.6 Benchmarks](https://huggingface.co/) (cited in Reddit post) | K2.6: SWE-Bench 80.2%, Terminal-Bench 66.7%, GPQA Diamond 91.1%, 135 tok/s. |
| S7 | [OpenCode Zen Pricing](https://opencode.ai/docs/zen/) | Confirms free models (DeepSeek V4 Flash Free, MiniMax M2.5 Free, Nemotron 3 Super Free, Big Pickle) are $0.00 without subscription. |
| S8 | [oh-my-openagent Issue #2393](https://github.com/code-yeongyu/oh-my-openagent/issues/2393) | `model_fallback` intercepts OpenCode's internal retry loop on usage limits, preventing infinite loops. |

---

## Priorities & Constraints

1. **Budget**: Stay within Go's $12/5hr pooled limit during normal sessions (~$7-8 projected).
2. **Model pools only**: `opencode-go/*`, `opencode/*` (Zen free), `openrouter/*:free`.
3. **Quality for critical roles**: Oracle, Sisyphus, Prometheus, and Deep Specialists get the best available models.
4. **Cost for high-volume roles**: Explore, Librarian, Junior, and trivial categories use free models exclusively.
5. **Reliability over rate-limiting**: Zen free models preferred over OpenRouter free where available (no rate limiting).
6. **Resilience**: Every agent has a fallback chain. Both `model_fallback` and `runtime_fallback` are enabled.

---

## Model Pools Available

### OpenCode Go (Paid — $10/mo, $12/5hr shared pool)

| Model | Req/5hr | Notes |
|-------|---------|-------|
| `opencode-go/kimi-k2.6` | 1,150 | Best benchmarks in Go pool; 256K context. |
| `opencode-go/kimi-k2.5` | 1,850 | Good quality, lower cost than K2.6. |
| `opencode-go/deepseek-v4-pro` | 3,450 | Strong reasoning; best available for Deep Specialists. |
| `opencode-go/deepseek-v4-flash` | **31,650** | 27x more efficient than K2.6; excellent value. |
| `opencode-go/mimo-v2.5-pro` | 1,290 | 1M context window; consulting/exploration role. |
| `opencode-go/mimo-v2.5` | 2,150 | Lower cost MiMo variant (≤256K context). |
| `opencode-go/minimax-m2.7` | 3,400 | Moderate cost, general purpose. |
| `opencode-go/minimax-m2.5` | 6,300 | Cheapest Go model for simple tasks. |
| `opencode-go/qwen3.5-plus` | 10,200 | Very cheap; good for utility roles. |
| `opencode-go/qwen3.6-plus` | 3,300 | Moderate, general purpose. |

### OpenCode Zen Free ($0.00)

| Model | Notes |
|-------|-------|
| `opencode/deepseek-v4-flash-free` | Same model as DS-V4-Flash, via Zen free tier. No rate limiting. |
| `opencode/minimax-m2.5-free` | Very capable for a free model. |
| `opencode/nemotron-3-super-free` | NVIDIA free tier — data logged, not for sensitive use. |
| `opencode/big-pickle` | Stealth model, free for limited time. |
| `opencode/qwen3.6-plus-free` | Free variant of Qwen3.6. |

### OpenRouter Free ($0.00, rate-limited)

| Model | Notes |
|-------|-------|
| `openrouter/meta-llama/llama-3.3-70b-instruct:free` | Solid general-purpose free model. |
| `openrouter/qwen/qwen3-coder:free` | Code-specialized. |
| `openrouter/nvidia/nemotron-nano-12b-v2-vl:free` | Vision-language model (multimodal). |

---

## Agent Design Decisions

### Sisyphus (Primary Orchestrator)

**Classification:** Communicators (S1, S4)
**Class traits:** Mechanics-driven prompts (~1,100 lines), instruction-following, Claude/Kimi/GLM-optimized.
**Canonical model:** `anthropic/claude-opus-4-7` — not available.

#### Options Considered

| Option | Req/5hr | Reasoning |
|--------|---------|-----------|
| `opencode-go/kimi-k2.6` | 1,150 | **Selected.** Safe override per guide (S4). Best benchmarks in Go pool: SWE-Bench 80.2%, GPQA Diamond 91.1% (S6). 135 tok/s speed. |
| `opencode-go/kimi-k2.5` | 1,850 | Close second. Cheaper, but K2.6 has significant benchmark advantage. |
| `opencode-go/glm-5.1` | 880 | Listed as safe override but burns budget fastest at 880 req/5hr. Community reports hitting 5hr limit in 2-3 hours with GLM-5.1 (S1). |
| `opencode-go/deepseek-v4-pro` | 3,450 | Excellent efficiency but classified as GPT-optimized. Guide warns non-Communicators models are "bad fit" for Sisyphus (S4). |

**Final:** `opencode-go/kimi-k2.6`

**Fallback chain:** `deepseek-v4-pro` → `deepseek-v4-flash`

**Ultrawork model:** `opencode-go/deepseek-v4-pro` (variant: `xhigh`) — provides a "hard problem" button without making every message expensive.

### Sisyphus-Junior (Task Executor)

**Classification:** Utility Runner (S4)
**Class traits:** Cheapest-fastest, high volume.
**Canonical model:** `opencode/gpt-5-nano` — not available.

#### Options Considered

| Option | Cost | Reasoning |
|--------|------|-----------|
| `opencode/deepseek-v4-flash-free` | Free | **Selected.** Same model as paid DS-V4-Flash via Zen free tier. No rate limiting. 31,650 req/5hr equivalent value. |
| `openrouter/meta-llama/llama-3.3-70b-instruct:free` | Free | Good fallback but rate-limited. |

**Final:** `opencode/deepseek-v4-flash-free`

**Fallback chain:** `openrouter/llama-3.3-70b:free` → `opencode/minimax-m2.5-free`

### Prometheus (Planner)

**Classification:** Dual-Prompt (S4, S5)
**Class traits:** Runtime auto-switch between Claude and GPT styles. Three-layer architecture: Planning layer.
**Canonical model:** `anthropic/claude-opus-4-7` — not available.

#### Options Considered

| Option | Reasoning |
|--------|-----------|
| `opencode-go/kimi-k2.6` | **Selected.** Matches Sisyphus model for planning consistency. Highest quality in Go pool. |
| `opencode-go/deepseek-v4-pro` | Good reasoning but not Dual-Prompt compatible. Guide requires Claude/GPT for auto-switch; K2.6 handles this better as a Communicators-class model. |

**Final:** `opencode-go/kimi-k2.6`

**Fallback chain:** `deepseek-v4-pro` → `deepseek-v4-flash`

### Metis (Plan Consultant)

**Classification:** Communicators (S4)
**Class traits:** Consulting role that verifies implicit intentions and AI-slop patterns.
**Canonical model:** `anthropic/claude-sonnet-4-6` — not available.

#### Options Considered

| Option | Context | Reasoning |
|--------|---------|-----------|
| `opencode-go/mimo-v2.5-pro` | 1M | **Selected.** Reddit post (S1) insight: consulting role benefits from 1M context for processing plan proposals. |
| `opencode-go/kimi-k2.6` | 256K | Better benchmarks but smaller context. Two different trade-offs. |

**Final:** `opencode-go/mimo-v2.5-pro`

**Fallback chain:** `kimi-k2.6` → `kimi-k2.5`

### Momus (Plan Reviewer)

**Classification:** Deep Specialist (S4)
**Class traits:** GPT-optimized, principle-driven critique. Called infrequently.
**Canonical model:** `openai/gpt-5.5` — not available.

#### Options Considered

| Option | Reasoning |
|--------|-----------|
| `opencode-go/deepseek-v4-pro` | **Selected.** Best reasoning model in Go pool (3,450 req/5hr). Rare calls justify premium cost. |
| `opencode-go/kimi-k2.6` | Excellent alternative but Communicators class, not Deep Specialist optimized. |

**Final:** `opencode-go/deepseek-v4-pro`

**Fallback chain:** `kimi-k2.6` → `deepseek-v4-flash`

### Atlas (Execution Conductor)

**Classification:** Dual-Prompt (S4, S5)
**Class traits:** Execution layer — history management, task routing, worker coordination.
**Canonical model:** `anthropic/claude-sonnet-4-6` — not available.

#### Options Considered

| Option | Req/5hr | Cost | Reasoning |
|--------|---------|------|-----------|
| `opencode-go/deepseek-v4-flash` | 31,650 | Low | **Selected.** 17x more efficient than K2.5 (1,850 req/5hr). Execution routing doesn't need premium reasoning. Frees budget for Sisyphus and Deep Specialists. |
| `opencode-go/kimi-k2.5` | 1,850 | Moderate | Canonical-class alternative but expensive for a routing role. |

**Final:** `opencode-go/deepseek-v4-flash`

**Fallback chain:** `deepseek-v4-pro` → `kimi-k2.5`

### Hephaestus (Builder)

**Classification:** Deep Specialist (S4)
**Class traits:** GPT-5.4 single chain, principle-driven autonomous exploration. **Cannot be safely overridden** with non-GPT models.
**Canonical model:** `openai/gpt-5.5` — not available.
**Override classification:** ⚠️ **DANGEROUS** (S4 explicitly marks this).

#### Options Considered

| Option | Reasoning |
|--------|-----------|
| `opencode-go/deepseek-v4-pro` | **Selected.** Best available substitute for principle-driven autonomous work. Admits it's a dangerous override. |
| `opencode-go/deepseek-v4-flash` | Weaker reasoning for autonomous exploration tasks. |
| `opencode-go/kimi-k2.6` | Strong but Communicators class doesn't match Deep Specialist workflow. |

**Final:** `opencode-go/deepseek-v4-pro` (with documented ⚠️ Dangerous override)

**Fallback chain:** `deepseek-v4-flash` → `kimi-k2.6`

### Oracle (Architecture Consultant)

**Classification:** Deep Specialist (S4)
**Class traits:** High-IQ reasoning, called infrequently, must be the best available.
**Canonical model:** `openai/gpt-5.5` — not available.

#### Options Considered

| Option | Reasoning |
|--------|-----------|
| `opencode-go/deepseek-v4-pro` | **Selected.** Best reasoning model in Go pool. xhigh variant maximizes reasoning effort. Rare calls (~1-5 per session) justify premium. |
| `opencode-go/kimi-k2.6` | Strong alternative (fallback position). |

**Final:** `opencode-go/deepseek-v4-pro` (variant: `xhigh`)

**Fallback chain:** `kimi-k2.6` → `deepseek-v4-flash`

### Explore (Codebase Navigator)

**Classification:** Utility Runner (S4)
**Class traits:** Codebase reconnaissance, pattern matching. High volume, low per-call stakes.
**Canonical model:** `openai/gpt-5.4-mini-fast` — not available.

#### Options Considered

| Option | Cost | Reasoning |
|--------|------|-----------|
| `opencode/deepseek-v4-flash-free` | Free | **Selected.** Zen free tier, no rate limiting. Same code quality as paid DS-V4-Flash. |
| `openrouter/qwen/qwen3-coder:free` | Free | Code-specialized alternative (fallback). |

**Final:** `opencode/deepseek-v4-flash-free`

**Fallback chain:** `openrouter/qwen/qwen3-coder:free` → `opencode/minimax-m2.5-free`

**Permission:** `edit: deny`, `bash: ask` — explore is read-only, should never edit files.

### Librarian (Research)

**Classification:** Utility Runner (S4)
**Class traits:** Multi-repo analysis, documentation lookup, implementation examples.
**Canonical model:** `openai/gpt-5.4-mini-fast` — not available.

#### Options Considered

| Option | Cost | Reasoning |
|--------|------|-----------|
| `opencode/deepseek-v4-flash-free` | Free | **Selected.** Same rationale as explore — Zen free, no rate limiting. Research doesn't need premium reasoning. |
| `openrouter/meta-llama/llama-3.3-70b-instruct:free` | Free | Solid alternative but rate-limited. |

**Final:** `opencode/deepseek-v4-flash-free`

**Fallback chain:** `openrouter/llama-3.3-70b:free` → `opencode/minimax-m2.5-free`

### Multimodal-Looker (Vision)

**Classification:** Specialized (vision)
**Class traits:** Image/PDF analysis, visual content extraction. Requires multimodal capability.
**Canonical model:** `openai/gpt-5.5` or `google/gemini-3-pro` — not available.

#### Decision

Per user directive: **"stay with MiMo"** — use MiMo family models.

| Option | Reasoning |
|--------|-----------|
| `opencode-go/mimo-v2.5-pro` | **Selected.** MiMo family per user directive. Multimodal support assumed but unconfirmed for this provider. |
| `opencode-go/kimi-k2.6` | Fallback if MiMo lacks vision. |
| `openrouter/nvidia/nemotron-nano-12b-v2-vl:free` | Free fallback with explicit vision-language (`vl`) support. |

**Final:** `opencode-go/mimo-v2.5-pro`

**Fallback chain:** `kimi-k2.6` → `openrouter/nvidia/nemotron-nano-12b-v2-vl:free`

---

## Category Design Decisions

Categories are used by `delegate_task()` when Sisyphus dispatches work to sub-agents. Each category maps to a domain with specific quality requirements.

### visual-engineering

| Consideration | Value |
|---------------|-------|
| **Model** | `opencode-go/kimi-k2.5` |
| **Rationale** | UI code generation needs solid instruction-following. K2.5 hits the sweet spot between K2.6 (costly) and DS-V4-Flash (not Communicators class). |
| **Alternatives considered** | K2.6 (overkill for most UI work), DS-V4-Flash (cheaper but weaker instruction following). |
| **Fallback** | `deepseek-v4-flash` → `minimax-m2.7` |

### ultrabrain

| Consideration | Value |
|---------------|-------|
| **Model** | `opencode-go/deepseek-v4-pro` (variant: `xhigh`) |
| **Rationale** | Hardest logic tasks need the best reasoner in the pool. Called rarely via delegation. |
| **Alternatives considered** | K2.6 (strong but lower GPQA Diamond score). |
| **Fallback** | `kimi-k2.6` → `deepseek-v4-flash` |

### deep

| Consideration | Value |
|---------------|-------|
| **Model** | `opencode-go/mimo-v2.5-pro` |
| **Rationale** | Autonomous deep exploration benefits from 1M context window (S1 insight). Per user directive: stay with MiMo. |
| **Alternatives considered** | K2.6 (better benchmarks but 256K context vs 1M). |
| **Fallback** | `deepseek-v4-pro` → `kimi-k2.5` |

### artistry

| Consideration | Value |
|---------------|-------|
| **Model** | `opencode-go/kimi-k2.5` |
| **Rationale** | Creative work needs quality but not flagship. K2.5 saves budget vs K2.6. |
| **Alternatives considered** | K2.6 (unnecessary premium), Minimax M2.7 (good fallback). |
| **Fallback** | `deepseek-v4-flash` → `minimax-m2.7` |

### quick

| Consideration | Value |
|---------------|-------|
| **Model** | `opencode/deepseek-v4-flash-free` |
| **Rationale** | Trivial tasks (typo fixes, single-file changes). High volume. Free model avoids touching Go pool. |
| **Alternatives considered** | OpenRouter Llama 3.3 free (rate-limited, fallback position). |
| **Fallback** | `openrouter/llama-3.3-70b:free` → `opencode/minimax-m2.5-free` |

### unspecified-low

| Consideration | Value |
|---------------|-------|
| **Model** | `openrouter/meta-llama/llama-3.3-70b-instruct:free` |
| **Rationale** | General low-effort tasks. OpenRouter free is sufficient; falls back to Zen free if rate-limited. |
| **Fallback** | `opencode/deepseek-v4-flash-free` → `opencode/minimax-m2.5-free` |

### unspecified-high

| Consideration | Value |
|---------------|-------|
| **Model** | `opencode-go/deepseek-v4-flash` |
| **Rationale** | Complex general tasks need capability but not premium reasoning. DS-V4-Flash at 31,650 req/5hr is extremely efficient. |
| **Fallback** | `deepseek-v4-pro` → `kimi-k2.5` |

### writing

| Consideration | Value |
|---------------|-------|
| **Model** | `opencode-go/deepseek-v4-flash` |
| **Rationale** | Prose generation. DS-V4-Flash handles this well at 31,650 req/5hr — no need for premium models. |
| **Alternatives considered** | K2.5 (overkill for writing), Minimax M2.5 (fine fallback). |
| **Fallback** | `kimi-k2.5` → `minimax-m2.5` |

---

## Settings & Properties

### model_fallback

**Value:** `true`
**Default:** `false`
**Source:** S8

Intercepts OpenCode's internal `session.status` retry events on usage limit errors. **Required** when using `runtime_fallback` — without it, hitting the Go pool's $12/5hr limit causes infinite retry loops instead of triggering the `fallback_models` chain.

### runtime_fallback

```json
{
  "enabled": true,
  "retry_on_errors": [400, 401, 429, 500, 502, 503, 504, 529],
  "max_fallback_attempts": 5,
  "cooldown_seconds": 30,
  "timeout_seconds": 20,
  "notify_on_fallback": true
}
```

Auto-switches to `fallback_models` chain on API errors. Extended `retry_on_errors` covers OpenRouter's common error codes (401 auth, 429 rate limit). Lowered `cooldown_seconds` and `timeout_seconds` for faster cycling through fallbacks.

### ultrawork

Applied to **sisyphus**:

```json
"ultrawork": {
  "model": "opencode-go/deepseek-v4-pro",
  "variant": "xhigh"
}
```

When the user types "ultrawork" or "ulw" in their message, Sisyphus temporarily upgrades from K2.6 to DS-V4-Pro (xhigh variant) for that turn only (S3). Acts as a "turbo button" for harder tasks without making every message expensive.

### fallback_models

Every agent and category has an ordered fallback chain. Format supports both simple strings and objects with per-model settings (S3). Chains follow the principle:

**Paid Go → Zen Free → OpenRouter Free**

This ensures:
- If K2.6 errors → DS-V4-Pro → DS-V4-Flash → still works
- If OpenRouter free is rate-limited → Zen free (no rate limit) → still works
- If the entire Go pool is exhausted → free models keep running independently

### background_task Concurrency

```json
{
  "providerConcurrency": {
    "opencode-go": 5,
    "opencode": 10,
    "openrouter": 3
  },
  "modelConcurrency": {
    "opencode-go/kimi-k2.6": 2,
    "opencode-go/deepseek-v4-pro": 2,
    "opencode-go/deepseek-v4-flash": 10,
    "opencode-go/mimo-v2.5-pro": 3
  }
}
```

Expensive models (K2.6, DS-V4-Pro) limited to 2 concurrent tasks to avoid burning the $12/5hr pool. DS-V4-Flash at 10 can run freely — 31,650 req/5hr is effectively unlimited for a single session. OpenRouter free at 3 avoids aggressive rate limiting.

### variant

Valid values per schema (S3): `none`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`.
Used at `xhigh` for oracle and ultrabrain (DeepSeek V4 Pro) to maximize reasoning effort.
Settings are compatibility-normalized — unsupported values are silently downgraded or removed.

### opencode.json defaults (model, small_model)

Set in `opencode.json` as the final catch-all in oh-my-openagent's model resolution chain (step 6, per S3):

- `model`: `openrouter/meta-llama/llama-3.3-70b-instruct:free` — final fallback for all agents
- `small_model`: same model — used for compaction/summarization and title generation

---

## Budget Analysis

Based on OpenCode Go's official limits page (S2) and the Reddit post's cost analysis (S1):

| Component | Models | Est. Usage/5hr | Est. Cost/5hr |
|-----------|--------|----------------|---------------|
| Sisyphus (primary) | K2.6 | ~400 messages | ~$4.00 |
| Deep Specialists (oracle, momus, hephaestus) | DS-V4-Pro | ~5-10 calls each | ~$1.50 |
| Consulting (metis) | MiMo-V2.5-Pro | ~5 calls | ~$0.80 |
| Planning (prometheus, atlas) | K2.6 + DS-V4-Flash | ~10-20 calls | ~$0.80 |
| Categories (delegated tasks) | various | ~10-20 calls | ~$1.00 |
| Utility runners (explore, librarian, junior) | Zen free | highest volume | **$0** |
| quick / unspecified-low | Free | high volume | **$0** |
| **Total** | | | **~$8.10/5hr** |

**$8.10 < $12 limit** ✅ Comfortably within budget.

If the session exceeds 5 hours or $12, the Go pool blocks and falls through to Zen free models (per S2: "If you reach the usage limit, you can continue using the free models").

---

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Kimi K2.6 thinking loops** | Sisyphus gets stuck on complex bugs. | User directive to disregard. If encountered, swap to `opencode-go/deepseek-v4-pro` or `opencode-go/glm-5.1`. |
| **Hephaestus without GPT-5.4** | Principle-driven autonomous exploration degraded. | Documented Dangerous override. DS-V4-Pro is best available substitute. Acceptable trade-off. |
| **MiMo-V2.5-Pro lacks vision** | Multimodal-looker fails on images. | Fallback to `openrouter/nemotron-nano-12b-v2-vl:free` (explicit VL support). |
| **Go pool exhausted mid-session** | All Go models fail. | `model_fallback` + `runtime_fallback` trigger fallback chains. Zen free models keep utility runners working. |
| **Zen free models discontinued** | Free-tier models become paid. | Models are "limited time" free. Monitor and reassign to OpenRouter free or paid Go equivalents. |
| **OpenRouter free rate limiting** | Explore/librarian get 429 errors. | Fallback chains cascade to Zen free models (no rate limiting). |

---

## Appendix: Model Specifications

| Model | Context | Key Strengths |
|-------|---------|---------------|
| kimi-k2.6 | 256K | Best overall benchmarks in Go pool. Strong instruction-following for Communicators. |
| kimi-k2.5 | 256K | Good quality at lower cost than K2.6. |
| deepseek-v4-pro | 128K? | Strong reasoning for Deep Specialists. Best GPT-5.4 substitute available. |
| deepseek-v4-flash | 128K? | 31,650 req/5hr — 27x more efficient than K2.6. Excellent for high-volume roles. |
| mimo-v2.5-pro | 1M | Large context for consulting/exploration. |
| minimax-m2.7 | ? | General-purpose, moderate cost. |
| minimax-m2.5 | ? | Cheapest Go model for simple tasks. |
| deepseek-v4-flash-free | Same as paid DS-V4-Flash | Free via Zen. No rate limiting. Preferred for utility runners. |

> *Note: Exact context window sizes for some models are not publicly documented and may vary by provider deployment.*
