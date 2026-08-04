# Eval-harness across all opencode skills — regression-testing rollout

- **Date**: 2026-08-04
- **Status**: draft (needs Momus review before execution)
- **Owner**: Sisyphus
- **Trigger**: eval-harness installed (clone at `~/tools/eval-harness`, bin symlink `~/.local/bin/eval-harness`); zero behavior-regression coverage on 74 CE skills + 15 config skills today.

## Goal

Baselined, regression-tested opencode skills: any edit to a skill (or a silent model/plugin drift) that changes its behavior is caught, attributed to one of 4 causes (SKILL_CHANGED / FIXTURE_STALE / MODEL_CHANGED / UNKNOWN_DRIFT), and triaged with a 6-field FAIL record — before it ships to real sessions.

## Context (verified facts)

- **Skills inventory**: 74 skills in `~/.agents/skills/` (CE + omo + ops), 15 in `~/.config/opencode/skills/`, 2 in `~/.cache/opencode/skills/`. All `~/.agents/skills` are chezmoi-managed (`dot_agents/skills/`).
- **Skills-root resolution gap**: eval-harness resolves `OPENCODE_SKILLS_ROOT` as env > walk-up `.opencode/skills/` > `~/.config/opencode/skills`. The CE skills live in `~/.agents/skills/` — **NOT in the default path**. `OPENCODE_SKILLS_ROOT` is currently unset → eval-harness would target the wrong 15 skills. Must set it (or per-project `.opencode/skills` symlink).
- **Registry**: default `~/.config/opencode/eval-harness/registry.yaml`, `enabled_repos: []` — per-repo opt-in; `enable-workspace` bulk-registers.
- **Config layer**: `EVAL_HARNESS_CONFIG` env or walk-up `.opencode/eval-harness.yaml` (keys: `model`, `budget_usd`, `max_seconds`).
- **Mechanics**: 6 check kinds (5 deterministic: shell-expect, file/contains, JSON-path, …; 1 optional LLM judge), 3-sample byte-hash stability on FAIL, 4-class attribution via env SHA capture, `$-cost` gating, exit 12 = regression, 13 = harness error. Commands: `baseline` / `run` / `accept` / `promote` / `status` / `trend` / `twotier`. Pre-push hook via `install-hooks.sh`.
- **Cost model**: `spawn` runs `opencode run` with a pinned model. Free-tier candidates exist (see Decisions).

## Decisions

### D1. Skills-root
Set `OPENCODE_SKILLS_ROOT="$HOME/.agents/skills"` for eval runs (env in the eval wrapper script, NOT in opencode.json — eval-harness only). Rationale: CE skills are the ones with drift risk; config-dir skills are thin.

### D2. Eval model (pin it)
`EVAL_MODEL=opencode-zen/deepseek-v4-flash-free` — free, 131K, documented reliable tool recovery (opencode-omo-config skill). Pinned in `.opencode/eval-harness.yaml` so `MODEL_CHANGED` attribution is meaningful (model drift must be an *upstream* change, not a config change).

### D3. Cost ceiling
`budget_usd: 0.10` per run, `max_seconds: 300` per case. 3-sample stability runs only on FAIL. Prose skills use `--mode=2tier` (cheap smoke → escalate to LLM judge only on FAIL). Rationale: $-cost gating is a first-class harness feature; free model keeps the ceiling rarely hit.

### D4. Eligibility tiers (what gets baselined)
- **Tier 1 — structured-output, deterministic** (Phase 1): skills whose behavior is a CLI/script with checkable output: `axi`, `ce-compound` + `ce-compound-refresh` (ship `validate-frontmatter.py` — deterministic file checks), `ce-release-notes`, `ce-sessions`, `ce-setup` (health probe), `omo-ce-bridge`, `self-learning` (cues.tsv shape), `ce-commit` (message shape).
- **Tier 2 — command/CLI wrappers** (Phase 2): `docker-axi`, `gh-axi`, `pg-axi`, `redis-axi`, `libsql-axi`, `mariadb-axi`, `godoxy-axi`, `crowdsec-axi`, `bws-axi`, `quota-axi`, `chezmoi-axi`, `dotfiles`. Each = one case: invoke the CLI's read-only subcommand, assert TOON-shape output (shell-expect `expect_regex` on `toon` fields / `expect_min`).
- **Tier 3 — prose/LLM-judge** (Phase 3, optional): `ce-plan`, `ce-brainstorm`, `ce-strategy`, `ce-ideate`, `ce-doc-review`. 2tier mode only; needs `ANTHROPIC_API_KEY` for the judge — gate behind explicit enable.
- **Excluded** (document, don't baseline): interactive/UI (`ce-polish-beta`, `ce-test-browser`, `ce-test-xcode`), external-credential/network-bound (`gws-axi`, `cloudflare-*`, `ce-gemini-imagegen`, `ce-demo-reel`, `ce-slack-research`, `xspace-pipeline`, `last30days`, `bws-axi` write paths), firstmate-internal skills (`metadata.internal: true`).

### D5. Fixtures & cases live inside each skill
`~/.agents/skills/<skill>/eval/cases/*.yaml` + `fixtures/` — co-located with SKILL.md so edits and evals move together; chezmoi-tracked automatically. Case YAML: `runner: opencode`, `prompt:`, `checks:` (kind `shell`/`file`/`contains` with `expect_regex`/`expect_exact`), optional `sandbox: true` for score_shell.

### D6. Cadence
1. **Pre-push hook** (dotfiles repo + any repo touching `.agents/skills` or `.config/opencode/skills`): run changed-skill cases only (`skills-only scope, smoke tier` — the built-in trigger).
2. **Session-start smoke**: `eval-harness status` + baselined Tier-1 quick set, non-blocking (warn-only mode).
3. **Weekly full sweep**: all Tier-1/2 baselines, `promote` flipped to blocking after 2 clean weeks.

### D7. Triage protocol
FAIL → `attribute.sh` classification → 4-class action table: SKILL_CHANGED (fix or re-baseline), FIXTURE_STALE (`accept --case`), MODEL_CHANGED (pin model or re-baseline + decide), UNKNOWN_DRIFT (3-sample; flaky:true → investigate, stable → file issue). Never `promote` a FAIL; never delete a failing case.

## Phases

| Phase | Deliverables | Exit criteria |
|---|---|---|
| 0 | `~/tools/eval-harness` wrapper: `OPENCODE_SKILLS_ROOT` + `EVAL_MODEL` + budget envs; `.opencode/eval-harness.yaml` at dotfiles repo root; registry init + enable dotfiles repo | `eval-harness status` shows registry + root; 1 throwaway case passes |
| 1 | Tier-1 baselines: ≥1 case each (≥2 for `axi`, `ce-compound*`); pre-push hook wired | `eval-harness run --skill <t1>` green ×3 consecutive; intentional skill edit → FAIL → attributed correctly |
| 2 | Tier-2 baselines (read-only subcommands only) | all green; network-bound cases sandboxed or excluded |
| 3 | Tier-3 prose via 2tier (opt-in) | LLM-judge cases stable; cost ceiling never breached |

## Risks

- **Model drift masquerading as skill regression**: mitigated by pinned EVAL_MODEL + `env_delta` in FAIL schema.
- **Flaky CLI skills** (network/selfhost-dependent): Tier-2 read-only subcommands can hit godoxy/crowdsec state — excluded or `sandbox: true`.
- **Eval cost creep**: budget_usd ceiling + 2tier + stability-on-FAIL-only; free model.
- **Harness rot**: eval-harness is npm-unpublished (clone-installed) — pin the clone SHA; upgrades are manual `git pull` + re-baseline.

## Definition of done

Registry enabled; ALL Tier-1 skills baselined with ≥1 deterministic case; pre-push hook firing on skill changes; first real regression triaged through the 4-class pipeline; `eval-harness trend` shows a stable green baseline across 2 weekly sweeps.

## Open questions

1. Pre-push hook scope: dotfiles repo only, or every repo with `~/.agents/skills` changes (hook path is per-repo; `enable-workspace` bulk-register)?
2. Should the wrapper live in `~/.local/bin/eval-harness` (already symlinked) or as a `dot_bin/eval-harness` chezmoi entry (currently excluded — install artifact)?
