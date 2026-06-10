---
name: docker-infra-mgmt
description: >
  Cross-stack Docker Compose infrastructure management — covers bws-init/locket
  secret injection patterns, Godoxy reverse proxy, socket-proxy, OCI Vault
  integration, OCIR registry conventions, restic backup/restore architecture,
  and Bitwarden SM administration shared across all stacks at /home/ubuntu/docker/.
compatibility: opencode
metadata:
  stacks: root,selfhost,pirate,hermes,linkwarden,flexget,newrelic,jessalaga,opencode-telegram-bot,mylar3
  services: godoxy,socket-proxy,crowdsec,bws-init,bws-locket,locket
  tools: docker,docker compose,bws,bwsh,locket,oci,restic,sqlite3
---

# Docker Infrastructure Management

Authoritative guide for managing the Docker Compose infrastructure at
`/home/ubuntu/docker/`. This covers patterns and practices shared across
**all** stacks — the bws-init/locket secret injection pipeline, Godoxy
reverse proxy, socket-proxy, OCI Vault integration, OCIR registry, restic
backup/restore architecture, and Bitwarden SM administration.

For **pirate-specific** service management (ARRs, Stremio, VPN proxies,
ebooks/audiobooks), see the `pirate-stack` skill.

---

## 1. Infrastructure Overview

### Stacks

| Directory | Compose File | Project | Purpose |
|-----------|-------------|---------|---------|
| `/home/ubuntu/docker/` (root) | `compose.yml` | `selfhost` | Core proxy, socket-proxy, CrowdSec, databases (MariaDB, PostgreSQL/MSSQL/Redis/libSQL/Turso), CloudBeaver |
| `selfhost/` | `compose.yml` | `selfhost` | Secondary socket-proxy + Godoxy, ntfy, tinyauth, dockhand, apprise |
| `pirate/` | `compose.yaml` | `pirate` | Media suite — Stremio, ARRs, VPN proxies, ebooks/audiobooks |
| `hermes/` | `compose.yml` | `hermes` | Hermes AI agent gateway + Telegram bot + dashboard |
| `linkwarden/` | `compose.yml` | `linkwarden` | Bookmark manager with Meilisearch |
| `flexget/` | `compose.yml` | `flexget` | Media automation with rclone + Google Drive |
| `jessalaga/` | `docker-compose.yml` | `jessalaga` | RSS reader |
| `opencode-telegram-bot/` | `docker-compose.yml` | `opencode-telegram-bot` | Telegram bot for OpenCode |
| `newrelic/` | `compose.yml` | `newrelic` | New Relic infrastructure monitoring |
| `mylar3/` | `compose.yml` | `mylar3` | Comic book management |

### Shared Resources

- **Network**: `selfhost_frontnet` (external bridge) — all stacks attach here for Godoxy routing
- **Godoxy**: Primary reverse proxy, routes to services via Docker labels
- **socket-proxy**: Restricts Docker API access to whitelisted operations (`127.0.0.1:2375`)
- **Bitwarden SM**: Central secrets store (project `selfhost-pirate`, ID: `eb78eee6-0397-420e-8a31-b45f000d2625`)
- **BWS token**: `~/.config/bwsh/token` — mounted into init containers as `:ro`
- **OCIR registry**: `us-chicago-1.ocir.io/axh7zpa5qpqc/` — custom images (bws-init, Linkwarden, Meilisearch)
- **CrowdSec**: WAF + appsec for exposed services
- **OCI Vault**: Alternative secret source for selfhost init (dual-source reconciliation)

### Common Conventions

- PUID=1001, PGID=998 (root `.env`)
- TZ=America/New_York
- Logging: `journald` driver for production services (not default json-file)
- Secrets and config files: `600` permissions, never committed to git
- Named volumes follow `{project}_{volume}` pattern (e.g. `pirate_prowlarr-secrets`)
- Docker Compose profiles for grouping services (e.g. `stremio`, `arrs`, `proxy`, `books`)
- `deploy.resources` limits on CPU and memory for resource-intensive services
- `read_only: true` + `tmpfs` for services that don't need writable rootfs
- `security_opt: no-new-privileges:true` + `cap_drop: [all]` as baseline, add back only needed caps

---

## 2. Secret Injection: bws-init / locket Pattern

The infrastructure uses the **bws-init** image
(`us-chicago-1.ocir.io/axh7zpa5qpqc/bws-init:latest`) for injecting secrets
from Bitwarden SM into containers. The image has a **standardized entrypoint**
(`/opt/init/locket-init.sh`) that handles both `inject` (config file templates)
and `exec` (env file + command) modes. All settings are controlled via
environment variables, eliminating inline bash `command:` blocks.

The entrypoint manages the full lifecycle:
1. Creates output directory (cold boot — tmpfs doesn't persist)
2. Cleans Docker `create_host_path` directory placeholders
3. Checks idempotency — skips locket if all outputs already exist
4. Delegates to `locket inject` or `locket exec`

Three variants exist today, but only **Variant A** is the recommended pattern
for new stacks and migrations.

### Variant A: Standardized entrypoint — locket inject (recommended)

The init container runs with environment variables instead of an inline command.
The entrypoint auto-detects `inject` mode when `TEMPLATES_DIR` and `OUTPUT_DIR`
are set. The output directory should be on **host tmpfs** (`/run/<stack>-secrets/`).

```yaml
  service-init:
    image: us-chicago-1.ocir.io/axh7zpa5qpqc/bws-init:latest
    container_name: service-init
    restart: "no"
    environment:
      TEMPLATES_DIR: /templates
      OUTPUT_DIR: /rendered
    volumes:
      - ./templates:/templates:ro
      - /run/mylar3-secrets:/rendered:rw
      - ~/.config/bwsh:/root/.config/bwsh:ro
    networks: []

  service:
    depends_on:
      service-init:
        condition: service_completed_successfully
    volumes:
      - /run/mylar3-secrets/config.ini:/config/config.ini:rw
```

**Key characteristics:**
- **No `command:` block** — all settings via env vars
- **Entrypoint handles**: `mkdir -p`, Docker placeholder cleanup, idempotency skip
- **Host tmpfs** (`/run/<stack>-secrets/`) — not named volumes — so secrets auto-clear on reboot
- **Bind mounts**: `:rw` if the service entrypoint chowns the file at startup (e.g., linuxserver images), `:ro` otherwise
- **BWS token**: mounted as `~/.config/bwsh:/root/.config/bwsh:ro` (includes token + cache)
- **Init runs as root** — short-lived container on root-owned tmpfs, no user data touched

**Customizable env vars (with defaults):**

| Variable | Default | Description |
|----------|---------|-------------|
| `TEMPLATES_DIR` | `/templates` | Directory with template files |
| `OUTPUT_DIR` | `/rendered` | Directory for rendered secrets |
| `SECRETS_PROVIDER` | `bws` | Secret provider for locket |
| `BWS_MACHINE_TOKEN` | `file:/root/.config/bwsh/token` | BWS token path |
| `LOCKET_INJECT_MODE` | `one-shot` | Locket inject mode |
| `LOCKET_FILE_MODE` | `0644` | File permissions for rendered secrets |
| `LOCKET_DIR_MODE` | `0755` | Directory permissions |

For **exec mode** (env file injection for services like newrelic), set `LOCKET_MODE=exec`
along with `LOCKET_ENV_FILE` for the output env file path and any additional args as
the `command:`.

### Variant B: key mapping + secrets-entrypoint (legacy — linkwarden, flexget, newrelic, hermes, ntfy)

> **Note**: This variant is being phased out. New stacks should use Variant A
> with `locket exec` for env file injection.

These stacks use the same bws-init image but with `BWS_KEY_MAPPING` and
`BWS_SECRET_PREFIXES` environment variables. The init container renders
a `.env` file into a named volume. The service uses `secrets-entrypoint.sh`
to source those variables before starting the application process.

```yaml
  service-init:
    image: us-chicago-1.ocir.io/axh7zpa5qpqc/bws-init:latest
    container_name: service-init
    restart: "no"
    environment:
      BWS_PROJECT_ID: ${BWS_PROJECT_ID}
      BWS_SECRET_PREFIXES: "BWS_SERVICE"
      BWS_KEY_MAPPING: "BWS_SERVICE_KEY:APP_KEY"
      BWS_SECRET_NAMES: "APP_KEY"
      CONFIG_TEMPLATE_DIR: /run/config-templates
      CONFIG_OUTPUT_DIR: /run/config-output
    volumes:
      - .:/run/config-templates:ro
      - service-secrets:/run/config-output
      - ~/.config/bwsh:/root/.config/bwsh:ro
      - ~/.cache/bwsh:/root/.cache/bwsh:rw
    networks: []

  service:
    entrypoint: ["/opt/init/scripts/secrets-entrypoint.sh", "service-cmd"]
    volumes:
      - service-secrets:/run/config-secrets:ro
    depends_on:
      service-init:
        condition: service_completed_successfully
```

### Variant C: selfhost init.sh (dual-source OCI Vault + Bitwarden SM with drift detection)

The `selfhost/` stack uses a custom `init.sh` (in `selfhost/bws-init/`) that
fetches secrets from **both** OCI Vault and Bitwarden SM, compares them for
drift, and renders templates. This is currently used by ntfy.

Key files:
- `selfhost/bws-init/init.sh` — main reconciliation script
- `selfhost/bws-init/Dockerfile` — custom image with OCI CLI
- `selfhost/bws-init/scripts/oci-vault-get-secret.sh` — OCI Vault helper

### Variant D: single-source Bitwarden SM (no OCI Vault, no bwsh — use Variant A)

> **Note**: This variant is effectively replaced by Variant A with the standardized
> `locket-init.sh` entrypoint. For new services, use Variant A directly with
> host tmpfs. The bwsh-based manual `init.sh` pattern is no longer needed
> because `locket` handles the entire inject pipeline.

For services that use Bitwarden SM as the **sole** secret source (no OCI Vault
replication, no drift detection, no bwsh wrapper), the bws-init image with the
standardized entrypoint is the recommended approach. See Variant A above.

**Key characteristics (Variant A / entrypoint-based approach):**
- Image size: ~15-20MB (Alpine + locket + bws + entrypoint script)
- No OCI CLI (saves ~150MB)
- No bwsh wrapper — locket handles BWS auth directly
- No inline bash — all configuration via environment variables
- Template syntax: `{{ UUID }}` via locket inject (not `envsubst`)

**Current bws-init Dockerfile:**
```dockerfile
FROM alpine:3.19

RUN apk add --no-cache bash curl openssl

# locket 0.17.3 compiled with compose feature
COPY locket /usr/local/bin/locket

# bws CLI for Bitwarden SM secret management
COPY bws /usr/local/bin/bws

# bwsh — shell wrapper for bws (legacy Variant B env injection)
COPY bwsh /usr/local/bin/bwsh

# Standard entrypoint — handles tmpfs lifecycle, Docker placeholder cleanup,
# idempotency check, and delegates to locket inject/exec
COPY scripts/locket-init.sh /opt/init/locket-init.sh
RUN chmod +x /opt/init/locket-init.sh

ENTRYPOINT ["/opt/init/locket-init.sh"]
```

**Entrypoint: `/opt/init/locket-init.sh`**

The standardized entrypoint handles two modes, auto-detected from env vars:

| Mode | Detection | Purpose |
|------|-----------|---------|
| `inject` (default) | `TEMPLATES_DIR` and `OUTPUT_DIR` are set | Render config file templates via `locket inject` |
| `exec` | `LOCKET_ENV_FILE` or `LOCKET_ENV` is set | Render env files and run command via `locket exec` |

**Lifecycle (inject mode):**
1. Verify `TEMPLATES_DIR` exists and contains files — fail fast if missing
2. `mkdir -p "$OUTPUT_DIR"` — ensures tmpfs directory exists on cold boot
3. Check each template file's expected output path for Docker directory placeholders
   (Compose v2.40+ creates `create_host_path` directories for missing bind-mount targets)
4. If all outputs already exist as regular files: exit 0 (idempotency skip)
5. Otherwise: run `locket inject` with `SECRET_MAP=${TEMPLATES_DIR}:${OUTPUT_DIR}`

**Lifecycle (exec mode):**
1. Set `SECRET_MAP` if both `TEMPLATES_DIR` and `OUTPUT_DIR` are provided
2. Run `locket exec "$@"` — passes through any `command:` arguments

**When to use each variant:**

| Variant | Use When | Image Size | Complexity |
|---------|----------|------------|------------|
| **A** | **New stacks and migrations (recommended)** — config file injection via `locket inject` or env file injection via `locket exec` | ~15-20MB | Low |
| **B** | Legacy stacks with bwsh key mapping + `secrets-entrypoint.sh` (linkwarden, flexget, newrelic, hermes, ntfy) | ~200MB | Medium |
| **C** | Legacy dual-source OCI Vault + BWSM with drift detection (selfhost only) | ~200MB | High |

### Common init container requirements

All init container variants require:
1. **BWS token directory**: `~/.config/bwsh:/root/.config/bwsh:ro` (includes both `token` and `cache/`)
2. **Template directory**: mapped into the init container as `:ro` (for inject mode)
3. **Output directory**: host tmpfs (`/run/<stack>-secrets/`) as `:rw`
4. **`restart: "no"`** — init runs once and exits
5. **`networks: []`** — init does not need network access (BWS token is pre-authenticated)

**For Variant A (recommended):** the init container mounts
`~/.config/bwsh:/root/.config/bwsh:ro` which provides both the token file
and the bwsh cache directory. No separate token file mount is needed.
No named volumes — use host tmpfs instead.

### Deprecated: OCI CLI vault-init

Older services (`opencode-telegram-bot/`, `linkwarden/`) use `vault-init.sh`
with the Oracle OCI CLI directly. These are being phased out in favor of
the bws-init pattern (Variant A). See Section 5.

---

## 3. Godoxy Reverse Proxy

### Architecture

Godoxy auto-discovers services via Docker labels and routes HTTP/HTTPS traffic.
The proxy runs in the root `compose.yml` with `network_mode: host`. It connects
to Docker through `socket-proxy` (not direct socket).

### Registering a Service

Add labels to any container attached to the `selfhost_frontnet` network:

```yaml
labels:
  proxy.servicename.port: 3000       # Container port to route to
  proxy.servicename.healthcheck.disable: true  # Skip health check
  proxy.servicename.homepage.show: true        # Show on dashboard
  proxy.aliases: alt-name                     # Alternative hostname
  proxy.exclude: true                         # Exclude from proxy
```

### TCP Services

For database proxies (MariaDB, PostgreSQL, MSSQL, Redis):

```yaml
labels:
  proxy.hostmariadb.scheme: tcp
  proxy.hostmariadb.port: 3306
```

### Middleware

Godoxy supports inline middleware via labels:

```yaml
  proxy.#1.middlewares.cidr_whitelist: |
    status: 403
    allow:
      - 10.0.0.0/8
```

### Logging

- Access logs: `godoxy/logs/`
- Config: `godoxy/config/`
- Error pages: `godoxy/error_pages/`
- Certs: `godoxy-certs` named volume

---

## 4. socket-proxy

### Purpose

Restricts Docker API access to prevent privilege escalation. Instead of
mounting `/var/run/docker.sock` directly, containers connect to
`socket-proxy` at `127.0.0.1:2375`, which only allows whitelisted operations.

### Allowed Operations

`ALLOW_START`, `ALLOW_STOP`, `ALLOW_RESTARTS`, `CONTAINERS`, `EVENTS`,
`INFO`, `PING`, `POST`, `VERSION`.

### Guidance

- **socket-proxy**: Production services needing limited Docker API access
- **Direct socket**: Services that need full access (crowdsecmgr, dockhand, godoxy app)

---

## 5. OCI Vault Secret Management

### vault-inject.sh (Root-Level)

`/home/ubuntu/docker/vault-inject.sh` can inject OCI Vault secrets into the
current shell or write them to a `.env.vault` file. It caches secrets for
1 hour in `/tmp/vault-inject-cache.sh`.

```bash
source vault-inject.sh                    # export into shell
source vault-inject.sh --write-env        # write .env.vault file
bash vault-inject.sh --audit              # verify only
```

### Per-Stack vault-init.sh

- `linkwarden/vault-init.sh` — injects into `linkwarden/.env.vault`
- `opencode-telegram-bot/vault-init.sh` — injects into `opencode-telegram-bot/.env.vault`

### Migration Path

Prefer the bws-init pattern (Section 2) over OCI CLI vault-init for all new
services. The bws-init pattern is simpler, faster, and centralized in Bitwarden SM.

---

## 6. OCIR Registry

### Custom Images

All custom images are hosted at `us-chicago-1.ocir.io/axh7zpa5qpqc/`:

| Image | Source | Used By |
|-------|--------|---------|
| `bws-init:latest` | `selfhost/bws-init/Dockerfile` | All stacks |
| `primary-server/linkwarden:latest` | Linkwarden source | linkwarden/ |
| `primary-server/meilisearch:v1.12.8` | Meilisearch source | linkwarden/ |

### Authentication

OCIR is accessed via OCI auth token stored in Docker config.
Do not commit credentials.

---

## 7. Restic Backup Architecture

### Principles

A cross-stack backup pattern using restic with S3-compatible storage.
Currently deployed in the `pirate/` stack but applicable to any stack.

### Key Components

1. **SQLite hot backups** — Consistent snapshots via `sqlite3 .backup`
   - Bind-mount services: direct access to `.db` files
   - Named-volume services: `docker cp` from container → host `sqlite3 .backup`

2. **Named volume exports** — `docker run --rm alpine tar czf` snapshots volume
   contents to `.volume-exports/*.tar.gz` for restic

3. **Restic snapshots** — S3-compatible backend with 7 daily / 4 weekly / 12 monthly retention

4. **Restore** — `restore.sh` pattern: stop services → restic restore → volume
   restore → DB overwrite → start services

### Adding a New Stack to Restic Backup

1. Add app data directories and volume export directories to the backup source list
2. Add init-bws services to the volume export loop
3. Add SQLite DB paths to the db-backup step
4. Schedule via crontab

### Credentials

- Stored in `./.restic-env` (NOT in git — `600` permissions)
- Format: `RESTIC_REPOSITORY`, `RESTIC_PASSWORD`

---

## 8. Bitwarden SM Administration

### CLI Tools

- **bws** (`/usr/local/bin/bws`, v2.1.0) — Bitwarden Secrets Manager CLI
- **bwsh** — Higher-level wrapper for environment variable injection

### Project

- `selfhost-pirate` project ID: `eb78eee6-0397-420e-8a31-b45f000d2625`
- Server: `https://vault.bitwarden.com`

### Adding a Secret

```bash
bws secret create \
  --project eb78eee6-0397-420e-8a31-b45f000d2625 \
  --key "BWS_SERVICE_KEY_NAME" \
  --value "<secret-value>"
```

### Token File

`~/.config/bwsh/token` — mounted into all init containers. Permissions: `600`.

---

## 9. Resource Limits & Compute Constraints

### Why It Matters

Without resource limits, a single container can consume all host CPU and memory.
Real-world example: `protonbyparr` (a byparr indexer proxy through gluetun VPN)
consumed **52% of all container CPU** and caused load spikes of 10.9 before limits
were applied.

### Setting Limits

Use `deploy.resources` in compose:

```yaml
deploy:
  resources:
    limits:
      cpus: "2.0"
      memory: 2G
      pids: 512
    reservations:
      cpus: "0.25"
      memory: 256M
```

### Guidelines

| Service Type | CPU Limit | Memory Limit | Notes |
|-------------|-----------|-------------|-------|
| Proxy/VPN (proton, warp) | 2.0 | 512M | Network-bound, but can spike during reconnection |
| Indexer proxy (byparr, flaresolverr) | 2.0 | 1G | CPU-intensive during search bursts |
| Database (mariadb, postgres) | 4.0 | 4G | Adjust based on dataset size |
| Reverse proxy (godoxy) | 1.0 | 256M | Lightweight, mostly I/O |
| Init containers | 0.5 | 128M | Short-lived, minimal resources |
| Monitoring (newrelic) | 1.0 | 512M | Host monitoring overhead |

### PIDs Limit

The `pids` limit prevents fork bombs. Set to 512 for most services, higher for
databases (1024+).

---

## 10. Networking

### Network Modes

| Mode | Use Case | Security |
|------|----------|----------|
| `bridge` (default) | Most services on `selfhost_frontnet` | Isolated, proxied access |
| `network_mode: host` | Databases, godoxy app, crowdsec | Full host network access — use sparingly |
| `network_mode: container:<name>` | Services piggybacking on another container's network (e.g., VPN-routed) | Inherits the target container's network stack |

### Port Mapping

**Only map ports that need direct host or external access.** Services on the same
Docker network reach each other by container name without mapped ports. Mapped ports
increase attack surface.

```yaml
# Only when needed:
ports:
  - "127.0.0.1:8080:8080"  # Host-only access (preferred for internal services)
  - "8080:8080"             # External access (only if needed)
```

### External Networks

`selfhost_frontnet` is the shared external bridge network. All stacks attach to it
for Godoxy proxy routing:

```yaml
networks:
  frontnet:
    external: true
    name: selfhost_frontnet
```

### DNS

Docker provides internal DNS resolution by container name. Use `container_name`
for predictable hostnames. For host access from containers, use
`host.docker.internal` (or `extra_hosts: host.docker.internal:host-gateway` on Linux).

---

## 11. Volume Management

### Named Volumes vs Bind Mounts

| Type | Use Case | Backup Method |
|------|----------|---------------|
| **Named volumes** | Config, secrets, application state | Volume export via `docker run --rm alpine tar` |
| **Bind mounts** | Data needing host access, git-tracked config | Direct restic backup of host path |

### Named Volume Export Pattern

Named volumes are not mounted on the host filesystem, so restic cannot back them
up directly. Export before backup:

```bash
docker run --rm \
  -v source_volume:/source:ro \
  -v /host/output:/output \
  alpine tar czf /output/volume-name.tar.gz -C /source .
```

### Stale Volume Cleanup

Stale volumes accumulate from compose changes. List and remove:

```bash
docker volume ls | grep <project>
docker volume rm <volume_name>
```

Common causes of stale volumes:
- Renamed services (old `{project}_{service}_data` volumes remain)
- Migrated from bind-mount to named-volume pattern
- Commented-out services in compose

### Volume Permissions

Init containers should set explicit permissions on rendered secrets.
With the standardized entrypoint (Variant A), defaults are configured via
environment variables and the entrypoint script:

```yaml
environment:
  LOCKET_FILE_MODE: "0644"   # Default — readable by any UID
  LOCKET_DIR_MODE: "0755"    # Default — world-traversable for compose CLI
```

**Why 0644/0755:**
- `0644` (not `0640`): Services run as various UIDs (MSSQL 10001, mylar3 911, decypharr 1001)
  — group-based permissions don't work when every service has a different UID
- `0755` (not `0750`): Docker Compose reads `env_file` paths at parse time as a non-root
  user — `0750` blocks world traversal, causing parse errors

For legacy patterns (inline bash), set `locket inject` flags explicitly:
```bash
locket inject ... --file-mode 0644 --dir-mode 0755
```

---

## 12. Logging

### Driver Selection

| Driver | Use When | Notes |
|--------|----------|-------|
| `journald` | Production services | Centralized, structured, survives container restarts |
| `json-file` (default) | Development only | No rotation by default, fills disk |

```yaml
logging:
  driver: journald
```

### Viewing Logs

```bash
# journald driver
journalctl -u docker --grep <container>
docker logs <container>

# json-file driver
docker logs <container>
```

### Log Rotation (json-file)

If you must use json-file, configure rotation:

```yaml
logging:
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"
```

---

## 13. Health Checks & Dependencies

### Health Check Types

```yaml
# Command-based
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 15s

# TCP-based (for databases)
healthcheck:
  test: ["CMD-SHELL", "pg_isready -h localhost -U postgres"]
  interval: 10s
  timeout: 5s
  retries: 5
```

### Dependency Conditions

```yaml
depends_on:
  service-init:
    condition: service_completed_successfully  # Init containers
  database:
    condition: service_healthy                 # Service dependencies
  cache:
    condition: service_started                 # Best-effort startup order
```

### Key Differences

- `service_started`: Container is running (default, no health check required)
- `service_healthy`: Health check must pass
- `service_completed_successfully`: Container exited with code 0 (for init containers)

### Dockerfile vs Compose Healthcheck

Dockerfile `HEALTHCHECK` and compose `healthcheck` use different syntax.
Prefer compose `healthcheck` for clarity and override capability.

---

## 14. Security Hardening

### Baseline for All Containers

```yaml
security_opt:
  - no-new-privileges:true
cap_drop:
  - all
read_only: true
tmpfs:
  - /tmp:rw
```

Then add back only the capabilities each service needs:

```yaml
# For fuse/filesystem mounts (decypharr, rclone)
cap_add:
  - SYS_ADMIN
devices:
  - /dev/fuse:/dev/fuse

# For network binding (godoxy)
cap_add:
  - NET_BIND_SERVICE
```

### Privileged Containers

Avoid `privileged: true`. Use specific `cap_add` instead. Only `newrelic-infra`
requires `privileged: true` for host monitoring.

### Secrets in Environment

Never put secrets directly in compose files. Use:
1. Named volumes from init containers (preferred)
2. `.env` files (not in git, 600 permissions)
3. Docker Swarm secrets (not used in this infrastructure)

### Image Pinning

Pin images to specific versions or digests for reproducibility:

```yaml
# Prefer digest for immutability
image: docker.io/valkey/valkey:9@sha256:3eeb09785cd61ec8...

# Or at minimum, pin the tag
image: ghcr.io/yusing/godoxy:latest  # Acceptable for actively maintained internal images
```

### Docker Socket Access

**Never mount `/var/run/docker.sock` directly** unless the service requires full
Docker API access. Use `socket-proxy` instead:

```yaml
# Good: through proxy
environment:
  DOCKER_HOST: "tcp://127.0.0.1:2375"

# Avoid: direct socket mount
volumes:
  - /var/run/docker.sock:/var/run/docker.sock  # Only for crowdsecmgr, dockhand, godoxy
```

---

## 15. Troubleshooting

### Init Container Fails

```bash
docker logs <service>-init
```

Common causes:
- BWS token expired or missing → check `~/.config/bwsh/token` exists and is valid
- Template directory not mapped → check compose volumes: `TEMPLATES_DIR` must exist inside the container
- `BWS_MACHINE_TOKEN` path wrong → default is `file:/root/.config/bwsh/token` — verify mount path
- Docker placeholder directory blocking file write → `locket-init.sh` handles this automatically,
  but if using a custom entrypoint, check for directories where files should be:
  `ls -la /run/<stack>-secrets/`
- Permission denied on output dir → host tmpfs directory must be `:rw` mounted; verify with
  `docker inspect <service>-init | jq '.[].Mounts'`

### Godoxy Service Unreachable

1. Verify container is in `selfhost_frontnet` network
2. Check Godoxy labels are correct (`proxy.<name>.port`)
3. Check `godoxy/logs/` for routing errors
4. Verify `crowdsec` is healthy (`docker exec crowdsec cscli lapi status`)

### Named Volume Missing

```bash
docker volume ls | grep <project>
docker compose run --rm <service>-init
```

### Socket Proxy Refusing Connection

Verify socket-proxy is running and the `ALLOW_*` env vars permit the
operation the downstream service needs.

### Container OOM Killed

Check if memory limits are too tight:

```bash
docker inspect <container> | grep -i oom
journalctl -u docker | grep -i oom
```

Increase `deploy.resources.limits.memory` or investigate memory leaks.

### High CPU Usage

Identify the culprit container:

```bash
docker stats --no-stream
```

If a container consistently exceeds its CPU limit, the kernel throttles it.
Either increase the limit or investigate the workload. Real-world example:
`protonbyparr` consumed 52% of all container CPU and caused load spikes of 10.9
before `deploy.resources.limits.cpus` was added.

### Container Won't Start — Port Conflict

```bash
# Error: "address already in use"
ss -tlnp | grep <port>
```

Remove the conflicting port mapping from compose or stop the competing service.
Remember: services on the same Docker network don't need mapped ports to reach
each other — mapped ports are only for host/external access.

### Container Won't Start — Volume Mount Error

```bash
# Error: "permission denied" on volume
```

Check volume permissions. Named volumes inherit permissions from the container's
user. Bind mounts use host filesystem permissions — ensure PUID/PGID match.

### Network Connectivity Between Containers

```bash
# Test from inside a container
docker exec -it <container> ping <other-container>
docker exec -it <container> curl http://<other-container>:<port>/health
```

If DNS resolution fails, verify both containers are on the same network:

```bash
docker inspect <container> | grep -A 10 "Networks"
```

### Image Pull Errors (OCIR)

```bash
docker login us-chicago-1.ocir.io
# Use OCI auth token as password
docker pull us-chicago-1.ocir.io/axh7zpa5qpqc/<image>:tag
```

### Stale Volumes Accumulating

List all volumes for a project:

```bash
docker volume ls | grep <project>
```

Remove stale volumes after verifying they're no longer needed:

```bash
docker volume rm <volume_name>
```

Stale volumes commonly result from renaming services, migrating bind-mounts to
named volumes, or commenting out services in compose files.
