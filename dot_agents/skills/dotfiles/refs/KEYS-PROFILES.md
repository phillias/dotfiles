# Key Profiles (~/.agents/keys)

Owner document for the per-profile key scheme loaded by `dot_zshenv.tmpl`
(Pull Request #284). Everything here reflects the loader and consumers as
codified in this repo.

## File layout

```
~/.agents/keys/
  <profile>/          # per-identity subdir, e.g. masculinecache/, phillias/
    .cf-ai-gw         # plain file: contents become CF_AI_GATEWAY_TOKEN
  default             # symlink -> the DEFAULT profile dir (may be absent)
```

- Profiles are plain directories named after a GitHub/host identity
  (`masculinecache/`, `phillias/` on this host as of writing).
- The `default` symlink selects which profile the shell environment
  auto-loads. It is optional: only exports happen through it, nothing else
  reads it.

## Symlink semantics and load order (dot_zshenv.tmpl)

1. `readlink ~/.agents/keys/default` — `||` swallows a missing symlink
   (`_default_profile=""`, readlink exit ignored).
2. If it is unset, empty, or does not name an existing directory under
   `~/.agents/keys/`: nothing is exported. In interactive shells (`[ -t 0 ]`)
   one stderr line warns once
   (`zshenv: ~/.agents/keys/default symlink missing; not exporting key profile vars`).
3. If the target dir is valid and `-r ~/.agents/keys/$profile/.cf-ai-gw`:
   `CF_AI_GATEWAY_TOKEN="$(cat …)"` is exported.
4. If `.cf-ai-gw` is missing/unreadable: nothing exported; single stderr warn
   (interactive only) naming the exact path.
5. `_default_profile` is unset; only `CF_AI_GATEWAY_TOKEN` is exposed to the
   rest of zshenv (and indirectly to every consumer below).

Hardened behavior (PR #284): any failure mode exports nothing — no empty
token is ever exported.

Non-default profiles are never auto-loaded. A consumer that needs a specific
profile reads the file by explicit path; it does not appear in zshenv.

## Filename -> env var mapping

`.cf-ai-gw` -> `CF_AI_GATEWAY_TOKEN`. That is the only mapping the loader
implements today.

## Consumers of CF_AI_GATEWAY_TOKEN (after zshenv)

Inside `dot_zshenv.tmpl` itself (migrated in PR #284):

- `ANTHROPIC_API_KEY` / `ANTHROPIC_BASE_URL` — Claude Code via CF AI Gateway.
- `OPENAI_API_KEY` / `OPENAI_BASE_URL` — Codex via CF AI Gateway.

Direct consumers:

- `dot_local/bin/executable_big-pickle-watch.sh` — uses
  `CF_AI_GATEWAY_TOKEN` (`GW_TOKEN=${CF_AI_GATEWAY_TOKEN:-}`) for the
  big-pickle health watch; treats empty as unpresent and logs missing.
- `dot_config/opencode/scripts/executable_dynamic-audit.mjs` — the audit
  script refuses to run without a non-empty `CF_AI_GATEWAY_TOKEN`
  (`audit_error: CF_AI_GATEWAY_TOKEN missing`); it makes no other
  auth fallback.

Note the exported value is not consumed by a single profile name:
consumers inherit whatever the `default` symlink pointed at when the shell
started, so switching profiles means new shells (or a restart of the
consuming daemon/script).

## Fresh-machine behavior

- Without `~/.agents/keys` or the `default` symlink: shells stay
  key-less; Claude/Codex zshenv exports receive an empty token, and the two
  direct consumers degrade gracefully (watch logs missing; audit exits with
  `audit_error`). Interactive zsh prints one stderr warning per shell.
- The `~/.agents/keys` tree is a local secret store — never committed; it is
  provisioned per machine, not by chezmoi.

## Migration contract from legacy ~/.config/opencode/.cf-ai-gw-token

The pre-#284 location was a single file,
`~/.config/opencode/.cf-ai-gw-token`, holding the gateway token and read by
tools that now read the env var instead.

- New source of truth: `~/.agents/keys/<profile>/.cf-ai-gw`, selected by
  `~/.agents/keys/default`.
- Migrate by copying the legacy file to
  `~/.agents/keys/<profile>/.cf-ai-gw`, pointing `default` at that profile,
  and verifying in a fresh shell: `echo ${#CF_AI_GATEWAY_TOKEN}` is
  non-zero and consumers (e.g. `big-pickle-watch.sh`) find it.
- Consumers were migrated in #284 from reading the file path to reading
  `CF_AI_GATEWAY_TOKEN` from the environment; they must not keep any legacy
  file-path fallback.
- The legacy path
  `~/dot_config/opencode/dot_gitignore`-adjacent references are kept only
  in docs/tests as historical mentions; runtime code no longer reads it.

## Guardrails

- Keep files `0600`, directories `0700` — secrets never leave the profile
  dir unencrypted in tracked state.
- Never commit any key file. Nothing under `~/.agents/keys` is managed by
  chezmoi.
- Don't add mappings in zshenv unless a consumer truly needs them at every
  shell start; one-off consumers should read by explicit profile path.
