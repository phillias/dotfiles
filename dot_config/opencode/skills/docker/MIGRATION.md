# Migration Process

> **Purpose**: Step-by-step migration procedures for moving services from
> hardcoded secrets / `.env` files / sidecar init containers to the
> documented injection hierarchy: compose provider (env vars, preferred),
> volume driver (config files, preferred), locket-init sidecar (fallback).
> This is a process reference, not a pattern reference. Full pattern
> descriptions are in `SKILL.md`.

---

## Table of Contents

1. [Guiding Principles](#1-guiding-principles)
2. [Migration Safety Protocol](#2-migration-safety-protocol)
3. [Service Migration Catalog](#3-service-migration-catalog)
4. [Migration Walkthrough: Compose Provider](#4-migration-walkthrough-compose-provider)
5. [Migration Walkthrough: Volume Driver](#5-migration-walkthrough-volume-driver)
6. [Migration Walkthrough: locket-init Sidecar (Fallback)](#6-migration-walkthrough-locket-init-sidecar-fallback)
7. [Init Container Requirements](#7-init-container-requirements)

---

## 1. Guiding Principles

These principles apply to every migration. See `SKILL.md §2` for the full
set with rationale.

- **Injection hierarchy**: Compose Provider (env vars) → Volume Driver
  (config files) → locket-init (fallback — only after approval).
- **Env vars are memory-only**: Never render secrets to `.env` files on
  disk. The compose provider injects directly into container environment.
- **No upstream modifications**: No image rebuilds, no entrypoint
  changes, no `command:` overrides. The service must work with the env
  var names provided by the upstream image.
- **Exhaust primary patterns first**: Always try compose provider and
  volume driver before escalating. If neither works, document why and
  present for approval.

---

## 2. Migration Safety Protocol

**Copy before change. Validate before cleanup. Never delete without
confirmation.**

### Rules

1. **Backup everything first** — copy compose files, config dirs, and
   `.env` files with permissions preserved:
   ```bash
   cp -a --preserve=mode,ownership,timestamps compose.yml compose.yml.bak
   cp -a --preserve=mode,ownership,timestamps .env .env.bak
   cp -a --preserve=mode,ownership,timestamps config/ config.bak/
   ```
2. **Validate before removing anything** — do not delete backups or old
   volumes until the migrated service has been confirmed functional.
3. **Test rendering before deploying** — always run a dry config check:
   ```bash
   docker compose config   # Must pass with zero errors
   ```
4. **Individual container replacement** — use `docker stop` / `docker rm`
   for individual service containers. Never run `docker compose down` on
   a shared stack.
5. **Defer cleanup** — after validation, present a summary of what can
   be cleaned up (old `.env` files, unused volumes, backup dirs). Do not
   delete without explicit confirmation.

---

## 3. Service Migration Catalog

### Legend

| Pattern | Priority | When To Use |
|---------|----------|-------------|
| **Compose Provider** | 1st | Service accepts secrets via env vars only |
| **Volume Driver** | 1st | Service needs secrets written to a config file |
| **locket-init** | Last | Compose provider + volume driver both cannot work |

### Services using `environment:` — Candidate for Compose Provider

| Service | Stack | Env Vars | Recommended Pattern |
|---------|-------|----------|-------------------|
| mariadb | selfhost | MYSQL_ROOT_PASSWORD, DB_PASSWORD | **Compose Provider** |
| postgres | selfhost | PG_DB_PASSWORD | **Compose Provider** |
| mssql | selfhost | SA_PASSWORD | **Compose Provider** |
| libsql | selfhost | LIBSQL_JWT_KEY | **Compose Provider** |
| turso | selfhost | TURSO_JWT_KEY | **Compose Provider** |
| crowdsec | selfhost | HOSTIP (not secret) | n/a |
| grimmory | grimmory | DB_PASSWORD, DATABASE_URL | **Compose Provider** |
| datadog-agent | myastrology | DD_API_KEY | **Compose Provider** |
| datadog-agent | miaction | DD_API_KEY | **Compose Provider** |
| datadog-agent | llpoa | DD_API_KEY | **Compose Provider** |

### Services using `env_file:` — Candidate for Compose Provider

| Service | Stack | Secrets | Recommended Pattern |
|---------|-------|---------|-------------------|
| myastrology | myastrology | OPENROUTER_API_KEY, DD_API_KEY, NEW_RELIC_LICENSE_KEY | **Compose Provider** via `env` list |
| pocketid | pocketid | ENCRYPTION_KEY | **Compose Provider** via `env` list |
| miaction/app | miaction | DD_API_KEY, NEW_RELIC_LICENSE_KEY | **Compose Provider** via `env` list |

### Services with config files — Candidate for Volume Driver

| Service | Stack | Config Files | Recommended Pattern |
|---------|-------|-------------|-------------------|
| crowdsec | selfhost | 8 YAML files | **Volume Driver** (if supported) or **locket-init** |
| godoxy | selfhost | config.yml | **Volume Driver** (if supported) or **locket-init** |
| cloudbeaver | selfhost | .cloudbeaver.runtime.conf | **Volume Driver** (if supported) or **locket-init** |
| mylar3 | mylar3 | config.ini | **Volume Driver** (if supported) or **locket-init** |
| restic | selfhost | .restic-env | **Volume Driver** (if supported) or **locket-init** |

### Services already using locket-init (validated reference)

| Service | Stack | Template Files | Pattern |
|---------|-------|---------------|---------|
| decypharr | pirate | config.json, auth.json | locket-init (inject mode) |

---

## 4. Migration Walkthrough: Compose Provider

### Overview

The compose provider is the **primary mechanism** for injecting env var
secrets. It uses Docker Compose's provider service API (v2.36.0+) — no
init containers, no tmpfs mounts, no systemd sequencing.

### How It Works

1. A `locket` provider service is declared in `compose.yml` with
   `options.env` listing `KEY={{ UUID }}` entries.
2. Docker Compose invokes `locket compose up <service>` when the
   provider service's dependencies are ready.
3. `locket` resolves each UUID against Bitwarden SM (via `bws`), then
   emits `setenv` messages for each resolved key-value pair.
4. Docker Compose injects the env vars into dependent containers **with
   the exact key names specified** — no prefix, no transformation.

### Prerequisites

- Docker Compose v2.36.0 or later (`docker compose version`)
- BWS project created with all target secrets
- BWS token at `$HOME/.config/bwsh/token` (mode 600)
- locket binary in `PATH`

### Step 1: Identify env var secrets

```bash
# Find all environment variables in compose
grep -A50 'environment:' compose.yml | grep -E '\$\{|PASSWORD|SECRET|TOKEN|KEY|API'

# Find all env_file references
grep 'env_file:' compose.yml

# Check current .env for hardcoded secrets
grep -E 'PASSWORD|SECRET|TOKEN|KEY|API' .env
```

### Step 2: Extract secrets to BWS

For each hardcoded secret value, create a BWS secret:

```bash
bws secret create --note "service-name secret description" <secret-value>
# → returns UUID like "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
```

### Step 3: Add the locket provider service to compose

Add a `locket` service to the compose file with the `provider` extension:

```yaml
services:
  locket:
    provider:
      type: locket
      options:
        provider: bws
        bws-token: file:$HOME/.config/bwsh/token
        env:
          - "MYSQL_ROOT_PASSWORD={{ a1b2c3d4-e5f6-7890-abcd-ef1234567890 }}"
          - "DB_PASSWORD={{ 2bb25ee5-5678-9abc-def0-123456789abc }}"

  <service>:
    image: upstream:latest
    depends_on:
      locket:
        required: true
    # The env vars are injected by the compose provider. Note: Compose prefixes
    # them with LOCKET_ — verify expected names match before relying on them.
```

**Important notes:**
- The env var name is **exactly** the key string before `=`. No prefix.
- Use `depends_on: locket: { required: true }` to ensure provider runs
  before the consuming service.
- The `env` list supports multi-line with one `KEY={{ UUID }}` per entry.
- For secrets that don't need BWS resolution, use a literal value:
  `"NON_SECRET_VAR=some_value"`

**⚠️ Docker Compose prefix constraint:** Compose **prefixes** all
provider-injected env vars with the provider service name (converted to
SCREAMING_SNAKE_CASE). A provider service named `locket` emitting
`MYSQL_ROOT_PASSWORD` will arrive in the container as
`LOCKET_MYSQL_ROOT_PASSWORD`.

This means the compose provider is best suited for services where:
- The env var names are arbitrary and the service doesn't know/care about
  the exact name (uncommon)
- The secrets are already supplied via other means (`environment:` block
  with literal values, `env_file:` from init container) — the provider is
  used alongside for verification or debugging
- The service can be configured to read the `LOCKET_`-prefixed names

**If the service expects specific unprefixed env var names,** fall back to
`env_file:` from a locket-init sidecar (see §6).

### Step 4: Test rendering

```bash
docker compose config   # Must pass with zero errors
```

If the compose version or provider plugin is not available, upgrade:

```bash
# Check current version
docker compose version
# Upgrade via Docker Desktop or package manager if < v2.36.0
```

### Step 5: Deploy

```bash
# Start the service (provider runs automatically via compose)
docker compose up -d <service>

# Verify the provider ran
docker compose logs locket

# Verify env vars injected into the service
docker compose exec <service> env | grep -E 'PASSWORD|KEY'
```

### Step 6: Validate and Clean Up

```bash
# Validate the service is functional (service-specific checks)
docker compose ps
docker compose logs <service> --tail 20

# Once validated — and only after user confirms — remove old backups
# rm compose.yml.bak .env.bak
```

---

## 5. Migration Walkthrough: Volume Driver

### Overview

The **volume driver** is the primary mechanism for injecting secrets
that must be written to config files. It uses Docker volumes backed by
the `locket` volume plugin. When a container reads from a volume mount,
the driver resolves `{{ UUID }}` references in the file content against
Bitwarden SM — no init containers, no tmpfs.

### Prerequisites

- locket volume driver registered (`locket volume register` or
  `docker plugin install`)
- BWS project created with all target secrets
- BWS token at `$HOME/.config/bwsh/token` (mode 600)
- locket binary in `PATH`

### Step 1: Identify config file secrets

```bash
# Find config files with potential secrets
find /path/to/service/config -type f \( -name "*.ini" -o -name "*.yaml" \
  -o -name "*.yml" -o -name "*.json" -o -name "*.toml" -o -name "*.conf" \) \
  -exec grep -l -iE 'password|secret|token|api_key|apikey|private_key|credential' {} \;
```

### Step 2: Create template files with UUID references

```bash
# Create a templates directory for the service
mkdir -p ./templates/<service>

# Copy original config to template
cp --preserve=mode,ownership,timestamps config.json ./templates/<service>/

# Replace secret values with BWS UUID references
# Original:   "api_key": "abc123"
# Template:   "api_key": "{{ a1b2c3d4-e5f6-7890-abcd-ef1234567890 }}"
```

### Step 3: Create a locket-backed volume in compose

```yaml
volumes:
  <service>-secrets:
    driver: locket
    driver_opts:
      provider: bws
      bws-token: file:$HOME/.config/bwsh/token
      source: ./templates/<service>/

services:
  <service>:
    image: upstream:latest
    volumes:
      - <service>-secrets:/app/config:ro
    # The volume driver resolves {{ UUID }} references on read.
    # No init container, no depends_on.
```

### Step 4: Test and Deploy

```bash
# Test the compose config
docker compose config

# Deploy
docker compose up -d <service>

# Verify the volume is properly mounted and secrets resolved
docker compose exec <service> cat /app/config/config.json
```

### Step 5: Validate

Same validation procedure as compose provider (§4 step 6).

---

## 6. Migration Walkthrough: locket-init Sidecar (Fallback)

> **Use this pattern only when the compose provider (for env vars) and
> volume driver (for config files) have been exhausted and the constraint
> conflict has been presented for approval.**

### How It Works

locket-init is a sidecar container that:
1. Reads `{{ UUID }}` template files from a mounted templates directory
2. Resolves UUIDs against Bitwarden SM (via `bws`)
3. Renders the resolved files to a shared tmpfs volume
4. Exits — the consuming service reads from the tmpfs mount

### Prerequisites

- BWS project created with all secrets
- BWS token at `$HOME/.config/bwsh/token` (600 permissions)
- `$HOME/.config/bwsh/` directory exists (for bwsh caching)
- locket binary installed at `/usr/local/bin/locket` or
  `$HOME/.local/bin/locket`
- locket-init image built locally from
  `$HOME/docker/locket-init/Dockerfile`

### Step 1: Identify secrets

```bash
# Find all ${VAR} references in compose
grep -A50 'environment:' compose.yml | grep '\${'

# Find all env_file references
grep 'env_file:' compose.yml

# Check current .env for hardcoded secrets
cat .env | grep -E 'PASSWORD|SECRET|TOKEN|KEY|API'
```

### Step 2: Extract secrets to BWS

For each hardcoded secret value, create a BWS secret:

```bash
bws secret create --note "service-name secret description" <secret-value>
# → returns UUID like "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
```

### Step 3: Create the env file template

```bash
# Create an .env template under the centralized templates directory
mkdir -p ./templates/<service>
cat > ./templates/<service>/<service>.env << EOF
SECRET_VAR1={{ uuid-1 }}
SECRET_VAR2={{ uuid-2 }}
NON_SECRET_VAR=literal_value
EOF
```

### Step 4: Add the stack-level init to compose

```yaml
services:
  <stack>-init:
    image: locket-init:latest
    container_name: <stack>-init
    restart: "no"
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        chmod 750 /rendered
        exec locket inject --provider bws --bws-token file:/bws-token
          --mode one-shot --map /templates:/rendered
          --user ${PUID}:${PGID} --file-mode 0644 --dir-mode 750
    volumes:
      - ./templates:/templates:ro
      - /run/<stack>-secrets:/rendered
      - $HOME/.config/bwsh:/root/.config/bwsh:rw
    networks: []

  <service>:
    image: upstream:latest
    env_file: /run/<stack>-secrets/<service>/<service>.env
    depends_on:
      <stack>-init:
        condition: service_completed_successfully
    # Remove old environment: block
    # Remove old env_file: pointing to .env
```

### Step 5: Deploy

```bash
# Create the tmpfs directory
sudo mkdir -p /run/<stack>-secrets

# Start the stack
docker compose up -d

# Verify
docker compose logs <stack>-init
docker compose ps
```

---

## 7. Init Container Requirements

The init container pattern (used by locket-init) requires:

1. **BWS token**: mounted from `$HOME/.config/bwsh/token` (mode 600)
2. **BWS cache**: `$HOME/.config/bwsh/` mounted `:rw` for bwsh caching
3. **Templates**: `./templates/` directory mounted `:ro`
4. **Output**: host tmpfs at `/run/<stack>-secrets/` mounted for rendered
   output
5. **Entrypoint**: `["/bin/sh", "-c"]` with chmod + exec pattern
6. **`restart: "no"`** — init runs once and exits
