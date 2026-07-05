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

### Routing Matrix

| Request Type | Route To |
|---|---|
| **Trivial** (1-2 files, no behavioral change, typo, config) | Execute directly — no plan needed |
| **Clear feature/fix** (multi-step, well-understood scope) | `/ce-plan` → plan → `/ce-work` → execute → `/ce-code-review` → ship |
| **Ambiguous/complex** (WHAT is unclear, product decisions needed) | `/ce-brainstorm` → requirements doc → `/ce-plan` → `/ce-work` |
| **Bug report / error** | `/ce-debug` → fix → `/ce-compound` (optional) |

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
