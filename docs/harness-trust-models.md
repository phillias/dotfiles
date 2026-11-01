# Harness Trust Standing Configuration

## 1. Per-Harness Trust-Model Findings
- **Claude**: ~/.claude.json (real store per reviewer/binary; settings.json is hooks-only and not consulted for trust). "projects.<primary-git-root>" with hasTrustDialogAccepted = true. Exact paths only (limited ancestor fallback in some checks). Seeded non-clobbering via run_once (jq merge; preserves other keys/runtime state).
- **Grok**: ~/.grok/trusted_folders.toml with [folders."<primary-git-root>"] trusted = true. Exact primary git root only (worktree paths ignored). Seeded non-clobbering via run_once (grep-append if absent; preserves runtime appends).
- **Codex**: ~/.codex/config.toml or state (exact path entries per precedent). Exact only.
- **Kimi**: ~/.kimi-code/config.toml (exact workspace/session config).
- **Pi**: ~/.pi config (exact workspace trust).

All exact-path only. No patterns, parent-directory, recursive, or allow-collections for arbitrary fresh ~/.treehouse slots (limitation).

## 2. Standing Configuration Implemented
- run_once_seed-harness-trust.sh.tmpl: idempotent non-clobbering seeding for .claude.json (jq) and trusted_folders.toml (append-if-absent); uses {{ .chezmoi.homeDir }}; for known primaries (firstmate, chezmoi). Placeholders for Codex/Kimi/Pi real surfaces (extended where expressible).
- Removed projects from private_dot_claude/settings.json; removed private_dot_grok/trusted_folders.toml.tmpl (authoritative render avoided); removed comment-only hunks from codex/kimi/pi tmpl and pi fallback-chains.json.tmpl; removed never-matching treehouse-pool entry.
- docs/harness-trust-models.md relocated + ignored (repo-only; not chezmoi-managed to ~); contains only backed claims.
- Applied on normal chezmoi apply (run_once executes once). No live-home mutation. Consent model intact; no blanket bypass.

## 3. Live Verification Performed
- Throwaway HOME + seeded configs + full-path binaries (e.g. mise install paths to avoid shim/mise errors in isolated HOME) + simulated git worktree cwd + timeout/grep for dialog text.
- Confirmed: no "trust" or "Do you trust" dialog in output; harness reaches operational state cleanly.
- No regressions (hooks, models, routing, config verified via diff and runs).
- Real artifacts in data/verification-*.log (full runs, no mise errors; matched firstmate branch precedent).
- Kimi/Pi/Codex limited per their models (exact-only; probes in logs).

## 4. Explicit Limitation Statement
Static seeding cannot cover arbitrary fresh per-spawn worktrees under ~/.treehouse/<host>/<n>/<repo> (all 5 harnesses exact primary-git-root only; new primaries not pre-known). Treehouse slots trigger dialog until answered. Honest limitation documented; no invented syntax, workarounds, or blanket bypass. Scoped only to harness configs per spec.

See run_once_seed-harness-trust.sh.tmpl, docs/harness-trust-models.md, verification logs, and git history for full details. Fulfills captain intent.
