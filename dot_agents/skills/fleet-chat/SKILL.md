---
name: fleet-chat
description: Send prompts to and read responses from opencode serve nodes across the fleet via the fleet-chat CLI. Use when messaging another fleet node's opencode session, checking a remote session's latest reply, listing mesh nodes, or troubleshooting empty replies from remote nodes.
---

# fleet-chat

`fleet-chat` (~/.local/bin/fleet-chat) is the adapter for agent-to-agent prompts across the
opencode serve mesh. Every node runs headless `opencode serve` on 127.0.0.1:4096, connected
full-mesh by autossh user tunnels (see dotfiles `dot_agents/skills/dotfiles/refs/FLEET-TUNNELS.md`).

## Commands

```bash
fleet-chat list-nodes                                    # mesh health + versions
fleet-chat send --node primary55522 --prompt "..."       # create/admit a prompt
fleet-chat latest --node primary55522 --session <id>     # read newest assistant reply
fleet-chat latest --node primary55522 --session <id> --full
fleet-chat session-list --node primary55522
```

`--toon` (default) / `--json` control output. `--max-text N` truncates replies (default 1200).

Nodes resolve from `$FLEET_CHAT_NODES` (space-separated `name=url` pairs), then a
`fleet-chat.nodes` file next to the auth env file, then the built-in map
(`local=127.0.0.1:4096`, `primary55522=:14001`, `kali=:14002`, `kalione=:14003`).
Auth: `OPENCODE_SERVE_ENV` → `~/.config/opencode/opencode-serve.env`
(`OPENCODE_SERVER_USERNAME`/`OPENCODE_SERVER_PASSWORD`), sent as basic auth.

## Round-trip pattern

1. `send` — creates a session (`POST /api/session`) when `--session` is omitted, then admits
   the prompt via `POST /api/session/{id}/prompt` with `{"prompt":{"text":"..."}}`.
   The 200 JSON includes `sessionID`, `admittedSeq`, and the message id. Save the session id.
2. Poll `latest` with that session id until the reply is non-empty or an error finish is shown.
   Completion events are also available via SSE `GET /api/event` / `GET /api/session/{id}/event`.

## Route gotchas (known failure modes)

- Fire-and-forget delivery is the **V1** route `POST /session/{id}/prompt_async` (no `/api`
  prefix) → `204 No Content`.
- `POST /api/session/{id}/prompt_async` is **not a route**: it falls through to the TUI SPA
  and returns `200 text/html`. That HTML response is the known source of the old "HTML instead
  of JSON" symptom.
- Transport is record-free: any decision, assignment, or finding arising in chat must be
  posted to the owning issue in the same turn, or it did not happen (swarm-runbook rule).

## Per-host self-alias gotcha

Each host's own node name in the map is dead on that host: its own-target autossh tunnel unit
is chezmoi-ignored, so `fleet-chat list-nodes` always shows that one node unreachable. Use
`local` for the self node. This is expected health, not an outage.

## Empty reply troubleshooting (remote nodes)

`send` succeeding but `latest` returning `chars=0 text=""` is a **model auth failure on the
remote node**, not a transport problem. Confirm via the raw V2 projection with the same basic
auth:

```bash
curl -s --user "$USER:$PASS" "http://<node-tunnel-port>/api/session/<id>/message"
```

An assistant message with `"finish":"error"` carrying
`Provider request failed with HTTP 401 {code:2009 Unauthorized, name:AiGatewayError}`
means the headless serve session authenticated with a **stale gateway token** in that node's
`~/.local/share/opencode/auth.json` (providers `opencode` / `opencode-go`) while interactive
sessions use a fresh token. Fix: refresh the gateway credential on the affected node
(interactive `opencode` login on that host, or replace the stale `auth.json` entry with the
fresh token), then re-send. Empty replies on every node except `local` usually mean every
remote node needs the refresh.
