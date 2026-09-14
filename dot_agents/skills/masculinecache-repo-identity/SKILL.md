# masculinecache repo identity

How every GitHub and npm operation on `masculinecache/*` repositories routes to the **masculinecache** account and never the global phillias personal credentials. Load this skill whenever touching a `masculinecache/*` repo (push, PR, release, gh/gh-axi API calls), when a gh call fails with a 403/auth error there, or before wiring a new masc repo into the fleet.

## The five layers (work together; source of truth named per layer)

1. **Repo-local mise env guard** — the repo's committed `.mise.toml` sets
   `[env] GH_REPO = "masculinecache/<repo>"` and
   `GH_CONFIG_DIR = "$HOME/.config/gh-masculinecache"`.
   Any mise-driven shell in the repo (crew workers' tool calls included) routes gh automatically.
   If mise is not active, export both by hand before any gh/gh-axi call.
   Source of truth: `<repo>/.mise.toml`.
2. **git identity + credential routing** — global `dot_gitconfig` (chezmoi source
   `dot_gitconfig`) uses `includeIf "hasconfig:remote.*.url:…masculinecache/*"` for both
   `https://` and `git@` URL forms, returning `~/.config/git/masculinecache.gitconfig`, which
   sets the masculinecache identity and a scoped credential helper. Source of truth: that file
   and `dot_gitconfig`.
3. **Credential-helper plumbing** — the helper pipeline ends in
   `~/.local/bin/gh-credential-dispatch`, which reads the `path=` line of the credential payload
   and routes `path=masculinecache*` to `GH_CONFIG_DIR=$HOME/.config/gh-masculinecache gh auth
   git-credential`; everything else uses the default gh config. Token values live inside
   `~/.config/gh-masculinecache/` (config.yml, hosts.yml) — never read, print, copy, or commit
   them; reference only the directory.
4. **Host PATH gh identity router** — `~/.local/bin/gh` wraps the system gh for callers that
   pass a repo by argument (the no-mistakes daemon, harness-level gh invocations): args matching
   `masculinecache/*` or `kunchenguid/axi` get `GH_CONFIG_DIR` set to the masc dir; an explicit
   `GH_CONFIG_DIR` from the caller always wins; anything else passes through unchanged.
   Note: the shipped `dot_local/bin/executable_gh` deliberately deviates from this host's
   current copy — it resolves gh from PATH (skipping itself) instead of hard-coded
   `/usr/local/bin/gh`/`/usr/bin/gh`, so it works on a fresh mise-only host with no
   system gh binary.
   gh-axi inherits this by shelling to the wrapped gh.
5. **npm publishing with zero credentials** — masc repos publish via npm **Trusted Publishing
   with OIDC** (workflow `id-token: write`, no PAT/gh token in the publish path).
   Source of truth: the repo's `publish.yml`.

## Hard rules

- One account per repo family: GitHub operations on masc repos use masculinecache only — never
  ambient/phillias credentials.
- On a 403 / wrong-account auth failure: **stop and report blocked**. Never retry with different
  credentials, never switch accounts.
- Labels in commits, PRs, and issues must read as masculinecache, not phillias.
- An explicit `GH_CONFIG_DIR` from a caller intentionally wins over both routers — do not add
  code that unsets it.

## Completing a new masc repo (checklist)

- [ ] committed `.mise.toml` with the `GH_REPO` + `GH_CONFIG_DIR` guard
- [ ] repo `AGENTS.md` identity rule paragraph (never ambient; fail loud; the five-layer pointer)
- [ ] registry check: repo name is `masculinecache/*`, publish workflow uses OIDC (no PAT secret)
- [ ] one-line remote config check: a test `gh api /user --jq .login` inside the mise env returns
      `masculinecache`

## Coverage register (2026-09-13)

| Repo | mise guard | AGENTS.md rules | publishing |
|---|---|---|---|
| axi-memory | yes (`f853a00`) | yes | OIDC trusted |
| chezmoi-axi | yes (`20da62d`) | yes | OIDC trusted |
| quota-axi | yes (`9e24fc7`) | yes | OIDC trusted |
| wrangler-axi | yes (`a37c265`) | yes | OIDC trusted |
| bws-axi | pending batch | pending batch | OIDC trusted |
