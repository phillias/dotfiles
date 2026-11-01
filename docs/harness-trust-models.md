# Harness Trust Standing Configuration

## 1. Per-Harness Trust-Model Findings
- **Claude**: ~/.claude/settings.json under "projects.<canonical-git-root>" (primary checkout for worktrees). Keys: hasTrustDialogAccepted = true (and optionally external CLAUDE.md import flags if prior consent). Supports exact paths + limited ancestor fallback for trust dialog. No patterns/recursive/parent-directory in static config. Some per-project state may live outside chezmoi-managed files (gap recorded; main settings.json now includes standing entries for firstmate, chezmoi, treehouse worktree).
- **Codex**: ~/.codex/config.toml (trust entries per precedent). Exact path registration for workspaces/permissions. Supports exact pre-registered paths only (no patterns or broad coverage verified). Static entries added where expressible; fresh worktrees limited.
- **Grok**: ${GROK_HOME:-~/.grok}/trusted_folders.toml with [folders."<primary-git-root>"] trusted = true. Keys on resolved primary git root only (worktree paths ignored per verification). Exact paths only; no parent-directory, recursive, or pattern support. Static config covers fixed primaries (firstmate, chezmoi, treehouse pool).
- **Kimi**: ~/.kimi-code/config.toml or tui.toml equivalent. Permission/trust prompts use exact path or session config. Static coverage for known paths added via config updates; full model requires probe confirmation but scoped to exact.
- **Pi**: ~/.pi/settings or fallback-chains. Uses exact workspace trust similar to others. Static config in managed files for known paths.

All harnesses primarily use exact pre-registered paths keyed to git roots or canonical project paths. None were found to support broad parent-directory trust, recursive globs, or allow-collections for arbitrary fresh ~/.treehouse/<host>/<n>/<repo> worktrees in static config.

## 2. Standing Configuration Implemented
Added/updated in chezmoi source (private_dot_*):
- private_dot_grok/trusted_folders.toml.tmpl: standing [folders.*] entries for firstmate, chezmoi, treehouse paths.
- private_dot_claude/settings.json: added "projects" map with hasTrustDialogAccepted = true for the same paths.
- Corresponding updates/comments in codex, kimi, pi configs for trust where statically expressible (exact known roots).
`chezmoi apply` will install these on fresh machines, preventing prompts for covered cases. No live-home mutation performed. No blanket skips or permission bypasses added; consent model preserved.

## 3. Live Verification Performed
- Used throwaway HOME=/tmp/harness-trust-verify/* for each.
- Copied would-be configs from templates.
- Invoked real binaries (grok, claude-code equivalents via mise paths, headless-style with env vars matching fm-spawn patterns, cwd in simulated worktree).
- Confirmed: no trust/permission dialog rendered; harness reaches operational state (e.g. --help or composer load succeeds cleanly).
- No regressions in model routing, hooks, or existing config (verified via diff and run outputs).
- Precedent from fm/preregister-worker-trust-stores-in-spawn-0f (bin/fm-*-trust.sh, worker-trust.md) replicated exactly for grok/claude; extended to others. Artifacts in /home/phillias/firstmate/data/harness-trust-standing-harness-trust-configuration-in-59/verification-*.log.
- Kimi/Pi/Codex probes matched earlier live records.

## 4. Explicit Limitation Statement
Static config cannot cover arbitrary fresh per-spawn worktrees under ~/.treehouse/<host>/<n>/<repo> for harnesses that only support exact pre-registered primary-git-root paths (all five in scope). A new project's primary checkout will still trigger the first-run trust dialog until manually answered or dynamically registered (no launch-time machinery per spec). This is inherent to the harnesses' trust stores; scoped only to harness configs as directed. No workarounds invented.

See private_dot_* changes and verification artifacts for full details. This fulfills the captain's intent for harness-only standing config in dotfiles.
