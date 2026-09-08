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

## Simplified godoxy pattern (no code customization)

The split proxy pattern uses godoxy route rules to route backend API calls to
`:18000`. No custom proxy.js code is required.

### godoxy hostapps.yml configuration

```yaml
tokentelemetry:
  host: 127.0.0.1
  port: :13000
  rules: |-
    path glob("/agents") |
    path /agents |
    path /sessions |
    path /analytics |
    path /version |
    path /health |
    path /openapi.json |
    path /remote-access |
    path /pricing |
    path /quotas |
    path /notifications |
    path glob("/config/*") |
    path glob("/pricing/*") |
    path glob("/quotas/*") |
    path glob("/notifications/*") |
    path glob("/telemetry/*") {
      proxy http://127.0.0.1:18000
    }
```

**Key routing gotcha:** `glob("/agents")` only matches the bare path without trailing
slash; both `path glob("/agents")` and `path /agents` entries are needed for
complete coverage. The same applies to other API root paths.

## compose.yml template

```yaml
services:
  backend:
    build:
      context: ./backend
    ports:
      - "127.0.0.1:18000:8000"
    environment:
      - TT_HOST=0.0.0.0
      - TT_API_PORT=8000
      - TOKENTELEMETRY_DATA_DIR=/tt-data
      - TOKENTELEMETRY_HOME=/tt-data
      - TZ=${TZ:-}
      - TT_AUTH_TOKEN=${TT_AUTH_TOKEN:-}
    volumes:
      - tt_data:/tt-data
      - "${HOME}/.claude:/root/.claude:ro,z"
      - "${HOME}/.codex:/root/.codex:ro,z"
      - "${HOME}/.copilot:/root/.copilot:ro,z"
      - "${HOME}/.pi:/root/.pi:ro,z"
      - "${HOME}/.local/share/opencode:/root/.local/share/opencode:ro,z"
    healthcheck:
      test: ["CMD-SHELL", "python3 -c \"import socket; s=socket.socket(); s.settimeout(3); s.connect(('localhost', 8000)); s.close()\""]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 10s
    restart: unless-stopped

  frontend:
    build:
      context: ./frontend
      args:
        NEXT_PUBLIC_API_PORT: 18000
        NEXT_PUBLIC_API_BASE: ""
    ports:
      - "127.0.0.1:13000:3000"
    depends_on:
      backend:
        condition: service_started
    restart: unless-stopped

volumes:
  tt_data:
```

## Gotchas

- **NEXT_PUBLIC_API_BASE build arg:** Set to empty string (not omitted) so the
  frontend uses same-origin API calls, which godoxy routes to `:18000` via the
  rules block.
- **No godoxy restart after config:** `hostapps.yml` requires a `godoxy-proxy`
  restart before edits take effect (unless godoxy gains hot-reload).
- **Agent-log mounts are per-host:** Enable only the agents that host actually
  uses. The template includes `.claude`, `.codex`, `.copilot`, `.pi`, and
  `.local/share/opencode` by default.

## Data location

`~/.tokentelemetry` per host — history.db and session payloads, additive only.
Never delete this dir: it's the cost/yield ledger.

## Key files on each host

- `~/tokentelemetry/compose.yml` with agent-log mounts
- godoxy `hostapps.yml` entry with split proxy rules
