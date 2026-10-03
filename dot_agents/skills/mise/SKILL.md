---
name: mise
description: >
  Fleet conventions for mise (mise-en-place), the version manager behind herdr,
  claude, gh-axi, node and other CLI tools. Covers the upgrade flow (chezmoi
  pin -> chezmoi apply -> mise-sync reconcile -> latest alias re-points), the
  path strategy (shims for PATH discovery, installs/<tool>/latest/<bin> for
  pinned references), the bans (versioned-dir refs, ~/.local/bin duplicate
  symlinks, in-tool self-updaters), and the phantom-version failure mode where
  non-exec probes report mise's own CalVer as the tool's version.
  Use when bumping or adding tool versions, wiring daemons/systemd units to
  mise-managed binaries, diagnosing "wrong version" or "two installs" reports,
  or choosing which path (shim vs latest vs versioned) a config should pin.
---

# mise

Fleet rules for mise-managed tools. Sources of truth:

- Pins: `~/.config/mise/config.toml` — chezmoi source `dot_config/mise/config.toml`
  (plain TOML, pins live in `[tools]`).
- Reconcile hook: `run_onchange_mise-sync.sh.tmpl` — fires on `chezmoi apply`
  when the manifest fingerprint changes: reports drift with
  `mise install --dry-run-code`, then provisions additively via `mise install`.
  Never prunes (that is a deliberate manual `mise prune`).

## Layout

layout[5]{what,where}:
  mise binary,~/.local/bin/mise (per-host build — mise --version differs per host; do not expect parity)
  version pins,~/.config/mise/config.toml [tools] (chezmoi-managed)
  shims,~/.local/share/mise/shims/<tool> -> the mise binary (resolves by argv0)
  installs,~/.local/share/mise/installs/<tool-id>/<version>/ (tool-id = declared id\, e.g. node or github-herdrdev-herdr)
  aliases,installs/<tool-id>/latest (-> newest installed) plus partial semver aliases (0.9\, 0) where applicable

## Golden rules

1. **PATH / discovery -> shims.** `~/.local/share/mise/shims/<tool>` is mise's
   intended interface. Exec'ing a shim resolves the pinned version and prints
   the true tool version.
2. **Pinned direct references -> `latest` alias.** Env vars, systemd unit
   paths, and scripts that must name a binary use
   `~/.local/share/mise/installs/<tool-id>/latest/<bin>` — the alias re-points
   on every install, so the reference survives upgrades.
3. **Never reference versioned dirs** (`.../<version>/...`) — `mise prune`
   deletes them on upgrade.
4. **Never duplicate a shim** with an ad-hoc `~/.local/bin/<tool>` symlink —
   phantom-install detectors (e.g. moshi) report it as a second install.
5. **Never use a tool's built-in self-updater under mise** (e.g. `herdr update`,
   channel systems) — it fights the mise layout. Upgrades flow through the pin.

## Upgrade flow

1. Edit the pin: `chezmoi edit ~/.config/mise/config.toml`.
2. `chezmoi apply` — mise-sync reports drift, then installs additively.
3. Verify: exec the shim (`<tool> --version`) and confirm `latest` re-pointed
   (`ls -l ~/.local/share/mise/installs/<tool-id>/`).
4. Restart any daemon or session holding the old binary open — running
   processes keep the old version until restarted.

Caveat: `latest` tracks the newest *installed* version, not the pin. The
pin-bump-then-apply flow keeps them in sync; installing a version without
bumping the pin diverges them.

## Phantom-version failure mode

Non-exec version probes (stat/readlink/file-content chains, as moshi uses)
that follow a shim land on the mise ELF and report **mise's own CalVer** as
the tool's version — e.g. "herdr (2026.9.1)" on a host whose `mise --version`
is exactly 2026.9.1, next to a real herdr 0.9.0. Exec'ing the shim prints the
truth. Diagnosis: compare the reported version to `mise --version` on that
host; a match means shim chain, not a second install.

Verified case study (2026-10-02, three hosts): memories
`f-2026-10-03-moshi-phantom-double-herdr-install` and
`h-2026-10-03-mise-path-strategy-shims-for-discovery-l`.

## Daemons / systemd

Service units on this fleet keep a minimal `PATH=/usr/local/bin:/usr/bin:/bin`
— daemons do not need the shims (the moshi-hook daemon works with zero herdr
visible to it; the interactive session's herdr server serves the data).

If a daemon genuinely must call a mise-managed tool, point an env var at the
`latest` alias via a systemd drop-in (drop-ins survive the tool rewriting its
unit; respect the path-parity rule — `%h`, never a literal home path):

```ini
# ~/.config/systemd/user/<svc>.service.d/<tool>.conf
[Service]
Environment=TOOL_PATH=%h/.local/share/mise/installs/<tool-id>/latest/<bin>
```

In the 2026-10 incident no env var was needed on any host — removing the
duplicate symlink and keeping the minimal unit PATH fixed everything.

## mise skills (packslip channel)

mise has a native skill-distribution channel for **packslip-installed tools**:
`mise skills ls` lists skills active tools declare;
`mise skills sync --dir ~/.agents/skills` symlinks them where agents read
skills (settings: `skills.dir`, `skills.auto_sync`, `skills.fetch`,
`skills.prune`). Links point into the active version's install dir — re-sync
after a version change. Handwritten skills in the target dir are preserved.
This distributes skills *declared by tools*; it is not a general mise-usage
skill.

## References

- Docs: https://mise.jdx.dev (dev tools, packslip resources, `mise skills`)
- Official mise skill status: jdx/mise discussion #6575 (none shipped in-repo yet)
- Community: kinoward/agent-skills "mise-guide" (human-written, portable);
  agentskillexchange "mise-dev-tool-version-manager" (auto-extracted, shallow)
