---
name: tokentelemetry
description: Deploy captions for TokenTelemetry selfhost at ~. Keep in your library when deploying, routing, or debugging the TokenTelemetry service on any fleet host.
---

# TokenTelemetry deployment (selfhost)

TokenTelemetry (https://github.com/VasiHemanth/tokentelemetry) is an agent
yield/cost dashboard. It runs per host under `~/tokentelemetry` (fork checkout
on `fork-main`) as a native systemd --user service, with the split proxy
pattern managed by godoxy hostapps.

## Layout / ports

- Backend (FastAPI/Next.js bundled `cli.js` backend): binds `127.0.0.1:18000`.
- Frontend (Next.js, served by the same process): binds `127.0.0.1:13000`.
- godoxy hostapp `tokentelemetry` — `port: :13000` default, plus an internal
  route-rule block proxying the backend API paths
  (`/agents* /sessions* /analytics* /version /health /openapi.json /remote-access /config* /pricing /quotas /notifications /telemetry*`)
  to `http://127.0.0.1:18000`.

The unit is `dot_config/systemd/user/tokentelemetry.service`; deploy via
`chezmoi apply` and `systemctl --user daemon-reload`. Enabling and starting:
`systemctl --user enable --now tokentelemetry.service`. The chezmoi source is
the authoritative unit; never hand-edit the installed copy.

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

## systemd --user unit

```ini
[Unit]
Description=TokenTelemetry - AI Agent Token Observability Dashboard
After=network.target

[Service]
Type=simple
WorkingDirectory=%h/tokentelemetry
ExecStart=/bin/bash -c 'export ANTHROPIC_API_KEY="$(cat "%h/.agents/keys/default/.anthropic-key")"; export NEXT_PUBLIC_API_BASE=""; exec %h/.local/share/mise/shims/node %h/tokentelemetry/bin/cli.js --port 13000 --api-port 18000 --host 127.0.0.1 --no-open'
Restart=on-failure
RestartSec=5
Environment=TOKENTELEMETRY_DATA_DIR=%h/.tokentelemetry
Environment=TOKENTELEMETRY_HOME=%h/.tokentelemetry
Environment=NODE_ENV=production
Environment=DO_NOT_TRACK=1
Environment=TT_NO_UPDATE_CHECK=1
MemoryHigh=1536M
MemoryMax=2G
CPUQuota=100%
CPUWeight=100
IOWeight=100
TasksMax=128

[Install]
WantedBy=default.target
```

Key points:

- The service runs the mise-shim `node` (via `%h/.local/share/mise/shims/node`)
  against `~/tokentelemetry/bin/cli.js` with `--port 13000 --api-port 18000
  --host 127.0.0.1 --no-open`. The fork checkout is at `~/tokentelemetry` on
  `fork-main`.
- The Tokens API key is read at start from
  `~/.agents/keys/default/.anthropic-key` into `ANTHROPIC_API_KEY`. The key
  value itself is never committed; only the file path is.
- Data dir: `TOKENTELEMETRY_DATA_DIR` and `TOKENTELEMETRY_HOME` both point at
  `%h/.tokentelemetry` (data extracted from the retired Docker volume).
- Memory envelope: `MemoryHigh=1536M`, `MemoryMax=2G`. Earlier 512M limit
  starved the Next.js production server; keep the envelope, don't shrink it.
- `Restart=on-failure`, `RestartSec=5`.

## Gotchas

- **NEXT_PUBLIC_API_BASE must be empty:** exported as an empty string in the
  ExecStart wrapper (not omitted) so the frontend uses same-origin API calls,
  which godoxy routes to `:18000` via the rules block.
- **No godoxy restart after config:** `hostapps.yml` requires a `godoxy-proxy`
  restart before edits take effect (unless godoxy gains hot-reload).
- **Key file must exist:** the unit fails fast if `~/.agents/keys/default/.anthropic-key`
  is missing at start.
- **Resource envelope:** do not lower `MemoryMax` below 2G; the Next.js
  production server starves under tighter limits.

## Data location

`~/.tokentelemetry` per host — history.db and session payloads, additive only.
Never delete this dir: it's the cost/yield ledger.

## Key files on each host

- `~/tokentelemetry` fork checkout (`bin/cli.js` on `fork-main`)
- `~/.config/systemd/user/tokentelemetry.service` (chezmoi source:
  `dot_config/systemd/user/tokentelemetry.service`)
- `~/.agents/keys/default/.anthropic-key` (Tokens/Anthropic API key, never committed)
- godoxy `hostapps.yml` entry with split proxy rules
