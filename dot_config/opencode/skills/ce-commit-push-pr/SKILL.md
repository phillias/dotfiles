---
name: ce-commit-push-pr
description: Commit, push, and open a PR with an adaptive, value-first description that scales in depth with the change. Use when the user says "commit and PR", "ship this", "create a PR", or "open a pull request". Also handles description-only flows ("write a PR description", "rewrite the PR body", "describe this PR") without committing or pushing.
---

# Git Commit, Push, and PR

Asking the user: use the platform's blocking question tool: AskUserQuestion in Claude Code, request_user_input in Codex, ask_user in Gemini, ask_user in Pi. Fall back to chat only when no blocking tool exists. Never silently skip the question.

## Mode

modes[3]{mode,trigger,steps}:
  Description-only,"write/draft a PR description",Step 4 only — print result, apply if asked
  Description update,refresh/rewrite existing PR description,Step 4 (PR mode) → Step 5 (preview, confirm, apply via gh pr edit)
  Full workflow,anything else,Steps 1-5 in order

If a PR ref was pasted, pass it to Step 4 so Pre-A resolves the right range.

## Context

On platforms other than Claude Code, run the Context fallback. In Claude Code, the labeled sections contain pre-populated data — use them directly.

context[7]{name,command}:
  Git status,!`git status`
  Working tree diff,!`git diff HEAD`
  Current branch,!`git branch --show-current`
  Recent commits,!`git log --oneline -10`
  Remote default branch,!`git rev-parse --abbrev-ref origin/HEAD 2>/dev/null || echo 'DEFAULT_BRANCH_UNRESOLVED'`
  Existing PR check,!`gh pr view --json url,title,state 2>/dev/null || echo 'NO_OPEN_PR'`
  Branch drift detection,!`BRANCH=$(git branch --show-current); if [ -n "$BRANCH" ]; then git fetch origin --quiet 2>/dev/null; LOCAL=$(git rev-parse HEAD); REMOTE=$(git rev-parse "origin/$BRANCH" 2>/dev/null); if [ "$LOCAL" = "$REMOTE" ]; then echo "SYNCHRONIZED"; elif git merge-base --is-ancestor HEAD "origin/$BRANCH" 2>/dev/null; then echo "BEHIND (fast-forward possible)"; elif git merge-base --is-ancestor "origin/$BRANCH" HEAD 2>/dev/null; then echo "AHEAD (safe to push)"; else echo "DIVERGED (local: ${LOCAL:0:8}, remote: ${REMOTE:0:8})"; fi; else echo "NO_UPSTREAM"; fi`

### Context fallback

```
printf '=== STATUS ===\n'; git status; printf '\n=== DIFF ===\n'; git diff HEAD; printf '\n=== BRANCH ===\n'; git branch --show-current; printf '\n=== LOG ===\n'; git log --oneline -10; printf '\n=== DEFAULT_BRANCH ===\n'; git rev-parse --abbrev-ref origin/HEAD 2>/dev/null || echo 'DEFAULT_BRANCH_UNRESOLVED'; printf '\n=== PR_CHECK ===\n'; gh pr view --json url,title,state 2>/dev/null || echo 'NO_OPEN_PR'
```

---

## Step 1: Resolve branch and PR state

Remote default branch returns something like `origin/main`; strip `origin/` prefix. If `DEFAULT_BRANCH_UNRESOLVED` or bare `HEAD`, try `gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'`. If both fail, fall back to `main`.

branch-routing[4]{state,action}:
  Detached HEAD,Explain branch required → ask to create feature branch → derive name from content → Step 3 if yes, stop if no
  Default branch with work,Ask to create feature branch (pushing default not supported) → Step 3 if yes, stop if no
  Default branch no work,Report no feature branch work → stop
  Feature branch,Continue

Note existing PR URL from PR check if `state: OPEN`. Step 5 uses it for new-PR vs existing-PR routing.

## Step 2: Determine conventions

Match repo style (project instructions > recent commits > conventional commits as default). With conventional commits, default to `fix:` over `feat:` when ambiguous — `fix:` remedies broken/missing behavior; `feat:` adds capabilities user couldn't previously accomplish. User may override.

## Step 3: Commit and push

Set commit identity before any commits. Author/committer name must be `<model>@<hostname>`:

```
export GIT_AUTHOR_NAME="$(opencode debug config 2>/dev/null | grep '"model"' | head -1 | grep -oP ':\s*"[^"]*"' | sed 's/.*"\(.*\)".*/\1/' || echo "unknown")@$(hostname -s)"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
```

If `opencode debug config` unavailable, fall back to `$OPENCODE_MODEL` or placeholder. Format is always `<model>@<hostname>` (e.g., `big-pickle@nasbox`).

Drift detection before push — if branch has upstream, check before committing:

```
git fetch origin
LOCAL_SHA=$(git rev-parse HEAD)
REMOTE_SHA=$(git rev-parse origin/$(git branch --show-current) 2>/dev/null)
if [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
  if git merge-base --is-ancestor HEAD origin/$(git branch --show-current); then
    echo "Branch is behind remote. Fast-forwarding..."
    git merge --ff-only origin/$(git branch --show-current)
  else
    echo "WARNING: Local and remote have diverged."
    echo "Local:  $LOCAL_SHA"
    echo "Remote: $REMOTE_SHA"
    echo "Rebase or resolve before pushing."
    exit 1
  fi
fi
```

If drift cannot be resolved automatically, **stop and report**. Never force-push without explicit user confirmation.

If on default branch, read `references/branch-creation.md` and follow its decision flow before continuing.

Scan changed files for distinct concerns. If clearly separate, create 2-3 commits max. Group at file level only — no `git add -p`. When ambiguous, one commit is fine.

Stage and commit each group. **Avoid `git add -A` and `git add .`** — they sweep in `.env`, build artifacts, generated files:

```
git add file1 file2 file3 && git commit -m "$(cat <<'EOF'
commit message here
EOF
)"
```

Then push: `git push -u origin HEAD`

If working tree clean and all commits pushed, this step is a no-op.

## Step 4: Compose the PR title and body

**You MUST read `references/pr-description-writing.md`** in full — the core principle at the top governs every step.

Evidence decision before composition:

evidence-rules[3]{condition,action}:
  User explicitly asked for evidence,Proceed directly to capture — if impossible, note briefly and proceed without
  Agent judgment: non-observable change,Skip prompt without asking (plumbing, type-only, backend refactor, docs/changelog/CI/test-only, pure refactors)
  Observable behavior and evidence not blocked,"Ask: 'This PR has observable behavior. Capture evidence for the PR description?'"

evidence-options[3]{choice,action}:
  Capture now,Load ce-demo-reel → returns Tier/Description/URL/Path → splice as ## Demo section or note local save
  Use existing evidence,Ask for URL or markdown embed → splice as ## Demo section
  Skip,Proceed without evidence section

Then continue with Steps A through G from the reference.

## Step 5: Apply and report

apply-rules[4]{mode,action}:
  Description-only,Print title and body — stop unless user asks to apply
  New PR (full workflow),Apply via gh pr create — report URL
  Existing PR (full workflow),Commits already on PR from Step 3 — report URL, ask to rewrite description → Step 4 + preview + apply if yes
  Description update or rewrite confirmed,Preview: ask "New title: `<title>` (`<N>` chars). Summary leads with: `<first two sentences>`. Total body: `<L>` lines. Apply?" → gh pr edit if confirmed

## Step 6: Post-PR cleanup

If PR was just created:

cleanup[3]{action,command}:
  Switch to default branch,git checkout <default_branch>
  Delete local feature branch,git branch -d <feature_branch>
  Prune stale remote-tracking refs,git fetch origin --prune

Use `-D` only if branch has unpushed commits (shouldn't happen after Step 3).

If PR already existed and new commits pushed: no cleanup needed.

If user is on merged branch: offer to clean up:
```
git branch --merged origin/<default_branch> | grep -v "^\*" | grep -v "<default_branch>"
git branch -d <merged_branch>
```

Remote branch deletion — after PR merge, GitHub may auto-delete. If not:
```
gh pr close <pr_number> --delete-branch  # only if merged, not just closed
```

Do NOT auto-delete remote branches without user confirmation.

---

## Applying via gh

The body **must** be written to a temp file and passed via `--body-file <path>`. Never use `--body-file -`, stdin pipes, heredoc-to-stdin, or `--body "$(cat ...)"` — wrappers can silently produce empty PR body while `gh` exits 0.

```
BODY_FILE=$(mktemp "${TMPDIR:-/tmp}/ce-pr-body.XXXXXX") && cat > "$BODY_FILE" <<'__CE_PR_BODY_END__'
<the composed body markdown goes here, verbatim>
__CE_PR_BODY_END__
```

The quoted sentinel keeps `$VAR`, backticks, and literal `EOF` inside the body from being expanded.

For `<TITLE>`: substitute verbatim. If it contains `"`, `` ` ``, `$`, or `\`, escape or use single quotes.

```
gh pr create --title "<TITLE>" --body-file "$BODY_FILE"   # new PR
gh pr edit   --title "<TITLE>" --body-file "$BODY_FILE"   # existing PR
```
