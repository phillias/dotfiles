# OS Dependencies

The OpenCode config and the firstmate distro rely on a set of host tools. All paths portable (`$HOME`/`~`/`%h`); never hardcode `/home/<user>`.

## Core CLI tools

| Tool | Role | Location |
|---|---|---|
| opencode | the runtime itself; `oc` alias launches `opencode --port 42069` (bare TUI only serves `/`; attach fails without port) | system |
| chezmoi | dotfiles source-of-truth (`~/.local/share/chezmoi`); configs are chezmoi-tracked, machine diffs via `.tmpl` | system |
| gh | GitHub (issues/PRs/checks/releases); `gh-axi` skill wraps it | ~/bin/gh |
| bw | Bitwarden CLI (vault/secrets); `bws-axi` skill wraps BWS | ~/bin/bw |
| wrangler | Cloudflare Workers CLI (deploy/dev) | ~/.npm-global/bin/wrangler |
| sqlite3 | local DB reads + opencode.db session queries (commit identity resolution) | /usr/bin/sqlite3 |
| no-mistakes | delivery-pipeline gate (PR/review/CI; dotfiles runs `no_ci: true` — empty forge checks pass) | ~/.local/bin/no-mistakes |
| node | JSONC validation, drift scripts (catalog-drift.mjs) | system |
| jq | JSON parsing (Zen model catalog checks) | system |
| **mise** | runtime/env manager (NEW — dependency to be added; manages toolchains like node/gh versions) | not yet on PATH |

## API keys (`~/.config/opencode/.*-key` files, chezmoi age-encrypted)

`.command-code.key` (COMMANDCODE_API_KEY / GOAT) · `.nvidia-key` (NVIDIA_API_KEY) · `.baseten-key` (BASETEN_API_KEY) · `.zen-key` (Zen) · `.groq-key` (dormant, survived) · `.google-client-id`/`.google-client-secret` · `.composio-key`.

Documented but NOT created: `.cheapestinference-key`, `.cheaperinference-key`, `.hetzner-key`, `.pokee-key` (POKEE_API_KEY — pokee provider dormant until a key exists).

`oc` alias loads all `.*-key` files into the environment at shell start. Shell profiles export the matching `{env:VAR}` references used by opencode.json provider `options`.

## Firstmate runtime

- **tmux** — verified default spawn backend (herdr/zellij/orca/cmux experimental); codex-app not accepted.
- **tasks-axi** — backlog backend (`.tasks.toml`; "manual" override available).
- **quota-axi** — local quota reads for dispatch profile selection.
- **lavish-axi** — structured decision/report surface.
- **chrome-devtools-axi** — browser work.
- **mem / axi-memory** — durable cross-session memory (`.local/bin/mem`).
- **systemd** — `catalog-drift.service`+timer, `selfimprove-drain` unit.
- **age** — chezmoi secret encryption (age-key.txt.age).
- **SQLite** — `~/.local/share/opencode/opencode.db` (session records; commit identity via `sqlite3 ... SELECT model FROM session ORDER BY time_updated DESC LIMIT 1`).

## MCP servers (global)

context7 (mcp.context7.com/mcp) · grep_app (mcp.grep.app) · websearch (mcp.exa.ai, x-api-key `{env:EXA_API_KEY}`) · mcp_everything (npx @modelcontextprotocol/server-everything). Optional (in opencode.json directly): netdata-bylocalhost, chrome-devtools, google-workspace, google-tasks-calendar.
