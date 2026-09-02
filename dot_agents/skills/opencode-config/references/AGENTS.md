# Agent & Category Routing

**Authoritative source: `~/.config/opencode/opencode-fallback.jsonc`** — that file owns every global/agent/category entry; this document only records the *rules and constraints* applied at chain authoring (the chain contents move with the config).

Live chain contents (decision A v5, 2026-09-01: GLM-5.1 ladder — `big-pickle → opencode-go/glm-5.1 → commandcode/zai-org/GLM-5.2 → openrouter/z-ai/glm-5 → opencode-zen/glm-5.1`, with the same ladder applied to every opencode interactive chain) and decision history live in `opencode-fallback.jsonc`'s header comment and `references/DESIGN.md` §2.6. OmO-era tier tables are archived in `ARCHIVE-OMO.md`.

## Fleet taxonomy

- **global ladder** = firstmate + secondmates (session model)
- **agents** = crewmates + ce-* wildcard
- **categories** = dispatch profiles (dispatch-rules.json)

**Resolution order:** session model → agent (exact match, then longest `*` wildcard) → category → global ladder. `no_global_tail` entries fail visibly at Zen (no free downgrade).

## Fallback config keys (live)

`enabled: true` · `retry_on_errors: [400,401,402,403,429,500,502,503,504,529]` · `max_fallback_attempts: 15` · `cooldown_seconds: 60` · `timeout_seconds: 120` · `notify_on_fallback: true`.

KTD6 constraints enforced at chain authoring: GPT-class models only via `opencode/` prefix; Ternary Bonsai never primary (single-shot only); ≤1-2 NIM models per chain; 400 stays in `retry_on_errors`.
