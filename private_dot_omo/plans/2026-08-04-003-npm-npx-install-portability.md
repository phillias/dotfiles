# npm/npx installs for opencode+OmO — portable chezmoi/dotfiles design

- **Date**: 2026-08-04
- **Status**: draft (needs Momus review before execution)
- **Owner**: Sisyphus
- **Trigger**: this session installed 8 plugins/tools across 4 mechanisms (opencode CLI, npm-global, git clones, go install) and hit registry/resolver/tracking inconsistencies. No canonical, portable install story exists for the opencode+OmO plugin stack.

## Goal

A single, chezmoi-committed manifest + idempotent reconciler that declares every opencode+OmO npm/npx/tool install (plugin or CLI) — handling the three install locations (global cache / user prefix / working-directory), pinning, verification, and cross-references — while keeping node_modules and other large derived artifacts out of the dotfiles repo and off every machine that applies them.

## Context — convoluted findings (session 2026-08-04, verified)

**F1. Three install locations, three different semantics**
| Location | Path | Mechanism | Referenced by |
|---|---|---|---|
| Global (opencode plugin cache) | `~/.cache/opencode/packages/<pkg>@latest/` | `opencode plugin <pkg> -g` (bun resolver) | `opencode.json` `plugin[]` by npm name (`opencode-snip`, `opencode-ntfy.sh`, `opencode-log-sanitizer`, `envsitter-guard`, `opencode-telemetry`) |
| User (npm prefix) | `~/.npm-global/lib/node_modules/` | `npm install -g` | `plugin[]` via `{env:HOME}/.npm-global/...` absolute path (`@tarquinen/opencode-dcp`) |
| Working directory | `<project>/.opencode/opencode.json` | per-project config | project-scope plugins; overrides global |

**F2. `opencode plugin` is not a universal installer.** It uses bun's resolver, which fails on some peer trees: `@tarquinen/opencode-dcp@latest` → "unable to resolve dependency tree" (its `@opentui/*` + `solid-js` peers), deterministically, retried 3×. `npm install -g` succeeds on the same package. Corollary: **when the opencode CLI fails, npm-global + `{env:HOME}` path entry is the workaround** — and the config entry stays portable (no hardcoded home, Parity Rule).

**F3. npm badges lie.** `opencode-toon-config-plugin` (404) and `@nano-step/eval-harness` (404) are not published despite README npm badges. Both required git clones (`~/.config/opencode/plugin/…`, `~/tools/eval-harness`). Registry state must be verified at install time, not trusted from READMEs.

**F4. Cache pollution on failed installs.** The bun fetcher writes cache entries *before* resolution succeeds: `~/.cache/opencode/packages/opencode-toon-config-plugin@latest/` exists despite the 404, and a literal `{env:HOME}` directory was created during the DCP resolution failure (the resolver treated the config string as a filesystem path). Cache is derived state — safe to `rm -rf` and re-fetch.

**F5. Binary/symlink artifacts are derived, not dotfiles.** `octm` (from telemetry's `node_modules/.bin`), `eval-harness` (clone entry `scripts/eval/run.sh`), `snip` (`go install` → `~/go/bin`, toolchain auto-switched to go1.25.12). All re-creatable; **decision: not chezmoi-tracked** (consistent with the node_modules/package-lock policy).

**F6. Third-party clones are nested git repos.** `~/.config/opencode/plugin/{opencode-toon-config-plugin,shell-strategy}` — chezmoi cannot manage nested repos → `.chezmoiignore` on `plugin/` + reproducibility notes (toon patch = 2 src edits + `bun run build`). The patch is currently only versioned in the PR body.

**F7. node_modules gap.** `~/.config/opencode/plugins/node_modules` was unmanaged AND unignored (unlike `profiles/*/node_modules` which is ignored) — fixed 2026-08-04. Audit rule: every derived dir must be either ignored or explicitly unmanaged-by-policy.

**F8. The auto-load dir has its own dependency graph.** `~/.config/opencode/plugins/package.json` pins `@opencode-ai/plugin: 1.14.39` + `@types/node` + `tsconfig.json` — the `.ts` plugins compile against these. `plugins/package.json`/`tsconfig.json` are tracked; `package-lock.json` + `node_modules` ignored. Version bump of `@opencode-ai/plugin` is a dotfiles change.

**F9. Load-order cross-reference.** `opencode.json` `plugin[]` is the ONLY load-order source (npm names + `./plugins/*.ts` auto-load + `./plugin/<clone>` + `{env:HOME}` absolute). Auto-load dir `.ts` files load regardless of the array; the array entries for them are redundant-but-harmless (they exist in the array as documentation). Changing load order = editing `plugin[]`.

**F10. Portability rules already in force.** `{env:HOME}` substitution works in `plugin[]`; the Parity Rule forbids hardcoded home paths in committed files; `$HOME`/`~`/`{{ .chezmoi.homeDir }}`/`%h` per target. Any new install artifact must satisfy this.

## Portability mechanisms (npm-native vs chezmoi)

**M1. `package.json` + lockfile = npm's own portable instruction.** `node_modules` is derived, never tracked; `pnpm install`/`npm ci` reproduces the tree from two files. Already partial in force: `plugins/package.json` pins `@opencode-ai/plugin: 1.14.39` (tracked). **Gap**: the repo convention is pnpm (`pnpm-lock.yaml` managed, per `.chezmoiignore`), but `plugins/` currently uses npm (`package-lock.json` ignored) — switch `plugins/` to pnpm so the auto-load dir deps become lockfile-reproducible cross-machine.

**M2. Global-prefix manifest for `npm install -g`.** Treat `~/.npm-global` as a project root: a tracked pinned package list (or `package.json` in the prefix) + idempotent script runs `npm install -g --prefix "$HOME/.npm-global" <pinned list>`. **Pin versions in the instruction** — bare names drift across machines and time.

**M3. `npx` = zero-install portability.** Shebang `#!/usr/bin/env -S npx --yes --package <pkg>@<ver> <pkg> "$@"` in committed `dot_bin/` scripts runs a tool with **no install state at all**. Trade-offs: cold-start latency + network dependence + cache re-fetch on miss. Best for rarely-run tools; wrong for hot-path CLIs.

**M4. chezmoi's "instructions that execute".** `run_once_*.sh.tmpl` = run once per machine on first apply (marker-idempotent); `run_onchange_*.sh.tmpl` = re-run when its fingerprint changes (the existing cleanup-and-sync pattern). Both must be TTY-safe (`--yes`/`--force`, no prompts — the sibling hook's TTY failure is the cautionary tale).

**M5. `.npmrc` tracked.** Registry, `prefix=~/.npm-global`, `fund=false`, `save=false` — committed, applies everywhere.

**Boundary rule (portability test).** An install instruction is portable iff (a) it pins versions, (b) it contains no absolute home path (`$HOME`/`~`/`{{ .chezmoi.homeDir }}`/`{env:HOME}` per target), (c) its output lands in a chezmoi-ignored or explicitly-unmanaged path. Anything failing (a)–(c) is not a dotfile.

**Stack mapping (instruction → tracked / state → ignored):**
| Install | Portable instruction (tracked) | State (ignored) | Mechanism |
|---|---|---|---|
| Auto-load dir deps | `plugins/package.json` + `pnpm-lock.yaml` (M1) | `plugins/node_modules`, `package-lock.json` | `pnpm install` via run_onchange |
| Global npm tools (codeburn, …) | pinned list in `scripts/install-globals.sh` (M2) | `~/.npm-global/lib/node_modules` | run_onchange, `--prefix $HOME/.npm-global` |
| One-shot CLIs | `npx --package=<pkg>@<ver>` shebang scripts (M3) | npx cache | zero-install |
| opencode plugins (cache) | `plugin-manifest.yaml` (D1) + `{env:HOME}` config refs | `~/.cache/opencode/packages` | reconciler (D2/D6) |
| Clones + derived bins (toon, eval-harness, snip) | manifest entries + reproducibility notes | `plugin/`, `~/tools`, `~/go/bin`, bin symlinks | manifest + `.chezmoiignore` |

## Decisions

### D1. Single source of truth — manifest in dotfiles
`dot_config/opencode/plugin-manifest.yaml` (chezmoi-tracked). Schema:
```yaml
schema_version: 1
plugins:
  - id: opencode-snip            # npm name OR local id
    source: opencode-cli         # opencode-cli | npm-global | clone | native
    pin: latest                  # npm dist-tag, version, or clone SHA
    verify: cache-dir            # cache-dir | npm-global-pkg | clone-built | file-exists
  - id: "@tarquinen/opencode-dcp"
    source: npm-global           # bun resolver fails (F2) — install via npm -g
    pin: 3.1.14
    verify: npm-global-pkg
  - id: opencode-toon-config-plugin
    source: clone                # npm 404 (F3)
    url: https://github.com/mmynsted/opencode-toon-config-plugin
    pin: main
    post_install: "bun run build" # dist/ not committed upstream
    verify: clone-built
  - id: octm
    source: derived              # bin from a plugin's node_modules/.bin (F5)
    from: opencode-telemetry
    verify: bin-exists
```

### D2. Install-method mapping (authoritative)
`opencode-cli` → try first; on resolver failure fall back to `npm-global` + `{env:HOME}` path entry (F2). `clone` → `git clone` to `~/.config/opencode/plugin/<id>` (ignored in chezmoi) + optional `post_install` + array entry `./plugin/<id>`. `native` → committed `.ts` in `plugins/` (F8). `derived` → symlink into `~/.local/bin`, never tracked (F5). Working-directory installs stay in `<project>/.opencode/opencode.json`, never in the manifest (F1).

### D3. Tracked vs derived boundary (audit rule)
**Tracked**: manifest, `opencode.json` `plugin[]`, `plugins/*.ts`, `plugins/package.json`+`tsconfig.json`+`pnpm-lock.yaml` (M1), `scripts/install-globals.sh` (M2), committed npx-shebang scripts (M3), `.npmrc` (M5), `.chezmoiignore` rules, any committed patch docs.
**Derived/ignored**: `node_modules/**`, `package-lock.json` (in plugins/, replaced by pnpm), `~/.cache/opencode/packages/**` (rm-able, F4), `plugin/` clones + their `dist/`, `~/.npm-global/**`, `~/.local/bin` symlinks, `~/go/bin` binaries, `~/tools` clones.
Every derived path must be covered by an ignore rule or an explicit "never add" policy (F7 audit). Enforced by the portability test (a)–(c).

### D4. Machine portability
Manifest and reconciler use `$HOME`/`~` only. Any machine-specific value (npm prefix override, OPENCODE_CONFIG_DIR) enters via chezmoi `.tmpl` or env — never a committed absolute path (F10). Multi-profile branches (master/personal/work) inherit the same manifest; per-machine deltas live in `.tmpl`.

### D5. Verification gate
Reconciler checks each entry's `verify` (cache dir exists / npm-global pkg resolvable / clone present + `dist/` fresh / bin symlink target exists) and prints a TOON diff (AXI: pre-computed aggregates, definitive empty state "all green"). Optional `--smoke` runs one `opencode run` per new plugin.

### D6. Reconciliation as a chezmoi run_onchange
New `run_onchange_install-plugins.sh.tmpl` (sibling of the existing cleanup-and-sync hook) with its own install fingerprint (manifest + `plugin[]` + clones' SHAs). Idempotent, `--yes`/non-interactive (TTY-safe — the existing hook already fails on TTY prompts), `--force` where npm needs it. Never runs `chezmoi add` (state lock, same constraint as the sibling hook).

## Phases

| Phase | Deliverables | Exit criteria |
|---|---|---|
| 0 | Capture current state (this session's findings F1–F10) | done — this document |
| 1 | Manifest schema + encode the 14-entry `plugin[]` + 3 derived artifacts (snip, octm, eval-harness) + 2 clones; **switch `plugins/` to pnpm** (M1, track `pnpm-lock.yaml`); **add pinned `scripts/install-globals.sh`** for global npm tools (M2) | manifest matches live installs 1:1; `verify` passes; `pnpm-lock.yaml` committed; `install-globals.sh` idempotent |
| 2 | Reconciler script (`~/.config/opencode/scripts/plugin-reconcile.sh`, chezmoi-tracked) implementing D2/D5; wire `install-globals.sh` into a run_onchange (M2/M4) | `plugin-reconcile` reports all-green; TOON output; exit 0/1/2 per AXI; global tools reconcile is a no-op when the pinned list is unchanged |
| 3 | `run_onchange_install-plugins` hook wiring (D6) | fresh-machine apply installs the full stack; second apply is a no-op |
| 4 | Portability proof: apply dotfiles on a second machine (or `chezmoi apply --dry-run` audit) | no node_modules/absolute-path leaks; all `verify` green |

## Risks

- **Registry drift**: npm 404s (F3) recur — reconciler must surface 404 as a structured error with the clone fallback hint, not fail silently.
- **Bun peer-resolution failures** (F2) on future plugins — mapping fallback is documented; reconciler attempts `opencode-cli` then `npm-global` automatically.
- **`latest` churn** breaking baseline behavior — pin by version in the manifest for quality-critical plugins (DCP), keep `latest` for tools where churn is wanted.
- **Nested-repo patch loss** (F6) — the toon patch moves into a committed `docs/` note or a tracked patch file in dotfiles (Phase 1), so clones stay disposable.
- **Hook TTY prompts** — reconciler must be fully non-interactive (D6); the sibling hook's failure mode is the cautionary tale.

## Definition of done

Manifest + reconciler committed; live stack (14 plugin-array entries, 2 clones, 3 derived bins) matches the manifest with `verify` all-green; `run_onchange_install-plugins` performs a clean install on a fresh checkout and no-ops on the second run; `plugins/` deps reproducible via `pnpm-lock.yaml`; global npm tools reproducible via pinned `install-globals.sh`; no `node_modules`, `package-lock`, clone repo, or absolute home path appears in the dotfiles repo beyond the documented boundary.

## Open questions

1. Manifest format: YAML (readable, diff-friendly) vs JSON (schema-validatable by opencode tooling)? Lean YAML.
2. Should `plugin[]` entries be generated from the manifest at reconcile time (single source of truth) or remain hand-maintained with the manifest as documentation? Lean: manifest is truth, reconciler patches `plugin[]` via `opencode plugin`/edit — but this touches `opencode.json` on every run, so gate behind `--update-config`.
3. Second-machine proof: is there a live second host to validate Phase 4, or is `chezmoi apply --dry-run` + a container smoke acceptable?
4. `plugins/` → pnpm migration (M1): do it now (lockfile churn + node_modules rebuild in one shot) or piggyback on the next `@opencode-ai/plugin` bump?
5. `.npmrc` (M5): global scope — commit `prefix` + `fund=false`, or also enforce a registry allowlist (only `registry.npmjs.org`)?
