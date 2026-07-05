---
name: ce-workflow
description: "Integrated OmO + Compound-Engineering workflow orchestrator. Routes incoming work through the correct CE skill pipeline — trivial execution, ce-plan, ce-brainstorm, or ce-debug — and manages handoffs between OmO hooks (.omo/plans/, Momus) and CE quality gates (ce-doc-review, ce-code-review)."
---

# OmO + CE Integrated Workflow

**Note: The current year is 2026.**

This skill defines the executable workflow when the OmO orchestrator (Sisyphus) has the compound-engineering plugin installed. It replaces the generic OmO `task(subagent_type="plan")` routing with the CE skill pipeline, while preserving OmO's built-in hooks (`.omo/plans/` → Momus review, `/start-work`, trivial-direct-execution path).

Load this skill early in the session — before the first work routing decision — so the detection and routing logic is active.

## Core Principles

1. **Preserve the trivial path.** One-liners, typo fixes, config-only changes, and single-file edits execute directly with no CE overhead. The CE pipeline only engages for multi-step, behavior-bearing work.
2. **Plan before you build.** Any work with 2+ steps, structural decisions, or test scenarios gets a CE-format plan first.
3. **One plan directory.** Plans live where OmO can find them (`.omo/plans/`) and where CE can read them (same format). No split-brain.
4. **Quality gates are not optional.** ce-doc-review and ce-code-review run automatically. Momus provides an extra pass on plans in `.omo/plans/`.
5. **Knowledge compounds.** After fixing a non-trivial bug, `ce-compound` captures the learning for future sessions.

## Precondition Detection

Before accepting any work, check whether CE skills are installed:

```bash
ls ~/.config/opencode/skills/ce-plan/SKILL.md 2>/dev/null && echo "CE_READY" || echo "CE_MISSING"
```

If `CE_MISSING`, fall back to the standard OmO workflow (generic plan agent, direct execution, no CE pipeline). Announce the fallback once per session.

---

## Workflow

### Phase 0: Classify the Request

Evaluate the user's incoming request against this routing matrix:

| Signal | Classification | Route | Example |
|---|---|---|---|---|
| 1-2 files, no behavioral change, typo, config-only, rename | **Trivial** | Execute directly | "Fix the typo in login.ts" |
| Single-file change with clear behavior | **Trivial** | Execute directly or use ce-work with bare prompt | "Add validation to email field" |
| Multi-step feature, clear scope, known patterns, no CONTEXT.md | **Feature** | ce-plan → ce-work | "Add user authentication with JWT" |
| Multi-step feature, clear scope, CONTEXT.md or ADRs exist | **Feature + Domain** | grill-with-docs → ce-plan → ce-work | "Add notification preferences UI" |
| WHAT is unclear, product decisions needed, no CONTEXT.md | **Ambiguous** | ce-brainstorm → ce-plan → ce-work | "We need a notification system" |
| WHAT is unclear, CONTEXT.md or ADRs exist | **Ambiguous + Domain** | grill-with-docs → ce-brainstorm → ce-plan → ce-work | "We need a notification system" |
| Bug report, error trace, regression, "doesn't work" | **Bug** | ce-debug → fix → (optional) ce-compound | "Users get 500 on checkout" |
| Large cross-cutting change, 10+ files, architectural decisions | **Large** | Offer ce-brainstorm first; respect user choice | "Migrate from REST to GraphQL" |

**Decision rules:**

- **When in doubt between Trivial and Feature**, classify up to Feature. A quick plan costs less than rework from a missed dependency.
- **When in doubt between Feature and Ambiguous**, ask one clarifying question about scope before routing. If the user can describe the expected behavior concretely, it's Feature, not Ambiguous.

### Phase 0.5: Plan Storage Resolution

Before any planning begins, resolve the plan output directory:

```
if OMO_PLANS_DIR environment variable is set:
  plan_dir = $OMO_PLANS_DIR
elif .omo/ directory exists at repo root:
  plan_dir = .omo/plans/
else:
  plan_dir = docs/plans/
```

Announce the resolved path once: `Using {plan_dir} for plan storage.`

### Phase 0.5a: Domain Alignment Gate (grill-with-docs)

Before routing to a CE skill, check whether the project has existing domain documentation
that the request should align with:

```bash
ls CONTEXT.md docs/adr/ CONTEXT-MAP.md BRAND.md 2>/dev/null | head -5
```

**When to run grill-with-docs:**
- `CONTEXT.md`, `BRAND.md`, `CONTEXT-MAP.md`, or `docs/adr/` exists at repo root **AND** the request is non-trivial (Feature, Ambiguous, or Large classification)
- The request uses overloaded/fuzzy terminology ("user", "session", "account", "workspace", "agent", "tenant") even without existing docs — offer as optional
- Large greenfield work with no existing docs — offer to establish a fresh CONTEXT.md
- User explicitly says "grill me" or "stress-test this"

**When to skip:**
- No CONTEXT.md, BRAND.md, CONTEXT-MAP.md, or ADRs exist (greenfield) **AND** request terminology is precise **AND** scope is bounded
- Request is classified Trivial

**Execution:**

grill-with-docs has `disable-model-invocation: true` — it runs in the orchestrator's own context,
not as a subagent. Sisyphus loads the grill-with-docs protocol directly:

1. **Propose** the session: "This project has [CONTEXT.md|ADRs] — want to run a quick grill-with-docs
   session to align terminology before we plan? Takes ~10-15 minutes."
2. **If accepted**: follow the `/grilling` protocol (one question at a time, using the platform's
   blocking question tool), using the `/domain-modeling` skill for doc updates:
   - Challenge the user's language against existing CONTEXT.md glossary
   - Sharpen fuzzy/overloaded terms and propose canonical alternatives
   - Cross-reference claims against code where possible
   - Update CONTEXT.md inline as terms get resolved
   - Offer ADRs sparingly (hard-to-reverse, surprising, real trade-off)
3. **After session**: CONTEXT.md has been updated with resolved terms. Proceed to Phase 1.
4. **If declined**: skip and proceed to Phase 1 directly.

**Note:** grill-with-docs is a user-facing deliberation skill (one question per turn), not a
batch-processing tool. The side-effect (updated CONTEXT.md, optional ADRs) compounds across
sessions — each grill leaves the project's domain model slightly more precise.

### Phase 1: Route to CE Skill

#### 1a. Trivial — Execute Directly

No CE skills needed. Execute the change, run diagnostics, and report done.

Do NOT create todos for single-step trivial work. Do NOT load additional skills.

#### 1b. Feature — (grill-with-docs →) ce-plan → ce-work

If Phase 0.5a determined that domain alignment is needed, run the grill-with-docs session first.
Otherwise proceed directly to ce-plan:

1. If the **Feature + Domain** variant was classified: run grill-with-docs per Phase 0.5a protocol
2. Invoke `ce-plan` with the feature description as `<feature_description>` input
   - Use: `task(category="unspecified-high", load_skills=["ce-plan"], prompt="Plan: {request}")`
   - Or invoke via platform skill primitive: `skill: ce-plan` with the description
   - If a grill-with-docs session was run, the context already contains sharpened terminology —
     reference the updated CONTEXT.md glossary in the plan prompt
3. ce-plan writes a CE-format plan to `{plan_dir}/YYYY-MM-DD-NNN-<type>-<name>-plan.md`
4. After plan is written:
   a. **ce-doc-review** runs automatically (headless mode) via ce-plan's Phase 5.3.8
   b. **Momus** reviews the plan if it was written to `.omo/plans/` (built-in OmO hook)
5. Present the post-generation handoff menu (ce-plan's Phase 5.4):
   - Default the first option to `Start ce-work` with the plan path
   - Other options: deeper doc review, create issue, open in Proof, done for now
6. If the user selects `Start ce-work`:
   ```bash
   skill: ce-work {plan_dir}/YYYY-MM-DD-NNN-<type>-<name>-plan.md
   ```

#### 1c. Ambiguous — (grill-with-docs →) ce-brainstorm → ce-plan → ce-work

If Phase 0.5a determined that domain alignment is needed, drill terminology first so the brainstorm
works with the project's established language:

1. If the **Ambiguous + Domain** variant was classified: run grill-with-docs per Phase 0.5a protocol
2. Invoke `ce-brainstorm` with the topic as `<feature_description>` input
   - Use: `task(category="unspecified-high", load_skills=["ce-brainstorm"], prompt="Brainstorm: {request}")`
   - Or invoke via platform skill primitive
   - If a grill-with-docs session was run, reference the updated CONTEXT.md glossary during brainstorming
3. ce-brainstorm produces a requirements doc in `docs/brainstorms/YYYY-MM-DD-<topic>-requirements.md`
4. After the requirements doc is written, ce-brainstorm's Phase 4 handoff offers next steps:
   - If the user selects "Proceed to plan", route to Phase 1b (ce-plan) with the requirements doc path
   - If the user wants to continue refining, loop back into brainstorming
5. ce-plan consumes the requirements doc as its origin document
6. Continue with ce-plan → ce-work → review per Phase 1b steps 3-5

#### 1d. Bug — ce-debug → fix → (optional) ce-compound

1. Invoke `ce-debug` with the error description or reproduction steps
   - Use: `task(category="unspecified-high", load_skills=["ce-debug"], prompt="Debug: {error description}")`
   - Or invoke via platform skill primitive
2. ce-debug produces a fix with root cause analysis
3. After fix is verified:
   - If the bug was non-trivial and worth documenting: `skill: ce-compound` to capture the solution
   - If trivial: skip ce-compound
4. The fix ships through the standard path (commit → PR)

### Phase 2: Execution Handoff

When `ce-work` receives a plan:

1. It reads the plan's Implementation Units (U-IDs), dependencies, test scenarios, and verification criteria
2. It creates a feature branch with a meaningful name derived from the plan title
3. It executes units in dependency order, using parallel subagents with worktree isolation for independent units
4. After each unit, it runs relevant tests and creates incremental commits
5. It applies `Simplify as You Go` between unit clusters
6. It never edits the plan body — progress is tracked via git commits and the task tracker

### Phase 3: Quality Gates

After `ce-work` completes all implementation units:

1. **Tier 1 — harness-native code review** (default, <400 lines, non-sensitive)
2. **Tier 2 — ce-code-review** if: sensitive surface touched (auth, payments, data migrations), or diff ≥400 lines across 3+ directories, or the plan explicitly requested it
3. **Residual Work Gate** — if Tier 2 ran and found residual findings, present the options menu (apply/fix, file tickets, accept and proceed, stop)
4. **Final Validation** — all tasks complete, tests pass, linting clean, requirements satisfied
5. **Post-Deploy Monitoring** section added to PR description

### Phase 4: Shipping

1. Commit and push via `ce-commit-push-pr` (or `ce-commit` if user prefers manual PR)
2. PR description includes:
   - Summary of changes
   - Link to the plan document
   - Post-Deploy Monitoring & Validation section
3. After PR is created, monitor for review feedback
4. Handle PR feedback via `ce-resolve-pr-feedback` when threads arrive

### Phase 5: Knowledge Compounding (Post-Ship)

After shipping a non-trivial bug fix or notable learning:

1. Invoke `ce-compound` to document the solution in `docs/solutions/`
2. This is optional — skip for trivial fixes, config changes, and routine feature work
3. Do not force this on the user. Offer once: "Want to document this fix for future reference?"

---

## Quick Reference: Skill Invocation Map

| Action | Invocation |
|---|---|---|
| Domain alignment (terminology sharpening) | `grill-with-docs` (interactive, one question at a time, updates CONTEXT.md inline) |
| Plan a feature | `ce-plan` with description |
| Run a brainstorm | `ce-brainstorm` with topic |
| Debug an error | `ce-debug` with error details |
| Execute a plan | `ce-work <plan-path>` |
| Review plan quality | `ce-doc-review mode:headless <plan-path>` |
| Review code quality | `ce-code-review` |
| Document a solution | `ce-compound [context]` |
| Handle PR feedback | `ce-resolve-pr-feedback` |
| Create commit + PR | `ce-commit-push-pr` |

## Error Recovery

| Symptom | Likely Cause | Action |
|---|---|---|
| `ce-plan` not found | CE plugin not installed | Fall back to OmO `task(subagent_type="plan")` |
| Plan saved to `docs/plans/` but `.omo/plans/` expected | `.omo/` directory doesn't exist | Either create `.omo/` in the repo root, or set `OMO_PLANS_DIR` env var. Plan location is cosmetic — execution works from either path |
| `ce-work` can't read plan | Plan lacks CE frontmatter (old OmO format) | ce-work reads any plan format. Pass the plan path explicitly |
| Momus review doesn't fire | Plan wasn't written to `.omo/plans/` | Review still happens via ce-doc-review. Momus is an additional pass, not the only one |
| `grill-with-docs` skill not found | Matt Pocock's skills not deployed | Run `chezmoi apply` to restore from dotfiles, or install via `npx skills add https://github.com/mattpocock/skills --skill grill-with-docs --yes`. Skip domain alignment gate until present |
| ce-doc-review or ce-code-review slow | Large diff or many findings | Tier 1 (harness-native) is faster for small changes. Escalate to Tier 2 only when warranted |
