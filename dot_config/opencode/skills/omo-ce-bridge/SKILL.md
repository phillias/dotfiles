---
name: omo-ce-bridge
description: "Integration bridge between OhMyOpenCode (OmO) orchestrator and Compound-Engineering (ce-*) skills. Defines routing contracts, plan format compatibility, and quality gate sequencing."
---

# OmO ↔ CE Integration Bridge

This skill defines the contract between the OmO orchestrator (Sisyphus) and the compound-engineering skill suite. Loaded automatically when the OmO orchestrator detects CE skills installed at `~/.config/opencode/skills/ce-*`.

## Pre-Planning Domain Alignment (grill-with-docs)

Before routing to `ce-plan` or `ce-brainstorm`, check whether the project has existing domain
documentation (`CONTEXT.md`, `docs/adr/`, `BRAND.md`, `CONTEXT-MAP.md`). When domain docs exist
**and** the request is non-trivial, a `/grill-with-docs` session precedes the planning pipeline
to sharpen terminology and update the domain glossary inline.

grill-with-docs runs interactively (one question per turn, `disable-model-invocation: true` —
loaded by Sisyphus directly, not delegated). It uses the sibling skills `/grilling` (the
relentless interview loop) and `/domain-modeling` (glossary + ADR writing discipline), plus
their reference format files `CONTEXT-FORMAT.md` and `ADR-FORMAT.md`.

**Skills location:** `~/.config/opencode/skills/{grill-with-docs,grilling,domain-modeling}/`
**Dependency:** All three Pocock skills must be present for the gate to fire. Also tracked
under chezmoi for reproducible deployment.

**Gate logic:**

| Condition | Action |
|---|---|
| `CONTEXT.md`/ADRs exist + Feature/Ambiguous/Large | Run grill-with-docs before next phase |
| Fuzzy overloaded terms (no docs) | Offer optionally |
| Large greenfield (no docs) | Offer to establish initial CONTEXT.md |
| Trivial scope | Skip |

## Routing Matrix

| Condition | Entry Point | Output | Followed By |
|---|---|---|---|
| Trivial work (1-2 files, typo, config only) | Execute directly | — | — |
| Clear feature/fix, multi-step, no domain docs | `ce-plan` | Plan in `.omo/plans/` or `docs/plans/` | `ce-work` → `ce-code-review` |
| Clear feature/fix, multi-step, domain docs exist | `grill-with-docs` → `ce-plan` | Updated CONTEXT.md + plan | `ce-work` → `ce-code-review` |
| Ambiguous scope, no domain docs | `ce-brainstorm` | Requirements doc in `docs/brainstorms/` | `ce-plan` → `ce-work` |
| Ambiguous scope, domain docs exist | `grill-with-docs` → `ce-brainstorm` | Updated CONTEXT.md + requirements doc | `ce-plan` → `ce-work` |
| Bug report / error / regression | `ce-debug` | Fix | `ce-compound` (optional) |

## Plan Format Compatibility

Plans produced by `ce-plan` use the CE YAML frontmatter format:

```yaml
---
title: Plan Title
type: feat|fix|refactor
status: active
date: YYYY-MM-DD
origin: docs/brainstorms/...  # optional
deepened: YYYY-MM-DD          # optional
---
```

These plans are consumed by:
- **ce-work** — reads Goal, Files, Approach, Test scenarios, Verification from each Implementation Unit
- **ce-doc-review** — validates plan quality via multi-persona review
- **Momus** — reviews plans in `.omo/plans/` for clarity, verifiability, completeness
- **ce-proof** — opens plan in Proof web editor for collaborative review

## Plan Storage Resolution

```
if .omo/ directory exists at repo root:
  plan_dir = .omo/plans/
else:
  plan_dir = docs/plans/
```

The `.omo/plans/` directory triggers the OmO built-in Momus review hook when a plan file is written there. `docs/plans/` is the CE convention for non-OmO projects.

## Quality Gate Sequencing

```
           ┌─ Pre-Planning Gate (if domain docs exist) ──┐
           │  grill-with-docs ─── CONTEXT.md updated     │
           │  (one question at a time) ─── optional ADR  │
           └─────────────────┬──────────────────────────-┘
                             │ sharpened terminology
                             ▼
Plan written (ce-plan)
  ↓
ce-doc-review (headless) ─── Momus (if .omo/plans/)
  ↓
Implementation (ce-work)
  ↓
ce-code-review
  ↓
ce-commit-push-pr
  ↓
ce-resolve-pr-feedback (if PR comments arrive)
```

## Skill Invocation Reference

| From | To | Mechanism |
|---|---|---|
| OmO (Sisyphus) | `grill-with-docs` (pre-planning gate) | Loaded directly in orchestrator context (`disable-model-invocation: true`). Follows `/grilling` protocol using `/domain-modeling` for doc updates. |
| OmO (Sisyphus) | `ce-plan` | `task(category="unspecified-high", load_skills=["ce-plan"], prompt=...)` |
| OmO (Sisyphus) | `ce-brainstorm` | `task(category="unspecified-high", load_skills=["ce-brainstorm"], prompt=...)` |
| `ce-plan` handoff | `ce-work` | Platform skill invocation with plan path |
| `ce-plan` handoff | `ce-doc-review` | `mode:headless <plan-path>` |
| OmO (Sisyphus) | `ce-debug` | `task(category="deep", load_skills=["ce-debug"], prompt=...)` |
| `ce-work` shipping | `ce-code-review` | Via shipping workflow |
| `ce-work` shipping | `ce-commit-push-pr` | Via shipping workflow |
