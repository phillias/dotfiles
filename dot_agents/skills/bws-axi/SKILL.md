---
name: bws-axi
description: Bitwarden Secrets Manager operations for agents — list projects and secrets with values redacted by default. Use whenever the user asks to check Bitwarden, list secrets, read a secret value, manage BWS projects, or when a task needs credentials/secrets from the Bitwarden vault. Also use when the user mentions "bws", "bitwarden", "secret", "vault", "credentials".
---

# bws-axi — Bitwarden Secrets Manager for agents

List projects and secrets, read values on demand. TOON output, values never shown unless `--full`.

## Requirements

- `bws` CLI 2.x (`bws --version`) — or set `BWS_BIN`
- Auth token: `BWS_ACCESS_TOKEN` env, or `BWS_TOKEN_FILE` pointing at a token file
  (default `~/.config/bwsh/token`, matching the `~/docker/selfhost/bws-init` pattern)

Run `bws-axi doctor` to diagnose both.

## Quick Reference

```bash
bws-axi                              # dashboard: projects + counts
bws-axi projects                     # list projects (name, id)
bws-axi items <project>              # list secret KEYS in a project (values never shown)
bws-axi secret <project> <key>       # one value, redacted (length only)
bws-axi secret <project> <key> --full # the actual value
bws-axi doctor                       # binary + token + auth check
bws-axi setup                        # ambient-context instructions
```

`<project>` accepts a name or id prefix.

## Safety rules

- Secret **values are never printed** by default — only key names, types, and value lengths
- `--full` is the explicit escape hatch for reading one value
- Mutations are intentionally out of scope (create/update/delete secrets → use `bws` directly)

## Errors

Errors go to stdout in TOON shape with a `code:` and actionable `help[n]:` hints.
Exit codes: 0 = success, 1 = error, 2 = usage error.
