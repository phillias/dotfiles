# Archived Patterns & Research

> **Purpose**: Historical reference for deprecated locket integration patterns,
> alternative approaches, and research findings. These are NOT recommended for
> new deployments. The opinionated approach is documented in `SKILL.md`.
>
> Moved here to keep the active skill focused and opinionated.

---

## Table of Contents

1. [Variant A: Sidecar Init for Env Vars](#variant-a-sidecar-init-for-env-vars)
2. [Variant B: Sidecar Init for Config Files](#variant-b-sidecar-init-for-config-files)
3. [Variant C: Docker Volume Driver](#variant-c-docker-volume-driver)
4. [Variant D2: User Systemd Service (inject --mode watch)](#variant-d2-user-systemd-service-inject---mode-watch)
5. [Quick Decision Tree](#quick-decision-tree)
6. [Pre-Migration Assessment Checklist](#pre-migration-assessment-checklist)
7. [Migration Gotchas](#migration-gotchas)
8. [Locket Integration Research Summary](#locket-integration-research-summary)
9. [OCI Vault Secret Management](#oci-vault-secret-management)
10. [Template File Examples](#template-file-examples)
11. [Legacy Service State](#legacy-service-state)

---

## Variant A: Sidecar Init for Env Vars

For services that read secrets from `environment:` in their compose file, the
init container uses `locket exec` to resolve BWS UUID references and write a
rendered `.env` file to a host directory. The service container reads this file
via Docker Compose's `env_file:` directive — no entrypoint modification needed.

**How it works:**
1. Init container runs `locket exec` with `-e "VAR={{ BWS-UUID }}"` for each secret
2. `locket exec` fetches secrets from BWS, resolves references, runs `printenv`
3. Output is written to a host directory as a `.env` file
4. Service container uses `env_file: /host/path/to/rendered/.env`
5. Docker Compose reads the file at parse time and sets env vars on the container

**Tested and confirmed working** with newrelic: `locket exec` resolves
`{{ 9bbcbc09-8553-49fd-ae29-b461016c647d }}` → actual secret value, written to
host file, consumed by container via `env_file:`.

```yaml
  service-init:
    image: bws-init:latest
    container_name: service-init
    restart: "no"
    volumes:
      - ./rendered:/output:delegated
      - ~/.config/bwsh:/root/.config/bwsh:ro
    command:
      - /bin/bash
      - -c
      - |
        locket exec --provider bws --bws-token file:/root/.config/bwsh/token \
          -e "SECRET_KEY={{ BWS-SECRET-UUID }}" \
          -e "CONFIG_VALUE=literal" \
          -- sh -c "printenv" | grep -E "^(SECRET_|CONFIG_)" > /output/.env
    networks: []

  service:
    image: upstream:latest
    env_file:
      - ./rendered/.env      # Host path to locket-rendered file
    depends_on:
      service-init:
        condition: service_completed_successfully
    # NO entrypoint modification
    # NO binary mounts
    # Original lifecycle (tini/s6/bare binary) untouched
```

**`env_file` path:** Can be absolute host path (`/path/to/.env`) or relative to
compose directory. Docker Compose resolves at parse time on the host, NOT inside
the container. This is why the init container must write to a host-accessible path
(bind mount or delegated volume).

---

## Variant B: Sidecar Init for Config Files

For services that read secrets from config files (not env vars), the init
container runs `locket inject` with `--map` to render template files. The
rendered files are written to a **host directory** (not a named volume), and
the service container bind-mounts the specific rendered file at the path where
the application expects it.

**Why host directory, not named volume:** Docker Compose does not support
mounting individual files from a named volume (e.g., `volname/file:/path`).
The workaround is to render to a host directory via bind mount, then
bind-mount the specific file into the service container.

**Single config file — overlay pattern:**

When a service already bind-mounts a config directory (e.g., `./config:/config`),
mount the rendered file at the specific path within that directory:

```yaml
  service-init:
    image: bws-init:latest
    container_name: service-init
    restart: "no"
    command:
      - "locket"
      - "inject"
      - "--provider"
      - "bws"
      - "--bws-token"
      - "file:/root/.config/bwsh/token"
      - "--mode"
      - "one-shot"
      - "--map"
      - "/templates:/run/secrets"
      - "--user"
      - "1001:998"
      - "--file-mode"
      - "0640"
      - "--dir-mode"
      - "0755"
    volumes:
      - ./templates:/templates:ro
      - ./rendered:/run/secrets          # Host dir for rendered output
      - ~/.config/bwsh:/root/.config/bwsh:ro
    networks: []

  service:
    image: upstream:latest
    volumes:
      - ./config:/config                  # Original config dir (preserved)
      - ./rendered/config.ini:/app/config/config.ini:ro  # Overlay single file
    depends_on:
      service-init:
        condition: service_completed_successfully
```

**Tested reference (mylar3):** This pattern was tested end-to-end with mylar3.
The init container rendered `config.ini` with 3 BWS secrets (http_password,
comicvine_api, qbittorrent_password) to `./rendered/config.ini`. The service
container mounted this at `/config/mylar/config.ini:ro` while preserving the
existing `./config:/config` bind mount (database, logs, cache intact). Service
started successfully.

**Multiple config files (multi-map):**

```yaml
  # Option A: Multiple --map flags for specific files
  command:
    - "locket", "inject", "--provider", "bws",
    - "--bws-token", "file:/root/.config/bwsh/token",
    - "--mode", "one-shot",
    - "--map", "/templates/config.yaml:/app/config/config.yaml",
    - "--map", "/templates/database.toml:/app/config/database.toml"

  # Option B: Directory-level --map (all templates → output dir)
  command:
    - "locket", "inject", "--provider", "bws",
    - "--bws-token", "file:/root/.config/bwsh/token",
    - "--mode", "one-shot",
    - "--map", "/templates:/run/secrets"
  volumes:
    - ./templates:/templates:ro
    - ./rendered:/run/secrets
  # Then mount individual files:
  # - ./rendered/config.yaml:/app/config/config.yaml:ro
  # - ./rendered/database.toml:/app/config/database.toml:ro
```

**Mounting rendered config files — the overlay problem:**

When a service already bind-mounts a config directory (e.g., `./config:/config`),
you cannot simply mount a volume at the same path — it would hide the entire
directory including databases and other files. Instead, mount individual rendered
files at their specific paths within the existing config directory:

```yaml
  service:
    volumes:
      - ./config:/config                    # Original config dir (kept)
      - service-secrets/config.ini:/config/mylar/config.ini:ro  # Overlay single file
```

This preserves all existing files (database, logs, cache) while replacing only
the config file containing secrets.

---

## Variant C: Docker Volume Driver

Locket implements the Docker Volume Plugin API (`docker.volumedriver/1.0`) as a
managed plugin. When installed on the Docker host, it provides tmpfs-backed
volumes with secrets injected by the Docker daemon — no init containers, no
sidecars, no entrypoint changes.

**Installation** (one-time, host-level):
```bash
docker plugin install ghcr.io/bpbradley/locket:plugin \
  --alias locket \
  config.source=/etc/locket
```

**Compose usage**:
```yaml
services:
  service:
    image: myapp:latest
    volumes:
      - locket-volume:/run/secrets:ro

volumes:
  locket-volume:
    driver: locket
    driver_opts:
      provider: bws
      bws-token: file:/etc/locket/tokens/bws
      user: 1001:998
      secret.template: "{{ bws://vault/secret-uuid }}"
```

**Tradeoffs vs systemd approach:**
- **Advantages**: Zero per-service compose boilerplate, no init container overhead,
  secrets never touch disk (tmpfs), built-in watch/rotation
- **Limitations**: Secrets are files only (not env vars), requires `CAP_SYS_ADMIN`,
  requires one-time host-level plugin installation, Linux-only (mount syscalls),
  single-template-per-volume (multi-file services need multiple volumes),
  `env_file:` cannot work with the plugin (resolves on host, not inside container)
- **Superseded by**: Systemd system service with `RuntimeDirectory` tmpfs —
  same tmpfs benefit, plus multi-file support, env var support, and unified
  lifecycle management

---

## Variant D2: User Systemd Service (inject --mode watch)

For environments without root access, a user-level systemd service can run
`locket inject --mode watch` as a persistent file-only watcher. This does NOT
manage compose lifecycle — it only keeps rendered files in sync with templates.

```ini
# ~/.config/systemd/user/locket-<service>-watch.service
[Unit]
Description=Locket Template Watcher - <service>
After=docker.service

[Service]
Type=simple
ExecStart=/home/phillias/.local/bin/locket inject \
  --provider bws \
  --bws-token file:/home/phillias/.config/bwsh/token \
  --map /home/phillias/<stack>/<service>/templates:/home/phillias/<stack>/<service>/rendered \
  --file-mode 0640 \
  --mode watch
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

**Limitations:**
- Cannot use `--user` flag (non-root can't chown) — files land as the running user
- Template changes re-render files but do NOT restart compose
- Compose must be managed separately (detached mode)
- Requires `Linger=yes` for user services to start at boot

**Sequence:**
```bash
systemctl --user start locket-<service>-watch.service
docker compose -f compose.yaml up -d <service>
```

---

## Quick Decision Tree

```
Does the service read secrets from environment variables?
├── YES → Does it use `env_file:` already?
│   ├── YES → Variant A: Replace .env with locket exec rendering
│   │          Init container: locket exec -e "VAR={{ UUID }}" -- sh -c "printenv" > rendered/.env
│   │          Service: env_file: ./rendered/.env
│   └── NO  → Variant A: Replace `environment:` block with locket exec rendering
│              Init container: locket exec -e "VAR={{ UUID }}" -- sh -c "printenv" > rendered/.env
│              Service: env_file: ./rendered/.env (replaces environment: block)
└── NO → Does the service read secrets from config files?
    ├── YES → How many config files?
    │   ├── 1 file → Variant B: locket inject + single overlay mount
    │   │          Init: locket inject --map /templates:/run/secrets → ./rendered/
    │   │          Service: ./rendered/config.ini:/app/config/config.ini:ro
    │   └── N files → Variant B: locket inject + directory mount + N overlay mounts
    │              Init: locket inject --map /templates:/run/secrets → ./rendered/
    │              Service: ./rendered/file1.yaml:/app/config/file1.yaml:ro
    │                     ./rendered/file2.toml:/app/config/file2.toml:ro
    └── NO → No secrets to migrate (already clean)
```

---

## Pre-Migration Assessment Checklist

### Critical Guardrails

**NEVER run `docker compose down` on a shared stack.** The selfhost stack
(selfhost/compose.yml) hosts services from multiple compose projects (hermes,
crowdsec, godoxy, etc.) all attached to `selfhost_frontnet`. Running `compose down`
stops ALL services in that stack — not just the ones you're migrating.

**Correct approach for migrating services INTO a shared stack:**
1. Stop old containers with `docker stop <name>` — NOT `docker compose down`
2. Remove old containers with `docker rm <name>` — NOT `docker compose down`
3. Add new service definitions to the target compose file
4. Start new services with `docker compose up -d <new-services>` — this does NOT
   disturb existing running services

**NEVER purge original data until the user validates the new service is functional.**
- Do NOT delete or overwrite the original `.env` file until the user confirms
  the migrated service works
- Do NOT delete or overwrite the original `config.ini`/config files until validated
- Do NOT remove old containers until the new containers are healthy
- Do NOT remove old volumes until the new volumes are populated and tested
- **Do NOT delete or overwrite the original `compose.yml` / `compose.yaml` file.**
  Rename to `compose.yml.bak` or move to a backup directory.
- **Do NOT delete or overwrite the original `.env` file of external services.**

**ALWAYS test the rendering BEFORE modifying the compose file:**
```bash
# Test locket render to a temp directory first
docker run --rm \
  -v ~/.config/bwsh/token:/root/.config/bwsh/token:ro \
  -v ./templates:/templates:ro \
  -v ./rendered:/run/secrets \
  bws-init:latest \
  locket inject --provider bws --bws-token file:/root/.config/bwsh/token \
    --mode one-shot --map /templates:/run/secrets

# Verify the output BEFORE deploying
cat ./rendered/*
```

**ALWAYS validate compose config before deploying:**
```bash
docker compose config  # Must pass with zero errors
```

### Step 1: Identify the secret consumption pattern

```bash
# Does the service use env_file?
grep 'env_file:' /path/to/compose.yml

# Does the service use environment: with ${VAR} references?
grep -A50 'environment:' /path/to/compose.yml | grep '\${'

# Does the service have config files with secrets?
find /path/to/service/config -type f \( -name "*.ini" -o -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.toml" -o -name "*.conf" \) -exec grep -l -iE 'password|secret|token|api_key|apikey|private_key|credential' {} \;
```

- [ ] **Env vars only** → locket exec + env_file
- [ ] **Config files with secrets** → locket inject + bind-mount
- [ ] **Both env vars AND config files** → Both patterns combined
- [ ] **Already uses env_file with hardcoded secrets** → Replace .env with locket exec rendering

### Step 2: Map the config file layout

```bash
# List all config files and their paths relative to the config directory
find /path/to/service/config -type f ! -name "*.db" ! -name "*.sqlite*" ! -path "*/cache/*" ! -path "*/logs/*" ! -name "*.log" | sort

# Check which config files are in bind-mounted directories vs named volumes
grep -A5 'volumes:' /path/to/compose.yml | grep -E '^\s+-.*:.*:'
```

Key questions:
- [ ] Is the config directory a **bind mount** (host path) or **named volume**?
- [ ] How many config files need secret injection?
- [ ] Do config files share a directory with databases or other persistent data?
  - Yes → MUST use overlay mounting (don't replace the whole directory)
  - No → can replace the entire config volume

### Step 3: Check for conflicts

- [ ] **Does the service already use `env_file:`?** If yes, the rendered `.env`
  replaces it. Ensure all non-secret vars from the original `.env` are included.
- [ ] **Does the service use `environment:` with `${VAR}` references?** If yes,
  these resolve from the host's `.env` at compose-parse time. After migration,
  they'll come from the locket-rendered file instead.
- [ ] **Are secrets hardcoded in the compose `environment:` block?** (e.g.,
  `TOKEN=abc123`). These must be extracted to BWS FIRST before migration.
- [ ] **Does the service have a custom entrypoint script?** (check
  `docker inspect <image> --format '{{json .Config.Entrypoint}}'`).

### Step 4: Plan the template files

For **env-var services**: No template files needed. The systemd service uses
`locket exec -e "VAR={{ UUID }}"` for each secret and writes the output to a
`.env` file. Non-secret config vars are written as literals:
`-e "CONFIG_VAR=literal_value"`.

For **config-file services**: For each config file requiring secrets:
1. Copy the original config to `templates/<filename>` (same filename as original)
2. Replace each secret value with `{{ BWS-SECRET-UUID }}`
3. Keep all non-secret config as literals
4. Verify the template filename matches the expected output filename exactly

```bash
# Create template from original
cp /path/to/service/config/app.ini /path/to/service/templates/app.ini

# Replace secrets with UUID references
sed -i 's/^password = .*/password = {{ BWS-SECRET-UUID }}/' /path/to/service/templates/app.ini
```

### Step 5: Test the rendering BEFORE deploying

For **env vars:**
```bash
mkdir -p /path/to/service/rendered

docker run --rm \
  -v ~/.config/bwsh/token:/root/.config/bwsh/token:ro \
  -v /path/to/service/rendered:/output \
  bws-init:latest \
  /bin/bash -c 'locket exec --provider bws --bws-token file:/root/.config/bwsh/token \
    -e "SECRET_KEY={{ BWS-SECRET-UUID }}" \
    -e "CONFIG_VAR=literal" \
    -- sh -c "printenv" | grep -E "^(SECRET_|CONFIG_)" > /output/.env'

cat /path/to/service/rendered/.env
```

For **config files:**
```bash
mkdir -p /path/to/service/rendered

docker run --rm \
  -v ~/.config/bwsh/token:/root/.config/bwsh/token:ro \
  -v /path/to/service/templates:/templates:ro \
  -v /path/to/service/rendered:/run/secrets \
  bws-init:latest \
  locket inject --provider bws \
    --bws-token file:/root/.config/bwsh/token \
    --mode one-shot \
    --map /templates:/run/secrets

cat /path/to/service/rendered/app.ini
```

### Step 6: Validate the compose config

```bash
# After writing the compose changes, validate BEFORE deploying
docker compose config

# Check for common errors:
# - "refers to undefined volume" → tried to mount a file from a named volume
# - YAML indentation errors → command array items must each start with "- "
# - Missing depends_on → service might start before init container finishes
```

---

## Migration Gotchas

1. **Named volume file mounting fails in Docker Compose.**
   `volname/file.ini:/path/file.ini:ro` → error "refers to undefined volume".
   Docker volumes mount as whole units, not individual files. **Fix:** Use a host
   directory (`./rendered`) bind-mounted into the init container, then bind-mount
   the specific file from the host directory into the service container.

2. **Template filename = output filename.** `locket inject` preserves source
   filenames. If the app expects `config.ini`, the template must be named
   `config.ini` — NOT `config.ini.template`. Plan accordingly.

3. **Overlay mounting preserves existing files.** When a service bind-mounts a
   config directory containing a database + config file, mounting a single
   rendered file at a sub-path (e.g., `./rendered/config.ini:/config/mylar/config.ini:ro`)
   preserves all other files (database, logs, cache) while replacing only the
   config file.

4. **Template syntax is `{{ UUID }}` — NOT `{{ .Secrets.UUID }}`.** Locket's BWS
   provider parses references as bare UUIDs via `Uuid::parse_str`. The `.Secrets.`
   prefix is NOT part of locket's template syntax. Confirmed by source code
   (`src/provider/references/bws.rs`) and live testing.

5. **`locket inject` writes files owned by root.** The init container runs as root
   and the rendered files are owned by root. Use `--user 1001:998` to match the
   service's PUID/PGID, or ensure the service user has read permissions.
   For read-only mounts, `0600` with matching UID/GID works; for services that
   need to write config at runtime, use `0644` or match the service user.

6. **Init container must complete before service starts.** Use
   `depends_on: service-init: condition: service_completed_successfully` to
   ensure secrets are rendered before the service container starts. Without this,
   the service may start with an empty or stale config file.

7. **Do not overwrite a service's compose file before stopping its containers.**
   Overwriting `pocketid/compose.yml` with reference-only content while the container
   is still running causes `docker compose down` to fail ("empty compose file"), leaving
   the old container orphaned on the shared network. **Fix:** Always stop containers
   with `docker stop <name>` first, then modify or remove the compose file.

8. **Migrating a service to a shared stack requires network re-attachment.**
   When moving a service from its own compose file to a shared stack (e.g., selfhost),
   the container must be on the shared network (e.g., `selfhost_frontnet`). Old
   containers on their original network won't be routable via the shared proxy.
   After migration, verify with `docker network inspect selfhost_frontnet` that
   the new container is attached.

9. **User systemd service cannot use `--user` flag for file ownership.**
   Non-root users cannot chown files. The `--user 1001:998` flag in `locket inject`
   or `locket exec` requires root. For user-level systemd services, omit `--user`
   and accept files owned by the running user. Docker bind-mounts work regardless
   of file ownership.

10. **Docker creates directories for missing bind-mount targets.**
    When using single-file bind mounts (`./rendered/config.json:/app/config.json:ro`),
    if the source file doesn't exist at `docker compose up` time, Docker creates it
    as a DIRECTORY. This breaks both locket rendering and container startup.
    **Fix:** Always run `locket inject` (one-shot) BEFORE `docker compose up` when
    using the file-first approach.

11. **`locket exec --watch` does NOT restart child on template changes.**
    In exec mode, `--watch` monitors `.env` changes for child restart. Template
    file changes ARE detected and trigger re-render (files updated on disk), but
    the child process (docker compose) is NOT restarted. For compose restart on
    template change, you must either:
    - Change `.env` (triggers locket's built-in restart)
    - Restart the systemd service: `systemctl restart locket-<service>`

12. **`locket exec --watch` child must run foreground, NOT detached.**
    `docker compose up -d` exits immediately, causing locket's watch loop to
    lose its child and terminate. Use `docker compose up` (foreground) so
    locket's child stays alive. locket monitors the child's PID — if the child
    exits, locket exits.

---

## Locket Integration Research Summary

Extensive research was conducted to evaluate alternative integration methods.
Key findings:

1. **`locket exec` cannot wrap running containers.** It is a process supervisor
   (fork+exec via `tokio::process::Command::spawn()`), not an init system. It
   spawns child processes with injected env vars but cannot attach to an
   already-running PID 1. Using it as an entrypoint wrapper would break
   s6-overlay (datadog — full init system managing 8+ services), tini subreaping
   (newrelic), and shell entrypoints that do user switching (pocket-id, grimmory).

2. **`locket exec` from host via `docker exec` doesn't work.** `docker exec -e`
   sets env vars for the exec'd process only, not for the running PID 1. The
   env vars don't persist after the exec process exits.

3. **Direct binary mounting into service containers was rejected.** Mounting
   `bws`, `bwsh`, and `locket` binaries from the host into service containers
   requires 3 volume mounts + entrypoint override per service, and `bwsh` needs
   bash which most Alpine-based service containers don't have.

4. **The sidecar init container + env_file pattern was selected as the standard**
   because it respects upstream service immutability (no Dockerfile/entrypoint
   changes), works with all init systems uniformly, and uses locket natively.
   (Note: now superseded by the systemd system service approach.)

5. **`env_file` with host path works.** Docker Compose `env_file:` can reference
   an absolute host path. The init container writes rendered secrets to a
   host-accessible directory, and the service container reads them via
   `env_file:`. Tested and confirmed end-to-end.

6. **Multi-file config injection works via multiple `--map` flags.** Each config
   file gets its own `--map source:dest` entry, or all templates can be in a
   single directory mapped to a single output directory.

7. **Locket inject template syntax is `{{ UUID }}` — NOT `{{ .Secrets.UUID }}`.**
   Discovered through source code analysis and live testing. The locket BWS provider
   parses references as bare UUIDs (`Uuid::parse_str`). Both `locket exec -e` and
   `locket inject` use the same `{{ UUID }}` format. The `.Secrets.` prefix is NOT
   part of locket's template syntax. Confirmed by:
   - Reading `src/provider/references/bws.rs` — `BwsReference(Uuid)` with `FromStr`
     parsing via `Uuid::parse_str(s)`
   - Reading test fixtures in `docker/tests/sidecar/secrets/bws/` — all use `{{ UUID }}`
   - Live testing with `locket inject --map /templates:/run/secrets` rendering
     `{{ fc11c903-... }}` → actual secret values in INI, YAML, and TOML files
   - Live testing with `locket exec -e "VAR={{ UUID }}"` resolving to actual values

8. **Volume plugin tested and confirmed working.** The locket Docker volume plugin
   (`ghcr.io/bpbradley/locket:plugin`) was installed and tested end-to-end with
   BWS secrets. Inline test secrets and BWS UUID references both resolve correctly
   through the plugin. All 7 decypharr secrets (API key, rclone password, Prowlarr
   token, Hydra2 token, Discord URL, auth password, auth API token) were verified
   resolved. The plugin requires `config.source` set to the BWS token directory
   at install time. Tested on the pirate stack.

9. **`locket compose` NOT available in current binaries.** The compose provider
   feature exists in locket's source code behind a `#[cfg(feature = "compose")]`
   gate as part of the `full` feature set, but no prebuilt binary or Docker image
   includes it. All published images (`ghcr.io/bpbradley/locket:latest`, `:bws`,
   `:op`, `:connect`, `:infisical`, `:aio`, `:plugin`) are compiled without the
   compose feature. Using the compose provider requires building locket from
   source with `--features compose` (or using default features, which include
   the `full` set covering all features).

10. **Volume plugin limitation: single-template-per-volume.** The volume plugin's
    `secret.template` driver option creates exactly ONE file per volume — you map
    one template string to one file at the mount point. This means:
    - **Multi-file configs require multiple volumes.** A service with 2 JSON config
      files (like decypharr's `config.json` + `auth.json` needing 7 BWS secrets)
      would need 2+ separate locket volumes, each with its own `secret.template`.
    - **`env_file` cannot work with the volume plugin.** Docker Compose resolves
      `env_file:` paths on the host at compose parse time, not inside the container.
      The volume plugin creates secrets at container-internal paths (tmpfs) that
      don't exist on the host, so `env_file:` can never find them.
    - **The volume plugin excels at single-file secrets.** For services that expect
      a single secret file (e.g., `/run/secrets/api_key`), the plugin provides
      zero-compose-boilerplate injection with tmpfs security and built-in rotation.

---

## OCI Vault Secret Management

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

Prefer the bws-init/locket pattern over OCI CLI vault-init for all new
services. The locket pattern is simpler, faster, and centralized in Bitwarden SM.

---

## Template File Examples

`config.ini`:
```ini
[General]
http_password = {{ fc11c903-5a32-4421-9e61-b46200cf156e }}
api_key = {{ 60e7b55c-32c3-46d6-91a9-b46200cf15b7 }}
literal_config_value = stays-as-is
```

`config.yaml`:
```yaml
database:
  password: {{ d544c78f-1439-481f-8b13-b46200cf160f }}
  username: {{ a1b2c3d4-e5f6-7890-abcd-ef1234567890 }}
api:
  key: {{ 12345678-1234-1234-1234-123456789abc }}
```

`database.toml`:
```toml
[connection]
password = "{{ d544c78f-1439-481f-8b13-b46200cf160f }}"
user = "{{ a1b2c3d4-e5f6-7890-abcd-ef1234567890 }}"
```

---

## Legacy Service State

### Services already using bws-init (to be migrated to systemd locket)

| Service | Stack | Current Pattern |
|---------|-------|----------------|
| newrelic | newrelic | bws-init + secrets-entrypoint.sh (entrypoint override) |
| llpoa | llpoa | bws-init + secrets-entrypoint.sh (entrypoint override) |

### Services with hardcoded secrets in compose (extract to BWS first)

| Service | Stack | Hardcoded Secret |
|---------|-------|-----------------|
| dockhand-hawser | dockhand-hawser | TOKEN |
| tinyauth | selfhost | TINYAUTH_AUTH_USERS (bcrypt hash) |

### Services with no secrets (no action needed)

socket-proxy, myspeed, cloudbeaver, redis/vallib, mylar3 (env vars only),
opencode-telegram-bot (volume-mounted .env), hermes (host-directory secrets)

---

## All Locket Deployment Methods

| Method | Invocation | Process Role | Env Vars | Config Files | Template Watch | Auto-Restart | Compose Lifecycle |
|---|---|---|---|---|---|---|---|
| **`inject` (one-shot)** | `locket inject --map src:dst` | Standalone, exits after render | ❌ | ✅ Resolve & write files | ❌ | ❌ | ❌ |
| **`inject --mode watch`** | `locket inject --mode watch --map src:dst` | Persistent file watcher | ❌ | ✅ Re-render on change | ✅ File-only | ❌ No process mgmt | ❌ |
| **`exec` (one-shot)** | `locket exec -e "VAR={{ uuid }}" -- <cmd>` | Spawns child, waits, exits | ✅ Resolve & pass to child | ❌ | ❌ | ❌ Single run | ❌ |
| **`exec --watch`** | `locket exec --watch true ... -- docker compose up <svc>` | Persistent orchestrator | ✅ Resolve & pass to child | ✅ Via `--map` | ✅ Templates + `.env` | ✅ On `.env` change (SIGTERM + restart) | ✅ Manages compose as child |
| **`compose up`** | Docker CLI plugin, called by `docker compose` | One-shot plugin call | ✅ Inject via `ComposeMsg::set_env()` | ❌ | ❌ | ❌ | ❌ Called by compose |
| **`compose down`** | Docker CLI plugin | No-op | ❌ | ❌ | ❌ | ❌ | ❌ |
| **`healthcheck`** | `locket healthcheck` | One-shot check | ❌ | ❌ | ❌ | ❌ | ❌ |
| **`volume` plugin** | Docker volume driver | Persistent tmpfs | ❌ | ✅ Single file only | ✅ Built-in rotation | ✅ Plugin-managed | ❌ |

---

## Systemd System Service (exec --watch)

This was the previous "opinionated" approach before being superseded by the
single sidecar pattern. The systemd approach conflicted with Docker's lifecycle
management — `docker compose down` caused locket to exit cleanly (status 0),
leaving the service permanently down until `systemctl start`.

**System unit template (rejected):**

```ini
[Unit]
Description=Locket Secrets - <service>
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=phillias
ExecStart=/home/phillias/.local/bin/locket exec \
  --provider bws \
  --bws-token file:/home/phillias/.config/bwsh/token \
  --map /home/phillias/<stack>/<service>/templates:/run/locket-<service>/rendered \
  --file-mode 0640 \
  --watch true \
  -- docker compose -f /home/phillias/<stack>/compose.yml up <service>
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**User unit template (rejected):**

```ini
[Unit]
Description=Locket Template Watcher - <service>
After=docker.service

[Service]
Type=simple
ExecStart=/home/phillias/.local/bin/locket exec \
  --provider bws \
  --bws-token file:/home/phillias/.config/bwsh/token \
  --map /home/phillias/<stack>/<service>/templates:/home/phillias/<stack>/<service>/rendered \
  --file-mode 0640 \
  --watch true \
  -- docker compose -f /home/phillias/<stack>/compose.yaml up <service>
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
```

**Problems that led to rejection:**

1. **Dual lifecycle managers** — systemd and Docker Compose both managing the
   same service. `docker compose down` → locket exits with status 0 → systemd
   `Restart=on-failure` does NOT trigger → service stays down permanently.
2. **Signal forwarding complexity** — locket must forward SIGTERM/SIGINT/SIGHUP
   to the docker compose process group. Any breakage in this chain orphans
   containers.
3. **Undocumented behavior** — critical interactions (child exit → locket exit
   → systemd restart decision) are only discoverable by reading Rust source.
4. **Template watching was unwanted** — `--watch` caused locket to monitor
   templates for changes and re-render, but auto-re-rendering without service
   restart produces stale configs. Services like godoxy crash on config changes.

---

## Compose Provider

The `locket compose` subcommand implements the Docker Compose provider plugin
API. When invoked by `docker compose`, it resolves BWS secrets and injects them
as environment variables into the service environment via `ComposeMsg::set_env()`.

**Availability:** NOT available in any published binary. The feature is gated
behind `#[cfg(feature = "compose")]` which is included in `default = ["full"]`,
but no prebuilt release includes it. Requires building from source at
`/tmp/locket/` with default features.

**Why it doesn't replace the sidecar:**
- One-shot only — no watching, no persistence, no lifecycle management
- Env vars only — cannot inject config files
- Docker Compose is the lifecycle manager, not locket
- Provides no benefit over the single sidecar pattern

---

## Per-Service Sidecar (Legacy Pattern)

The previous approach had one init container per service:

```yaml
  decypharr-init:
    image: bws-init:latest
    container_name: decypharr-init
    restart: "no"
    volumes:
      - ./decypharr/templates:/templates:ro
      - ./decypharr/rendered:/run/secrets
      - /home/phillias/.config/bwsh/token:/bws-token:ro
    command: >
      locket inject --provider bws --bws-token file:/bws-token
      --mode one-shot --map /templates:/run/secrets
      --user ${PUID}:${PGID} --file-mode 0640

  decypharr:
    depends_on:
      decypharr-init:
        condition: service_completed_successfully
```

**Problems:**
- N init containers for N services instead of 1
- N BWS token mounts instead of 1
- Templates scattered across service directories instead of centralized
- Rendered files written to disk instead of tmpfs
- No bwsh caching (token file mounted, not `~/.config/bwsh/` directory)---
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

Authoritative guide for managing the Docker Compose infrastructure at
`$HOME/docker/`. This covers patterns and practices shared across
**all** stacks — secret injection (ordered by preference: compose provider
for env vars, volume driver for config files, locket-init sidecar as
fallback only), Godoxy reverse proxy, socket-proxy, OCI Vault integration,
OCIR registry, restic backup/restore architecture, and Bitwarden SM
administration.

For **pirate-specific** service management (ARRs, Stremio, VPN proxies,
ebooks/audiobooks), see the `pirate` skill.

---

## 1. Prerequisites & Initial Setup

Before any stack can use the compose provider for secret injection, three
components must be built and installed. None come pre-packaged — they must
be compiled from source.

### Go Toolchain

Both `locket` and the patched `docker-compose` are Go projects. Install Go
1.24+ for local builds:

```bash
# Install from golang.org or via system package
go version  # → go version go1.24.X linux/amd64
```

The locket-compose Dockerfile (see §1.3) fetches Go inside the build container
so you don't need Go installed on the host just to rebuild compose — but you
**do** need Go on the host to rebuild locket (or use the locket-init Dockerfile,
which has its own builder stage).

### locket Binary

The `locket` CLI must be compiled with the `compose` feature to act as a
Docker Compose provider. It lives at `~/.local/bin/locket`.

**Build it:**

```bash
# Clone and build with all provider features
git clone --depth 1 --branch v0.17.3 \
    https://github.com/softprops/locket.git /tmp/locket
cd /tmp/locket
go build -o ~/.local/bin/locket \
    -ldflags="-s -w" \
    --features compose,bws,exec
```

Alternatively, the `locket-init:latest` Dockerfile at
`$HOME/docker/locket-init/Dockerfile` has a multi-stage builder pattern
that can be adapted to produce just the binary.

**Install the symlink so Compose discovers it as a provider:**

```bash
# Required: enables `provider.type: locket` in compose.yaml
ln -sf ~/.local/bin/locket ~/.docker/cli-plugins/docker-locket
```

Verify:
```bash
locket compose --help  # Must list compose subcommand
docker info | grep -i locket
```

### docker-compose CLI Plugin (with rawsetenv)

The stock Docker Compose CLI plugin **prefixes** all provider-injected env
vars with the provider service name (e.g. `MYSQL_ROOT_PASSWORD` becomes
`LOCKET_MYSQL_ROOT_PASSWORD`). PR #13742 adds a `rawsetenv` message type
that lets providers inject env vars **without** the prefix.

The patched binary is built from `$HOME/docker/locket-compose/`:

```bash
cd ~/docker/locket-compose
./build.sh
# → produces ./docker-compose (~55 MB, version v2.40.3-rawsetenv)

# Install it:
cp docker-compose ~/.docker/cli-plugins/docker-compose
```

The Dockerfile uses a multi-stage build that:
1. Clones `docker/compose` at `v2.40.3` (shallow, no repo in build context)
2. Fetches PR #13742 from GitHub and applies it
3. Builds with `-trimpath` and version `v2.40.3-rawsetenv`

**Rebuild after:**

```bash
docker compose version  # → v2.40.3-rawsetenv
```

> ⚠️ **Every `docker compose` upgrade from upstream will lose the patch.**
> Re-run `./build.sh` and reinstall `~/.docker/cli-plugins/docker-compose`
> after upgrading compose. This is a local patch to an unmerged PR.

### Provider Descriptor JSON

Docker Compose discovers compose providers via JSON descriptors in
`~/.docker/compose/providers/`. Create or verify:

```bash
mkdir -p ~/.docker/compose/providers/
```

File `~/.docker/compose/providers/locket.json`:

```json
{
  "description": "Materialize secrets from environment or templates",
  "up": {
    "parameters": [
      { "name": "provider", "type": "string", "enum": "bws" },
      { "name": "bws-token", "type": "string" },
      { "name": "env", "type": "array" },
      { "name": "env-file", "type": "string" }
    ]
  },
  "down": { "parameters": [] }
}
```

This declares what CLI flags locket accepts for `compose up`. Additional
parameters (`bws-api-url`, `bws-identity-url`, `log-level`) can be added
as needed.

### bws CLI & Bitwarden SM Token

The `bws` CLI at `/usr/local/bin/bws` (v2.1.0+) talks to Bitwarden Secrets
Manager. The machine token lives at `~/.config/bwsh/token` and is mounted
into init containers as `:ro`.

```bash
bws version
bws secret list \
  --project eb78eee6-0397-420e-8a31-b45f000d2625
```

### Verification Checklist

Before using the compose provider on any stack, verify all five components:

| # | Component | Check Command |
|---|-----------|---------------|
| 1 | locket binary | `locket compose --help` |
| 2 | Provider symlink | `ls -la ~/.docker/cli-plugins/docker-locket` |
| 3 | Patched compose | `docker compose version` shows `v2.40.3-rawsetenv` |
| 4 | Provider descriptor | `ls ~/.docker/compose/providers/locket.json` |
| 5 | bws + token | `bws secret list --project eb78eee6-0397-420e-8a31-b45f000d2625` |

---

## 2. Infrastructure Overview

### Stacks

| Directory | Compose File | Project | Purpose |
|-----------|-------------|---------|---------|
| `$HOME/docker/` (root) | `compose.yml` | `selfhost` | Core proxy, socket-proxy, CrowdSec, databases (MariaDB, PostgreSQL/MSSQL/Redis/libSQL/Turso), CloudBeaver |
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
- **OCIR registry**: `us-chicago-1.ocir.io/axh7zpa5qpqc/` — custom images (Linkwarden, Meilisearch)
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

## 3. Guiding Principles

These principles govern all secret injection decisions and migration work.
They must not be bypassed without explicit approval.

### Injection Hierarchy

1. **Compose Provider (env vars)** — Primary. Injects into container environment at
   orchestration time. Zero extra containers. Zero disk writes. Env vars in memory only.
2. **Volume Driver (config files)** — Primary for file-based secrets. Resolves at
   volume mount time. Zero init containers. Rendered to Docker volume (not host disk).
3. **locket-init Sidecar (fallback)** — Only after compose provider and volume driver
   are exhausted AND explicit approval is granted. Renders to host tmpfs.

### Env Vars Are Memory-Only

- Secrets injected via the compose provider exist only in the container's runtime
  environment. They are NEVER rendered to `.env` files on disk.
- For services needing `env_file:` at compose parse time, this is a known limitation
  of the compose provider. Document and escalate — do not silently fall back to
  file-based injection.

### No Upstream Modifications

- **No image rebuilds** — never modify a service's Dockerfile.
- **No entrypoint changes** — never override or wrap the container entrypoint.
- **No `command:` overrides** — never use compose `command:` to inject secrets.
- The consuming service must work with the env var names or config file paths as
  provided by the upstream image. If the compose provider delivers env vars with
  exact key names the service expects, no adaptation is needed.

### Operations Must Be Service-Scoped

- **Restrict all management operations** (`docker compose up`, `down`, `restart`,
  `stop`, `rm`) to the **specific service being acted on**, not the entire stack.
- **Never run `docker compose up -d` without service names.** This starts every
  service in the stack including critical path components (godoxy, pocketid,
  crowdsec) that should not be disrupted.
- **Never run `docker compose down`** on a shared stack — use `docker stop` /
  `docker rm` for individual containers.
- **Correct:** `docker compose up -d mariadb` or `docker compose restart mariadb`
- **Incorrect:** `docker compose up -d` (starts everything), `docker compose down`
- **Full-stack operations require explicit user approval** — describe which
  services will be affected and why a full-stack operation is necessary first.

### Validation Before Cleanup

- **Never delete** volumes, configs, `.env` files, or compose files until the
  migrated service is validated as functional.
- **Always copy with permissions preserved** before making changes:
  ```bash
  cp -a --preserve=mode,ownership,timestamps original.env original.env.bak
  cp -a --preserve=mode,ownership,timestamps config/ config.bak/
  ```
- **Defer all cleanup** until you confirm the service is running and healthy.
- **Test rendering before deploying:**
  ```bash
  docker compose config   # Must pass with zero errors
  ```

### Escalation Path

If the compose provider (for env vars) and volume driver (for config files) cannot
meet the requirement within these principles, document the specific constraint
conflict and present it for approval before proceeding to locket-init.

---

## 4. Compose Provider (Env Vars — Primary)

### Overview

The **compose provider** is the primary mechanism for injecting Bitwarden SM
secrets as environment variables into Docker Compose services. It integrates
directly with Docker Compose's provider service API (available since Compose
v2.36.0+) — no init containers, no tmpfs, no systemd sequencing.

The provider works by declaring a `provider.type: locket` service in
compose.yaml. When `docker compose up` runs, Compose discovers the `locket`
provider (via the `docker-locket` CLI plugin), invokes `locket compose up`,
which resolves `{{ UUID }}` secret references against Bitwarden SM and returns
them via JSON protocol on stdout. Compose then injects the resolved values as
environment variables into dependent services.

### How It Works

1. **Compose file declares** a service with `provider.type: locket` and
   `options.env` listing `KEY={{ UUID }}` entries — one per secret
2. **Docker Compose discovers** the provider by looking for a CLI plugin named
   `docker-locket` in `~/.docker/cli-plugins/` (defined in
   `docker/compose/pkg/compose/plugins.go` — `getPluginBinaryPath` checks CLI
   plugin dirs first, then falls back to PATH lookup)
3. **Compose invokes** `locket compose --project-name=<NAME> up --options...`
4. **locket resolves** each `{{ UUID }}` against Bitwarden SM via the bws
   provider
5. **locket emits** JSON line-delimited messages on stdout:
   - `{"type":"setenv","message":"KEY=value"}` — injects env var into dependent services
   - `{"type":"info","message":"..."}` — status updates
   - `{"type":"error","message":"..."}` — failure reporting
6. **Compose injects** resolved env vars into services that `depends_on: locket`

The env var name is exactly the key you specify in the `env` list — locket emits **no prefix** of its own. For example, `env: ["DATABASE_PASSWORD={{ uuid }}"]` causes locket to emit `DATABASE_PASSWORD=<resolved-value>`. The key name is passed through as-is.

> **⚠️ Docker Compose prefix constraint (stock):** Stock Docker Compose **prefixes** all provider-injected env vars with the provider service name converted to SCREAMING_SNAKE_CASE. For a provider service named `locket`, an env var `MYSQL_ROOT_PASSWORD` arrives in the container as `LOCKET_MYSQL_ROOT_PASSWORD`. This is Compose's behavior, not locket's.
>
> **Fix — rawsetenv (patched compose):** PR #13742 (applied in `$HOME/docker/locket-compose/`, see §1.3) adds a `rawsetenv` message type. Providers emit `{"type":"rawsetenv","message":"KEY=val"}` and Compose injects it **without any prefix**. The patched compose binary is required for this to work — stock compose ignores the `rawsetenv` field.
>
> **Legacy workaround (stock compose only):** The dependent service can expose the unprefixed name by referencing the prefixed value in its `environment:` block, but this must be coordinated — the provider env var `MYSQL_PASSWORD` becomes `LOCKET_MYSQL_PASSWORD` in the container, and the service would need `MYSQL_PASSWORD` exposed as well.
>
> **When the prefix is a problem and patched compose isn't available:** If the consuming service expects specific env var names and cannot reference the prefixed form, the compose provider may not be suitable for that service. Fall back to `env_file:` from a locket-init sidecar (see §6). This constraint is documented as a finding: Docker Compose providers namespace env vars by service name, which breaks services that expect exact env var names without prefix.

### When to Use

| Scenario | Recommendation |
|----------|---------------|
| Services need env vars from Bitwarden SM | **Use compose provider** — no extra containers, no tmpfs |
| Services need config files from templates | Use volume driver (Section 5) |
| Complex init or env_file at parse time | Use locket-init sidecar (Section 6) — fallback only after confirmation |

**Choose the compose provider when:**
- Your service reads secrets from environment variables (the common case)
- You want zero extra containers (no init sidecar)
- You want secrets resolved at compose orchestration time, not at container startup
- You're using Docker Compose v2.36.0+

### Installation

Three components are required:

**1. Compose-enabled binary**

The `locket` CLI at `~/.local/bin/locket` must be compiled with the `compose`
feature. Verify:

```bash
$ locket compose --help
Docker Compose provider API

Usage: locket compose --project-name <PROJECT_NAME> <COMMAND>

Commands:
  up        Injects secrets into a Docker Compose service environment
  down      Handler for Docker Compose `down` (no-op)
  metadata  Handler for Docker Compose `metadata`
  help      Print this message or the help of the given subcommand(s)
```

If `compose` is not listed as a subcommand, rebuild with the `compose` feature
flag (see Build Instructions below).

**2. Provider descriptor JSON**

Docker Compose v2 discovers compose providers in
`~/.docker/compose/providers/*.json`. Create or verify the provider descriptor:

```bash
mkdir -p ~/.docker/compose/providers/
```

The file `~/.docker/compose/providers/locket.json` declares the available
parameters. Minimal content:

```json
{
  "description": "Materialize secrets from environment or templates",
  "up": {
    "parameters": [
      { "name": "provider", "type": "string", "enum": "bws" },
      { "name": "bws-token", "type": "string" }
    ]
  },
  "down": { "parameters": [] }
}
```

See the installed file for the full parameter set (including `bws-api-url`,
`bws-identity-url`, `env-file`, `env`, `log-level`, etc.).

**3. CLI plugin symlink**

Docker Compose's provider discovery (`getPluginBinaryPath` in
`docker/compose/pkg/compose/plugins.go`) resolves the provider type name by
first looking for a Docker CLI plugin `docker-<type>` in the CLI plugin
directories. Only one symlink is needed:

```bash
# Single symlink — enables `provider.type: locket` in compose.yaml
ln -sf ~/.local/bin/locket ~/.docker/cli-plugins/docker-locket

# Optional — also enables `docker locket` subcommand (same binary)
```

The `docker-compose-locket` naming convention (compose v1 style) is **not
required**. Docker Compose v2's provider API uses `docker-<type>` resolution.

**4. Verification**

```bash
# Check the compose provider descriptor exists
ls -la ~/.docker/compose/providers/locket.json

# Check the binary has compose support
~/.local/bin/locket compose --help

# Verify the CLI plugin is registered
docker info | grep locket
```

### Compose File Usage

```yaml
services:
  locket:
    provider:
      type: locket
      options:
        provider: bws
        bws-token: file:$HOME/.config/bwsh/token
        env:
          - "DATABASE_PASSWORD={{ 46042c9c-1234-5678-abcd-ef0123456789 }}"
          - "API_KEY={{ 2bb25ee5-5678-9abc-def0-123456789abc }}"

  myapp:
    image: myapp:latest
    depends_on:
      - locket
    # DATABASE_PASSWORD and API_KEY are injected directly
    # by the compose provider — no prefix, no transformation
```

The `env` list under `options` contains `KEY={{ UUID }}` entries. locket
resolves each UUID against the bws provider and emits `setenv` JSON messages.
Compose injects them with exactly the key name specified — **no prefix, no
transformation**. The consuming service sees `DATABASE_PASSWORD` and `API_KEY`
directly.

### Two-File Alternative (`.env.locket`)

For stacks where secrets are already defined in a `.env.locket` file (the
legacy `locket exec` pattern), the compose provider can re-use the same file
via the `env-file` option:

```yaml
services:
  locket:
    provider:
      type: locket
      options:
        provider: bws
        bws-token: file:$HOME/.config/bwsh/token
        env-file: $HOME/docker/stack/.env.locket

  myapp:
    depends_on:
      - locket
```

The `env-file` option points to a file with `KEY={{ UUID }}` lines — the same
format used by `locket exec -e`. This provides a migration path from
`locket exec` to the compose provider without reformatting secrets.

Note: `COMPOSE_PROVIDER` is **not a Docker environment variable** — it is a
Podman-specific variable (`PODMAN_COMPOSE_PROVIDER` in `containers/podman`).
Docker Compose activates the locket provider through `provider.type: locket`
in the compose file, not through environment variables. Do not set
`COMPOSE_PROVIDER=locket`.

### Systemd Service Pattern

For production deployments where the compose provider runs as a **persistent
service** (rather than one-shot via `docker compose up`), use a user systemd
unit:

```ini
[Unit]
Description=Locket compose provider — <project>
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$HOME/.local/bin/locket compose \
    --project-name <project> \
    --provider bws \
    --bws-token file:$HOME/.config/bwsh/token \
    up <service>
Restart=on-failure
RestartSec=5s
TimeoutStopSec=30s
WorkingDirectory=$HOME/<project-dir>

[Install]
WantedBy=default.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now <name>.service
```

The `locket compose up` command reads the compose file from the
`WorkingDirectory`, resolves `{{ UUID }}` secret references, and keeps the
service running in foreground. On failure, systemd restarts it. On stop,
locket forwards SIGTERM to the compose process.

### Limitations

| Capability | Compose Provider | Fallback |
|------------|:----------------:|----------|
| Environment variable injection | ✅ Primary | |
| Config file templating (YAML, INI, JSON) | ❌ | Use volume driver (Section 5) |
| `env_file:` at compose parse time | ❌ | Use locket-init sidecar (Section 6) |
| Multi-step init (download + inject + chown) | ❌ | Use locket-init sidecar (Section 6) |
| Auto-clear secrets on reboot (tmpfs) | ❌ | Use locket-init sidecar (Section 6) |

### Build Instructions

Two binaries must be built from source: `locket` (the provider) and
`docker-compose` (patched with rawsetenv support).

#### locket Binary

locket is compiled from source in a Docker container with host-mounted cargo
caches. The build environment is documented in
`selfhost/locket-builder/Dockerfile`:

```dockerfile
FROM rust:alpine AS builder
RUN apk add --no-cache musl-dev
WORKDIR /src/locket
RUN git clone --branch v0.17.3 --depth 1 \
    https://github.com/phillipsj/locket.git .
RUN cargo build --release --no-default-features \
    --features "bws,exec,compose"
```

The resulting binary is copied to `~/.local/bin/locket` on the host and also
baked into the `locket-init:latest` image.

For a quick local rebuild without Docker:

```bash
git clone --depth 1 --branch v0.17.3 \
    https://github.com/softprops/locket.git /tmp/locket
cd /tmp/locket
go build -o ~/.local/bin/locket \
    -ldflags="-s -w" \
    --features compose,bws,exec
```

#### docker-compose CLI Plugin (Patched with rawsetenv)

Stock Docker Compose prefixes all provider env vars with the service name.
PR #13742 adds a `rawsetenv` message type that bypasses the prefix. The
patched binary is built from `$HOME/docker/locket-compose/`:

```bash
cd ~/docker/locket-compose
./build.sh
cp docker-compose ~/.docker/cli-plugins/docker-compose
```

See §1.3 for full details. The Dockerfile at
`$HOME/docker/locket-compose/Dockerfile` does a multi-stage build:
1. Clones `docker/compose` at `v2.40.3`
2. Fetches and applies PR #13742 from GitHub
3. Builds with `-trimpath` and version `v2.40.3-rawsetenv`

> ⚠️ **Every compose upgrade loses the patch.** Rebuild and reinstall after
> updating compose. This is a local patch to an unmerged PR.

---

## 5. Locket Volume Driver (Config Files — Primary)

### Overview

The **volume driver** is the primary mechanism for injecting Bitwarden SM
secrets as **config file contents** (JSON, YAML, INI, env files, etc.) into
Docker Compose services. It is the config file counterpart to the compose
provider (Section 4) — use the compose provider for env vars, and the volume
driver for files.

locket provides a **Docker volume plugin** (`locket:latest`, image:
`ghcr.io/bpbradley/locket:plugin`) that resolves Bitwarden SM secrets as file
contents at **volume mount time**, before the consuming container starts. This
eliminates the need for init containers entirely — secrets are resolved
transparently when Docker attaches the volume.

The volume driver is a distinct binary from the locket compose/exec CLI. It runs
as a Docker plugin process (`docker plugin ls` → `locket:latest`), exposing a
Unix socket at `/run/docker/plugins/locket.sock`.

The plugin mounts the host `~/.config/bwsh/` directory to `/etc/locket/` inside
its container, giving it access to the BWS token and template files.

### Installation

The volume driver runs as a **Docker plugin** — a separate process from the
`locket` CLI, managed by the Docker daemon.

**Install from registry:**

```bash
# Install the plugin (enabled by default)  
docker plugin install locket:latest

# Verify it's running
docker plugin ls
# → locket:latest  enabled  0
```

The plugin image comes from `ghcr.io/bpbradley/locket:plugin` (automatically
pulled by `docker plugin install`). The plugin container mounts
`~/.config/bwsh/` → `/etc/locket/` for BWS token and template access. See
`docker plugin inspect locket:latest` for current mount config.

**Update the plugin:**

```bash
docker plugin disable locket:latest
docker plugin upgrade locket:latest
docker plugin enable locket:latest
```

The upgrade pulls the latest tag from the registry. There is no version pinning
for Docker plugins.

**Rebuild from source (for local modifications):**

locket's volume plugin is a separate binary compiled with the `volume` feature
flag. The plugin Dockerfile lives at `ghcr.io/bpbradley/locket:plugin` —
rebuild requires the locket monorepo. For most deployments, the registry
install is sufficient.

**Troubleshooting:**

- **`docker plugin ls` shows `locket:latest` with no row** → plugin not installed.
  Run `docker plugin install locket:latest`.
- **Volume creation hangs** → check the plugin logs:
  `journalctl -u docker.service --since "5 min ago" | grep locket`
- **Secrets not resolving** → verify `~/.config/bwsh/token` is valid and
  templates exist in `~/.config/bwsh/templates/<service>/`.

### When to Use

The volume driver is the **primary choice** for config file rendering. Use it
whenever a service needs config files from templates:

| Approach | Init Container | Host tmpfs | Config Files | Env Vars |
|----------|---------------|------------|--------------|----------|
| **Compose Provider** (Section 4) | Not needed | Not needed | Not supported | Compose-time resolution |
| **Volume Driver** (this section) | Not needed | Not needed | Volume mount at startup | Not supported |
| **locket-init** (Section 6) | Required | Required | `locket inject` | Via `.env` template |

**Choose the volume driver when (primary):**
- The service reads config from files on a known path
- You want the simplest compose file (no init container, no tmpfs)
- You don't need `env_file:` at compose parse time

**Fall back to locket-init (Section 6) when:**
- The service needs `env_file:` at compose parse time
- You need multi-step init (download + inject + chown)
- You want secrets to auto-clear on host reboot (tmpfs)

### Template Placement

Templates must live under `~/.config/bwsh/templates/` because the plugin maps
`~/.config/bwsh` → `/etc/locket`. The plugin reads them from
`/etc/locket/templates/`.

```
~/.config/bwsh/
├── locket.toml          # Plugin configuration
├── token                # BWS machine token (600)
├── cache/               # BWS cache directory
└── templates/           # Template files for the volume driver
    └── decypharr/
        ├── config.json  # locket {{ UUID }} template
        └── auth.json    # locket {{ UUID }} template
```

Templates use locket's `{{ UUID }}` syntax for Bitwarden SM references, exactly
as in the locket-init approach (Section 6).

### Compose Configuration

Define a named volume with `driver: locket:latest` and per-file `driver_opts`:

```yaml
volumes:
  locket-decypharr-multi:
    driver: locket:latest
    driver_opts:
      provider: bws
      bws-token: "file:/etc/locket/token"
      secret.config.json: "@/etc/locket/templates/decypharr/config.json"
      secret.auth.json: "@/etc/locket/templates/decypharr/auth.json"
```

**Key format for `driver_opts`:**
- `provider: bws` — Bitwarden SM is the secret provider
- `bws-token: "file:/etc/locket/token"` — Path to the BWS token inside the
  plugin container. On the host this is `~/.config/bwsh/token`, mapped to
  `/etc/locket/token` inside the plugin
- `secret.<filename>: "@<template-path>"` — Renders the template at
  `<template-path>` into a file named `<filename>` inside the volume
  - The `@` prefix means "read template from this path"
  - Without `@`, the value is an inline secret string
  - The `<filename>` becomes the filename inside the mounted volume

Mount in the consuming service:

```yaml
services:
  decypharr:
    volumes:
      - locket-decypharr-multi:/secrets:ro
```

The service sees files at `/secrets/config.json` and `/secrets/auth.json`.

### Multi-File Test Example

From `pirate/compose.locket-decypharr-test.yaml` (verified working):

```yaml
services:
  verify:
    image: alpine:latest
    container_name: decypharr-locket-test
    command:
      - sh
      - -c
      - |
        echo "=== Testing locket volume driver (multi-file) ==="
        echo ""
        echo "Contents of /secrets/:"
        ls -la /secrets/
        echo ""
        if [ -f /secrets/config.json ] && [ -f /secrets/auth.json ]; then
          echo "SUCCESS: Both config.json and auth.json exist"
          echo ""
          head -10 /secrets/config.json
          echo ""
          cat /secrets/auth.json
        else
          echo "FAILURE: Missing files"
          exit 1
        fi
    volumes:
      - locket-decypharr-multi:/secrets:ro
    restart: "no"

volumes:
  locket-decypharr-multi:
    driver: locket:latest
    driver_opts:
      provider: bws
      bws-token: "file:/etc/locket/token"
      secret.config.json: "@/etc/locket/templates/decypharr/config.json"
      secret.auth.json: "@/etc/locket/templates/decypharr/auth.json"
```

### Inline Secret Example

For simple cases where the value is known and no template is needed, pass it
directly (no `@` prefix):

```yaml
volumes:
  locket-single:
    driver: locket:latest
    driver_opts:
      provider: bws
      bws-token: "file:/etc/locket/token"
      secret.api-key: "sk-abc123..."
```

Creates a single file `/secrets/api-key` with content `sk-abc123...`.

### Limitations

1. **No `env_file:` support** — The volume resolves at mount time (container
   startup), but Docker Compose reads `env_file:` paths at parse time, before
   any container starts. Services needing compose-time env file resolution
   should use the locket-init approach (Section 6) with a `.env` template.

2. **Volume lifecycle** — Named volumes persist across `docker compose down`
   / `up`. To force re-resolution of secrets, remove the volume:
   `docker volume rm <name>`. The driver resolves secrets when a new volume
   is created, not on every container start.

3. **Shared namespace** — All templates share `~/.config/bwsh/templates/`.
   Use subdirectories for organization (e.g., `templates/decypharr/`),
   referenced by full path in `driver_opts`.

4. **CLI vs plugin** — The `locket` CLI at `~/.local/bin/locket` is compiled
   with `--features "bws,exec,compose"` and does NOT include the `volume`
   subcommand. Volume functionality lives only in the Docker plugin image.
   Troubleshoot volume state via `docker volume inspect` and
   `docker plugin inspect locket:latest`.

---

## 6. locket-init Sidecar Container (Fallback — Only After Confirmation)

### Overview

The **locket-init** sidecar container is the **fallback** approach for secret
injection. It should only be used when the compose provider (Section 4) and
volume driver (Section 5) cannot meet the requirement. Before reaching for
locket-init, confirm that neither the compose provider (for env vars) nor the
volume driver (for config files) can handle the use case.

locket-init uses the `locket-init:latest` image (built from
`$HOME/docker/locket-init/Dockerfile`) with a **standardized
entrypoint** (`/opt/init/locket-init.sh`) that handles both `inject` (config
file templates) and `exec` (env file + command) modes. All settings are
controlled via environment variables, eliminating inline bash `command:`
blocks.

The entrypoint manages the full lifecycle:
1. Creates output directory (cold boot — tmpfs doesn't persist)
2. Cleans Docker `create_host_path` directory placeholders
3. Checks idempotency — skips locket if all outputs already exist
4. Delegates to `locket inject` or `locket exec`

### When to Fall Back to locket-init

Refer to the decision table below and only use locket-init after verifying
that Sections 2 and 3 cannot handle the requirement:

| Requirement | Compose Provider (§2) | Volume Driver (§3) | locket-init (§4) |
|-------------|:---------------------:|:------------------:|:----------------:|
| Environment variable injection | ✅ **Primary** | ❌ | ✅ (fallback) |
| Config file templating | ❌ | ✅ **Primary** | ✅ (fallback) |
| `env_file:` at compose parse time | ❌ | ❌ | ✅ |
| Multi-step init (download + inject + chown) | ❌ | ❌ | ✅ |
| Auto-clear secrets on reboot (tmpfs) | ❌ | ❌ | ✅ |
| Runtime file writes from service (LinuxServer.io) | ❌ | ❌ | ✅ |
| Secrets shared across multiple output files | ✅ | ✅ | ✅ |
| Fresh-stack bootstrapping | ✅ | ✅ | ✅ |

**Only use locket-init when:**
1. **`env_file:` at compose parse time** — Docker Compose validates
   `env_file:` paths before any container starts. The volume driver resolves at
   mount time (too late) and the compose provider handles `environment:` block
   vars only (not `env_file:`). locket-init creates rendered files via an init
   container that completes before the main service starts.
2. **Multi-step initialization** — Some services need a sequence: download
   assets, inject secrets, adjust ownership.
3. **Secrets that auto-clear on reboot** — Host tmpfs (`/run/<stack>-secrets/`)
   is cleared on every reboot.
4. **Services that rewrite their own configs** — Common with LinuxServer.io
   images. The init renders fresh from canonical templates on each restart.
5. **Complex permission models** — locket supports `--user PUID:PGID`,
   `--file-mode`, and `--dir-mode` flags.

### Variant A: Standardized entrypoint — locket inject

The init container runs with environment variables instead of an inline command.
The entrypoint auto-detects `inject` mode when `TEMPLATES_DIR` and `OUTPUT_DIR`
are set. The output directory should be on **host tmpfs** (`/run/<stack>-secrets/`).

```yaml
  service-init:
    image: locket-init:latest
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

For **exec mode** (run a command with resolved env vars in a single-entrypoint pattern),
set `LOCKET_MODE=exec` along with any additional args as the `command:`. Note that
`LOCKET_ENV_FILE` is accepted for the output env file path but is **not functional**
in locket v0.17.3 — use `inject` mode with a `.env` template for env_file services instead.

> **Archived variants:** Variants B (key mapping + secrets-entrypoint), C (dual-source OCI Vault + BWSM), and D (single-source BWSM) have been removed. See `pirate/ARCHIVE/README.md` for the archived descriptions and reasoning.

**Key characteristics:**
- Image size: ~15-20MB (Alpine + locket + bws + entrypoint script)
- No OCI CLI (saves ~150MB)
- No bwsh wrapper — locket handles BWS auth directly
- No inline bash — all configuration via environment variables
- Template syntax: `{{ UUID }}` via locket inject (not `envsubst`)

**Current locket-init Dockerfile:**
```dockerfile
FROM alpine:3.19

RUN apk add --no-cache bash curl openssl

# locket 0.17.3 compiled with compose feature
COPY locket /usr/local/bin/locket

# bws CLI for Bitwarden SM secret management
COPY bws /usr/local/bin/bws

# bwsh — shell wrapper for bws (legacy init.ps1-style env injection — retained for compatibility)
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
| `exec` | `LOCKET_ENV_FILE` or `LOCKET_ENV` is set | Run command with resolved env vars via `locket exec`. ⚠️ `LOCKET_ENV_FILE` not functional in locket v0.17.3 — env_file services should use `inject` mode with `.env` template instead |

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
3. ⚠️ `LOCKET_ENV_FILE` is NOT functional in locket v0.17.3 — locket does not write env files in exec mode. Use `inject` mode with a `.env` template for services that require `env_file:` in compose.

### Common init container requirements

All init container variants require:
1. **BWS token directory**: `~/.config/bwsh:/root/.config/bwsh:ro` (includes both `token` and `cache/`)
2. **Template directory**: mapped into the init container as `:ro` (for inject mode)
3. **Output directory**: host tmpfs (`/run/<stack>-secrets/`) as `:rw`
4. **`restart: "no"`** — init runs once and exits
5. **`networks: []`** — init does not need network access (BWS token is pre-authenticated)

**For the init container:** mount
`~/.config/bwsh:/root/.config/bwsh:ro` which provides both the token file
and the bwsh cache directory. No separate token file mount is needed.
No named volumes — use host tmpfs instead.

### env_file Parse-Time Bootstrap Issue

When a service uses `env_file:` in docker-compose, Compose reads the file **at
parse time** on the host, **before any containers start**. This creates a
chicken-and-egg problem: the init container renders the env file into a tmpfs
volume, but Compose has already tried (and failed) to read it.

**Workaround:** The env file must exist on the host **before** `docker compose up`
runs. Two strategies:

**Strategy 1 — Template file path (preferred):** Create a `.env` template inside
the template directory and use `tmpfs` for the output. The env file gets rendered
by the init container. Compose reads the rendered output from tmpfs, which is
accessible at parse time because tmpfs bind-mount targets are created by Compose
v2.40+ as regular directories (via `create_host_path`).

```yaml
# In the service that needs env_file:
environment:
  # init container creates /rendered/.env from /templates/.env
  LOCKET_FILE_MODE: "0644"
volumes:
  - /run/<stack>-secrets/:/rendered:ro
env_file: /rendered/.env    # ← Compose reads this at parse time from host
```

However, **template filenames starting with `.` are hidden by shell glob expansion.**
The `locket-init.sh` script must use `shopt -s dotglob` to include them:

```bash
# locket-init.sh — ensures `.env` templates are detected
shopt -s nullglob dotglob
```

The script auto-detects this pattern: when a template filename starts with `.`,
the rendered output path is expected to be a hidden file.

**Strategy 2 — Host-side `.env` file (legacy):** For the **first deploy** of a
fresh stack where tmpfs doesn't exist yet, you must create a placeholder on the
host:

```bash
# Before first deploy — creates parse-time target
mkdir -p /run/<stack>-secrets/
touch /run/<stack>-secrets/.env
```

This ensures `docker compose up` can parse the `env_file:` path. The init container
then overwrites it with the rendered secrets. Subsequent restarts work without
this step because the tmpfs directory persists on the host filesystem between
stops.

**Why not `locket exec` with `LOCKET_ENV_FILE`:** locket v0.17.3 does not write
env files in exec mode — the flag is accepted but ignored. For env_file services,
always use `inject` mode with a `.env` template.

### Deprecated: OCI CLI vault-init

Older services (`opencode-telegram-bot/`, `linkwarden/`) use `vault-init.sh`
with the Oracle OCI CLI directly. These are being phased out — prefer the
compose provider (Section 4) for env vars or volume driver (Section 5) for
config files.

---

## 7. Godoxy Reverse Proxy

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

## 8. socket-proxy

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

## 9. OCI Vault Secret Management

### vault-inject.sh (Root-Level)

`$HOME/docker/vault-inject.sh` can inject OCI Vault secrets into the
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

Prefer the compose provider (Section 4) for env var injection, volume driver
(Section 5) for config file templating, or locket-init sidecar (Section 6) as a
fallback — over OCI CLI vault-init for all new services. The locket patterns are
simpler, faster, and centralized in Bitwarden SM.

---

## 10. OCIR Registry

### Custom Images

Custom images are hosted at `us-chicago-1.ocir.io/axh7zpa5qpqc/`:

| Image | Source | Used By |
|-------|--------|---------|
| `locket-init:latest` | `$HOME/docker/locket-init/Dockerfile` (local build, not pushed to OCIR) | All stacks |
| `primary-server/linkwarden:latest` | Linkwarden source | linkwarden/ |
| `primary-server/meilisearch:v1.12.8` | Meilisearch source | linkwarden/ |

The `locket-init` image is built locally. The build is documented in
`selfhost/locket-builder/Dockerfile` (see Section 4).

### Authentication

OCIR is accessed via OCI auth token stored in Docker config.
Do not commit credentials.

---

## 11. Restic Backup Architecture

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

## 12. Bitwarden SM Administration

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

## 13. Resource Limits & Compute Constraints

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

## 14. Networking

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

## 15. Volume Management

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

## 16. Logging

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

## 17. Health Checks & Dependencies

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

## 18. Security Hardening

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

## 19. Troubleshooting

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
