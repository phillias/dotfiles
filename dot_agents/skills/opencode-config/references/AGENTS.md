# Agent & Category Routing

Live agent/category chain design. **Authoritative source: `~/.config/opencode/opencode-fallback.jsonc`** — this file mirrors it and must be kept in sync via the drift-promotion gate (DESIGN.md §2.5). OmO-era tier tables are archived in `ARCHIVE-OMO.md`.

## Fleet taxonomy

- **global ladder** = firstmate + secondmates (session model)
- **agents** = crewmates
- **categories** = dispatch profiles (dispatch-rules.json)

**Resolution order:** session model → agent (exact match, then longest `*` wildcard) → category → global ladder. `no_global_tail` entries fail visibly at chain end (no free downgrade).

**Decision A (captain, 2026-08-12, updated 2026-09-21):** utility agents and categories run CF AI Gateway dynamic/TUI → Vercel AI Gateway vmc/tui → opencode-go subsidized tail; specialized agents keep pinned models with fallback Z.AI → GOAT → Go → Zen only. Vercel is the CF-gateway-outage fallback; opencode-go is the session-gated subsidized pool tail.

## Global ladder (2026-09-21)

Two-path architecture (captain decision 2026-09-19):
- **Path 1** — CF AI Gateway `CfAiGw/dynamic/TUI`: cascading GLM ladder (free → subsidized → PAYG). The gateway route handles intra-GLM cascade internally; opencode-go can never be a gateway route node (x-opencode-session header requirement).
- **Path 2** — This fallback config: CfAiGw/dynamic/TUI first → Vercel vmc/tui → opencode-go tail.

| Stage | Models |
|---|---|
| 0 | `CfAiGw/dynamic/TUI` (CF AI Gateway — GLM ladder) |
| 1 | `vercel/vmc/tui` (Vercel AI Gateway — 1M context, BYOK + system creds) |
| 2 | `opencode-go/glm-5.1`, `opencode-go/deepseek-v4-flash` (Go subsidized pool — session-gated) |

## Agents map

| Agent | Primary | Fallback chain | Tail |
|---|---|---|---|
| general | CfAiGw/dynamic/TUI | vercel/vmc/tui → opencode-go/glm-5.1 → opencode-go/deepseek-v4-flash | global tail |
| explore | (same as general) | same | global tail |
| self-improve | opencode-zen/glm-5.1 | Z.AI GLM-5.2 → GOAT GLM-5.1 → Go glm-5.1 → Zen kimi-k2.6 | no_global_tail |
| solutions-research | opencode-zen/nematron-3-ultra-free | GOAT kimi-k2.6 → Go kimi-k2.6 → Zen kimi-k2.6 | no_global_tail |

## Categories map

| Category | Primary | Variant | Fallback | Tail |
|---|---|---|---|---|
| quick | CfAiGw/dynamic/TUI | — | vercel/vmc/tui → opencode-go/glm-5.1 → opencode-go/deepseek-v4-flash | global tail |
| unspecified-low | (same as quick) | — | same | global tail |
| ultrabrain | opencode-go/deepseek-v4-pro | xhigh | GOAT ds-v4-pro → Zen ds-v4-pro | no_global_tail |
| deep | opencode-go/kimi-k2.6 | — | Z.AI GLM-5.2 → GOAT Kimi-K2.6 → Go Kimi-K2.6 → Zen Kimi-K2.6 | no_global_tail |
| unspecified-high | (same as deep) | — | same | no_global_tail |
| visual-engineering | opencode/gpt-5.3-codex | — | GOAT gpt-5.6-luna → Zen gpt-5.3-codex | no_global_tail |
| artistry | opencode-zen/gemini-3.5-flash | — | GOAT mimo-v2.5 → GOAT inkling → Go mimo-v2.5 → Zen mimo-v2.5-free | no_global_tail |
| writing | opencode-zen/deepseek-v4-flash-free | — | GOAT ds-v4-flash → Go ds-v4-flash → Zen big-pickle | no_global_tail |

## Fallback config keys (live)

`enabled: true` · `retry_on_errors: [400,401,402,403,429,500,502,503,504,529]` · `max_fallback_attempts: 20` · `cooldown_seconds: 15` · `timeout_seconds: 30` · `notify_on_fallback: true`.

KTD6 constraints enforced at chain authoring: GPT-class **primary** models via the `opencode/` prefix in opencode harness chains (openrouter/GOAT GPT lanes are valid as fallbacks and gateway dynamic-route lanes — zen gpt-5.x itself is broken on chat/completions, so no `opencode/` lane can exist inside a gateway route graph); Ternary Bonsai never primary (single-shot only); ≤1-2 NIM models per chain; 400 stays in `retry_on_errors`.
