# Harness Trust Standing Configuration

## 1. Per-Harness Trust-Model Findings
- **Claude**: real store is `~/.claude.json` (`projects.<path>.hasTrustDialogAccepted`); `settings.json` is hooks-only and is not consulted for trust. The resolver only ascends from cwd to the enclosing git root, never past it, so a grant on a primary checkout never matches a fresh worktree (whose root is the worktree itself). Exact path only. Seeded non-clobbering (jq merge; preserves other keys and runtime state).
- **Grok**: `~/.grok/trusted_folders.toml`, `[folders."<path>"] trusted = true`. Grok's own docs state a grant covers subdirectories of the same repository but not a nested git checkout, so a worktree is its own, uncovered workspace. Exact path only. Seeded non-clobbering (append-if-absent; preserves runtime appends). Grok also exposes a blanket `[folder_trust] enabled = false` switch (`GROK_FOLDER_TRUST=0`) that would cover arbitrary fresh directories, but flipping it removes per-directory consent entirely rather than adding standing entries for known paths — not adopted here; it needs separate authorization if full worktree coverage is wanted.
- **Pi**: real store is `~/.pi/agent/trust.json`, a flat `"<path>": true` map (verified against the live file on this machine). Its trust-manager walks ancestors up to `/` (not bounded by a git root), so a single grant on `$HOME` covers every path underneath it, including fresh worktrees — the live file already carried exactly this grant before this change. Seeded non-clobbering (jq merge of `"$HOME": true`).
- **Codex**: real store is `~/.codex/config.toml`, `[projects."<path>"] trust_level = "trusted"` (confirmed via `ProjectConfigToml`/`trust_level` strings in the installed 0.153.4 binary). No evidence of ancestor-walk matching, so treated as exact path only, same worktree gap as Claude/Grok. `config.toml` is itself a chezmoi-authoritative render; `[projects.*]` entries are appended after that render rather than living in the template, so a runtime grant Codex records for another path isn't wiped by the next apply.
- **Kimi**: real store is `~/.kimi-code/workspace-trust/wd_<slug>_<12hexhash>` (one JSON file per root: `{"root": "<path>", "trustedAt": <ms>}`). Hash = first 12 hex of sha256(normalized path); slug = lower basename, runs of `[^a-z0-9._-]` -> `-`, dashes trimmed, 40 chars max. Verified against kimi-code 2.1.1 (encodeWorkDirKey in dist). `readWorkspaceTrust` looks up the exact root only (no ancestor walk), so only the two primary paths are seeded. Live-verified with real binary in throwaway HOME (no dialog, artifact in task data dir).

## 2. Standing Configuration Implemented
- `run_after_seed-harness-trust.sh.tmpl`: runs after every chezmoi apply (survives runtime writes and re-render of templated configs like Codex). Each store updated under dedicated `flock` with post-write read-back (fails script if keys didn't land). jq missing now loud warning + exit 0 (non-abort; retries next apply). Claude/Pi stores are only rewritten when the keys are absent. Kimi seeded with verified sha256 hash derivation (wd_<slug>_<12hex> files).
- Lock paths avoid collision with harness mkdir-locks (dedicated .chezmoi-seed.lock for Claude/Pi/Codex; Grok non-destructive <>).
- `umask 077` + final chmod for 0600 stores.
- Doc kept as decision record (`.chezmoiignore` covers `docs/` dir; repo-only).

## 3. Verification Performed
- Real per-harness verification in throwaway HOME + full-path binaries + simulated worktree cwd: actual session start for each (recorded logs in task data dir show no "trust dialog" or permission prompt, clean operational exit 0).
- Script dry-runs, idempotency with simulated runtime state, jq-missing (now fail-soft warning + exit 0), lock/read-back, Kimi hash derivation, Codex append after render, and `chezmoi managed`/`execute-template` all confirmed.
- Doc claims now match code (locks, grants, Kimi hash verified, no template pointer for Codex).

Artifacts: task data dir (verification-*.log with real sessions).

## 4. Explicit Limitation Statement
- **Codex drift tradeoff**: [projects] seeding is in the run_after script (not the authoritative render) so runtime grants survive; this causes "has changed since chezmoi last wrote it" drift on interactive `chezmoi apply` (resolved with `--force` in fleet cron that re-renders then re-seeds). No template clobber option adopted.
- **Worktrees**: Live-verified in throwaway HOME with real binaries: linked worktrees resolve trust to their own git root path (not main repo), so seeded primary paths do not cover fresh `~/.treehouse/<host>/<n>/<repo>` slots. Only the two primary paths are seeded; no worktree slot is enumerated or covered (Pi's `$HOME` grant is the exception). No blanket bypass.
- Kimi fully seeded (hash derivation verified and implemented).
- Pi $HOME grant covers all descendants (including worktrees).

See `run_after_seed-harness-trust.sh.tmpl` (Kimi/Codex/Grok/Pi/Claude seeding with locks/read-back/fail-soft), and git history for details. All per captain intent and 005.msg/007.msg decisions.
