# Team Profile OpenCode Rules

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

## Safety Guardrails

The agent **must not** perform the following without explicit user confirmation:

- `git push --force` or `git push --force-with-lease`
- `git reset --hard` on a branch with unpushed commits
- `git branch -D` (force delete)
- `git rebase --onto` against shared branches
- Deleting files outside the project scope
- Modifying files in `~/.config/opencode/` without being asked to

## Compound Engineering Skills (Team Profile)

The following CE skills are available in this profile and should be used automatically when the task matches their purpose:

- **`/ce-plan`** — Structured planning with confidence gating. Use when the user says "plan this", "how should we build", or when a brainstorm doc is ready. This produces durable implementation plans in `docs/plans/`.
- **`/ce-code-review`** — Parallel multi-agent code review with tiered personas. Use when reviewing code changes before creating a PR. Supports `mode:autofix` for hands-off fixing and `mode:report-only` for read-only review.
- **`/ce-debug`** — Systematic root cause analysis with test-first fixes. Use when debugging errors, investigating test failures, or tracing causal chains. Investigates before proposing fixes.
- **`/ce-compound`** — Document solved problems to compound team knowledge. Use after fixing a non-trivial issue to capture context in `docs/solutions/`.
- **`/ce-brainstorm`** — Interactive requirements exploration. Use when scope is unclear or the user presents a vague feature request. Outputs a requirements document for `/ce-plan`.
- **`/ce-optimize`** — Iterative optimization loops with measurement gates. Use for performance tuning or systematic improvement.
- **`/ce-strategy`** — Create or maintain `STRATEGY.md`. Use when establishing or updating product strategy.

**Invocation:** Use the `skill` tool with `name: ce-<skill>` to invoke these. Each CE skill spawns specialized sub-agents that have been pre-configured with budget-optimized models (GLM-5.1 for code review, Kimi K2.6 for architecture, Nemotron free for research, Big Pickle for document review).

**Do not use** `/lfg` (removed from this profile — it is a token-heavy autonomous pipeline that conflicts with the ultrawork discipline of manual QA and scenario contracts).

## Ultrawork Discipline

When in ultrawork mode (`/ulw`), follow the strict RED → GREEN → SURFACE cycle with scenario contracts and manual QA. Do not delegate CE skills inside ultrawork — the protocol is hands-on. CE skills may be used *before* entering ultrawork (e.g., `/ce-plan` to create a plan, then `/ulw` to execute it with TDD discipline).

## Model Budget Awareness

All CE sub-agents in this profile are pinned to budget-optimized models. Do not override their model assignments. The session model (Sisyphus's current model) is used for skill entry points only; sub-agents use their own pinned models.
