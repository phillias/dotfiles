---
name: pirate-infra-mgmt
description: >
  **DEPRECATED** — This skill has been split into:
  1. `docker-infra-mgmt` — cross-stack patterns (bws-init/locket, Godoxy,
     socket-proxy, OCI Vault, restic backup, Bitwarden SM)
  2. `pirate-stack` — pirate-specific per-service management, profiles,
     proxy routing, backup scripts, troubleshooting
compatibility: opencode
metadata:
  status: deprecated
  replaced_by: docker-infra-mgmt, pirate-stack
---

# DEPRECATED

This skill has been split into two more focused skills:

**`docker-infra-mgmt`** — Cross-stack infrastructure management covering
the bws-init/locket secret injection pipeline, Godoxy reverse proxy,
socket-proxy, OCI Vault integration, OCIR registry conventions, the restic
backup/restore architecture, and Bitwarden SM administration. Use this when
working with any stack's infrastructure patterns.

**`pirate-stack`** — Pirate media suite management covering per-service
operations (aios, decypharr, prowlarr, jackett, nzbhydza2, shelfmark,
grimmory, storyteller, proton, warp), compose profiles, proxy routing
variants, init-bws specifics, and backup/restore script usage. Use this
when managing services within the pirate stack.

Load the appropriate skill instead.
