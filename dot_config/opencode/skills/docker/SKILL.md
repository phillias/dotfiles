---
name: docker
description: >
  Cross-stack Docker Compose infrastructure management — covers locket-init/locket
  secret injection patterns, Godoxy reverse proxy, socket-proxy, OCI Vault
  integration, OCIR registry conventions, restic backup/restore architecture,
  and Bitwarden SM administration shared across all stacks at $HOME/docker/.
compatibility: opencode
metadata:
  stacks: root,selfhost,pirate,hermes,linkwarden,flexget,newrelic,jessalaga,opencode-telegram-bot,mylar3
  services: godoxy,socket-proxy,crowdsec,locket-init,locket
  tools: docker,docker compose,bws,bwsh,locket,oci,restic,sqlite3
---

# Docker Infrastructure Management

> **Audience**: AI agent. Optimized for runtime discovery and decision-tree
> diagnosis, not static reference. When in doubt, **check the live system**
> — the compose files, running containers, and Docker state are ground truth.
>
> All paths use `$HOME` — resolve at runtime. All UUIDs, project IDs, and
> registry paths use placeholders — replace with actual values from the
> live environment or Bitwarden SM.
>
> **Companion files**: `$HOME/.config/opencode/skills/docker/ARCHIVE.md`
> (deprecated patterns), `$HOME/.config/opencode/skills/docker/MIGRATION.md`
> (migration walkthroughs). Full standalone runbook also at
> `$HOME/docker/DOCKER_RUNBOOK.md`.

---

## 1. Stack Map

### 1.1 Stack Inventory

Discover the actual stacks at runtime:

```bash
ls -d $HOME/docker/*/compose.y* $HOME/docker/compose.y* 2>/dev/null
```

Known stacks (verify against live):

| Directory | Project Name | Purpose |
|-----------|-------------|---------|
| `$HOME/docker/` (root) | `selfhost` | Reverse proxy, databases, CrowdSec, monitoring |
| `$HOME/docker/selfhost/` | `selfhost` | Secondary proxy, tinyauth, dockhand, apprise |
| `$HOME/docker/pirate/` | `pirate` | Media suite (Stremio, ARRs, VPN, ebooks) |
| `$HOME/docker/hermes/` | `hermes` | AI agent gateway + Telegram bot |
| `$HOME/docker/linkwarden/` | `linkwarden` | Bookmark manager |
| `$HOME/docker/flexget/` | `flexget` | Media automation |
| `$HOME/docker/jessalaga/` | `jessalaga` | RSS reader |
| `$HOME/docker/opencode-telegram-bot/` | `opencode-telegram-bot` | Telegram bot |
| `$HOME/docker/newrelic/` | `newrelic` | Host monitoring |
| `$HOME/docker/mylar3/` | `mylar3` | Comic book manager |

### 1.2 Critical Path

Services that must be healthy for everything else to work.
**Check these first during any outage:**

```
socket-proxy (127.0.0.1:2375)
  └── godoxy (reverse proxy, network_mode: host)
      └── crowdsec (LAPI + AppSec)
```

- **socket-proxy** restricts Docker API — if down, nothing that needs Docker API works
- **godoxy** is the HTTP entry point — if down, all web UIs are unreachable
- **crowdsec** blocks traffic at the proxy level — if unhealthy, godoxy may still route but with degraded security

### 1.3 Shared Resources

Discover at runtime — do not assume static config:

| Resource | Discovery Command | Indicator |
|----------|------------------|-----------|
| Shared network | `docker network ls \| grep frontnet` | Should show `selfhost_frontnet` |
| BWS token | `ls -la $HOME/.config/bwsh/token` | Mode 600, non-empty |
| locket binary | `locket compose --help 2>&1` | Must list `compose` subcommand |
| Patched compose | `docker compose version` | Should show `rawsetenv` suffix |
| Provider descriptor | `ls $HOME/.docker/compose/providers/locket.json` | Must exist |
| Provider symlink | `ls -la $HOME/.docker/cli-plugins/docker-locket` | Symlink to locket binary |
| OCIR registry | `docker login $OCIR_REGISTRY 2>&1` | Success = configured |
| CrowdSec LAPI | `docker exec crowdsec cscli lapi status 2>&1` | Should report healthy |

### 1.4 Common Conventions

Verify these match in live compose files — they're conventions, not guarantees:

| Convention | Typical Value |
|------------|--------------|
| PUID | 1001 |
| PGID | 998 |
| TZ | America/New_York |
| Logging driver | `journald` (production), `json-file` (dev) |
| Secrets permissions | 600, never committed |
| Named volume pattern | `{project}_{volume}` (e.g. `pirate_prowlarr-secrets`) |
| Security baseline | `no-new-privileges:true`, `cap_drop: [all]`, `read_only: true` |

---

## 2. Operating Principles

> These guardrails govern ALL decisions and actions. Violating them without
> explicit user approval is a hard block. They exist because every one of
> them was learned the hard way.

### 2.1 Injection Hierarchy

```
Compose Provider (env vars)   → PRIMARY — zero extra containers, memory-only
Volume Driver (config files)  → PRIMARY — zero init containers, resolves at mount
locket-init Sidecar           → FALLBACK — only after exhausting above two
```

Always try compose provider and volume driver first. If neither works,
document why, present for approval, then consider locket-init.

### 2.2 Env Vars Are Memory-Only

- Secrets injected via the compose provider exist only in the container's
  runtime environment. NEVER render them to `.env` files on disk.
- If a service needs `env_file:` at compose parse time, this is a known
  limitation. Document and escalate — do NOT silently fall back to file-based
  injection.

### 2.3 No Upstream Modifications

- **No image rebuilds** — never modify a service's Dockerfile.
- **No entrypoint changes** — never override or wrap the container entrypoint.
- **No `command:` overrides** to inject secrets.
- The service must work with the env var names and config file paths provided
  by the upstream image. If the compose provider delivers exact key names, no
  adaptation is needed.

### 2.4 Operations Must Be Service-Scoped

This is the most frequently violated rule. Get it right every time:

| ✅ Correct | ❌ Incorrect |
|------------|-------------|
| `docker compose up -d mariadb` | `docker compose up -d` (starts everything) |
| `docker compose restart godoxy` | `docker compose down` (kills critical path) |
| `docker stop <container>` | `docker compose down` on a shared stack |
| `docker compose logs locket --tail 20` | |

**Full-stack operations require explicit user approval** — describe which
services will be affected and why it's necessary.

### 2.5 Validate Before Cleanup

- **Never delete** volumes, configs, `.env` files, or compose files until the
  migrated service is confirmed functional.
- **Always copy with permissions preserved** before making changes:
  ```bash
  cp -a --preserve=mode,ownership,timestamps original.env original.env.bak
  ```
- **Test before deploying:** `docker compose config` must pass with zero errors.
- **Defer all cleanup** until user confirms.

### 2.6 Escalation Path

If no injection method works within these principles:
1. Document the specific constraint conflict
2. Present for user approval
3. Only then proceed to locket-init or other fallback

---

## 3. Decision Trees

### 3.1 Secret Injection Method

```
New service needs secrets
│
├── Does the service read secrets from ENVIRONMENT VARIABLES?
│   │
│   ├── YES → Does it use `env_file:` at compose parse time?
│   │   │
│   │   ├── YES → locket-init sidecar (Play 7)
│   │   │         Compose reads env_file path before containers start.
│   │   │         Compose provider and volume driver cannot help here.
│   │   │
│   │   └── NO  → Compose provider (Play 2)
│   │             Declare `provider.type: locket` with `options.env`.
│   │             Zero extra containers. Env vars injected at compose time.
│   │
│   └── NO → Does the service read secrets from CONFIG FILES?
│       │
│       ├── YES → Volume driver (Play 4)
│       │         locket Docker volume plugin. Resolves at mount time.
│       │         Zero init containers. Works for JSON, YAML, INI, TOML.
│       │         ⚠️ NOT for env_file at compose parse time.
│       │
│       └── NO → No action needed, or evaluate need.
│
│   IF BOTH env vars AND config files → Compose provider for env vars
│   + volume driver for config files. If config file has env_file
│   requirement, escalate to locket-init.
│
│   IF all three fail → Check the Failed Path Archive (Section 6)
│   for why specific methods were rejected.
```

### 3.2 Service Won't Start

```
docker compose ps shows service not running
│
├── Check service logs first
│   docker compose logs <service> --tail 50
│
├── Check init container status (if service has depends_on init)
│   docker compose logs <service>-init --tail 20
│   docker compose ps -a | grep init
│
├── Check compose config is valid
│   docker compose config
│   # If fails: YAML error, missing volume, undefined network
│
├── Common failures by symptom:
│   │
│   ├── "address already in use" → Port conflict
│   │   ss -tlnp | grep <port>
│   │   Check if another container or host process has the port
│   │
│   ├── "permission denied" on volume mount
│   │   Check PUID/PGID match between service and file ownership
│   │   Named volumes: permissions from container user
│   │   Bind mounts: permissions from host filesystem
│   │
│   ├── Init container exited non-zero
│   │   Check BWS token validity → bws secret list
│   │   Check template directory is mounted and has files
│   │   Check output directory is writable (tmpfs or bind mount)
│   │
│   ├── locket provider service failed
│   │   docker compose logs locket
│   │   Check rawsetenv patch: docker compose version
│   │   Check provider symlink: ls -la ~/.docker/cli-plugins/docker-locket
│   │
│   └── Container OOM killed
│       docker inspect <container> | grep -i oom
│       journalctl -u docker | grep -i oom
│       → Increase deploy.resources.limits.memory
│
└── If still stuck → Escalate to full system diagnosis (Section 5)
```

### 3.3 Secret Resolution Failure

```
Secrets not appearing in the container or wrong values
│
├── Which injection method?
│   │
│   ├── COMPOSE PROVIDER
│   │   ├── Check locket provider ran: docker compose logs locket
│   │   │   Look for "rawsetenv" or "setenv" messages
│   │   ├── Check for prefix problem:
│   │   │   docker compose exec <service> env | grep -i LOCKET_
│   │   │   If vars have LOCKET_ prefix → rawsetenv patch missing
│   │   │   Fix: rebuild patched compose (Play 3)
│   │   ├── Check BWS token: bws secret list (exit 0 = token valid)
│   │   └── Check UUIDs in provider options.env match actual BWS secrets
│   │       bws secret list | grep <expected-key>
│   │
│   ├── VOLUME DRIVER
│   │   ├── Check plugin is running: docker plugin ls | grep locket
│   │   ├── Check volume exists: docker volume ls | grep locket
│   │   ├── Check volume details: docker volume inspect <volume>
│   │   ├── Template path correct?
│   │   │   Verify ~/.config/bwsh/templates/<service>/ has the file
│   │   ├── Volume may be stale (secrets resolved once at creation):
│   │   │   docker volume rm <volume> && docker compose up -d <service>
│   │   └── Plugin logs: journalctl -u docker.service --since "5 min ago" | grep locket
│   │
│   └── LOCKET-INIT SIDECAR
│       ├── docker logs <service>-init (not docker compose logs!)
│       ├── BWS token mounted? docker inspect <init> | jq '.[].Mounts'
│       ├── Template files exist inside container?
│       │   docker run --rm -it --entrypoint sh <init-image> -c "ls /templates/"
│       ├── Output dir writable? Check /run/<stack>-secrets/ permissions
│       └── Idempotency skip? If outputs already exist, init skips.
│           Touch a template file to force re-render: touch templates/.env
│
└── If secrets still wrong → Fall back to manual verify:
    bws secret get <UUID>
    # Compare with what's in the container
```

---

## 4. Incident Plays

### Play 1: Reboot Recovery

**Symptom**: Host rebooted. Some or all containers failed to start.

**Check order — critical path first:**

```
1. Is Docker running?
   systemctl is-active docker

2. Is socket-proxy up?
   docker ps --filter name=socket-proxy --format '{{.Status}}'

3. Is godoxy up?
   docker ps --filter name=godoxy --format '{{.Status}}'
   # If down, check compose: cd $HOME/docker && docker compose up -d godoxy

4. Is crowdsec up?
   docker ps --filter name=crowdsec --format '{{.Status}}'
```

**Known reboot breakages:**

| Issue | Indicator | Fix |
|-------|-----------|-----|
| tmpfs directories missing | `/run/<stack>-secrets/` does not exist | `mkdir -p /run/<stack>-secrets/` before compose up |
| locket-init containers need to re-render | Init container logs show "output dir missing" | `docker compose up -d <service>-init` (runs once, exits) |
| BWS token path changed | `bws secret list` fails | Check `$HOME/.config/bwsh/token` exists (mode 600) |
| Docker daemon not started | `docker ps` fails | `systemctl start docker` |
| locket symlink missing | No provider discovery | `ln -sf ~/.local/bin/locket ~/.docker/cli-plugins/docker-locket` |
| Compose patched binary replaced | No `rawsetenv` support | Rebuild (Play 3) |

**Recovery sequence:**

```bash
# 1. Ensure Docker is running
systemctl start docker

# 2. Verify critical infrastructure
docker ps --filter name=socket-proxy --format '{{.Names}} {{.Status}}'
docker ps --filter name=godoxy --format '{{.Names}} {{.Status}}'
docker ps --filter name=crowdsec --format '{{.Names}} {{.Status}}'

# 3. Check tmpfs directories exist
ls -d /run/*-secrets/ 2>/dev/null || echo "MISSING: create tmpfs dirs"

# 4. Start stacks that need BWS/locket (may need init containers to run first)
docker compose -f $HOME/docker/compose.yml up -d godoxy crowdsec
```

**Failed Path Note**: Running `docker compose up -d` (no service name) starts
EVERYTHING in the stack — including critical path components. Always specify
the service name. Full-start requires explicit approval.

---

### Play 2: Secret Rotation Failure

**Symptom**: A secret was rotated in Bitwarden SM but the service still uses
the old value, or the service fails to start after rotation.

**Diagnosis flow:**

```bash
# 1. Check the secret in BWS is what you expect
bws secret get <UUID>

# 2. Determine injection method for this service
# Check compose file for provider.type: locket, volume driver, or init container
grep -A5 'locket\|provider\|init' $HOME/docker/<stack>/compose.yml

# 3. Force re-resolution based on method:
```

| Method | Force Re-resolution | Notes |
|--------|-------------------|-------|
| Compose provider | `docker compose up -d <service>` | Provider resolves on every `compose up` |
| Volume driver | `docker volume rm <volume> && docker compose up -d <service>` | Volumes cache resolved secrets — must delete volume |
| locket-init sidecar | `touch templates/<file> && docker compose up -d <service>-init` | Touch triggers idempotency skip bypass |

**Validation:**

```bash
# For compose provider:
docker compose exec <service> env | grep <SECRET_NAME>

# For config files:
docker compose exec <service> cat /path/to/config/file

# For init containers:
docker logs <service>-init --tail 10
```

**Known failure mode**: locket compose provider caches BWS responses in
`~/.config/bwsh/cache/`. If a secret was rotated but the cache hasn't
expired, the old value is served. Clear cache:

```bash
rm -rf ~/.config/bwsh/cache/*
```

---

### Play 3: Compose Upgrade Broke rawsetenv

**Symptom**: After a `docker compose` upgrade, provider-injected env vars
now have the `LOCKET_` prefix. Services fail because they expect unprefixed
names.

**Root cause**: The patched compose binary (PR #13742) was replaced by the
upgrade. Stock compose does not support `rawsetenv` messages.

**Check:**

```bash
docker compose version
# Expected: v2.40.3-rawsetenv
# Actual (if broken): v2.40.3 (or other, no -rawsetenv suffix)

# Confirm prefix problem:
docker compose exec <service> env | grep LOCKET_
# If vars show LOCKET_MYSQL_ROOT_PASSWORD instead of MYSQL_ROOT_PASSWORD → hit
```

**Fix:**

```bash
cd $HOME/docker/locket-compose
./build.sh
cp docker-compose ~/.docker/cli-plugins/docker-compose
docker compose version  # Verify rawsetenv suffix returned
docker compose up -d <affected-service>
```

**If build fails:**

```bash
# Check Go toolchain
go version

# Check build script has the right compose version
cat $HOME/docker/locket-compose/Dockerfile | grep "docker/compose"

# Try manual build:
cd /tmp
git clone --depth 1 --branch v2.40.3 https://github.com/docker/compose.git
cd compose
# Apply PR #13742 manually (see Dockerfile for patch URL)
go build -o ~/.docker/cli-plugins/docker-compose ./cmd
```

**Failed Path Note**: Every `docker compose` upgrade overwrites
`~/.docker/cli-plugins/docker-compose`. There is no upgrade hook to
re-apply the patch. This must be done manually. The build script at
`$HOME/docker/locket-compose/build.sh` is the canonical fix.

---

### Play 4: Volume Driver Not Resolving

**Symptom**: Config files inside the container are missing, have `{{ UUID }}`
verbatim instead of resolved values, or the service can't find its secrets.

**Diagnosis flow:**

```bash
# 1. Is the plugin installed and enabled?
docker plugin ls
# → locket:latest must show as "enabled" with non-zero plugin ID

# If not listed:
docker plugin install locket:latest

# If disabled:
docker plugin enable locket:latest

# 2. Check the volume definition in compose
docker compose config | grep -A10 'driver: locket'

# 3. Check the volume exists and inspect it
docker volume ls | grep locket
docker volume inspect locket-<service>

# 4. Check inside the volume (test container)
docker run --rm -v locket-<service>:/secrets:ro alpine ls -la /secrets/
docker run --rm -v locket-<service>:/secrets:ro alpine cat /secrets/<file>
# If cat shows {{ UUID }} → volume not resolving
# If file missing → template path wrong in driver_opts

# 5. Check plugin logs for errors
journalctl -u docker.service --since "10 min ago" | grep -i locket
```

**Common fixes:**

| Symptom | Fix |
|---------|-----|
| Plugin not installed | `docker plugin install locket:latest` |
| Volume stale (resolved once, not refreshed) | `docker volume rm <vol> && docker compose up -d` |
| Template missing from `~/.config/bwsh/templates/` | Check `ls ~/.config/bwsh/templates/<service>/` |
| BWS token expired | `bws secret list` — if fails, renew token at Bitwarden SM |
| Plugin logs show connection refused | Restart Docker: `systemctl restart docker` |

**Failed Path Note**: The volume driver resolves secrets ONCE when the
volume is created. Subsequent `docker compose up` (without volume removal)
use the cached values. If a secret is rotated, the volume driver does NOT
re-resolve until the volume is deleted and recreated. This is by design —
do not file as a bug.

---

### Play 5: Backup Restore

**Symptom**: Data loss or corruption. Need to restore from restic.

**Source of truth**: `$HOME/docker/pirate/` stack has the restic integration.
For other stacks, check if they have backup scripts.

**Discovery:**

```bash
# Check for restic config
ls $HOME/docker/pirate/.restic-env 2>/dev/null

# Check for backup scripts
find $HOME/docker -name "restore*" -o -name "backup*" 2>/dev/null

# List restic snapshots (if repo accessible)
source $HOME/docker/pirate/.restic-env 2>/dev/null
restic snapshots 2>/dev/null
```

**Standard restore sequence:**

```bash
# 1. Stop the service being restored
docker stop <service>

# 2. Restore from restic (if configured)
restic restore <snapshot-id> --target /restore-point/

# 3. For named volumes: restore from volume export
#    Find .tar.gz exports in the stack directory
ls $HOME/docker/<stack>/.volume-exports/
tar xzf .volume-exports/<volume>.tar.gz -C /tmp/restored/

# 4. For bind mounts: directly copy restored data
cp -a /restore-point/<path>/* /original/path/

# 5. For SQLite databases: restore .backup file
sqlite3 /path/to/database.db ".restore /path/to/backup.db"

# 6. Restart the service
docker start <service>

# 7. Validate
docker compose exec <service> <health-check-command>
```

**Failed Path Note**: Named volumes must be exported before restic can
back them up. The export pattern (`docker run --rm alpine tar czf`) must
be part of the backup routine — if it was never set up, named volume data
is not in restic. Check the export setup at `$HOME/docker/pirate/backup.sh`.

---

### Play 6: Proxy/Certificate Failure

**Symptom**: Web UIs return connection refused, TLS errors, or godoxy error
pages. Services reachable directly (port mapping) but not through the proxy.

**Diagnosis flow:**

```bash
# 1. Is godoxy running?
docker ps --filter name=godoxy --format '{{.Status}}'
docker logs godoxy --tail 20

# 2. Is socket-proxy running?
docker ps --filter name=socket-proxy --format '{{.Status}}'

# 3. Check godoxy logs for routing errors
ls $HOME/docker/godoxy/logs/
tail -50 $HOME/docker/godoxy/logs/access.log 2>/dev/null
tail -50 $HOME/docker/godoxy/logs/error.log 2>/dev/null

# 4. Check the target service is on the proxy network
docker inspect <service> | jq '.[].NetworkSettings.Networks | keys'
# Should include "selfhost_frontnet"

# 5. Check the service has proxy labels
docker inspect <service> | jq '.[].Config.Labels | with_entries(select(.key | startswith("proxy")))'

# 6. Check crowdsec is not blocking
docker exec crowdsec cscli decisions list
docker exec crowdsec cscli lapi status
```

**Common fixes:**

| Symptom | Check | Fix |
|---------|-------|-----|
| Service has no proxy labels | `docker inspect` shows no `proxy.*` labels | Add `proxy.<name>.port: <port>` label |
| Service not on frontnet | Network list missing `selfhost_frontnet` | Add network: `docker network connect selfhost_frontnet <service>` |
| Crowdsec blocking | `cscli decisions list` shows the IP | `cscli decisions delete --ip <ip>` |
| Port mapping wrong | `proxy.<name>.port` doesn't match container port | Fix label to match `EXPOSE` or container port |
| TLS cert expired | Browser shows cert error | Check godoxy cert volume: `docker volume inspect godoxy-certs` |
| godoxy can't reach socket-proxy | `DOCKER_HOST` env var not set | Ensure `DOCKER_HOST=tcp://127.0.0.1:2375` in godoxy env |

**Failed Path Note**: Godoxy auto-discovers services via Docker labels.
It does NOT need a static config file — the labels ARE the config. If a
service is unreachable, it's almost always a missing label or a network
attachment issue, not a godoxy config issue.

---

### Play 7: locket-init Sidecar Fails

**Symptom**: Main service waits on init container, init exits non-zero.

**Diagnosis**:

```bash
# 1. Check init container logs
docker logs <service>-init

# 2. Common failure patterns in logs:
#    "BWS token not found" → ~/.config/bwsh not mounted correctly
#    "Templates directory empty" → TEMPLATES_DIR has no files
#    "Permission denied" → OUTPUT_DIR not writable
#    "No such file or directory" → template path wrong

# 3. Verify mounts inside the init container
docker inspect <service>-init | jq '.[].Mounts'

# 4. Manual test: run the init with same mounts
docker run --rm \
  -v $HOME/.config/bwsh:/root/.config/bwsh:ro \
  -v $HOME/docker/<stack>/templates:/templates:ro \
  -v /run/<stack>-secrets:/rendered \
  locket-init:latest

# 5. Check BWS token is valid
docker run --rm -v $HOME/.config/bwsh:/root/.config/bwsh:ro \
  locket-init:latest bws secret list
```

**Failed Path Note**: The init container's idempotency check skips
re-rendering if output files already exist. If a template changed but the
output file hasn't been updated, `touch` the template file or delete the
output and re-run the init container. This is a common "gotcha" when
rotating secrets — the init container exits 0 without doing anything.

---

## 5. Diagnosis Toolbox

### 5.1 Runtime Discovery Commands

These should be your FIRST tools — they tell you what's actually running,
not what the config says should be running.

| Goal | Command |
|------|---------|
| List running containers | `docker ps` |
| List ALL containers (including stopped) | `docker ps -a` |
| Check container health | `docker ps --filter health=healthy` |
| See container resource usage | `docker stats --no-stream` |
| Inspect container config | `docker inspect <container>` |
| View container logs | `docker logs <container> --tail 50` |
| View compose logs for a service | `docker compose logs <service> --tail 50` |
| Validate compose config | `docker compose config` |
| List all compose projects | `docker compose ls` |
| List networks | `docker network ls` |
| Inspect network attachments | `docker network inspect selfhost_frontnet` |
| List volumes | `docker volume ls` |
| List Docker plugins | `docker plugin ls` |
| Check Docker daemon health | `docker info` |
| Check locket provider | `docker info \| grep -i locket` |
| List BWS secrets | `bws secret list --project $BWS_PROJECT_ID` |
| Check BWS token | `bws secret list` (exit 0 = valid) |

### 5.2 Healthy vs Unhealthy Indicators

| Component | Healthy Indicator | Unhealthy Indicator |
|-----------|------------------|-------------------|
| socket-proxy | `docker ps` shows `Up`, port 2375 reachable | `docker ps` shows `Exited` or port not responding |
| godoxy | `docker ps` shows `Up (healthy)`, web UIs load | `docker ps` shows unhealthy, logs show connection errors |
| crowdsec | `cscli lapi status` returns 200 | LAPI unreachable, `cscli decisions list` fails |
| Compose provider | `docker compose logs locket` shows `rawsetenv` messages | Logs show `error` or empty, env vars have `LOCKET_` prefix |
| locket volume plugin | `docker plugin ls` shows `locket:latest enabled` | Not listed, or shows `disabled` |
| locket-init sidecar | Init container exits 0, logs show successful render | Init exits non-zero, logs show BWS/template/perm error |
| BWS token | `bws secret list` returns data | Exits with auth error |
| Database container | Health check passes, port responds | `docker ps` shows unhealthy, port not responding |

### 5.3 Log Locations

| Source | Command |
|--------|---------|
| Docker daemon | `journalctl -u docker -n 50 --no-pager` |
| Container logs (journald driver) | `docker logs <container>` or `journalctl -u docker --grep <container>` |
| Container logs (json-file driver) | `docker logs <container>` |
| Godoxy access | `cat $HOME/docker/godoxy/logs/access.log` |
| Godoxy errors | `cat $HOME/docker/godoxy/logs/error.log` |
| locket volume plugin | `journalctl -u docker.service --since "10 min ago" \| grep locket` |
| System boot | `journalctl -b -n 100 --no-pager` |

### 5.4 Network Diagnostic Commands

```bash
# Check if a port is in use
ss -tlnp | grep <port>

# Test network connectivity between containers
docker exec -it <container-a> ping <container-b>
docker exec -it <container-a> curl -v http://<container-b>:<port>/

# Check container network attachment
docker inspect <container> | jq '.[].NetworkSettings.Networks | keys'

# List all containers on the shared network
docker network inspect selfhost_frontnet | jq '.[].Containers | keys'
```

### 5.5 Volume Diagnostic Commands

```bash
# List volumes for a project
docker volume ls | grep <project>

# Inspect volume details
docker volume inspect <volume>

# Test mount a volume to see its contents
docker run --rm -v <volume>:/data:ro alpine ls -la /data/

# Check for stale volumes (no longer referenced by any container)
docker volume ls -f dangling=true

# Export a named volume contents
docker run --rm -v <volume>:/source:ro alpine tar cz -C /source .
```

### 5.6 Resource Diagnostic Commands

```bash
# Container resource usage
docker stats --no-stream

# Check if OOM was triggered
docker inspect <container> | grep -i oom
journalctl -u docker | grep -i oom

# Check current deploy.resources on a container
docker inspect <container> | jq '.[].HostConfig.Resources'

# Check Docker daemon resource usage
docker system df
```

---

## 6. Failed Path Archive

> **Purpose**: Summaries of approaches that were tried and rejected, so
> future debugging doesn't repeat dead ends. If you find yourself
> considering one of these paths, read the summary first.

### 6.1 locket exec as Entrypoint Wrapper

**Tried**: Using `locket exec` to wrap a service's entrypoint, injecting
env vars at process startup.
**Result**: REJECTED. locket exec is a process supervisor (fork+exec via
`tokio::process::Command::spawn()`), not an init system. It cannot attach
to already-running PID 1. Wrapping entrypoints broke:
- s6-overlay (Datadog — full init system managing 8+ services)
- tini subreaping (New Relic)
- Shell entrypoints that do user switching (Pocket ID, Grimmory)

**When to revisit**: If locket adds a `docker exec` style injection that
can attach to running processes without replacing PID 1.

### 6.2 Direct Binary Mounting into Service Containers

**Tried**: Mounting `bws`, `bwsh`, and `locket` binaries from the host
into service containers and overriding the entrypoint.
**Result**: REJECTED. Required 3 volume mounts + entrypoint override per
service. `bwsh` needs bash, which most Alpine-based service containers
don't have. Violates "no upstream modifications" principle.

**When to revisit**: If a standardized `locket-init` image becomes the
universal approach and entrypoint wrapping becomes the convention.

### 6.3 Systemd System Service for locket exec --watch

**Tried**: Running `locket exec --watch -- docker compose up <service>`
as a systemd system service.
**Result**: REJECTED. Dual lifecycle managers (systemd + Docker Compose)
caused conflicts. `docker compose down` caused locket to exit with status
0, and systemd `Restart=on-failure` did NOT trigger — service stayed down
permanently. Signal forwarding complexity (SIGTERM → locket → compose
process group) was fragile. Template watching re-rendered files without
restarting the service, producing stale configs.

**When to revisit**: If locket adds native compose lifecycle management
that doesn't depend on exec --watch.

### 6.4 locket exec with LOCKET_ENV_FILE

**Tried**: Using `locket exec` with `--env-file` to write rendered env
vars to a file for services using `env_file:`.
**Result**: BROKEN. locket v0.17.3 accepts the `LOCKET_ENV_FILE` flag but
does NOT write env files in exec mode. The flag is parsed and ignored.
This was confirmed through source code reading and live testing.

**When to revisit**: locket v0.18+ may fix this. Test with a simple
`locket exec -e "TEST=value" --env-file /tmp/test.env -- true` before
relying on it.

### 6.5 docker compose down on Shared Stacks

**Tried**: Using `docker compose down` to stop individual services during
migration of a shared stack (selfhost).
**Result**: DANGEROUS/KNOWN BAD. `docker compose down` stops ALL services
in the stack, including critical path (godoxy, crowdsec, socket-proxy).
Use `docker stop <container>` and `docker rm <container>` instead.

**Never revisit**: Always use service-scoped operations.

### 6.6 Named Volume File Mounting

**Tried**: `volname/file.ini:/path/file.ini:ro` in Docker Compose.
**Result**: ERROR. Docker volumes mount as whole units, not individual
files. Compose returns "refers to undefined volume". The workaround is to
use a host directory bind mount and mount individual files from there.

**When to revisit**: If Docker Compose adds file-level volume mounting
support.

### 6.7 Compose Provider Without rawsetenv (Stock Compose)

**Tried**: Using the compose provider with stock Docker Compose (without
PR #13742 patch).
**Result**: ALL env vars get `LOCKET_` prefix. Only works for services
that either don't care about exact env var names or can reference the
prefixed version. This is Docker Compose's behavior, not locket's.

**When to revisit**: If upstream Docker Compose merges PR #13742, the
patched binary becomes unnecessary.

### 6.8 locket compose Feature — Published Binaries

**Tried**: Finding a prebuilt locket binary with the `compose` feature
enabled.
**Result**: NOT AVAILABLE. All published images
(`ghcr.io/bpbradley/locket:latest`, `:bws`, `:op`, `:connect`, `:infisical`,
`:aio`, `:plugin`) are compiled without the `compose` feature. The feature
exists behind `#[cfg(feature = "compose")]` and requires building from
source.

**When to revisit**: If the upstream publishes a binary with `compose`
in the default feature set.

### 6.9 OCI Vault vault-init.sh (Legacy)

**Tried**: Using `vault-init.sh` with OCI CLI for secret injection.
**Result**: SUPERSEDED. OCI Vault approach is being phased out in favor
of Bitwarden SM + locket. The OCI CLI is ~150MB, slow, and requires
complex IAM policies. Remaining legacy services (opencode-telegram-bot,
linkwarden) should be migrated to BWS.

**When to revisit**: Only if BWS becomes unavailable.

### 6.10 locket exec from Host via docker exec

**Tried**: `docker exec -e VAR=value container command` to inject secrets
into a running container.
**Result**: DOES NOT WORK. `docker exec -e` sets env vars for the exec'd
process only — they don't persist in PID 1 and disappear when the exec
process exits.

**Never revisit**: This is a fundamental Docker limitation.

### 6.11 Multiple Init Containers (One Per Service)

**Tried**: One init container per service, each with its own BWS token
mount and template directory.
**Result**: SUPERSEDED. The standardized locket-init entrypoint uses env
vars instead of inline bash `command:` blocks, reducing boilerplate.
The current pattern uses stack-level init containers (one per stack, not
one per service).

---

## 7. Quick Reference

### Canonical Commands (No Prose)

```bash
# Start a single service
docker compose -f compose.yml up -d <service>

# Restart a single service (without stopping dependencies)
docker compose restart <service>

# Stop a single service (never use compose down on shared stacks)
docker stop <container> && docker rm <container>

# View service logs
docker compose logs <service> --tail 50 -f

# Check compose config validity
docker compose config

# Check locket provider status
docker info | grep locket
docker compose logs locket

# Check locket volume plugin
docker plugin ls | grep locket
docker volume ls | grep locket

# Test BWS token
bws secret list --project $BWS_PROJECT_ID

# Rebuild patched compose
cd $HOME/docker/locket-compose && ./build.sh && cp docker-compose ~/.docker/cli-plugins/docker-compose

# Force init container re-render
touch $HOME/docker/<stack>/templates/<service>/.env
docker compose up -d <stack>-init

# Check container mounts
docker inspect <container> | jq '.[].Mounts'

# List containers on shared network
docker network inspect selfhost_frontnet | jq '.[].Containers | keys'

# Reset stale volume driver secrets
docker volume rm locket-<service> && docker compose up -d <service>
```

### Injection Method Selection (One-Line)

```
env vars only (no env_file) → compose provider
config files only → volume driver
env_file at parse time or complex init → locket-init sidecar
```

### Boot Sequence Check

```
1. Docker daemon         → systemctl is-active docker
2. socket-proxy          → docker ps --filter name=socket-proxy
3. godoxy                → docker ps --filter name=godoxy
4. crowdsec              → docker ps --filter name=crowdsec
5. Databases             → docker ps --filter name=mariadb --filter name=postgres
6. Stacks                → docker compose ls
```

---

## 8. Reference: Secret Inventory

> Placeholder section — populate with actual service-to-secret mappings
> as services are onboarded. This prevents "which UUID goes with which
> service" confusion during rotation.

| Service | Secret Name | BWS Key | Injection Method |
|---------|------------|---------|-----------------|
| _Add services here_ | _env var name_ | _BWS key_ | _compose provider / volume driver / locket-init_ |

**How to discover current secrets (runtime):**

```bash
# For compose provider services:
docker compose exec <service> env | sort

# For env_file services:
cat /run/<stack>-secrets/<service>/.env

# For config file services:
docker compose exec <service> cat /path/to/config.file
```

---

## Appendix: Sensitive Data Map

The following identifiers appear in the companion files and have been
**masked** in this runbook. When migrating content from the skill to the
runbook, ensure these are never exposed:

| Data Type | Actual Value (masked) | Used In |
|-----------|----------------------|---------|
| BWS Project ID | `$BWS_PROJECT_ID` | bws commands |
| OCIR Registry | `$OCIR_REGISTRY` | docker pull/push |
| BWS Token Path | `$HOME/.config/bwsh/token` | All mounts |
| Secret UUIDs | `$BWS_UUID` or `{{ UUID }}` | Compose files, templates |
| BWS Server URL | `https://vault.bitwarden.com` | bws config |
| PUID/PGID | `$PUID:$PGID` | Compose files |
| OCIR auth token | _not stored in files_ | Docker login |

**Never hardcode any of these in compose files, scripts, or documentation.**
All identifiers should be referenced via environment variables, BWS secret
lookups, or runtime discovery.
