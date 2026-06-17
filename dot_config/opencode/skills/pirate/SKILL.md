---
name: pirate
description: >
  Runbook for the Pirate media suite at $HOME/docker/pirate/ — Stremio
  (AIostreams), ARR indexers (Prowlarr/Jackett/NZB Hydra2), VPN proxies
  (Proton/Warp), ebook/audiobook services (Shelfmark/Grimmory/Storyteller),
  and Decypharr. Covers stack health assessment, architecture, per-service
  triage, backup/restore, and a register of known-failed troubleshooting
  paths. Designed for AI consumption: teaches discovery over static
  reference to resist environment drift.
compatibility: opencode
metadata:
  stacks: pirate
  services: aios,decypharr,prowlarr,jackett,nzbhydra2,shelfmark,grimmory,storyteller,proton,warp
  tools: docker compose,locket,sqlite3,restic
  profiles: all,stremio,arrs,proxy,books
  replaces: pirate-infra-mgmt, pirate-stack
---

# Pirate Stack Runbook

This is an ops runbook for AI agents. It does not hardcode live-discoverable
state (paths, volume names, IPs). Instead it teaches **how to discover** the
current environment using `docker` commands, and provides the
non-discoverable knowledge: topology relationships, failure archetypes,
triage roadmaps, and a register of known-failed troubleshooting paths.

Base path: `$HOME/docker/pirate/`

For cross-stack patterns (locket-init secret injection, Godoxy reverse
proxy, socket-proxy, OCI Vault, restic backup architecture), see the
`docker` skill. For Godoxy-specific routing, see the `selfhost` skill.

---

## 0. Stack Health Primer

Before diving into a specific service, assess overall stack health:

```bash
# What's supposed to be running? (profiles: all, stremio, arrs, proxy, books)
docker compose --profile all ps --all

# Spot unhealthy or exited containers
docker compose --profile all ps --all | grep -E "(unhealthy|exit)"

# Surface recent errors across all running services
docker compose --profile all logs --tail=10 2>/dev/null | \
  grep -E "(Error|ERROR|Fatal|WARN)"

# Check expected named volumes exist
docker volume ls | grep pirate

# Verify environment file has expected variables
grep -v "^#" .env | grep -v "^$"

# Check what ports are published (drift-resistant: always read from compose)
docker compose --profile all config | grep -A1 "ports:"
```

If nothing looks wrong at this level, the issue is likely application-level
(provider keys, DB state, upstream services) rather than infrastructure.

---

## 1. Stack Architecture

### 1.1 Compose Profiles

The stack uses profiles for targeted startup:

```bash
docker compose --profile all up -d        # everything
docker compose --profile stremio up -d    # aios
docker compose --profile arrs up -d       # prowlarr, jackett, nzbhydra2, decypharr
docker compose --profile proxy up -d      # proton (VPN), warp (Cloudflare)
docker compose --profile books up -d      # shelfmark, grimmory, storyteller
```

### 1.2 Proxy Topology

Services route through different proxy layers. This topology is not
obvious from compose config alone — it encodes which VPN/SOCKS5 layer
each service uses and which combination containers chain off the bases:

- **`proton`** — Gluetun VPN gateway. Base container for all `proton*` variants.
- **`warp`** — Cloudflare Warp SOCKS5 proxy. Base for all `warp*` variants.
- **`*flare`** variants (protonflare, warpflare) — add Flaresolverr for
  Cloudflare-bypass on top of the base proxy.
- **`*byparr`** variants (protonbyparr, warpbyparr) — add Flaresolverr +
  Byparr on top of the base proxy.

**To discover which proxy a service routes through:**
```bash
docker inspect <service> -f '{{json .HostConfig.NetworkMode}}'
```

The response shows either `container:<proxy>` (shares proxy's network stack)
or `service:<proxy>` (Docker DNS through the proxy service).

### 1.3 Secrets (locket-init)

All pirate services use the **locket-init** pattern (see `docker` skill
§2): each service has a `*-init` container that runs `locket inject` to
render secrets into a named volume.

**Exception:** aios uses OCI vault-init (legacy). Its secrets are
maintained separately, not through the locket pipeline. Do not attempt to
convert aios to locket-init — this is intentional.

**Re-initialize secrets for any service:**
```bash
docker compose run --rm <service>-init
```

**To check if an init ran successfully:** verify the corresponding named
volume exists (`docker volume ls | grep <service>`) and check the init
container's exit code in `docker compose ps --all`.

Most compose environment variables live in `./.env`. Secrets are never
committed to git. If a container fails with "variable not set" on startup,
the missing variable likely belongs in `.env`, not in `compose.yaml`.

### 1.4 Data Storage Patterns

| Type | How to discover |
|------|----------------|
| Named volumes | `docker volume ls \| grep pirate` |
| Bind mounts | `docker inspect <service> -f '{{json .Mounts}}'` |
| SQLite DBs | Check mounts — if a `.db` file path appears, that's the DB |
| MariaDB (grimmory) | Host database via `host.docker.internal:3306` |

Config and secrets are always in named volumes. App data may be on bind
mounts (varies per service — discover via inspect).

### 1.5 Startup Dependencies

Order matters during recovery:

1. **MariaDB** must be reachable before grimmory starts.
   Verify: `docker exec <mariadb-container> mariadb-admin ping`
2. **Proxy base containers** (proton, warp) must start before their chain
   variants (protonflare, protonbyparr, warpflare, warpbyparr).
3. **aios init** needs OCI vault secrets to exist before init runs.
4. **locket-init** containers need `locket` binary functional and the
   backing secrets service reachable.

After full-stack restart: wait for base containers (proton, warp, DB) to
report healthy before starting dependent services.

---

## 2. Per-Service Triage

Each service follows the same format:
- **Red flags:** Log patterns or symptoms that signal trouble
- **Health check:** Quick command to verify the service is working
- **Diagnosis roadmap:** Ordered steps to narrow down the root cause
- **Resolution paths:** Symptom → fix mappings
- **Failed paths:** What has been tried and didn't work, or known
  unsupported configurations

---

### aios (AIostreams)

**Red flags:**
- Provider key errors in logs (real-debrid, etc.)
- Init container exits non-zero

**Health check:**
```bash
docker compose --profile stremio ps aios
# Also check: docker compose --profile stremio logs --tail=20 aios
```

**Diagnosis roadmap:**
1. Init failure → check OCI vault secrets exist and permissions
2. Runtime errors → check `AIOS.env` for missing or expired provider keys
3. Container not starting → verify `AIOS.env` has the required keys

**Resolution paths:**
- Expired/missing provider key → update `AIOS.env` and recreate
- Init failure → check OCI vault — this service does NOT use locket-init

**Failed paths:**
- Do NOT attempt to convert aios to locket-init. It intentionally remains
  on OCI vault-init for legacy reasons.

---

### decypharr

**Red flags:**
- FUSE errors in logs ("Permission denied", "fusermount")
- Init container fails (bws/locket token issue)
- Encrypted filesystem layer not available

**Health check:**
```bash
docker compose --profile arrs ps decypharr
# Container should show "Up" status
```

**Diagnosis roadmap:**
1. FUSE errors → verify `SYS_ADMIN` capability and `/dev/fuse` device in
   the compose service definition
2. Init failure → check `~/.config/bwsh/token` or locket connectivity
3. Volume missing → `docker volume ls | grep decypharr` (expects 5 volumes)

**Resolution paths:**
- FUSE errors → ensure compose has `cap_add: SYS_ADMIN` and
  `devices: [/dev/fuse]`
- Init failure → `docker compose --profile arrs run --rm decypharr-init`
- Missing volume → init recreates it automatically

**Failed paths:**
- Removing FUSE requirements is not possible — encrypted filesystem is
  core to decypharr's function.

---

### prowlarr

**Red flags:**
- DB corruption errors on startup ("SQL logic error", migration failures)
- Indexers not showing in UI
- Init container fails

**Health check:**
```bash
docker compose --profile arrs ps prowlarr
# Check logs for DB errors on start
docker compose --profile arrs logs --tail=30 prowlarr
```

**Diagnosis roadmap:**
1. Startup crash → check logs for SQLite corruption messages
2. Init failure → verify template files render correctly
3. Indexer issues → check if prowlarr can reach indexers through its
   proxy layer

**Resolution paths:**
- **DB corruption:**
  1. `docker compose --profile arrs stop prowlarr`
  2. Copy latest hot backup from `prowlarr/prowlarr.db` back to the named
     volume mount path
  3. `docker compose --profile arrs start prowlarr`
  4. If that fails: restore from restic —
     `./restore.sh -a prowlarr -t "12h"`
- Init failure → `docker compose --profile arrs run --rm prowlarr-init`

**Failed paths:**
- Do not attempt in-place SQLite repair on a corrupted DB. Always restore
  from hot backup or restic snapshot.

---

### jackett

**Red flags:**
- No indexers responding in UI
- Init container fails
- Config errors in logs

**Health check:**
```bash
docker compose --profile arrs ps jackett
# Check for crash-loop (restarting status)
```

**Diagnosis roadmap:**
1. Init failure → check template JSON files are valid
2. Runtime issues → verify proxy routing is correct
   (`docker inspect jackett -f '{{json .HostConfig.NetworkMode}}'`)
3. Config issues → template rendering may have produced invalid config

**Resolution paths:**
- Init failure → `docker compose --profile arrs run --rm jackett-init`
- Proxy issues → check the base proxy container (proton or warp) is healthy

**Failed paths:**
- (none documented yet)

---

### nzbhydra2

**Red flags:**
- Not reachable via reverse proxy
- Init container fails
- Proxy connectivity errors

**Health check:**
```bash
docker compose --profile arrs ps nzbhydra2
# Not directly exposed on a host port — verify through proxy
```

**Diagnosis roadmap:**
1. Init failure → check template files
2. Not reachable → check service is running and Godoxy config routes to it
3. Proxy issues → verify network mode matches expected proxy chain

**Resolution paths:**
- Init failure → `docker compose --profile arrs run --rm nzbhydra2-init`
- Proxy connectivity → check Godoxy routing (see `selfhost` skill)

**Failed paths:**
- (none documented yet)

---

### shelfmark (Ebook Reader)

**Red flags:**
- Users/groups not loading
- Init container fails
- Two template directories: `shelfmark/` and `shelfmark-plugins/`

**Health check:**
```bash
docker compose --profile books ps shelfmark
```

**Diagnosis roadmap:**
1. Users not loading → check `users.db` inside the `shelfmark-secrets`
   named volume
2. Init failure → check **both** template directories exist and have valid
   content: `ls ./templates/shelfmark/ ./templates/shelfmark-plugins/`

**Resolution paths:**
- Users/groups not loading → restore from hot backup:
  1. `docker compose --profile books stop shelfmark`
  2. Copy `shelfmark/users.db` back into the named volume mount path
  3. `docker compose --profile books start shelfmark`
- Init failure → `docker compose --profile books run --rm shelfmark-init`

**Failed paths:**
- (none documented yet)

---

### grimmory (Comic Server)

**Red flags:**
- Healthcheck hangs (`wget` to `/api/v1/healthcheck` times out)
- Logs contain: "Connection is not available, request timed out"
- Logs contain: "DATABASE_PASSWORD variable is not set. Defaulting to blank string."
- Container shows "Up" but won't serve requests

**Health check:**
```bash
curl http://localhost:6760/api/v1/healthcheck
# Expected: {"data":{"status":"UP",...}}
```

**Diagnosis roadmap:**
1. Check `.env` has `DATABASE_PASSWORD` set — if missing, container
   recreate blanks the password (restart is fine, recreate is not)
2. Check MariaDB is reachable:
   ```bash
   docker exec <mariadb-container> mariadb-admin ping
   docker exec <mariadb-container> mariadb -u root -p -e "SHOW DATABASES;"
   ```
3. If MariaDB is reachable and password is set but healthcheck hangs →
   connection pool exhaustion

**Resolution paths:**
- **DATABASE_PASSWORD blank:** add to `.env`, then recreate:
  `docker compose --profile books up -d --force-recreate grimmory`
- **Connection pool exhaustion** (healthcheck hangs, "timed out" in logs):
  1. `docker compose --profile books restart grimmory` — clears stuck threads
  2. Verify: `curl http://localhost:6760/api/v1/healthcheck`
  3. After ~60-90s it should return UP
- **MariaDB not reachable:** check MariaDB container is running and
  `host.docker.internal:3306` resolves

**Failed paths:**
- Do NOT attempt to tune HikariCP connection pool via environment
  variables — this image does not support it.
- Do NOT set `DATABASE_PASSWORD` directly in `compose.yaml`. It MUST be
  in `.env` to survive container recreates.
- Root cause of pool exhaustion: MariaDB restart closes all HikariCP
  connections. HikariCP `maxLifetime` (1800s) > MariaDB `wait_timeout`
  (600s). The mismatch is not configurable in this image without a rebuild.

---

### storyteller (Audiobook Server)

**Red flags:**
- Init container fails
- DB corruption or data loss
- Audiobooks not showing in UI

**Health check:**
```bash
docker compose --profile books ps storyteller
```

**Diagnosis roadmap:**
1. Init failure → check template files in `./templates/storyteller/`
2. Data missing → check the bind mount at `./storyteller/`
3. DB issues → the SQLite DB (`storyteller.db`) is on the bind mount,
   not inside a named volume

**Resolution paths:**
- Init failure → `docker compose --profile books run --rm storyteller-init`
- DB/data corruption → restore from restic snapshot (the data dir is on a
  bind mount, so restic captures it directly)
- DB-specific recovery → copy `storyteller.db` hot backup from backup dir

**Failed paths:**
- (none documented yet)

---

### proton (Gluetun VPN Gateway)

**Red flags:**
- gluetun status shows disconnected
- Auth errors in logs ("authentication failed")
- Dependent proxy variants (protonflare, protonbyparr) cannot reach network

**Health check:**
```bash
docker exec proton gluetun status
# Expected: running and connected
docker logs proton | tail -10
```

**Diagnosis roadmap:**
1. Check VPN connection: `docker exec proton gluetun status`
2. Check for auth errors: `docker logs proton | grep -i "auth\|error\|fail"`
3. Check Proton VPN service status (external — may be an upstream outage)

**Resolution paths:**
- Auth errors → stale VPN credentials. Re-init secrets:
  `docker compose --profile proxy run --rm proton-init`
- VPN dropped but auto-reconnecting → gluetun handles this; wait 30s
- Persistent failure → check upstream Proton VPN service status

**Failed paths:**
- Do not restart proton while proxy variants depend on it. Stop variants
  first, then restart proton, then restart variants.

---

### warp (Cloudflare Warp Proxy)

**Red flags:**
- Connectivity issues from dependent services
- Init container fails
- SOCKS5 proxy not responding

**Health check:**
```bash
docker compose --profile proxy ps warp
# Container should show "Up" status
```

**Diagnosis roadmap:**
1. Init failure → check secrets init ran successfully
2. Connectivity → verify dependent services can reach warp's SOCKS5 port
   (1080)

**Resolution paths:**
- Init failure → `docker compose --profile proxy run --rm warp-init`
- Connectivity issues → check the proxy chain: dependent services use
  `network_mode: service:warp` or `container:warp`

**Failed paths:**
- (none documented yet)

---

## 3. Backup & Restore

All scripts live at `$HOME/docker/pirate/`.

### 3.1 Database Backups (`db-backup.sh`)

Hot-copies SQLite databases using `sqlite3 .backup` for consistent
snapshots without downtime:

```bash
./db-backup.sh
```

**Coverage:**
- **Covers:** aios, prowlarr, shelfmark, storyteller (SQLite)
- **Not covered:** grimmory (MariaDB — manual `mariadb-dump` required),
  decypharr / nzbhydra2 / jackett (non-SQLite — volume export only)

### 3.2 Restic Backups (`restic-backup.sh`)

Full infrastructure backup to S3-compatible storage:

```bash
./restic-backup.sh
```

Scheduled via crontab: `0 3 * * *`

**Pipeline:**
1. Run `db-backup.sh` for SQLite hot backups
2. Export all named volumes to `.volume-exports/*.tar.gz`
3. Restic backup — app directories + `.volume-exports/`
4. `restic forget --prune` — retention: 7 daily, 4 weekly, 12 monthly

Volume exports directory: `./.volume-exports/` (permissions 700,
in `.gitignore`).

Restic credentials in `.restic-env` (permissions 600, not in git).

### 3.3 Restore (`restore.sh`)

```bash
# Dry run (preview only, no changes)
./restore.sh -a <app> -t "6h" -n

# Restore a single app
./restore.sh -a prowlarr -t "24h"

# Restore everything to last week
./restore.sh -a all -t "1w"

# Restore to a specific timestamp
./restore.sh -a all -t "2026-06-05 14:00:00"
```

**Before restoring:** verify the snapshot exists first with `-n` (dry-run).

**Restore process:**
1. Stop affected services (or all if `-a all`)
2. `restic restore` the requested paths
3. Restore named volumes from `.volume-exports/` tarballs
   (app-aware filtering)
4. Overwrite live DB files from hot backups
5. Start services

### 3.4 On Failure

If a named volume export fails during backup:
```bash
# Test manually
docker run --rm -v pirate_<volume>:/source:ro alpine tar tzf - /source
```

If the volume doesn't exist (was removed), the script skips it
gracefully. Recreate with `docker compose run --rm <service>-init`.

---

## 4. Migration Notes

### 4.1 Bind Mount → Named Volume (init-locket pattern)

See `docker` skill §2 for the general cross-stack pattern. Pirate-specific
steps:

1. Create template files in `./templates/<service>/`
2. Add `*-init` service and named volume in `compose.yaml`
3. Update the service to use the named volume
4. Add to the volume export loop in `restic-backup.sh`
5. Add `docker cp` snippet to `db-backup.sh` if SQLite
6. After validation: migrate old data and remove bind-mount paths

### 4.2 Legacy Data Volumes

Stale named volumes from earlier compose revisions:

- `pirate_prowlarr_data` (replaced by `pirate_prowlarr-secrets`)
- `pirate_nzbhydra2_data` (replaced by `pirate_nzbhydra2-secrets`)
- `pirate_jackett_data` (replaced by `pirate_jackett-secrets`)

Do NOT remove these until you have verified the replacement
`*-secrets` volumes contain all needed data:
```bash
# Compare contents before removing
docker run --rm -v pirate_prowlarr_data:/old:ro alpine ls -la /old
docker run --rm -v pirate_prowlarr-secrets:/new:ro alpine ls -la /new
```

Only remove after verification:
```bash
docker volume rm pirate_prowlarr_data \
  pirate_nzbhydra2_data \
  pirate_jackett_data
```

---

## 5. Failed-Path Register

This section documents troubleshooting paths that have been tried and
failed, or configurations known to be unsupported. Future agents should
check here before exploring these paths to avoid wasted effort.

| Service | Failed path | Reason |
|---------|-------------|--------|
| aios | Converting to locket-init | Intentionally remains on OCI vault-init (legacy). Do not migrate. |
| grimmory | Tuning HikariCP via env vars | Not supported by this container image. Requires app rebuild or external config file. |
| grimmory | Setting DATABASE_PASSWORD in compose.yaml | Must be in `.env` — compose values don't survive `--force-recreate` during config drift. |
| grimmory | Fixing pool exhaustion without restart | Stuck Tomcat threads cannot be cleared without container restart. No graceful drain path. |
| prowlarr | In-place SQLite repair | Always restore from hot backup or restic. In-place repair has a history of making corruption worse. |
| decypharr | Removing FUSE/SYS_ADMIN requirements | Encrypted filesystem layer is fundamental to decypharr's function. |
| proxy | Starting proxy variants before base containers | protonflare/protonbyparr need proton up first. warpflare/warpbyparr need warp up first. |
| general | Filesystem-level copy on live SQLite DBs | Use `sqlite3 .backup` (as `db-backup.sh` does). cp on a live DB produces inconsistent snapshots. |
| general | Removing legacy `*-data` volumes before verification | Always compare contents with replacement `*-secrets` volumes first. Data loss risk. |
