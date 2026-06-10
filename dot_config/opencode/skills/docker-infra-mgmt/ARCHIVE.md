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
- No bwsh caching (token file mounted, not `~/.config/bwsh/` directory)