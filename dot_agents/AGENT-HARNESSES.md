# Agent harness fleet — verified matrix (2026-11-07)

17 harnesses supported by firstmate (`firstmate/.agents/skills/harness-adapters/references/harness/<name>.md` is the per-harness source of truth). npm/mise-installable pins live in `dot_config/mise/config.toml` under the "Agent harnesses" section.

## Verified primary + secondmate

claude, codex, opencode, omp, agy, grok, cursor.

## Crewmate/scout-only

kiro, gemini, devin, polytoken, commandcode, cortex, hermes, kimi, muse, rovo.

## Install + auth matrix

| Harness | CLI | Install | Plan (device-OAuth-first) |
|---|---|---|---|
| claude | `claude` | npm `@anthropic-ai/claude-code` (mise pin, `--ignore-scripts=false`) | Anthropic Pro $20 (OAuth `/login`) |
| codex | `codex` | npm `@openai/codex` | ChatGPT Plus $20 (OAuth) |
| opencode | `opencode` | mise core backend (`opencode` pin) | Free; optional OpenCode Go $10 (`opencode auth login`) |
| omp | `omp` | npm `@oh-my-pi/pi-coding-agent` | Free; BYO provider OAuth (60+ providers) |
| agy | `agy` | `curl -fsSL https://antigravity.google/cli/install.sh \| bash` (also pinned `github:google-antigravity/antigravity-cli`) | Free Google OAuth; AI Pro $19.99 optional |
| kiro | `kiro-cli` | `curl -fsSL https://cli.kiro.dev/install \| bash` | Kiro Free; Pro ~$20 later |
| grok | `grok` | npm `@xai-official/grok` | Free; X Premium $30 (OAuth) |
| cursor | `cursor-agent` | `curl https://cursor.com/install -fsS \| bash` (auto-updating; mise pin not meaningful) | Free; Premium $30 (`agent login`) |
| gemini | `gemini` | npm `@google/gemini-cli` | Free Google OAuth — but firstmate workers need `GEMINI_API_KEY` pre-exported (OAuth doesn't survive daemon env) |
| devin | `devin` | `curl -fsSL https://cli.devin.ai/install.sh \| bash` | Free; Pro $20 (browser login) |
| polytoken | `polytoken` | `curl -fsS https://get.polytoken.dev \| bash` (self-updates) | Free; built-in device OAuth (`codex_device`, `kimi_code_device`) |
| commandcode | `cmd`/`cmdc` | npm `command-code` (Node ≥22) | GOAT $10 (`cmd login`) |
| cortex | `cortex` | `curl -LsS https://ai.snowflake.com/static/cc-scripts/install.sh \| sh` | CoCo trial → $20/mo (Snowflake SSO) |
| hermes | `hermes` | `curl -fsSL https://hermes-agent.nousresearch.com/install.sh \| bash` | Nous Portal Free; Plus $20 (`hermes setup --portal`) |
| kimi | `kimi` | npm `@moonshot-ai/kimi-code` (Node ≥22.19) | Kimi membership Plus (OAuth device-code; Go tier has no coding quota) |
| muse | `muse` | `curl -fsSL https://dev.meta.ai/install.sh \| sh` | Everyday $5/mo (`muse login` device sign-in) |
| rovo | `acli rovodev` | Atlassian ACLI installer | Free 350 credits (scoped token, no device OAuth); **product reaching EOL** |

## Notes

- `@oh-my-pi/pi-coding-agent` ships the `omp` binary only — it coexists with the `pi` pin (`@earendil-works/pi-coding-agent@0.84.2`, held back for the 0.85+ stream-parsing regression). Pinned at 18.13.2: the last release compatible with the fleet's bun 1.3.14 (18.13.3+ requires bun ≥ 1.4.4; bump bun first to go newer).
- `@google/gemini-cli` 0.67.0 verified as the gemini harness; `command-code` 1.88.5 ships `cmd`/`cmdc`/`command-code`.
- Curl-installed CLIs are deliberately not mise-pinned (auto-updaters: cursor, polytoken; no npm distribution: agy/kiro/devin/cortex/hermes/muse/rovo).
- Plan-lane recommendations for these harnesses: see `dot_agents/skills/provider-catalog/references/CODING-PLANS.md`.
