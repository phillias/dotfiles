---
name: tokentelemetry
description: Deploy captions for TokenTelemetry selfhost at ~. Keep in your library when deploying, routing, or debugging the TokenTelemetry service on any fleet host.
---

# TokenTelemetry deployment (selfhost)

TokenTelemetry (https://github.com/VasiHemanth/tokentelemetry) is an agent
yield/cost dashboard. It runs per host under `~/tokentelemetry` with the split
proxy pattern managed by godoxy hostapps.

## Layout / ports

- Backend (FastAPI, container `tokentelemetry-backend-1`): bind `127.0.0.1:18000`.
- Frontend (Next.js, container `tokentelemetry-frontend-1`): bind `127.0.0.1:13000`.
- godoxy hostapp `tokentelemetry` — `port: :13000` default, plus an internal
  route-rule block proxying the backend API paths
  (`/agents* /sessions* /analytics* /version /health /openapi.json /remote-access /config* /pricing /quotas /notifications /telemetry*`)
  to `http://127.0.0.1:18000`.

## Gotchas (verbatim)

- The Dockerfile needs `ARG NEXT_PUBLIC_API_BASE=""` declared explicitly, and
  compose must pass it as a build arg — without it same-origin API calls fall
  back to `:18000`, which godoxy doesn't route, and every API call times out.
- No godoxy restart after config: `hostapps.yml` requires a `godoxy-proxy`
  restart before edits take effect (unless godoxy gains hot-reload).
- The API route match: `glob("/agents/*")` only matches subpaths; bare
  `/agents` needs its own `path /agents` entry in godoxy rule blocks.
- Agent-log mounts in compose are per-host — enable ONLY the agents that host
  actually uses (`.claude`, `.codex`, `.copilot`, `.pi`,
  `$HOME/.local/share/opencode`).
- The split proxy at :3011 (proxy/proxy.js + tokentelemetry-proxy.service) is
  retired on this host; it can be made redundant if godoxy rules ever need it,
  removed lazy — re-add if the godoxy rule ever regresses.

## Data location

`~/.tokentelemetry` per host — history.db and session payloads, additive only.
Never delete this dir: it's the cost/yield ledger.

## Key files on each host

- `~/tokentelemetry/compose.yml`, `agent-log` mounts
- `~/tokentelemetry/proxy/proxy.js` — split proxy (retired on most hosts,
  still useful reference)
- `~/.config/systemd/user/tokentelemetry-proxy.service` — disable+rm when proxy
  goes away.
