# Agent credential seeding

`scripts/deploy-agent-credentials.sh` copies portable agent CLI credential snapshots from Bitwarden Secrets Manager project `phillias` (`fe9eea09-9eaf-45e6-a72f-b45e0150b29d`) into `$HOME`.

The vault copy is a first-login seed, not a live source.
After a successful deploy, that host's own CLI refreshes its tokens.
A stale snapshot only costs one extra laptop login on a new host.

Flags, status lines, and the per-row error contract are owned by `deploy-agent-credentials.sh --help`.

## Manifest

`scripts/agent-credentials.conf` is tab-separated: tool, secret key, `$HOME`-relative path, mode.
Blank lines and comments are ignored.
Secret values are the base64 of the credential file and are never stored in this repo.

| tool | secret key | path | mode | seeded |
| --- | --- | --- | --- | --- |
| commandcode | `AGENT_COMMANDCODE_AUTH_JSON` | `.commandcode/auth.json` | `0600` | yes (secret already in BWS) |
| codex | `AGENT_CODEX_AUTH_JSON` | `.codex/auth.json` | `0600` | yes |
| claude | `AGENT_CLAUDE_CREDENTIALS_JSON` | `.claude/.credentials.json` | `0600` | yes |
| opencode | `AGENT_OPENCODE_AUTH_JSON` | `.local/share/opencode/auth.json` | `0600` | yes |
| grok | TBD | TBD |  | no — portability unverified (dotfiles#589 findings parking lot) |

Claude's target is a dotfile inside `.claude/`.
OpenCode's target is two directories deeper (`.local/share/opencode/`).
The deploy script creates those parents with `mkdir -p` and does not strip a leading dot from any path segment.

## Adding a tool

Add a manifest row only after the credential file is verified as portable JSON on a fleet host.
Create the matching `AGENT_<TOOL>_...` secret in BWS project `phillias` (base64 of the file).
Secret creation is a captain gate.
Do not commit the secret value.
Leave grok out until its credential file is shown to be portable.

## Deploy-once and live credentials

The script writes a target only when that file is absent.
Overwriting a live credential requires explicit `--force`, because the local CLI holds newer refresh tokens than any snapshot.
`--force` saves the previous file beside the target as `<name>.bak.<UTC timestamp>` and then replaces it.

A missing secret is a per-entry error (`code=missing-secret`).
The run still processes every other row and exits nonzero if any row failed.
It does not fail the whole run at the first missing secret.
BWS authentication failure stops the run before any write.

## Fallback

When seeding cannot be used, log in on the laptop and copy the auth file onto the host.
Do not use a tunnel race as the login method.
