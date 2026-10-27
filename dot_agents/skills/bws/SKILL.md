---
name: bws
description: Bitwarden Secrets Manager (bws CLI) operations and fleet integration for agents — token management, project-id resolution, state-file pitfalls, load-keys.sh troubleshooting, and fleet-wide rotation procedures. Use whenever a task needs to read or rotate vault secrets on a fleet server, diagnose BWS-FALLBACK noise or invalid_client errors, manage the fleet-shared .bws-token, or understand how ~/.agents/keys/load-keys.sh works. Also use when the user mentions "bws", "bws token", "bws fallback", "vault token", "secrets manager", or asks how to rotate/fix the bws token on any fleet server.
---

# bws — Bitwarden Secrets Manager CLI + fleet integration

The `bws` CLI (v2.x, resolved via mise at
`~/.local/share/mise/installs/bitwarden-secrets-manager/latest/bws`)
authenticates with a static machine-account access token — no interactive
login. The fleet uses one shared machine account, with its token distributed
via chezmoi age-encryption to each server's `~/.agents/keys/<profile>/.bws-token`.

## Architecture

```
~/.agents/keys/
├── default -> phillias            # active profile (symlink)
├── phillias/.bws-token            # machine-account token (95B, mode 600)
├── .bws-project-phillias.id       # non-secret project-id cache (37B, umask 077)
├── retired/<profile>/<key>.age    # retired copies; direct-harvester fallback only
└── load-keys.sh                   # sourced by .zshenv and .profile
```

`load-keys.sh` runs in every shell (`.zshenv` sources it) and:

1. Re-reads the token from the `.bws-token` file every source — a stale
   ambient `BWS_ACCESS_TOKEN` in a long-running shell is always replaced by
   the current file value. The file wins over ambient (this is deliberate;
   a pre-rotation ambient token in an agent session caused repeated vault
   authentication failures for hours before this rule landed).
2. Resolves the bws project id: cache → pinned id → dynamic name lookup.
   The phillias profile is pinned to `fe9eea09-9eaf-45e6-a72f-b45e0150b29d`
   so a vault project rename cannot break logins.
3. Calls `bws -t <token> ...` on every API call. The `-t` flag bypasses the
   state-file session cache at `~/.config/bws/state/<client-uuid>` — that
   cache can go stale (hours TTL) and shadow a valid token with
   `400 invalid_client` until the state file is deleted.
4. Exports each mapped key as its env var. On bws failure it uses the
   5-minute fresh or <=24-hour stale vault cache when available; otherwise it
   warns to stderr and leaves vault-only exports unset. It never decrypts age
   files and does not write a fallback log. Direct shell-less harvesters may
   use their retired age copy only when their vault fetch fails; a successful
   fetch with a missing key is an error.

## Token format

`0.<client-uuid>.<secret-data>` — the client UUID names the machine account
that minted it. When diagnosing, compare the token prefix (the first 14
chars after `0.`) against the vault's machine-account list to confirm which
account issued it. Bitwarden free tier has a 3-machine-account limit and
has been observed auto-revoking tokens; a paid or trial plan stops that.

## Quick operations

```bash
# List projects (3 expected on the fleet: phillias, SelfHost-Prod, masculinecache)
bws project list -o json

# List secrets in a project (121 in phillias as of 2026-10-15)
bws secret list <project-id> -o json

# Read one secret by key from the JSON array
bws secret list <project-id> -o json | jq -r '.[] | select(.key==".cf-ai-gw") | .value'

# Since Wave A2 (2026-10-27), shell-less consumers read the ENV-SHAPED keys
# (e.g. CF_AI_GATEWAY_TOKEN, ANTHROPIC_KEY — they stay in phillias); the
# dot-prefixed keys (.cf-ai-gw, .anthropic-key, …) and their on-disk age
# copies are fallback-only for direct harvesters when the bws fetch fails;
# the shared login-env loader never touches age and uses only its <=24h cache.

# Use a specific token for a one-off call (bypasses env + state)
bws -t "$(cat ~/.agents/keys/default/.bws-token)" project list -o json
```

For redacted project/secret browsing, prefer the `bws-axi` wrapper (TOON
output, values hidden by default); use raw `bws` for value reads and for
everything `bws-axi` does not wrap.

## Rotate the fleet-shared token (on any server)

1. In the Bitwarden web vault (Machine accounts → the shared fleet account
   → Access tokens), create a new access token. Copy the value immediately —
   it is shown once.
2. Write it to the profile token file: `~/.agents/keys/default/.bws-token`
   (which resolves through the profile symlink). Mode 600.
3. In the dotfiles chezmoi source, re-encrypt for the fleet:
   `chezmoi add --encrypt --force ~/.agents/keys/default/.bws-token`
4. Branch, commit, push, open a PR to the dotfiles master. One reviewer
   merges.
5. Every server picks it up via its 15-minute `chezmoi-sync-cron`
   (`chezmoi-axi sync --force`), or a manual `chezmoi apply` for immediacy.
6. Long-running agent sessions hold the old ambient token until they source
   a shell that re-reads the file — the loader's file-wins rule heals them
   on the next shell. The loader has no age fallback; direct harvesters have
   separate, silent age fallback behavior on vault fetch failure.
7. Clear the bws state cache if stale sessions linger:
   `rm -rf ~/.config/bws/state` (the loader's `-t` flag makes this a
   belt-and-suspenders step, not a required one).

Never hand-edit the token file on one server without shipping it through
dotfiles — the 15-minute chezmoi sync will revert the local file to the
master version and strand the un-shipped rotation (this bit us once: PR
#436 encrypted a token that had already been reverted by the cron tick).

## Diagnose unavailable-vault warnings

`load-keys.sh` does not currently write `BWS-FALLBACK` lines or
`.bws-fallback.log`. When bws is unavailable, inspect its stderr warning and
whether the 5-minute or <=24-hour cache is usable. Direct harvesters silently
use their retired age copy only on fetch failure; if a direct fetch succeeds
but the requested key is absent, they fail loudly instead.

| condition | stage | resolution |
|---|---|---|
| token file absent/unreadable | loader or direct harvester cannot authenticate | restore `~/.agents/keys/<profile>/.bws-token` |
| no bws or jq binary | direct harvester cannot fetch | restore the mise bws/jq tools; age fallback applies only to that fetch failure |
| `bws secret list` returns non-JSON | vault fetch failed | check token, API availability, or timeout; re-test with `bws -t` directly |
| fetch succeeds but requested key is absent | direct harvester received a valid response | restore or rename the vault secret; it must not use age fallback |
| retired `.age` cannot decrypt | direct-harvester fallback unavailable | check `~/.config/chezmoi/key.txt` and the retired file |

Triage procedure for a noisy shell:

```bash
# 1. Is the token itself good? (bypasses ambient + state entirely)
bws -t "$(cat ~/.agents/keys/default/.bws-token)" project list -o json

# 2. If that works but ambient calls fail, the session holds a stale
#    ambient token or a stale state file. Both are self-healing under the
#    current loader (file-wins + -t flag): open a new shell, or re-source:
#    unset BWS_ACCESS_TOKEN BWS_TOKEN_FILE; source ~/.agents/keys/load-keys.sh

# 3. If the direct call fails with 400 invalid_client, the token is
#    revoked server-side. Rotate per the procedure above.

# 4. If the direct call fails with empty output (no error), suspect the
#    timeout 5 bound or a Bitwarden API rate-limit window; retry after a
#    minute before concluding anything.
```

## Lessons that shaped this setup

- **Project renames break name-based resolution** (2026-10-15): renaming
  `phillias` to `Fleet SelfHost` in the vault produced
  `bws-project-unresolved` on every fresh login until the pin landed.
  Ids are stable; names are not. Resolution order: cache → pin → name.
- **State files can mask and cause auth failures** (2026-10-15): a valid
  token tested `invalid_client` because the state-file session had gone
  stale and shadowed it. The `-t` flag on every loader call sidesteps the
  whole mechanism. Deleting `~/.config/bws/state` is the manual fix.
- **Bitwarden free tier revokes machine tokens** (2026-10-15): four tokens
  across three machine accounts all went invalid within minutes while the
  org sat on the free tier; upgrading to a trial plan stopped it. If tokens
  keep dying with no state or ambient explanation, check the org plan.
- **Chezmoi owns the token file** (2026-10-15): a hand-edited token was
  silently reverted by the 15-minute sync before it could be encrypted and
  shipped, so a "rotation" PR carried the OLD token. Rotate through
  `chezmoi add --encrypt --force` on a fresh branch, never from a dirty tree.
- **Cache and direct-harvester fallback are distinct**: the shared loader uses
  only its <=24-hour vault cache and warns when no cache is usable; direct
  harvesters silently use retired age copies only when their vault fetch fails.
  A successful vault response missing a requested key is never a fallback case.

## Fleet deployment model

The token file, the loader, and this skill all live in the dotfiles chezmoi
source under `dot_agents/` and deploy to every fleet server via `chezmoi
apply`. Changes ship through a dotfiles PR via the no-mistakes pipeline
(revised 2026-09-02 workflow: no-mistakes PR to phillias/dotfiles, base master;
merge is the captain gate). After merging,
each server converges on the 15-minute crontab, or immediately with a manual
`chezmoi apply`.
