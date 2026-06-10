---
name: pirate-stack
description: >
  Management of the Pirate media suite at /home/ubuntu/docker/pirate/ — Stremio
  (AIostreams), ARR indexers (Prowlarr/Jackett/NZB Hydra2), VPN proxies
  (Proton/Warp), ebook/audiobook services (Shelfmark/Grimmory/Storyteller),
  and Decypharr. Covers per-service operations, profiles, proxy routing,
  init-bws specifics, and backup/restore script usage. Depends on
  docker-infra-mgmt skill for cross-stack patterns (bws-init, Godoxy, etc.).
compatibility: opencode
metadata:
  stacks: pirate
  services: aios,decypharr,prowlarr,jackett,nzbhydra2,shelfmark,grimmory,storyteller,proton,warp
  tools: docker compose,bws,locket,sqlite3,restic
  profiles: all,stremio,arrs,proxy,books
---

# Pirate Stack Management

Service-specific management guide for the Pirate media suite at
`/home/ubuntu/docker/pirate/`. For cross-stack patterns (bws-init/locket
secret injection, Godoxy reverse proxy, socket-proxy, OCI Vault, restic
backup architecture), see the `docker-infra-mgmt` skill.

---

## 1. Stack Architecture

### Compose Profiles

The stack is organized into profiles for targeted startup:

```bash
# Start everything
docker compose --profile all up -d

# Start only specific groups
docker compose --profile stremio up -d   # aios
docker compose --profile arrs up -d      # prowlarr, jackett, nzbhydra2, decypharr
docker compose --profile proxy up -d     # proton (VPN), warp (Cloudflare)
docker compose --profile books up -d     # shelfmark, grimmory, storyteller
```

### Proxy Routing Variants

Services can route through different proxy layers. The routing is determined
by `network_mode` in the compose config:

| Name | Proxy | Network Config |
|------|-------|----------------|
| `proton` | Proton VPN (gluetun) | `network_mode: container:proton` |
| `warp` | Cloudflare Warp | `network_mode: service:warp` |
| `protonflare` | Proton VPN + Flaresolverr | `network_mode: service:protonflare` |
| `warpflare` | Cloudflare Warp + Flaresolverr | `network_mode: service:warpflare` |
| `protonbyparr` | Proton VPN + Flaresolverr + Byparr | `network_mode: service:protonbyparr` |
| `warpbyparr` | Cloudflare Warp + Flaresolverr + Byparr | `network_mode: service:warpbyparr` |

### Secrets Architecture

All pirate services use Variant A of the bws-init pattern (see `docker-infra-mgmt`
skill Section 2). Each service has a `*-init` container that runs `locket inject`
to render secrets into a named volume.

### Data Storage

| Type | Location | Backup Method |
|------|----------|---------------|
| Named volumes (config/secrets) | Docker named volumes (`pirate_*`) | Volume export → tar.gz → restic |
| Bind mounts (data) | `./AIOS/data`, `./storyteller`, `./grimmory` | Direct restic |
| SQLite DBs | Named volumes or bind mounts | `docker cp` + host `sqlite3 .backup` |
| MariaDB (grimmory) | host.docker.internal:3306 | MariaDB dump (manual) |

### Environment File

Most compose environment variables are in `./.env`. Do not commit secrets to git.

---

## 2. Per-Service Reference

### aios (AIostreams)

- **Container**: `aios`
- **Port**: 3000
- **Profile**: `stremio`
- **Config**: `AIOS.env` (bind mount)
- **DB**: `./AIOS/data/db.sqlite` (SQLite)
- **Backup**: Direct `sqlite3 .backup` on bind mount
- **Init**: Not init-bws — uses OCI vault-init (legacy)
- **Notes**: Requires `AIOS.env` with real-debrid/other provider keys

### decypharr

- **Container**: `decypharr`
- **Port**: 8282
- **Profile**: `arrs`
- **Config**: **5 named volumes** — `decypharr-{secrets,app,auth,config,configs}`
- **Backup**: Volume export (5 volumes)
- **Init**: bws-init with `locket inject`
- **Special**: Requires `SYS_ADMIN` capability and `/dev/fuse` device

### prowlarr

- **Container**: `prowlarr`
- **Port**: 9696
- **Profile**: `arrs`
- **DB**: Inside `prowlarr-secrets` named volume at `/config/prowlarr.db` (SQLite)
- **Backup**: `docker cp prowlarr:/config/prowlarr.db` → host `sqlite3 .backup`
- **Init**: `prowlarr-init` — templates from `./templates/prowlarr/`
- **Logs**: `docker logs prowlarr` (journald driver)

### jackett

- **Container**: `jackett`
- **Port**: 9117
- **Profile**: `arrs`
- **Config**: `jackett-secrets` named volume (JSON config files)
- **Backup**: Volume export
- **Init**: `jackett-init` — templates from `./templates/jackett/`

### nzbhydra2

- **Container**: `nzbhydra2`
- **Port**: Not directly exposed (access through proxy)
- **Profile**: `arrs`
- **Config**: `nzbhydra2-secrets` named volume
- **Backup**: Volume export
- **Init**: `nzbhydra2-init` — templates from `./templates/nzbhydra2/`

### shelfmark (Ebook Reader)

- **Container**: `shelfmark`
- **Port**: 8084
- **Profile**: `books`
- **DB**: Inside `shelfmark-secrets` named volume at `/config/users.db` (SQLite)
- **Backup**: `docker cp shelfmark:/config/users.db` → host `sqlite3 .backup`
- **Init**: `shelfmark-init` — templates from `./templates/shelfmark/` and `./templates/shelfmark-plugins/`

### grimmory (Comic Server)

- **Container**: `grimmory`
- **Port**: 6760
- **Profile**: `books`
- **DB**: MariaDB on host (`host.docker.internal:3306/grimmory`) — not SQLite
- **Data dir**: `./grimmory` (bind mount at `/app/data`)
- **Secrets**: `grimmory-secrets` named volume at `/run/secrets`
- **Init**: `grimmory-init` — templates from `./templates/grimmory/`
- **Backup**: MariaDB dump needed (not covered by db-backup.sh)
- **Data dir**: backed up via restic bind-mount path

### storyteller (Audiobook Server)

- **Container**: `storyteller`
- **Port**: 8002
- **Profile**: `books`
- **DB**: `./storyteller/storyteller.db` (SQLite, bind mount)
- **Data dir**: `./storyteller` (bind mount at `/data:rw`)
- **Secrets**: `storyteller-secrets` named volume at `/run/secrets`
- **Init**: `storyteller-init` — templates from `./templates/storyteller/`
- **Backup**: Direct `sqlite3 .backup` on bind mount; restic for data dir

### proton (Gluetun VPN Gateway)

- **Container**: `proton`
- **Profile**: `proxy`
- **Config**: `proton-secrets` named volume
- **HTTP proxy**: `proton:8888` (other containers attach via `network_mode: container:proton`)
- **Init**: `proton-init` — templates from `./templates/proton/`
- **Special**: `network_mode: host` — runs at the host network level
- **Restart behavior**: Auto-reconnects on VPN drop; check logs for auth errors

### warp (Cloudflare Warp Proxy)

- **Container**: `warp`
- **SOCKS5 proxy**: port 1080
- **Profile**: `proxy`
- **Config**: `warp-secrets` named volume
- **Init**: `warp-init`
- **Note**: Used as an alternative to proton for services that don't need VPN

---

## 3. Backup and Restore

### Script Location

All scripts live in `/home/ubuntu/docker/pirate/`.

### Database Backups (`db-backup.sh`)

Hot-copies SQLite databases using `sqlite3 .backup` for consistent snapshots:

```bash
./db-backup.sh
```

Backup strategy per service:

| Service | Method | Output |
|---------|--------|--------|
| aios | Direct `sqlite3 .backup` | `AIOS/data/db.sqlite` |
| prowlarr | `docker cp` + `sqlite3 .backup` | `prowlarr/prowlarr.db` (named volume → host) |
| shelfmark | `docker cp` + `sqlite3 .backup` | `shelfmark/users.db` (named volume → host) |
| storyteller | Direct `sqlite3 .backup` | `storyteller/storyteller.db` |
| grimmory | **Not covered** (MariaDB) | Manual `mariadb-dump` |
| decypharr/nzbhydra2/jackett | **Not SQLite** — volume export only | N/A |

### Restic Backups (`restic-backup.sh`)

Full infrastructure backup to S3-compatible storage:

```bash
./restic-backup.sh
```

Scheduled via crontab: `0 3 * * *`

Process:
1. **Step 1**: Run `db-backup.sh` for SQLite hot backups
2. **Step 2**: Export all named volumes to `.volume-exports/*.tar.gz`
3. **Step 3**: Restic backup — app directories + `.volume-exports/`
4. **Step 4**: `restic forget --prune` — 7 daily, 4 weekly, 12 monthly

Volume exports directory: `./.volume-exports/` (700 permissions, in `.gitignore`)

### Restore (`restore.sh`)

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

Restore process:
1. Stop affected services (or all if `-a all`)
2. `restic restore` the requested paths
3. Restore named volumes from `.volume-exports/` tarballs (app-aware filtering)
4. Overwrite live DB files from hot backups
5. Start services

### Credentials

Restic credentials in `.restic-env` (600 permissions, not in git).

---

## 4. Common Operations

### Start/Stop a Service

```bash
cd /home/ubuntu/docker/pirate
docker compose --profile <profile> up -d <service>
docker compose stop <service>
docker compose rm -sfv <service>   # Full clean removal
```

### Check Service Logs

```bash
docker logs <service>
# Most services use journald:
journalctl -u docker --grep <service>
```

### Rebuild a Service After Config Change

```bash
cd /home/ubuntu/docker/pirate
docker compose --profile <profile> up -d <service> --force-recreate
```

### Reinitialize Secrets (rerun init container)

```bash
docker compose run --rm <service>-init
```

---

## 5. Troubleshooting

### Service Fails to Start — Init Container Issue

```bash
docker logs <service>-init
```

Common causes:
- `bwstoken` file missing or expired → check `~/.config/bwsh/token`
- Template files incorrect → check `./templates/<service>/`
- Named volume not created → `docker volume ls | grep pirate`

### VPN/Proxy Not Working (proton)

```bash
docker logs proton | tail -30
# Check if VPN tunnel is established
docker exec proton gluetun status
```

### prowlarr DB Corrupted

If prowlarr fails with DB errors:
1. Stop prowlarr: `docker compose stop prowlarr`
2. Restore from latest hot backup (in `prowlarr/prowlarr.db`)
3. Restart: `docker compose start prowlarr`
4. If that fails, restore from restic snapshot:
   `./restore.sh -a prowlarr -t "12h"`

### shelfmark Users/Groups Not Loading

Similar to prowlarr — restore from `shelfmark/users.db` hot backup.

### grimmory DB Connection Issues

Grimmory uses MariaDB on host (`localhost:3306`):
1. Check MariaDB is running: `docker exec mariadb mariadb-admin ping`
2. Verify database exists: `docker exec mariadb mariadb -u root -p -e "SHOW DATABASES;"`
3. No hot backup exists for MariaDB — use `mariadb-dump` periodically

### Named Volume Export Fails

If a volume fails to export during backup:
```bash
# Test manually
docker run --rm -v pirate_<volume>:/source:ro alpine tar tzf - /source
```

If the volume doesn't exist (was removed), the script skips it gracefully.
Recreate by running `docker compose run --rm <service>-init`.

### decypharr Fuse Errors

```
docker logs decypharr
# Ensure SYS_ADMIN cap and /dev/fuse device are present in compose
```

---

## 6. Migration Notes

### Bind Mount → Named Volume (init-bws pattern)

See `docker-infra-mgmt` skill Section 2 for the general pattern.
Pirate-specific migration steps:

1. Create template files in `./templates/<service>/`
2. Add `*-init` service and named volume in `compose.yaml`
3. Update the service to use the named volume
4. Add to the volume export loop in `restic-backup.sh`
5. Add `docker cp` snippet to `db-backup.sh` if SQLite
6. After validation: migrate old data and remove bind-mount paths

### Legacy Data Volumes

Stale named volumes from earlier compose revisions:
- `pirate_prowlarr_data` (replaced by `pirate_prowlarr-secrets`)
- `pirate_nzbhydra2_data` (replaced by `pirate_nzbhydra2-secrets`)
- `pirate_jackett_data` (replaced by `pirate_jackett-secrets`)

These can be removed after verifying the replacement volumes have all data:
```bash
docker volume rm pirate_prowlarr_data pirate_nzbhydra2_data pirate_jackett_data
```
