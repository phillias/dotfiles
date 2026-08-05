---
name: compound
description: Document a solved problem or capture a durable learning into docs/solutions/, or refresh/consolidate stale learning docs there. Use after a non-trivial problem is solved and verified, when the user says "document this", "compound this", "refresh learnings", or when a learning doc looks stale or duplicated. Headless-capable for automations.
argument-hint: "[optional: brief context or scope hint] [mode:headless]"
---

# compound

Capture solved problems and durable learnings into a searchable `docs/solutions/` store so the next occurrence takes minutes instead of research. Knowledge compounds: the first solve takes research, the documented solve is a lookup.

This is a self-contained skill. It does not depend on other skills or agents — the research, overlap check, and refresh logic run in this skill's own flow.

## Modes

- **capture** (default) — document a solved problem or learning into `docs/solutions/`.
- **refresh** — review existing docs against the current codebase; update, consolidate, or mark stale ones.
- Select with the first argument: `compound capture "..."` or `compound refresh [scope]`. No argument means capture.

Check `$ARGUMENTS` for `mode:headless`. Tokens starting with `mode:` are flags, not context — strip `mode:headless` before treating the remainder as context.

mode_detection[2]{mode,when,behavior}:
  Interactive (default),No mode token present,"Ask Full vs Lightweight (capture) or scope (refresh); confirm edits"
  Headless,"mode:headless" in arguments,"No blocking questions. Run capture Full without session history; apply the discoverability edit silently if needed; in refresh, apply unambiguous actions and mark ambiguous ones stale. End with a structured terminal report."

Headless mode is for automations and skill-to-skill invocation. The artifact is identical to an interactive run; only the questions and review passes are skipped.

## Support files

Read on demand at the step that needs them — do not bulk-load at skill start.

- `references/schema.yaml` — canonical frontmatter fields and enum values (read when validating YAML)
- `references/yaml-schema.md` — category mapping from problem_type to directory (read when classifying)
- `assets/resolution-template.md` — section structure for new docs (read when assembling)
- `scripts/validate-frontmatter.py` — YAML parser-safety validation (run on every written doc)

## Capture flow

1. **Preconditions (advisory):** the problem is solved and verified (not in-progress), and non-trivial (not a typo or obvious error). If not, emit `Documentation skipped` and stop.

2. **Classify.** Read `references/schema.yaml` and `references/yaml-schema.md`. Determine the track and category:
   - **Bug track**: problem_type in bug_categories — build_error, test_failure, runtime_error, performance_issue, database_issue, security_issue, ui_bug, integration_issue, logic_error.
   - **Knowledge track**: problem_type in knowledge_categories — architecture_pattern, design_pattern, tooling_decision, convention, workflow_issue, developer_experience, documentation_gap, best_practice (fallback only).
   Suggest a filename `[sanitized-problem-slug]-[date].md`.

3. **Overlap check.** Search `docs/solutions/` for existing docs covering the same problem. Grep-first: run parallel case-insensitive content searches against frontmatter fields (`title:.*<keyword>`, `tags:.*(<k1>|<k2>)`, `module:.*<name>`). Read only frontmatter (first 30 lines) of candidates; fully read only strong matches. Score overlap across problem statement, root cause, solution approach, referenced files, and prevention rules:
   - **High** (4-5 dimensions) → update the existing doc with fresher context instead of creating a duplicate. Keep its path and frontmatter; add `last_updated: YYYY-MM-DD`. Do not change the title unless framing shifted.
   - **Moderate** (2-3) → create the new doc normally; flag the pair for a future refresh consolidation.
   - **Low/none** → create the new doc normally.

4. **Assemble.** Build the markdown file following `assets/resolution-template.md`, using the track-appropriate sections:
   - Bug track: Problem, Symptoms, What Didn't Work, Solution (with code before/after), Why This Works (root cause), Prevention (with concrete examples/tests).
   - Knowledge track: Context, Guidance (with examples), Why This Matters, When to Apply, Examples.
   Capture the failures too — the approaches ruled out and why save more time than the win itself.

5. **Write.** `mkdir -p docs/solutions/[category]/`; write the doc. Then run `python3 scripts/validate-frontmatter.py <output-path>` until exit 0. The script catches silent corruption: malformed `---` delimiters, unquoted ` #` in scalars, unquoted `: ` in scalars. It does not enforce schema.

6. **Discoverability check.** If `AGENTS.md` or `CLAUDE.md` exists in the repo and does not already tell agents that a searchable `docs/solutions/` store exists (semantic check, not string match), add the smallest line that communicates: the folder exists, its structure (category dirs, frontmatter fields), and that it's relevant when implementing or debugging in documented areas. Prefer a single line in an existing architecture/directory section over a new headed section. In headless mode apply silently and report it; interactive mode propose and get consent. If neither instruction file exists, skip.

## Refresh flow

Use when the user asks to refresh learnings, or when capture surfaces a candidate that is stale/contradicted/consolidation-worthy.

1. **Scope.** A scope hint (filename, module, category, pattern topic) narrows the review; no hint means the whole `docs/solutions/` tree. Interactive mode asks scope first; headless processes everything in scope.

2. **Review order.** Learning docs first (primary evidence), then pattern docs derived from them (a stale learning makes a derived pattern look more valid than it is).

3. **Classify each candidate** against the current codebase into: Keep (no-op), Update (fix references/details), Consolidate (merge overlapping docs and delete the subsumed one), Delete (unambiguous: content now false, no unique value), Replace (superseded by a newer capture). Mark ambiguous cases stale in frontmatter (`status: stale`, `stale_reason`, `stale_date`) rather than acting on a guess.

4. **Apply.** Headless: apply unambiguous actions, record applied vs recommended in the report, never pause for permission. Interactive: confirm ambiguous actions one at a time.

5. **Report.** Always emit the two-section report: **Applied** (writes that succeeded) and **Recommended** (writes that failed or were ambiguous, with rationale).

## Output

### Capture success (headless)

```
✓ Documentation complete (headless mode)

File: docs/solutions/<category>/<filename>.md  (created | updated)
Track: <bug | knowledge>
Category: <category>
Overlap: <none | low | moderate — see <path> | high — existing doc updated>
Instruction-file edit: <none needed | applied to <path> | gap noted, not applied>

Documentation complete
```

### Capture skipped (headless)

```
✗ Documentation skipped (headless mode)

Reason: <one sentence — e.g., "no solved problem detected" or "solution not yet verified">

Documentation skipped
```

### Refresh (headless)

```
✓ Refresh complete (headless mode)

Applied:
- <action>: <path>
- ...
Recommended:
- <action>: <path> — <why>

Refresh complete
```

## Rules

- The primary output is ONE file — the final documentation. Research runs in your own reasoning; do not spawn subagents or create intermediate files.
- Overlap is decided before writing: update beats duplicate when the same problem + root cause + solution already exists.
- Never write secret VALUES (tokens, passwords, connection strings). Record where they live, never the value.
- Validate every written doc with `scripts/validate-frontmatter.py` before declaring success.
- Keep the doc tight and concrete: commands, paths, order, gotchas — a procedure, not a one-off answer.
- In headless mode: never ask questions, never pause, end with the structured report, and stop.
