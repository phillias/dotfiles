# Pirate Stack – Migration & System-Specific Reference

> This file captures migration procedures and configuration unique to this
> **system** (host: `ubuntu`, base path: `~/docker/pirate/`).
> It is **not** part of the long-term runbook — it exists so that the
> runbook (`SKILL.md`) can stay portable and drift-resistant.
>
> If you are cloning these skills to a new machine, this file is the
> checklist of what needs manual reconfiguration.

---

## 1. Bind Mount → Named Volume Migration

### 1.1 General Pattern

See `docker` skill §2 for the cross-stack locket-init pattern. These are
the per-service steps when migrating a service from bind-mount config to
a named-volume + init-container setup:

1. Create template files in `./templates/<service>/`
2. Add `*-init` service and named volume in `compose.yaml`
3. Update the service to use the named volume instead of bind mount
4. Add to the volume export loop in `restic-backup.sh`
5. If the service uses SQLite, add a `docker cp` snippet to `db-backup.sh`
6. After validation: migrate old data from the bind mount path and remove
   the bind-mount declaration

### 1.2 Completed Migrations

| Service | Old Volume | New Volume | Date |
|---------|-----------|------------|------|
| prowlarr | `pirate_prowlarr_data` | `pirate_prowlarr-secrets` | — |
| nzbhydra2 | `pirate_nzbhydra2_data` | `pirate_nzbhydra2-secrets` | — |
| jackett | `pirate_jackett_data` | `pirate_jackett-secrets` | — |

### 1.3 Legacy Volume Cleanup

Stale volumes still present on disk are safe to remove only after
verifying the replacement `*-secrets` volumes contain all needed data:

```bash
docker run --rm -v pirate_prowlarr_data:/old:ro alpine ls -la /old
docker run --rm -v pirate_prowlarr-secrets:/new:ro alpine ls -la /new

# Only after verification:
docker volume rm pirate_prowlarr_data \
  pirate_nzbhydra2_data \
  pirate_jackett_data
```

---

## 2. OCI Vault Configuration

### 2.1 Overview

OCI Vault is used **only** by `aios` (AIostreams). All other pirate
services use the locket-init / bws-init pattern. This is a legacy choice
— aios predates the locket-init conversion and was never migrated.

**Do not attempt to convert aios to locket-init.**

### 2.2 OCI CLI Setup

OCI CLI authentication is required for vault operations. On this system:

- **Profile:** `DEFAULT`
- **Config:** `~/.oci/config`
- **Key:** `~/.oci/oci_api_key.pem`

The OCI CLI must be installed and authenticated for vault-init to work.
If `vault-init.sh` or the aios init container fails, check:

```bash
oci --version
oci iam region list  # quick connectivity test
```

### 2.3 OCI Vault Secrets

Secrets used by aios are stored in an OCI Vault. The vault OCID and
secret OCIDs are configured in the aios init script/environment. To
create or update a secret:

```bash
oci vault secret create-base64 \
  --vault-id <vault-ocid> \
  --secret-name <name> \
  --description "<description>" \
  --secret-content-content "$(echo -n '<value>' | base64 -w0)" \
  --secret-content-name "content" \
  --secret-content-stage "CURRENT" \
  --key-id <key-ocid>
```

### 2.4 vault-init.sh

The `vault-init.sh` script (referenced by the aios init container) reads
secrets from OCI Vault and renders them into `AIOS.env`. If the init
container fails:

1. **Check OCI CLI auth:** `oci iam region list`
2. **Check vault reachability:** verify vault OCID is correct
3. **Check secret OCIDs:** verify each referenced secret still exists
4. **Check permissions:** the OCI user/instance-principal needs
   `SECRET_READ` on the vault

### 2.5 Per-Service Secret Inventory

This table maps each service to its secret source and what secrets it
requires. Useful when re-provisioning or auditing.

| Service | Secret Method | Secrets Required |
|---------|--------------|------------------|
| aios | OCI vault-init | Real-Debrid / other provider API keys (`AIOS.env`) |
| decypharr | locket-init (bws) | EncFS password, API tokens (5 named volumes) |
| prowlarr | locket-init (bws) | API key, DB credentials, proxy config |
| jackett | locket-init (bws) | API key, indexer config |
| nzbhydra2 | locket-init (bws) | API key, proxy config |
| shelfmark | locket-init (bws) | Users DB, app config |
| grimmory | locket-init (bws) | DB password (`DATABASE_PASSWORD` in `.env`), app config |
| storyteller | locket-init (bws) | App config |
| proton | locket-init (bws) | VPN credentials (OpenVPN/WireGuard) |
| warp | locket-init (bws) | Warp license/team token |

---

## 3. System Paths & Conventions

These are specific to this host and should be updated when deploying to a
new machine.

| Item | Value |
|------|-------|
| Base path | `~/docker/pirate/` |
| User | `ubuntu` (UID 1000) |
| Docker group | `998` |
| Timezone | `America/New_York` |
| OCI config | `~/.oci/config` (profile `DEFAULT`) |
| Bitwarden session token | `~/.config/bwsh/token` |
| locket binary | Managed by bws-init containers |
| Restic credentials | `.restic-env` (600 perms, not in git) |

---

## 4. Scripts Reference

All scripts live in the pirate base directory.

| Script | Purpose | Invocation |
|--------|---------|-----------|
| `db-backup.sh` | Hot-copy SQLite DBs via `sqlite3 .backup` | `./db-backup.sh` |
| `restic-backup.sh` | Full backup pipeline (DB + volumes → restic → S3) | `./restic-backup.sh` (cron: `0 3 * * *`) |
| `restore.sh` | Restore from restic snapshots | `./restore.sh -a <app\|all> -t "<duration>"` |
| `vault-init.sh` | OCI Vault → `AIOS.env` (aios only) | Referenced by aios init container |

### Restic Retention Policy

```
keep_daily:   7
keep_weekly:  4
keep_monthly: 12
```
