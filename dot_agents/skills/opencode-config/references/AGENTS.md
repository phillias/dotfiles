# Agent & Category Routing

Live agent/category chain design. **Authoritative source: `~/.config/opencode/opencode-fallback.jsonc`** — this file mirrors it and must be kept in sync via the drift-promotion gate (DESIGN.md §2.5). OmO-era tier tables are archived in `ARCHIVE-OMO.md`.

## Fleet taxonomy

- **global ladder** = firstmate + secondmates (session model)
- **agents** = crewmates + ce-* wildcard
- **categories** = dispatch profiles (dispatch-rules.json)

**Resolution order:** session model → agent (exact match, then longest `*` wildcard) → category → global ladder. `no_global_tail` entries fail visibly at Zen (no free downgrade).

**Decision A (captain, 2026-08-12):** utility agents run big-pickle → GOAT → Go → Cloudflare → Zen → free; specialized agents keep pinned models with fallback GOAT → Go → Zen only. **Decision B:** GOAT leads so its exhaustion rate is observable.

## Global ladder (2026-08-16)

| Stage | Models |
|---|---|
| 0 | `opencode-zen/big-pickle` |
| 1 | `commandcode/moonshotai/Kimi-K2.6`, `commandcode/deepseek/deepseek-v4-flash` (GOAT) |
| 2 | `opencode-go/kimi-k2.6`, `opencode-go/deepseek-v4-flash` (Go) |
| 3 | `cloudflare/@cf/moonshotai/kimi-k2.7-code`, `cloudflare/@cf/zai-org/glm-4.7-flash` (Cloudflare free — moved ahead of Zen free 2026-08-16) |
| 4 | `opencode-zen/deepseek-v4-flash-free`, `opencode-zen/nemotron-3-ultra-free` (Zen free) |
| 5 | `nvidia/deepseek-ai/deepseek-v4-flash`, `openrouter/nvidia/nemotron-3-super-120b-a12b:free`, `baseten/openai/gpt-oss-120b` |
| 6 | `google/gemini-2.5-flash` (pay last resort) |

## Agents map

| Agent | Primary | Fallback chain | Tail |
|---|---|---|---|
| general | big-pickle | GOAT kimi-k2.6 → GOAT ds-v4-flash → Go kimi-k2.6 → Go ds-v4-flash → CF kimi-k2.7-code → CF glm-4.7-flash → Zen ds-v4-flash-free → Zen nemotron-3-ultra-free | global free tail |
| explore | (same as general) | same | global free tail |
| self-improve | opencode-zen/glm-5.1 | GOAT GLM-5.1 → Go glm-5.1 → Zen kimi-k2.6 | no_global_tail |
| solutions-research | opencode-zen/nemotron-3-ultra-free | GOAT kimi-k2.6 → Go kimi-k2.6 → Zen kimi-k2.6 | no_global_tail |
| ce-* (wildcard) | — | GOAT Kimi-K2.6 → GOAT GLM-5.1 → GOAT ds-v4-flash → Zen kimi-k2.6 | no_global_tail |

ce-* deliberately omits the Go stage — 35/51 personas are Go-pinned as primary.

## Categories map

| Category | Primary | Variant | Fallback | Tail |
|---|---|---|---|---|
| quick | big-pickle | — | same as general (GOAT→Go→CF→Zen) | global free tail |
| unspecified-low | (same as quick) | — | same | global free tail |
| ultrabrain | opencode-go/deepseek-v4-pro | xhigh | GOAT ds-v4-pro → Zen ds-v4-pro | no_global_tail |
| deep | big-pickle | — | GOAT Kimi-K2.6 → Go Kimi-K2.6 → Zen Kimi-K2.6 | no_global_tail |
| unspecified-high | (same as deep) | — | same | no_global_tail |
| visual-engineering | opencode/gpt-5.3-codex | — | GOAT gpt-5.6-luna → Zen gpt-5.3-codex | no_global_tail |
| artistry | cloudflare/@cf/google/gemma-4-26b-a4b-it | — | GOAT mimo-v2.5 → GOAT inkling → Go mimo-v2.5 → Zen mimo-v2.5-free | no_global_tail |
| writing | opencode-zen/deepseek-v4-flash-free | — | GOAT ds-v4-flash → Go ds-v4-flash → Zen big-pickle | no_global_tail |

## Fallback config keys (live)

`enabled: true` · `retry_on_errors: [400,401,402,403,429,500,502,503,504,529]` · `max_fallback_attempts: 15` · `cooldown_seconds: 60` · `timeout_seconds: 120` · `notify_on_fallback: true`.

KTD6 constraints enforced at chain authoring: GPT-class models only via `opencode/` prefix; Ternary Bonsai never primary (single-shot only); ≤1-2 NIM models per chain; 400 stays in `retry_on_errors`.

## Stale inline sample warning

SKILL.md's old inline fallback JSONC sample (Zen-free stage 3, CF stage 4) predates the 2026-08-16 Cloudflare move — the live `opencode-fallback.jsonc` is the only truth.
