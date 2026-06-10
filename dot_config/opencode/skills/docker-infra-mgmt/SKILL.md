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

The infrastructure uses **four variants** of the same bws-init image
(`us-chicago-1.ocir.io/axh7zpa5qpqc/bws-init:latest`) for injecting secrets
from Bitwarden SM into containers. The base image contains `locket` (from
`ghcr.io/bpbradley/locket:bws`); Variants B/C/D additionally require OCI CLI
only when OCI Vault integration is needed.

### Variant A: locket inject — used by pirate services

The init container runs `locket inject` with a `--map` flag to render
template files into a named volume. The service then mounts that volume
read-only.

```yaml
  service-init:
    image: us-chicago-1.ocir.io/axh7zpa5qpqc/bws-init:latest
    container_name: service-init
    restart: "no"
    entrypoint: ["/bin/sh", "-c"]
    command:
      - mkdir -p /run/secrets && locket inject --provider bws
          --bws-token file:/run/secrets/bwstoken --mode one-shot
          --map /templates/service:/run/secrets
          --user 1001:998 --file-mode 0640 --dir-mode 0755
    volumes:
      - ./templates/service:/templates/service:ro
      - service-secrets:/run/secrets
      - ~/.config/bwsh/token:/run/secrets/bwstoken:ro

  service:
    depends_on:
      service-init:
        condition: service_completed_successfully
    volumes:
      - service-secrets:/run/secrets:ro
```

### Variant B: key mapping + secrets-entrypoint — used by linkwarden, flexget, newrelic, hermes, ntfy

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

### Variant D: single-source Bitwarden SM (no OCI Vault) — recommended for new services

For services that use Bitwarden SM as the **sole** secret source (no OCI Vault
replication, no drift detection), the init container can be dramatically
simplified. This is the recommended pattern for new services and new server
installations (e.g., Kali).

**Differences from Variant C:**
- No OCI CLI installed in the image (~150MB savings)
- No `oci-vault-get-secret.sh` script
- No drift detection logic
- `init.sh` reduces to: fetch from BWSM → render templates → exit
- Image size drops from ~200MB to ~15-20MB

**Simplified Dockerfile:**
```dockerfile
FROM alpine:3.19

RUN apk add --no-cache bash curl openssl

# locket for Bitwarden SM inject (Variant A)
COPY --from=ghcr.io/bpbradley/locket:bws /usr/local/bin/locket /usr/local/bin/locket

COPY scripts/ /opt/init/scripts/
RUN chmod -R +x /opt/init/scripts/

ENTRYPOINT []
```

**Simplified init.sh (no drift detection):**
```bash
#!/bin/bash
set -u

CONFIG_TEMPLATE_DIR="${CONFIG_TEMPLATE_DIR:-/config/templates}"
CONFIG_OUTPUT_DIR="${CONFIG_OUTPUT_DIR:-/config}"
BWSH_TOKEN_FILE="${BWSH_TOKEN_FILE:-/root/.config/bwsh/token}"
BWS_PROJECT_ID="${BWS_PROJECT_ID:?BWS_PROJECT_ID must be set}"

mkdir -p "$CONFIG_OUTPUT_DIR"

# Step 1: Fetch secrets from Bitwarden SM
export BWS_DEFAULT_PROJECT_ID="$BWS_PROJECT_ID"
bwsh run -p "$BWS_DEFAULT_PROJECT_ID" env > /tmp/bws-all.env 2>/dev/null || {
    echo "ERROR: Failed to fetch secrets from Bitwarden SM" >&2; exit 1;
}

# Step 2: Parse secrets into associative array
declare -A SECRETS
while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^# ]] && continue
    [[ "$key" =~ ^(${BWS_SECRET_PREFIXES:-BWS_}) ]] || continue
    clean_key="${key#BWS_}"
    # Apply key mapping if set (format: "FROM:TO,FROM:TO,...")
    if [[ -n "$BWS_KEY_MAPPING" ]]; then
        IFS=',' read -ra mappings <<< "$BWS_KEY_MAPPING"
        for mapping in "${mappings[@]}"; do
            from="${mapping%%:*}"; to="${mapping##*:}"
            [[ "$key" == "$from" ]] && { clean_key="$to"; break; }
        done
    fi
    SECRETS["$clean_key"]="$value"
done < <(grep -E "^(${BWS_SECRET_PREFIXES:-BWS_})" /tmp/bws-all.env)

echo "Fetched ${#SECRETS[@]} secrets from Bitwarden SM"

# Step 3: Render templates
for template in "$CONFIG_TEMPLATE_DIR"/*.template; do
    [[ -f "$template" ]] || continue
    output="${CONFIG_OUTPUT_DIR}/$(basename "$template" .template)"
    envsubst < "$template" > "$output"
    chmod 600 "$output"
    echo "Rendered $output"
done

echo "Secret injection complete. Exiting."
```

**When to use each variant:**

| Variant | Use When | Image Size | Complexity |
|---------|----------|------------|------------|
| **A** | Pirate services with `{{ ocid }}` templates | ~15MB | Low |
| **B** | Services needing env var injection (linkwarden, flexget, newrelic, hermes) | ~200MB | Medium |
| **C** | Dual-source OCI Vault + BWSM with drift detection (legacy ntfy) | ~200MB | High |
| **D** | New services, single-source BWSM only (recommended) | ~15-20MB | Low |

### Common init container requirements

All four variants require:
1. **BWS token file**: `~/.config/bwsh/token` mounted into the init container
2. **BWS project ID**: `BWS_PROJECT_ID` env var matching the Bitwarden SM project
3. **Template directory**: mapped into the init container as `:ro`
4. **Named volume**: for rendered secrets output
5. **`restart: "no"`** — init runs once and exits

### Deprecated: OCI CLI vault-init

Older services (`opencode-telegram-bot/`, `linkwarden/`) use `vault-init.sh`
with the Oracle OCI CLI directly. These are being phased out in favor of
the bws-init pattern. See Section 5.

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

Init containers should set explicit ownership and permissions on rendered secrets:

```bash
locket inject ... --user 1001:998 --file-mode 0640 --dir-mode 0755
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
- BWS token expired or missing → check `~/.config/bwsh/token`
- Template directory not mapped → check compose volumes
- `BWS_PROJECT_ID` mismatch → verify against Bitwarden SM project

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
