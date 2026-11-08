# UI-Design Skill Benchmarks (Nov 2026 survey)

Empirical evidence on which agent UI-design skills to reach for. No canonical benchmark
exists, but four independent small-N tests converge. All are single-run directional tests —
treat as signal, not proof.

## Benchmarks

### Happycapy Skill Arena — frontend-design (happycapy.ai/skill-arena/frontend-design)
6 skills x 3 tasks on Sonnet 5, 2 blind AI judges, 5 scoring axes.

- Three-way tie at 8.0: `frontend-design` (Anthropic; best all-rounder — dashboard +
  portfolio), `design-taste-frontend` (taste-skill; task-completeness 9.0; ~87K-char,
  token-heavy SKILL.md), `superdesign` (won the SaaS-landing task).
- `web-design-guidelines` (Vercel) scored 6.8 — it is an auditor/checklist, not a
  look-generator.

### AgentCraft 8-skill test (agentcraft.dev, Oct 30 2026)
Covers `impeccable` and `hallmark` directly.

- `frontend-design`: steadiest output, cheapest.
- `taste-skill` + `impeccable`: strongest visual point of view.
- `hallmark`: most distinctive results, but read 15 files / $0.25 on one brief — heavy.
- `impeccable` + `make-interfaces-feel-better`: polishers, not generators.

### designskill.qiaomu.ai 10-task lab (8 variants incl. full impeccable)
- `impeccable`'s deterministic `detect.mjs` (45 rules, non-LLM) was uniquely reliable as a
  **pre-ship gate** — the only reproducible check among the skills tested.
- `frontend-design` won the creative tasks; `web-design-guidelines` was best for a11y.

### ui-bench.dev
Model-level (not skill-level) landing-page leaderboard — use it to pick the model under
the skill, not to pick the skill. Top: Opus 4.7 (84 UX avg).

## Consensus / house guidance

| Need | Reach for |
|---|---|
| Creative visual POV (generating a look) | `taste-skill` (`design-taste-frontend`) or `frontend-design` |
| Polish / hardening an existing UI | `impeccable` (polisher, not generator) |
| Deterministic pre-ship gate in CI | `npx impeccable detect` (non-LLM, 45 rules) |
| A11y audit | `web-design-guidelines` (Vercel) — as auditor only |
| Token-tight sessions | `frontend-design` (cheap, steady); avoid `hallmark` (15-file reads) |

Reddit r/ClaudeCode threads comparing impeccable vs taste vs frontend-design are mixed —
consistent with the bench result that they occupy different roles rather than one ranking.

## Implication for the house stack

- Keep `impeccable detect` as the CI gate (already mandated in SKILL.md taste guardrails).
- For generated looks, pair a generator skill (taste-skill / frontend-design) with the
  impeccable gate; do not use impeccable as the generator.
