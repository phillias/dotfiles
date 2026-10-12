# Key profiles — `~/.agents/keys`

Owner documentation for the `~/.agents/keys` key-profile scheme: flat keys plus
per-profile key directories, and the shell-level loader contract.

Applied by chezmoi via `dot_agents/private_keys/README.md` →
`~/.agents/keys/README.md` (the `chezmoi add` convention target for the
live `~/.agents/keys` dir).

## Layout

```
~/.agents/keys/            # drwx------ (700)
├── README.md              # this file
├── load-keys.sh           # shared loader sourced by zshenv and profile
├── default -> <profile>   # RELATIVE symlink naming the default key profile
├── <profile>/             # PROFILE dirs: per-identity/per-host key sets (drwx------)
│   ├── .cf-ai-gw          # CF AI Gateway token consumed by opencode + zshenv
│   ├── .phoenixgrove-coding-plan-key
│   ├── .groq-key
│   ├── .bws-token         # optional: BWS machine-account token for this profile
│   └── ...                # all keys live in profile subdirectories
└── ...
```

Conventions:

- **All keys** live in profile subdirectories. One secret per file, value only
  (no `KEY=` prefix). All secrets are dotfiles (leading `.`).
- **Profiles** are subdirectories named with a lowercase slug identifying the
  machine or persona (e.g. `phillias`, `masculinecache`). Any consumer outside
  the shell rc selects a profile by **explicit path** — non-default profiles are
  never auto-loaded.
- **Default profile** is designated by the `default` symlink in
  `~/.agents/keys`, pointing at a *relative* profile dirname
  (`ln -s phillias default` — not an absolute path; the loader resolves it
  under `~/.agents/keys`).

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
2. **Per-agent configs consume env vars or `{file:}` reads — provenance stays
   in the shell export or `~/.agents/keys`.** e.g. Codex consumes via
   `env_key = "CF_AI_GATEWAY_TOKEN"` with `shell_environment_policy`
   `inherit = "all"` in `~/.codex/config.toml`; opencode resolves
   `{file:~/.agents/keys/<profile>/…}` at config parse. Neither pattern reads
   keystores directly.
3. **Skills follow the same single-source pattern** at `~/.agents/skills`:
   per-agent harnesses source them via **symlink farms**, e.g.
   `~/.claude/skills/<name> -> ../../.agents/skills/<name>`; other harnesses do
   the equivalent. (Documented here only — consolidation of live skill symlinks
   is out of scope for this task.)

Offloaded rc-block consolidation note: `dot_zshenv.tmpl` and the shared loader handle all provider keys. The only exception is `HARBOR_API_KEY` (zshrc-only, sourced from `$HOME/firstmate/projects/mybiz/.harbor-key`). The loader silently skips missing default profiles to avoid noise in non-interactive shells.

## Loader contract

| Loader | When | Behavior |
|---|---|---|
| `~/.agents/keys/load-keys.sh` | sourced by zshenv and profile | Shared loader that reads from `~/.agents/keys/default` profile. Loads all keys from the default profile directory into environment variables. Silently skips missing files. |
| `~/.zshenv` (dot_zshenv.tmpl) | every zsh, interactive + non-interactive | Sources `load-keys.sh` for non-interactive availability, then derives gateway routing vars (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, etc.) from `CF_AI_GATEWAY_TOKEN`. |
| `~/.profile` | login shells | Sources `load-keys.sh` for bash login shells and SSH sessions. |
| `~/.zshrc` | interactive zsh | Sources `load-keys.sh` (redundant but harmless) for interactive sessions. |
| `~/.bashrc` | interactive bash | Sources `load-keys.sh` (redundant but harmless) for interactive sessions. |

Design invariants:

1. Secrets never appear in repo history — only age-encrypted copies (see below).
2. Loaders are additive and idempotent: every guard is per-file, so a partially
   provisioned directory degrades gracefully to fewer exported vars.
3. Non-default profiles are opt-in via explicit path (e.g. opencode config uses
   `{file:~/.agents/keys/phillias/.cf-ai-gw}` to select a profile at parse
   time, independent of the `default` symlink).

### zshrc flat-key → env var mapping

```
.groq-key            GROQ_API_KEY            .cloudflare-key   CLOUDFLARE_API_KEY
.cerebras-key        CEREBRAS_API_KEY        .command-code-key COMMAND_CODE_API_KEY
.mistral-key         MISTRAL_API_KEY         .hf-key           HF_API_KEY
.sambanova-key       SAMBANOVA_API_KEY       .nvidia-key       NVIDIA_API_KEY
.google-key          GOOGLE_API_KEY          .baseten-key      BASETEN_API_KEY
.together-key        TOGETHER_API_KEY        .intern-key       INTERN_API_KEY
.zen-key             OPENCODE_ZEN_API_KEY    .openrouter-key   OPENROUTER_API_KEY
.zai-key             ZHIPU_API_KEY           .exa-key          EXA_API_KEY
.vercel-gateway-key  AI_GATEWAY_API_KEY
.google-client-id    GOOGLE_CLIENT_ID        .composio-key     COMPOSIO_API_KEY
.google-client-secret GOOGLE_CLIENT_SECRET   .qwen-key         QWEN_API_KEY
.fireworks-key       FIREWORKS_API_KEY       .synthetic-key    SYNTHETIC_API_KEY
                                             .kenari-key       KENARI_API_KEY
                                             .seevio-key       SEEVIO_API_KEY
.atlascloud-key      ATLASCLOUD_API_KEY
```

`CLOUDFLARE_ACCOUNT_ID` is hardcoded in the rc (not a secret). `HARBOR_API_KEY`
sources from `$HOME/firstmate/projects/mybiz/.harbor-key`, outside this scheme.

## Repo mapping (chezmoi)

Age-encrypted copies live in the dotfiles repo at `dot_agents/private_keys/`
(target `~/.agents/keys` as a private dir). All encrypted files are stored in
per-profile subdirectories:

- `private_<profile>/encrypted_private_dot_<name>.age`
  → `~/.agents/keys/<profile>/.<name>`
- `symlink_default` → relative symlink target (content: `<profile>`)

Example: `private_phillias/encrypted_private_dot_groq-key.age` decrypts to
`~/.agents/keys/phillias/.groq-key`, and `~/.agents/keys/default -> phillias`
makes it the default profile.

Keys provisioned out-of-band (BWS cron sweeps, manual `chezmoi add --encrypt`
steps, ad-hoc machine setup) are not all in the repo; the absence of a repo
copy for a key is expected for locally-provisioned secrets — do not "fix" that
by committing plaintext.

To add or rotate a managed key: edit the source value, then
`chezmoi add --encrypt ~/.agents/keys/<profile>/.<name>` (or
`chezmoi re-add <path>`), commit the `.age` file, and `chezmoi apply` on target
hosts. See the `dotfiles` / `chezmoi-axi` agent skills for the wrapper
commands.

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
  `~/.agents/keys/<profile>/.bws-token` (same scheme as any other key:
  value only, mode 600). Repo copy:
  `private_<profile>/encrypted_private_dot_bws-token.age`, rotated like any
  managed key via `chezmoi add --encrypt` / `chezmoi re-add`.
- **Loader exports** (default profile only, sourced like all other keys):
  - `BWS_TOKEN_FILE` — path to the default profile's `.bws-token`
    (consumed by the `bws-axi` wrapper).
  - `BWS_ACCESS_TOKEN` — the token value itself; plain `bws` requires this
    env var and does **not** read `BWS_TOKEN_FILE`.
  - `BWS_BIN` — pinned `bws` binary at the mise latest alias
    (`~/.local/share/mise/installs/bitwarden-secrets-manager/latest/bws`),
    per the mise path strategy for env-var consumers.

Machine accounts and tokens are minted only by the org admin in the
Bitwarden web vault (the `bws` CLI cannot create them).

### Migrating keys into BWS

`~/scripts/bws-migrate-keys.sh` (source: `scripts/bws-migrate-keys.sh`)
uploads each key file in a profile to the matching BWS project as a secret
with the same key name. `--dry-run` prints the plan without touching the
vault; per-key idempotency skips names that already exist. Expected
counts: `phillias` 58 (57 keys + token), `masculinecache` 1. Values are
read only at execution time and never logged. After migration is verified,
retiring the local age-encrypted key files is a destructive,
captain-gated decision (see the migration task brief).

## Troubleshooting

- **zshenv warns about a missing default symlink** (interactive shells only):
  `ln -s <profile> ~/.agents/keys/default`, then verify
  `source ~/.zshenv && echo "set: ${CF_AI_GATEWAY_TOKEN:+yes}"`.
- **A provider var is empty but the key file exists**: check file readability
  (`test -r`) and that the file has no stray `export` wrapping; loader `cat`s
  the raw value only.
- **Profile key ignored by opencode**: opencode selects via `{file:…}` at
  config parse; edit the config path to the right profile, not the default
  symlink.
