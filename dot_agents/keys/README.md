# Key profiles — `~/.agents/keys`

Owner documentation for the `~/.agents/keys` key-profile scheme: flat keys plus
per-profile key directories, and the shell-level loader contract.

Applied by chezmoi via `dot_agents/keys/README.md` → `~/.agents/keys/README.md`.

## Layout

```
~/.agents/keys/            # drwx------ (700)
├── README.md              # this file
├── .<provider>-key        # FLAT keys: one raw secret per file, no newline guarantees
├── default -> <profile>   # RELATIVE symlink naming the default key profile
├── <profile>/             # PROFILE dirs: per-identity/per-host key sets (drwx------)
│   ├── .cf-ai-gw          # CF AI Gateway token consumed by opencode + zshenv
│   ├── .phoenixgrove-coding-plan-key
│   └── .npmjs-key
└── ...
```

Conventions:

- **Flat keys** (`.groq-key`, `.qwen-key`, …) live directly in the directory root.
  One secret per file, value only (no `KEY=` prefix). All secrets are dotfiles
  (leading `.`).
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

Offloaded rc-block consolidation note: some vars (`HARBOR_API_KEY` in zshrc,
several flat keys after guard checks in bashrc) are exported **only** in
interactive rc files. Moving those loads into zshenv would change behavior for
non-interactive shells/reparented daemons — a **needs-decision** for the
captain if we ever want one consolidated loader. Not changed in this task.

## Loader contract

| Loader | When | Behavior |
|---|---|---|
| `~/.zshenv` (dot_zshenv.tmpl) | every zsh, interactive + non-interactive | Reads `~/.agents/keys/default`. If the symlink exists and names an existing profile dir, loads that profile's `.cf-ai-gw` into `CF_AI_GATEWAY_TOKEN`. On missing symlink/profile/key: exports nothing; prints a hint **only on interactive shells** (TTY check), so cron/scripts never see stderr noise. Downstream, `~/.zshenv` derives `ANTHROPIC_API_KEY`/`OPENAI_API_KEY` from `CF_AI_GATEWAY_TOKEN` to route Claude Code / Codex through the CF AI Gateway. |
| `~/.zshrc` | interactive zsh | Guards each flat key with `[ -f … ]` and exports its env var (mapping table below). Missing files are silently skipped — no errors, no partial exports. |
| `~/.bashrc` | interactive bash | Same flat-key guard/export pattern as zshrc for the bash-side toolset. |

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
.google-client-id    GOOGLE_CLIENT_ID        .composio-key     COMPOSIO_API_KEY
.google-client-secret GOOGLE_CLIENT_SECRET   .qwen-key         QWEN_API_KEY
.fireworks-key       FIREWORKS_API_KEY       .synthetic-key    SYNTHETIC_API_KEY
                                             .kenari-key       KENARI_API_KEY
```

`CLOUDFLARE_ACCOUNT_ID` is hardcoded in the rc (not a secret). `HARBOR_API_KEY`
sources from `$HOME/firstmate/projects/mybiz/.harbor-key`, outside this scheme.

## Repo mapping (chezmoi)

Age-encrypted copies live in the dotfiles repo at `dot_agents/private_keys/`
(target `~/.agents/keys` as a private dir):

- `encrypted_dot_<name>.age` → flat `~/.agents/keys/.<name>`
- `private_<profile>/encrypted_private_dot_<name>.age`
  → `~/.agents/keys/<profile>/.<name>`
- Keys provisioned out-of-band (BWS cron sweeps, manual `chezmoi add --encrypt`
  steps, ad-hoc machine setup) are not all in the repo; the absence of a repo
  copy for a flat key is expected for locally-provisioned secrets — do not
  "fix" that by committing plaintext.

To add or rotate a managed key: edit the source value, then
`chezmoi add --encrypt ~/.agents/keys/.<name>` (or
`chezmoi re-add <path>`), commit the `.age` file, and `chezmoi apply` on target
hosts. See the `dotfiles` / `chezmoi-axi` agent skills for the wrapper
commands.

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
