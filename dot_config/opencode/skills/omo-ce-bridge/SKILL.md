---
name: omo-ce-bridge
description: "Integration bridge between OhMyOpenCode (OmO) orchestrator and Compound-Engineering (ce-*) skills. Defines routing contracts, plan format compatibility, and quality gate sequencing."
---

# OmO ↔ CE Integration Bridge

This skill defines the contract between the OmO orchestrator (Sisyphus) and the compound-engineering skill suite. Loaded automatically when the OmO orchestrator detects CE skills installed at `~/.config/opencode/skills/ce-*`.

## Routing Matrix

| Condition | Entry Point | Output | Followed By |
|---|---|---|---|
| Trivial work (1-2 files, typo, config only) | Execute directly | — | — |
| Clear feature/fix, multi-step | `ce-plan` | Plan in `.omo/plans/` or `docs/plans/` | `ce-work` → `ce-code-review` |
| Ambiguous scope, product fuzzy | `ce-brainstorm` | Requirements doc in `docs/brainstorms/` | `ce-plan` → `ce-work` |
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
Plan written
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
| OmO (Sisyphus) | `ce-plan` | `task(category="unspecified-high", load_skills=["ce-plan"], prompt=...)` |
| OmO (Sisyphus) | `ce-brainstorm` | `task(category="unspecified-high", load_skills=["ce-brainstorm"], prompt=...)` |
| `ce-plan` handoff | `ce-work` | Platform skill invocation with plan path |
| `ce-plan` handoff | `ce-doc-review` | `mode:headless <plan-path>` |
| OmO (Sisyphus) | `ce-debug` | `task(category="deep", load_skills=["ce-debug"], prompt=...)` |
| `ce-work` shipping | `ce-code-review` | Via shipping workflow |
| `ce-work` shipping | `ce-commit-push-pr` | Via shipping workflow |
