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
├── .bws-fallback.log      # historical; no current writer
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

## Loader contract (bws-first, cache-or-warning)

| Loader | When | Behavior |
|---|---|---|
| `~/.agents/keys/load-keys.sh` | sourced by zshenv and profile | Reads the 45 exported migrated keys from the **bws project named like the default profile** (one `bws secret list` call; project id cached at `~/.agents/keys/.bws-project-<profile>.id`). On bws failure, uses a <=24h vault cache when available; it never age-decrypts retired files. |
| `~/.zshenv` (dot_zshenv.tmpl) | every zsh, interactive + non-interactive | Sources `load-keys.sh`, then derives gateway routing vars (`OPENAI_API_KEY`, etc.) from the exported values; clears `ANTHROPIC_API_KEY` (vault exports `ANTHROPIC_KEY`). |
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
   re-resolve) before the loader fails soft if no usable cache exists.

**Unavailable-vault behavior.** When bws cannot supply a key, `load-keys.sh`
uses a fresh cache (<=5 minutes) or a stale cache (<=24 hours) when available;
otherwise it emits a warning to stderr, leaves vault-only exports unset, and
continues. It never reads or decrypts retired age files and does not write a
fallback log.

Direct harvesters (`tokentelemetry-env-harvest.sh` and
`glm-free-lane-scan.sh`) silently use their retired age copy only when the
vault fetch fails; a successful fetch missing its key fails loudly and never
falls back. Secret values are never printed or logged — key names and events
only. **Watch the loader log**: every line is a place that still depends on
the retired files.

Design invariants:

1. Secrets never appear in repo history — only age-encrypted copies.
2. Loaders are additive and idempotent: a partially provisioned node degrades
   gracefully to fewer exported vars.
3. Non-default profiles are opt-in via explicit path, never auto-loaded.
4. systemd units and other shell-less consumers get their secrets at start by
   harvesting the live vault value (bws or the login-env loader) and writing
   a `/run` credential file: the no-mistakes daemon drop-in
   (`nm-daemon-env-harvest.sh`), `tokentelemetry-env-harvest.sh`, and
   `cloudflare-ddns-harvest.service`. Direct harvest scripts re-read the vault
   every start and use retired age copies only when the vault fetch fails; a
   successful fetch missing its key is an error. The daemon login-env loader
   never touches age: it may use its <=24h vault cache when bws is unavailable,
   then fails soft. Do not add new consumers that age-decrypt directly.

### Exported env-shaped keys (pattern-driven loader)

As of 2026-10-19, `load-keys.sh` exports every vault secret whose key matches
`^[A-Z][A-Z0-9_]+$`, except keys beginning with `BWS_` or `BYS_`. It exports
the vault key as-is; it does not translate dotfile names into environment
variable names. For example, `.groq-key` is not env-shaped and is not exported,
while the vault secret `META_KEY` is exported as `META_KEY`. Muse's native login
is unaffected: it reads `META_API_KEY`, not `META_KEY`.

(2026-10-19) The Anthropic vault secret is `ANTHROPIC_KEY`, exported as-is;
the shared loader also clears inherited or cached `ANTHROPIC_API_KEY` values,
so it cannot override Claude's native login. The legacy `.anthropic-key` name
is filtered by the pattern loader and remains inert. (2026-10-27, Wave A2)
`tokentelemetry.service` harvests `ANTHROPIC_KEY` directly with bws+jq at
unit start (`tokentelemetry-env-harvest.sh` -> `%t/tokentelemetry.env`) and
maps it to `ANTHROPIC_API_KEY`; the direct read is required precisely because
the loader never exports `ANTHROPIC_API_KEY`.

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

- **bws unavailable**: check stderr for the `load-keys` warning, then fix the
  bws token or network; the loader uses only its <=24h cache and has no local
  age fallback.
- **bws down and a var is empty but the retired file exists**: check
  the bws project contents and cache age; the loader never reads the retired
  file, which is available only to direct harvesters on fetch failure.
- **zshenv warns about a missing default symlink** (interactive shells only):
  `ln -s <profile> ~/.agents/keys/default`, then verify
  `source ~/.zshenv && echo "set: ${CF_AI_GATEWAY_TOKEN:+yes}"`.
- **Stale bws project id**: delete `~/.agents/keys/.bws-project-<profile>.id`;
  the loader re-resolves and re-caches on next shell (it also self-heals once
  automatically after a fetch failure).
- **Provider var empty**: the key exists in neither the usable bws response
  nor cache — check the bws project contents and the key status map above.
