# Key Profiles (~/.agents/keys)

Owner document for the per-profile key scheme loaded by `dot_zshenv.tmpl`
(Pull Request #284). Everything here reflects the loader and consumers as
codified in this repo.

## File layout

```
~/.agents/keys/
  <profile>/.bws-token       # machine-account token for the profile
  default                     # symlink -> the active profile dir
  retired/<profile>/<key>.age # retired copies; direct-harvester fallback only
  load-keys.sh                # shared vault loader
```

Profiles are directories named after a GitHub/host identity. The `default`
symlink selects the profile token and cached vault state used by
`load-keys.sh`; it does not make retired files active. The loader exports
matching env-shaped vault keys, including `CF_AI_GATEWAY_TOKEN` and
`ANTHROPIC_KEY`, and never decrypts retired age files. Direct shell-less
harvesters may use their corresponding retired age copy only after a failed
vault fetch; a successful fetch missing its key is an error.

## Loader semantics (dot_zshenv.tmpl)

`dot_zshenv.tmpl` sources `~/.agents/keys/load-keys.sh` for every shell. The
loader reads the profile's `.bws-token`, calls bws with `-t`, and exports the
matching vault keys. On vault failure it uses a fresh (<=5 minute) or stale
(<=24 hour) vault cache when available; otherwise it warns to stderr and
leaves vault-only exports unset. It never reads or decrypts retired age files.

Non-default profiles are never auto-loaded. A consumer that needs a specific
profile reads it by explicit path; it does not appear in zshenv.

## Filename -> env var mapping

The loader uses env-shaped vault keys directly (for example,
`CF_AI_GATEWAY_TOKEN` and `ANTHROPIC_KEY`). Dot-prefixed files such as
`.cf-ai-gw` are retired compatibility copies, not the current loader source.

## Consumers of CF_AI_GATEWAY_TOKEN (after zshenv)

Inside `dot_zshenv.tmpl` itself (migrated in PR #284):

- `ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_API_KEY` — explicit
  Claude Code Vercel AI Gateway fallback; native Anthropic OAuth is the default.
- `OPENAI_API_KEY` / `OPENAI_BASE_URL` — CF AI Gateway fallback route for
  firstmate worker harnesses (codex itself uses native OpenAI via ChatGPT
  sign-in, which ignores these).

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

- Without `~/.agents/keys`, the `default` symlink, or a usable vault/cache,
  shells stay key-less and the loader warns or fails soft. Direct harvesters
  fail unless their explicit env override or fetch-failure age fallback is
  available.
- The `~/.agents/keys` tree is a local secret store — never committed; it is
  provisioned per machine, not by chezmoi.

## Migration contract from legacy ~/.config/opencode/.cf-ai-gw-token

The pre-#284 location was a single file,
`~/.config/opencode/.cf-ai-gw-token`, holding the gateway token and read by
tools that now read the env var instead.

- The current source of truth is the phillias bws vault's env-shaped
  `CF_AI_GATEWAY_TOKEN`, selected by the profile token and `default` symlink.
- Migrate by placing the bws token in the selected profile and verifying in a
  fresh shell: `echo ${#CF_AI_GATEWAY_TOKEN}` is non-zero. The old `.cf-ai-gw`
  file is retained only as a direct-harvester fallback copy.
- Consumers were migrated in #284 from reading the file path to reading
  `CF_AI_GATEWAY_TOKEN` from the environment; they must not keep any legacy
  file-path fallback.
- The legacy path
  `~/dot_config/opencode/dot_gitignore`-adjacent references are kept only
  in docs/tests as historical mentions; runtime code no longer reads it.

## Guardrails

- (2026-10-27, Wave A2) The source of `CF_AI_GATEWAY_TOKEN` is now the phillias
  bws vault (env-shaped `CF_AI_GATEWAY_TOKEN`, exported by `load-keys.sh`);
  the plaintext profile-file mechanism described above is superseded, and the
  dot-key `.cf-ai-gw` plus its retired age copy are fallback-only. Direct
  shell-less harvesters fall back to age only when bws is unreachable; the
  daemon login-env loader never touches age and uses only its <=24h vault
  cache when bws is unavailable.
- Keep files `0600`, directories `0700` — secrets never leave the profile
  dir unencrypted in tracked state.
- Never commit any key file. Nothing under `~/.agents/keys` is managed by
  chezmoi.
- Don't add mappings in zshenv unless a consumer truly needs them at every
  shell start; one-off consumers should read by explicit profile path.
