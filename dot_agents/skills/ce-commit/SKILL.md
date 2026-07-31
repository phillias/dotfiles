---
name: ce-commit
description: Create a git commit with a clear, value-communicating message. Use when the user says "commit", "commit this", "save my changes", "create a commit", or wants to commit staged or unstaged work. Produces well-structured commit messages that follow repo conventions when they exist, and defaults to conventional commit format otherwise.
---

# Git Commit

Create a single, well-crafted git commit from the current working tree changes.

## Context

On platforms other than Claude Code, skip to "Context fallback" and run the command there. In Claude Code, the five labeled sections contain pre-populated data — use them directly.

context[5]{name,command}:
  Git status,!`git status`
  Working tree diff,!`git diff HEAD`
  Current branch,!`git branch --show-current`
  Recent commits,!`git log --oneline -10`
  Remote default branch,!`git rev-parse --abbrev-ref origin/HEAD 2>/dev/null || echo '__DEFAULT_BRANCH_UNRESOLVED__'`

### Context fallback

In Claude Code, skip this section — data above is already available.

```
printf '=== STATUS ===\n'; git status; printf '\n=== DIFF ===\n'; git diff HEAD; printf '\n=== BRANCH ===\n'; git branch --show-current; printf '\n=== LOG ===\n'; git log --oneline -10; printf '\n=== DEFAULT_BRANCH ===\n'; git rev-parse --abbrev-ref origin/HEAD 2>/dev/null || echo '__DEFAULT_BRANCH_UNRESOLVED__'
```

---

## Workflow

### Step 1: Gather context

Use context above — do not re-run commands.

Remote default branch returns `origin/main`; strip `origin/` prefix. If `__DEFAULT_BRANCH_UNRESOLVED__` or bare `HEAD`:
```
gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'
```
If both fail, fall back to `main`.

If clean working tree (no staged, modified, untracked files): report nothing to commit and stop.

If detached HEAD: explain branch required → ask to create feature branch. Use blocking question tool: AskUserQuestion in Claude Code, request_user_input in Codex, ask_user in Gemini, ask_user in Pi. Fall back to chat only when no blocking tool exists. Never silently skip.

- If user creates branch: derive name from content, `git checkout -b <branch-name>`, re-run `git branch --show-current`
- If user declines: continue with detached HEAD commit

### Step 2: Determine commit message convention

Priority order:

convention-rules[3]{priority,source,action}:
  1,Repo conventions in context,Follow those — do not re-read files
  2,Recent commit history,Examine 10 most recent commits — match pattern
  3,Default: conventional commits,type(scope): description

Conventional commit types: feat, fix, docs, refactor, test, chore, perf, ci, style, build.

Where fix: and feat: both fit, default to fix: (remedies broken/missing behavior). Reserve feat: for new capabilities. User may override.

### Step 3: Consider logical commits

Scan changed files for distinct concerns. If clearly separate, create separate commits.

commit-grouping[3]{rule,detail}:
  File level only,No git add -p or splitting hunks
  Obvious separation,Split (different features, unrelated fixes)
  Ambiguous,One commit is fine

Sweet spot: 2-3 logical commits. Do not over-slice.

### Step 4: Stage and commit

If on main/master/default branch: warn user → ask to continue or create feature branch. Use blocking question tool. If user creates branch: `git checkout -b <branch-name>`.

Commit message:
- **Subject**: Concise, imperative mood, focused on *why* not *what*. Follow Step 2 convention.
- **Body** (when needed): Blank line separator. Explain motivation, trade-offs, future reader context. Omit for obvious single-purpose changes.

Stage and commit in single call. Prefer specific files over `git add -A` / `git add .` to avoid .env, credentials, unrelated changes. Use a heredoc to preserve formatting:

```
git add file1 file2 file3 && git commit -m "$(cat <<'EOF'
type(scope): subject line here

Optional body explaining why this change was made,
not just what changed.
EOF
)"
```

### Step 5: Confirm

Run `git status` after commit. Report commit hash(es) and subject line(s).
