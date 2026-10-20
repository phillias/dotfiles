# Key profiles — `~/.agents/keys`

Owner documentation for the `~/.agents/keys` key-profile scheme: the bws-first
loader contract, the retired-key layout, and recovery procedures.

Applied by chezmoi via `dot_agents/private_keys/README.md` →
`~/.agents/keys/README.md` (the `chezmoi add` convention target for the
live `~/.agents/keys` dir).

## Key status map (post-BWS-migration, 2026-10-13)

| Status | Keys | Where they live |
|---|---|---|
| **Active** (not migrated) | `.bws-token` (per profile), `.google-tasks-token` | `~/.agents/keys/<profile>/` — unchanged, chezmoi age-encrypted in the repo as before |
| **Retired** (57 migrated keys: 56 in the `phillias` profile + `masculinecache/.npmjs-key`) | Every other migrated key | bws project named like the profile is the live source; age-encrypted copies at `~/.agents/keys/retired/<profile>/<name>.age` for fallback + recovery |
| **Excluded from migration** | `.google-tasks-token` | Stays chezmoi age-encrypted in the active profile dir (binary/non-UTF-8; cannot be a bws secret). Never enters the loader or retired tree |

Retired key inventory (56 in the `phillias` profile): the 45 exported by the
loader (map below) plus 11 recovery-only keys with no exported var:
`.althub.co.za-api-rss-key`, `.animez.to-rss-key`, `.cf-ai-gw-token`,
`.command-code.key`, `.map-api-key`, `.prowlarr.phillias.cc-api-key`,
`.rapidseedbox-utorrent-password`, `.seedpool-api-token`,
`.speedapp.io-api-token`, `.telegram-chat-id`, `.x-cookies.env`.
`masculinecache/.npmjs-key` is the 57th retired file.

## Layout

```
~/.agents/keys/            # drwx------ (700)
├── README.md              # this file
├── load-keys.sh           # shared loader sourced by zshenv and profile
├── default -> <profile>   # RELATIVE symlink naming the default key profile
├── .bws-fallback.log      # durable tripwire log: one line per fallback event
├── .bws-project-<profile>.id  # cached bws project id (not a secret)
├── <profile>/             # ACTIVE profile dirs: only never-migrated keys
│   ├── .bws-token         # BWS machine-account token for this profile
│   └── .google-tasks-token    # binary/non-UTF-8, stays chezmoi-managed
└── retired/               # RETIRED keys: age-encrypted recovery copies
    ├── <profile>/
    │   ├── .groq-key.age      # age -d returns the value in seconds
    │   └── ...                # one .age per migrated key
    └── masculinecache/
        └── .npmjs-key.age
```

Conventions:

- **Active profile dirs hold only never-migrated keys** (`.bws-token`,
  `.google-tasks-token`). All migrated keys moved to bws + the retired tree;
  the old live files are removed on apply via `.chezmoiremove`.
- **One secret per file, value only** (no `KEY=` prefix), dotfile names.
- **Default profile** is the `default` symlink's relative target
  (`ln -s phillias default`); non-default profiles are never auto-loaded.
- **Retired files are raw age ciphertext** (repo source drops the `encrypted_`
  prefix so chezmoi does not decrypt them on apply). Recovery needs age alone,
  no bws: `age -d -i ~/.config/chezmoi/key.txt <file>` (or `chezmoi decrypt
  <file>`).

## Multi-harness contract (primary)

`~/.agents/keys` serves **every** harness firstmate dispatches — claude, codex,
pi, grok, kimi, cursor, opencode — through one primary contract plus per-agent
sourcing conventions:

1. **Shell-level env export is the universal availability layer.** All agent
   harnesses are launched through a login/non-interactive or interactive shell,
   so they inherit whatever the `~/.agents/keys` loaders exported
   (`CF_AI_GATEWAY_TOKEN`, `<PROVIDER>_API_KEY`, OAuth ids/secrets). Once a key
   is exported after `exec zsh -l` (or the equivalent zshenv evaluation), every
   harness can read it without per-agent wiring. This shell inheritance is the
   documented primary contract; nothing below bypasses it.
2. **Per-agent configs consume env vars — provenance stays in the shell
   export.** e.g. Codex consumes via `env_key = "CF_AI_GATEWAY_TOKEN"` with
   `shell_environment_policy` `inherit = "all"` in `~/.codex/config.toml`;
   opencode providers use `{env:CF_AI_GATEWAY_TOKEN}` (post-migration; the old
   `{file:~/.agents/keys/...}` indirections retired with the key files).
   Neither pattern reads keystores directly.
3. **Skills follow the same single-source pattern** at `~/.agents/skills`:
   per-agent harnesses source them via **symlink farms**, e.g.
   `~/.claude/skills/<name> -> ../../.agents/skills/<name>`; other harnesses do
   the equivalent. (Documented here only — consolidation of live skill symlinks
   is out of scope for this task.)

Offloaded rc-block consolidation note: `dot_zshenv.tmpl` and the shared loader handle all provider keys. The only exception is `HARBOR_API_KEY` (zshrc-only, sourced from `$HOME/firstmate/projects/mybiz/.harbor-key`). The loader silently skips missing default profiles to avoid noise in non-interactive shells.

## Loader contract (bws-first, loud fallback)

| Loader | When | Behavior |
|---|---|---|
| `~/.agents/keys/load-keys.sh` | sourced by zshenv and profile | Reads the 45 exported migrated keys from the **bws project named like the default profile** (one `bws secret list` call; project id cached at `~/.agents/keys/.bws-project-<profile>.id`). On any bws failure, falls back per key to age-decrypting the retired file — loudly. |
| `~/.zshenv` (dot_zshenv.tmpl) | every zsh, interactive + non-interactive | Sources `load-keys.sh`, then derives gateway routing vars (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, etc.) from the exported values. |
| `~/.profile` | login shells | Sources `load-keys.sh` for bash login shells and SSH sessions. |
| `~/.zshrc` / `~/.bashrc` | interactive shells | Source `load-keys.sh` (redundant but harmless). |

bws resolution order: auth from ambient `BWS_ACCESS_TOKEN` or the profile's
`.bws-token` file; binary from `BWS_BIN`, PATH, or the mise latest alias
(`~/.local/share/mise/installs/bitwarden-secrets-manager/latest/bws`).

**Per-shell fetch tradeoff.** Because `load-keys.sh` is sourced by `~/.zshenv`
on every zsh (interactive and non-interactive), the `bws secret list` fetch runs
once per shell, so shell startup now includes a network round-trip (previously
instant local reads). This is the accepted bws-first tradeoff: values are never
cached to disk (that would defeat keeping secrets off disk) and non-interactive
shells are not skipped (that would permanently consume the retired recovery
path). Each bws call is bounded by a 5s timeout, so a shell where bws is
unreachable waits at most ~10s (initial secret list, then one project-list
re-resolve) before the loud age fallback fires.

**Fallback tripwire.** When bws cannot supply a key — daemon unreachable,
token missing/broken, secret absent — the loader age-decrypts
`~/.agents/keys/retired/<profile>/<key>.age` and exports that. EVERY fallback
appends one greppable line to `~/.agents/keys/.bws-fallback.log` AND writes
the same line to stderr:

```
BWS-FALLBACK 2026-10-13T22:30:00Z profile=phillias key=.groq-key var=GROQ_API_KEY reason=bws-fetch-failed
```

The fallback is a tripwire that shows where references still need re-pointing
to bws; it is never silent cover. Secret values are never printed or logged —
key names and events only. A node whose bws token is missing or broken still
boots a working environment via fallback + log. **Watch the log**: every line
is a place that still depends on the retired files.

Design invariants:

1. Secrets never appear in repo history — only age-encrypted copies.
2. Loaders are additive and idempotent: a partially provisioned node degrades
   gracefully to fewer exported vars.
3. Non-default profiles are opt-in via explicit path, never auto-loaded.
4. systemd units and other shell-less consumers get their secrets at start,
   through one of two patterns: age-decrypting the retired file directly
   (see `tokentelemetry.service`, `glm-free-lane-scan.sh` — local age never
   depends on bws reachability), or harvesting the live vault value through a
   login shell and writing a `/run` credential file (the no-mistakes daemon
   drop-in, `cloudflare-ddns-harvest.service` — preferred for values that
   rotate in the vault, because retired age copies go stale after rotation).

### Exported env-shaped keys (pattern-driven loader)

As of 2026-10-19, `load-keys.sh` exports every vault secret whose key matches
`^[A-Z][A-Z0-9_]+$`, except keys beginning with `BWS_` or `BYS_`. It exports
the vault key as-is; it does not translate dotfile names into environment
variable names. For example, `.groq-key` is not env-shaped and is not exported,
while the vault secret `META_KEY` is exported as `META_KEY`. Muse's native login
is unaffected: it reads `META_API_KEY`, not `META_KEY`.

`CLOUDFLARE_ACCOUNT_ID` is hardcoded in the rc (not a secret). `HARBOR_API_KEY`
sources from `$HOME/firstmate/projects/mybiz/.harbor-key`, outside this scheme.

`CLOUDFLARE_DDNS_API_TOKEN` (added 2026-10-19) feeds the `cloudflare-ddns`
systemd units on cabinkali: `cloudflare-ddns-harvest.service` (root,
sandbox-free, patterned on `nm-daemon-env-harvest.sh`) harvests it via
`runuser -u phillias -- zsh -lc` at each start, clearing the shared five-minute
loader cache first, and writes
`/run/cloudflare-ddns/config.ini` (0640 root:cloudflare-ddns); both DDNS
units then run `/usr/bin/cloudflare-ddns --config /run/cloudflare-ddns/config.ini`,
so no token ever sits on a unit command line or in `/etc`.
The live-host unit files are not chezmoi-managed; rotating the token is a
bws secret update alone — the harvest re-reads the vault at each unit start,
so no retired age copy exists or is needed.
Zone-scoped Cloudflare tokens return 401 on `/user/tokens/verify` even when
valid — use a `zones?name=<zone>` lookup as the liveness probe (the harvest
script's fail-fast does exactly that).

## Repo mapping (chezmoi)

Age-encrypted copies live in the dotfiles repo at `dot_agents/private_keys/`
(target `~/.agents/keys` as a private dir):

- **Active keys** — `private_<profile>/encrypted_private_dot_<name>.age`
  → `~/.agents/keys/<profile>/.<name>` (decrypted on apply). Only
  `.bws-token` and `.google-tasks-token` remain active.
- **Retired keys** — `private_retired/private_<profile>/private_dot_<name>.age`
  → `~/.agents/keys/retired/<profile>/.<name>.age` (raw ciphertext on apply;
  the `encrypted_` prefix is deliberately absent).
- `symlink_default` → relative symlink target (content: `<profile>`).
- `.chezmoiremove` (repo root) removes the 57 old live key paths on apply,
  completing the move: values live in bws, recovery copies in `retired/`.

Recovery of any retired key (age alone, no bws, no chezmoi):

```sh
age -d -i ~/.config/chezmoi/key.txt ~/.agents/keys/retired/<profile>/.<name>.age
```

To add or rotate a managed key: create/update the bws secret in the profile's
project, refresh the retired copy
(`chezmoi encrypt ~/.agents/keys/<profile>/.<name> >
dot_agents/private_keys/private_retired/private_<profile>/private_dot_<name>.age`),
commit, and `chezmoi apply` on target hosts. Never commit plaintext.

## Bitwarden Secrets Manager (BWS)

BWS gives agents fluid, never-locked vault access: machine-account access
tokens do not require master-password unlocking (unlike `bw`/`bws` user
sessions). The BWS layout mirrors the profile scheme:

- **Project per profile.** Each key profile gets one BWS project of the same
  name (`phillias`, `masculinecache`), each with one machine account of the
  same name. Free org tier allows 3 projects + 3 machine accounts; the
  existing `selfhost-Dev` account consumes one slot, so per-node accounts
  do not fit — per-persona accounts fit exactly.
- **Token per profile.** Each profile's machine-account token lives at
  `~/.agents/keys/<profile>/.bws-token` (active, never retired; repo copy
  `private_<profile>/encrypted_private_dot_bws-token.age`).
- **Loader exports** (default profile only, sourced like all other keys):
  - `BWS_TOKEN_FILE` — path to the default profile's `.bws-token`
    (consumed by the `bws-axi` wrapper).
  - `BWS_ACCESS_TOKEN` — the token value itself; plain `bws` requires this
    env var and does **not** read `BWS_TOKEN_FILE`.
  - `BWS_BIN` — pinned `bws` binary at the mise latest alias.

Machine accounts and tokens are minted only by the org admin in the
Bitwarden web vault (the `bws` CLI cannot create them).

### Migration status: COMPLETE (2026-10-13)

57 key files were migrated into the `phillias` (56) and `masculinecache` (1)
projects alongside the 64 pre-existing selfhost secrets, and the on-disk
copies were **retired by moving, not deleting**: source files `git mv`-ed to
`private_retired/` (history preserved), live files removed via `.chezmoiremove`
as the retired age copies landed. `.google-tasks-token` stayed chezmoi-managed
(binary/non-UTF-8) and every node's `.bws-token` stayed live. The historical
migration script `scripts/bws-migrate-keys.sh` is kept for reference.

## Troubleshooting

- **Fallback events appearing**: `grep BWS-FALLBACK ~/.agents/keys/.bws-fallback.log`.
  Each line names a key the loader could not get from bws — fix the cause
  (bws token, network, missing secret) or re-point the consumer named by the
  var; the log is the re-pointing work list, not noise to suppress.
- **bws down and a var is empty but the retired file exists**: check
  `chezmoi decrypt ~/.agents/keys/retired/<profile>/.<name>.age` works; the
  loader tries `chezmoi decrypt` then raw `age -d` with the chezmoi identity.
- **zshenv warns about a missing default symlink** (interactive shells only):
  `ln -s <profile> ~/.agents/keys/default`, then verify
  `source ~/.zshenv && echo "set: ${CF_AI_GATEWAY_TOKEN:+yes}"`.
- **Stale bws project id**: delete `~/.agents/keys/.bws-project-<profile>.id`;
  the loader re-resolves and re-caches on next shell (it also self-heals once
  automatically after a fetch failure).
- **Provider var empty and no fallback line**: the key exists in neither bws
  nor the retired tree — check the bws project contents and the key status
  map above.
