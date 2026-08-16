# Archived OmO-era Material (provenance only)

Superseded OpenCode-Modification-Orchestrator (OmO) design material. Retired 2026-08-09: the OmO plugin was purged from opencode.json + node_modules; `~/.omo/omo.jsonc` recovered config seeded opencode-fallback.jsonc. Since 2026-08-09 `~/.omo/omo.jsonc` is **provenance only** — do not edit it for routing. This file preserves history; the live design lives in `DESIGN.md`, `AGENTS.md`, and `~/.config/opencode/opencode-fallback.jsonc`.

## Model Selection Priorities (SUPERSEDED 2026-08-12 by paid-first)

OmO-era tiered agent model assignment:

- **Tier 1 Quality Agents** — Sisyphus, Prometheus, Metis, Momus (xhigh), Oracle (xhigh), Hephaestus, Ultrabrain (xhigh), Visual-Engineering — each with primary + fallback chains.
- **Tier 2 High-Volume Utility** — Sisyphus-Junior, Atlas, Explore, Librarian, Quick, Unspecified-Low.
- **Tier 3 Specialized** — Multimodal-Looker (Together Bonsai single-shot), Artistry (HF gemma-4), Writing (Cloudflare llama-3.3-70b).

## Config File Hierarchy (OmO-era)

- **User scope:** `~/.omo/omo.jsonc` authoritative under its `[opencode]` block.
- **Project scope:** `<project>/.omo/omo.jsonc` overrides user scope.
- **Deep-merge order:** defaults → user → project.
- Legacy `oh-my-openagent.jsonc` NOT read (orphan).
- Key lessons: 400 must stay in `retry_on_errors`; 2026-08-01 orphan-edits incident (agent/category edits landed in the wrong file).

## Key decisions (with OmO-era provenance)

| # | Decision |
|---|---|
| 1 | Big Pickle primary |
| 2 | Gemma4-12B Multimodal (later replaced — see PROVIDERS.md broken-models) |
| 3 | free→subsidized→pay global fallback — **SUPERSEDED by paid-first (2026-08-12)** |
| 4 | OmO the only plugin — **RETIRED 2026-08-09** |
| 5 | Go pool merged Jun |
| 6 | MoE preference |
| 7 | auto-compaction false |
| 8 | single global config layer |
| 9 | GPT model routing needs `opencode/` prefix |
| 10 | Ternary Bonsai REVERTED 2026-07-31 (single-shot only) |

## OmO-era architecture tree

`~/.omo/` contained: `omo.jsonc` (the OmO config), `migration-backup/` (recovery from pre-single-root), `plans/`. Agent/category routing edits went to omo.jsonc — SUPERSEDED. The tree survives only as provenance; the opencode-side tree (opencode.json, opencode-fallback.jsonc, dispatch-rules.json, plugins/, scripts/) is the live architecture.

## Legacy file status

- `~/.omo/omo.jsonc` — provenance only
- `oh-my-openagent.jsonc` — LEGACY ORPHAN (never read)
- `migration-backup/` — recovery history
