# Global OpenCode Rules

> **Note for team profiles:** When `OPENCODE_CONFIG_DIR` is set (e.g., running `oc team`), OpenCode loads the profile's own `AGENTS.md` instead of this global file. Team-specific rules (including Compound Engineering skill instructions) are defined in `~/.config/opencode/profiles/<profile>/AGENTS.md`.

## Git Commit Identity

Before any `git commit`, the agent **must** set the commit author identity dynamically:

```bash
export GIT_AUTHOR_NAME="$(opencode debug config 2>/dev/null | grep '"model"' | head -1 | grep -oP ':\s*"[^"]*"' | sed 's/.*"\(.*\)".*/\1/' || echo "unknown")@$(hostname -s)"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
```

Alternatively, if `opencode debug config` is slow/unavailable, check the session's active model via the `$OPENCODE_MODEL` environment variable or fall back to a known model name placeholder and prompt the user on first commit.

The format is always: **`<model>@<hostname>`** — e.g., `big-pickle@nasbox` or `gpt-oss-120b@phillias-dev`.

This applies to both `GIT_AUTHOR_NAME` and `GIT_COMMITTER_NAME`.

## Conventional Commits

All commit messages **must** follow the Conventional Commits format:

```
<type>(<scope>): <description>

<body> (optional)
<footer> (optional)
```

Types: `feat`, `fix`, `chore`, `docs`, `style`, `refactor`, `perf`, `test`, `ci`, `build`

## PR Workflow

When pushing changes intended for a pull request:

1. **Before pushing**, check if a PR already exists from the current branch using `gh pr view --json title,body,state,baseRefName` or check the branch's upstream status.
2. **If a PR already exists**: push new commits, then update the PR body/description with `gh pr edit` to reflect the new changes.
3. **If no PR exists**: create a feature branch, push it, and open a pull request via `gh pr create --base master`.

To infer the base branch: compare `git merge-base` against `master` and `develop` and any other likely upstream branches, then pick the closest one (smallest divergence).

## Compound-Engineering Integration (OmO + CE)

When the compound-engineering plugin is installed (skills present at `~/.config/opencode/skills/ce-*`), route planning and execution through CE skills instead of the built-in OmO plan agent:

### Pre-Planning Domain Alignment

Before routing to ce-plan or ce-brainstorm, check whether the project has existing domain
documentation (`CONTEXT.md`, `docs/adr/`, `BRAND.md`, or `CONTEXT-MAP.md` at repo root).

When domain docs exist **AND** the request is non-trivial (Feature, Ambiguous, or Large), offer a
`/grill-with-docs` session to align the request's terminology with the project's established language.
This runs interactively (one question at a time) and updates `CONTEXT.md` inline.

- `CONTEXT.md` exists + non-trivial scope → Offer grill-with-docs before planning
- No CONTEXT.md + fuzzy terminology → Offer grill-with-docs optionally
- Greenfield + large feature → Offer to establish initial CONTEXT.md via grill-with-docs
- Trivial scope → Skip domain alignment

Deployment: tracked in dotfiles via `chezmoi apply`. To install manually: `npx skills add https://github.com/mattpocock/skills --skill grill-with-docs --yes`

### Routing Matrix

| Request Type | Route To | Domain Variant |
|---|---|---|
| **Trivial** (1-2 files, no behavioral change, typo, config) | Execute directly — no plan needed | — |
| **Clear feature/fix** (multi-step, well-understood scope) | `/ce-plan` → plan → `/ce-work` → execute → `/ce-code-review` → ship | With CONTEXT.md: `/grill-with-docs` → plan → execute |
| **Ambiguous/complex** (WHAT is unclear, product decisions needed) | `/ce-brainstorm` → requirements doc → `/ce-plan` → `/ce-work` | With CONTEXT.md: `/grill-with-docs` → brainstorm → plan → execute |
| **Bug report / error** | `/ce-debug` → fix → `/ce-compound` (optional) | — |

### Plan Storage

CE plans are written to `docs/plans/` by default. When `.omo/` exists at the repo root (OmO project), ce-plan auto-detects it and writes to `.omo/plans/` instead — this triggers the OmO built-in Momus review hook.

### Execution

After ce-plan produces a plan, execute with `/ce-work <plan-path>`. The shipping workflow (code review → PR) runs within ce-work's Phase 3-4.

### Review Chain

1. **ce-doc-review** runs automatically after ce-plan writes the plan (headless mode)
2. **Momus** reviews plans written to `.omo/plans/` (built-in OmO hook)
3. **ce-code-review** runs after ce-work completes implementation
4. **ce-resolve-pr-feedback** handles review threads post-PR

## Safety Guardrails

The agent **must not** perform the following without explicit user confirmation:

- `git push --force` or `git push --force-with-lease`
- `git reset --hard` on a branch with unpushed commits
- `git branch -D` (force delete)
- `git rebase --onto` against shared branches
- Deleting files outside the project scope
- Modifying files in `~/.config/opencode/` without being asked to

## Compound Engineering Skills

The following CE skills are available and should be used automatically when the task matches their purpose:

- **`/ce-plan`** — Structured planning with confidence gating. Use when the user says "plan this", "how should we build", or when a brainstorm doc is ready. Produces durable plans in `docs/plans/`.
- **`/ce-code-review`** — Parallel multi-agent code review with tiered personas. Use when reviewing code changes before creating a PR. Supports `mode:autofix` for hands-off fixing and `mode:report-only` for read-only review.
- **`/ce-debug`** — Systematic root cause analysis with test-first fixes. Use when debugging errors, investigating test failures, or tracing causal chains.
- **`/ce-compound`** — Document solved problems to compound team knowledge. Use after fixing a non-trivial issue to capture context in `docs/solutions/`.
- **`/ce-brainstorm`** — Interactive requirements exploration. Use when scope is unclear or the user presents a vague feature request. Outputs a requirements document for `/ce-plan`.
- **`/ce-optimize`** — Iterative optimization loops with measurement gates. Use for performance tuning or systematic improvement.
- **`/ce-strategy`** — Create or maintain `STRATEGY.md`. Use when establishing or updating product strategy.

**Invocation:** Use the `skill` tool with `name: ce-<skill>`. Each CE skill spawns specialized sub-agents pre-configured with budget-optimized models (GLM-5.1 for code review, Kimi K2.6 for architecture, Nemotron free for research, Big Pickle for document review).

**Do not use** `/lfg` (removed — token-heavy autonomous pipeline that conflicts with ultrawork discipline of manual QA and scenario contracts).

## Ultrawork Discipline

When in ultrawork mode (`/ulw`), follow the strict RED → GREEN → SURFACE cycle with scenario contracts and manual QA. Do not delegate CE skills inside ultrawork — the protocol is hands-on. CE skills may be used *before* entering ultrawork (e.g., `/ce-plan` to create a plan, then `/ulw` to execute it with TDD discipline).

## Model Budget Awareness

All CE sub-agents are pinned to budget-optimized models. Do not override their model assignments. The session model (Sisyphus's current model) is used for skill entry points only; sub-agents use their own pinned models.

## Token Budget Discipline

Token budget is a first-class design constraint. Every tool output, API response format, and skill
instruction must minimize token consumption without sacrificing signal.

The authoritative source for this discipline is the **AXI skill** (`~/.agents/skills/axi/SKILL.md`),
which defines 10 design principles for building agent-ergonomic CLIs. Load it when designing or
reviewing any tool, CLI, or structured output that an agent will consume.

**The 10 AXI Principles (index):**

1. Token-efficient output (TOON format — ~40% fewer tokens than JSON)
2. Minimal default schemas (3-4 fields, not 10)
3. Content truncation (large output with size hints + `--full`)
4. Pre-computed aggregates (total counts in list output)
5. Definitive empty states (state the zero with context)
6. Structured errors and exit codes (errors to stdout, no interactive prompts)
7. Ambient context (session hooks before skills)
8. Content first (no args = live data, not usage text)
9. Contextual disclosure (next-step suggestions after output)
10. Consistent help (`--help` per subcommand)

**Directive:** When building or reviewing agent-facing tools, CLIs, or skill outputs, treat token
count as a measurable cost. Prefer TOON over JSON. Default to 3-4 fields, not 10. Truncate large
output with size hints. Include aggregate counts. Fail with structure, not noise.

**When to load the full AXI skill:** Any task involving CLI design, tool output formatting,
AXI compliance review, or agent-facing tooling. Do NOT load it for general coding, debugging,
infrastructure, or code review — it would be noise.
