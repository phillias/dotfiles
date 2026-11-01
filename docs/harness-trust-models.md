# Harness Trust Standing Configuration

## 1. Per-Harness Trust-Model Findings
- **Claude**: real store is `~/.claude.json` (`projects.<path>.hasTrustDialogAccepted`); `settings.json` is hooks-only and is not consulted for trust. Exact path only. Seeded non-clobbering via run_once (jq merge; preserves other keys and runtime state).
- **Grok**: `~/.grok/trusted_folders.toml`, `[folders."<path>"] trusted = true`. Exact path only. Seeded non-clobbering via run_once (append-if-absent; preserves runtime appends). Grok also exposes a blanket `[folder_trust] enabled = false` switch (`GROK_FOLDER_TRUST=0`) that would cover arbitrary fresh directories, but flipping it removes per-directory consent entirely rather than adding standing entries for known paths — not adopted here; it needs separate authorization if full worktree coverage is wanted.
- **Pi**: real store is `~/.pi/agent/trust.json`, a flat `"<path>": true` map (verified against the live file on this machine). Exact path only. Seeded non-clobbering via run_once (jq merge). Pi also exposes a blanket `defaultProjectTrust = "always"` setting (in `~/.pi/agent/settings.json`, default `"ask"`) with the same bypass trade-off as Grok's switch above — not adopted here for the same reason.
- **Codex**: real store is `~/.codex/config.toml`, `[projects."<path>"] trust_level = "trusted"` (confirmed via `ProjectConfigToml`/`trust_level` strings in the installed 0.153.4 binary). Exact path only. Seeded as static entries directly in `private_dot_codex/config.toml.tmpl`, since that file is already a chezmoi-authoritative render — a runtime append here would be wiped on the next `apply`.
- **Kimi**: real store is `~/.kimi-code/workspace-trust/wd_<name>_<hash>`, one file per trusted root (`{"root": "<path>", "trustedAt": <ms>}`). The hash in the filename is not reverse-engineered, so pre-seeding a file for a known path risks writing a file Kimi never looks up. Left unseeded.

## 2. Standing Configuration Implemented
- `run_once_seed-harness-trust.sh.tmpl`: idempotent, non-clobbering seeding, under a per-store `flock`, with a post-write read-back check that fails the script (and thus leaves run_once un-recorded, so it retries on the next apply) if the expected keys did not land:
  - `~/.claude.json` — jq merge of `projects.<path>.hasTrustDialogAccepted = true`.
  - `~/.pi/agent/trust.json` — jq merge of `"<path>": true`.
  - `~/.grok/trusted_folders.toml` — append `[folders."<path>"]` blocks if absent.
  - If `jq` is missing, the script fails loudly (exit 1) instead of silently skipping the Claude/Pi seeding and being recorded as done.
- `private_dot_codex/config.toml.tmpl`: static `[projects."<path>"] trust_level = "trusted"` entries (chezmoi-rendered, so no separate run_once logic is needed or safe here).
- Known paths seeded on all four covered harnesses: `{{ .chezmoi.homeDir }}/firstmate` and `{{ .chezmoi.homeDir }}/.local/share/chezmoi`.
- This doc is chezmoi-ignored as a directory (`.chezmoiignore`: `docs`), so it and its parent directory are not installed to `~`.

## 3. Verification Performed
- The only artifact produced by prior verification attempts is `data/.../verification-grok.log`. Its content is `grok --help` usage text followed by `exit: 0` — the binary printed its help and exited without starting a session, so it does not demonstrate that any trust dialog was or was not shown. No verification artifacts exist for Claude, Pi, Codex, or Kimi.
- This round's fix was verified by: `bash -n` syntax-checking the modified script, a dry run of the Claude/Pi/Grok seeding logic (jq merge, flock, re-read check) against throwaway JSON/TOML files standing in for the real stores, and a read of the live `~/.pi/agent/trust.json` and `~/.codex/config.toml` to confirm the assumed schemas. No interactive harness session was launched, so no trust dialog was observed directly.

## 4. Explicit Limitation Statement
Static seeding only covers the two known primary paths above, on Claude, Grok, Pi, and Codex. It does not cover:
- Kimi, at all (hash-keyed store, algorithm unverified).
- Arbitrary fresh per-spawn worktrees under `~/.treehouse/<host>/<n>/<repo>` on any of the five harnesses — these paths are not known ahead of time, so an exact-path store can't be pre-seeded for them. Grok's `folder_trust` disable and Pi's `defaultProjectTrust = "always"` would each cover this for their harness, but both remove per-directory consent entirely; adopting either is a bigger step than the intent's "standing configuration in the harnesses' own config surfaces" ask and needs separate authorization.

See `run_once_seed-harness-trust.sh.tmpl`, `private_dot_codex/config.toml.tmpl`, and git history for details.
