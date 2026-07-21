---
name: ce-clean-gone-branches
description: Clean up local branches whose remote tracking branch is gone. Use when the user says "clean up branches", "delete gone branches", "prune local branches", "clean gone", or wants to remove stale local branches that no longer exist on the remote. Also handles removing associated worktrees for branches that have them. Auto-triggers after PR merge, at session start, and before new feature branches.
---

# Clean Gone Branches

Delete local branches whose remote tracking branch has been deleted, including any associated worktrees.

## When This Skill Fires

### Explicit triggers (user-initiated)
- User says "clean up branches", "delete gone branches", "prune local branches"
- User asks to remove stale branches

### Auto-triggers (agent-initiated)

auto_triggers[5]{trigger,when,action}:
  After PR merge,"ce-commit-push-pr completes and PR state is MERGED",Offer to clean up the merged branch
  Session start,"Agent begins work on an existing repo with stale branches",Warn about gone branches, offer cleanup
  Before new feature branch,"User asks to create a branch for new work",Ensure clean baseline, detect drift
  After `git pull`,Branch may have gone remote-side,Detect and offer to prune
  Drift detected,"ce-commit-push-pr Step 3 detects diverged branches",Surface stale branches as part of drift report

### Agent behavior on auto-trigger

When auto-triggering, present a brief warning:

```
⚠ Found 3 local branches with deleted remotes:
  - feature/old-thing
  - bugfix/resolved-issue
  - experiment/abandoned

Clean them up? (y/n)
```

If user declines, note the branches exist but continue with the original task.

## Branch State Detection

Before cleanup, detect the state of each branch to avoid accidental data loss:

```bash
# For each local branch, classify its state
BRANCH="feature/my-branch"
LOCAL_SHA=$(git rev-parse "$BRANCH")
REMOTE_SHA=$(git rev-parse "origin/$BRANCH" 2>/dev/null)

if [ -z "$REMOTE_SHA" ]; then
  echo "GONE"  # Remote deleted — safe to cleanup
elif [ "$LOCAL_SHA" = "$REMOTE_SHA" ]; then
  echo "SYNCHRONIZED"  # In sync — safe to delete
elif git merge-base --is-ancestor "$LOCAL_SHA" "$REMOTE_SHA" 2>/dev/null; then
  echo "BEHIND"  # Local is behind — fast-forward possible
elif git merge-base --is-ancestor "$REMOTE_SHA" "$LOCAL_SHA" 2>/dev/null; then
  echo "AHEAD"  # Local has unpushed commits — warn before delete
else
  echo "DIVERGED"  # Histories diverged — needs resolution
fi
```

### State handling

state_handling[5]{state,action}:
  GONE,Safe to delete — remote no longer exists
  SYNCHRONIZED,Safe to delete — local matches remote
  BEHIND,Safe to delete — local work is subset of remote
  AHEAD,WARN — branch has unpushed commits. Ask for confirmation with commit count
  DIVERGED,BLOCK — refuse to delete. Show divergence and suggest resolution

For AHEAD branches, show:
```
⚠ feature/my-branch has 2 unpushed commits:
  a1b2c3d Add new feature
  e4f5g6h Fix edge case

Delete anyway? These commits will be lost. (y/n)
```

For DIVERGED branches, show:
```
⛔ feature/my-branch has diverged from remote:
  Local:  a1b2c3d (2 commits ahead)
  Remote: e4f5g6h (1 commit ahead)

Resolve divergence before deleting. Options:
  1. git rebase origin/feature/my-branch
  2. git merge origin/feature/my-branch
  3. Keep both (skip cleanup)
```

## Custody Recovery (from no-mistakes)

When a branch appears stranded (e.g., from a failed operation), offer recovery before deletion:

```bash
# Check if branch has unmerged PR
PR_STATE=$(gh pr list --head "$BRANCH" --json state --jq '.[0].state' 2>/dev/null)

if [ "$PR_STATE" = "OPEN" ]; then
  echo "Branch has open PR — skipping cleanup"
elif [ "$PR_STATE" = "MERGED" ]; then
  echo "PR merged — safe to cleanup"
else
  # No PR found — check if commits are worth preserving
  COMMITS=$(git log --oneline origin/"DEFAULT_BRANCH".."$BRANCH" 2>/dev/null | wc -l)
  if [ "$COMMITS" -gt 0 ]; then
    echo "Branch has $COMMITS unmerged commits — offer to create PR or archive"
  fi
fi
```

## Workflow

### Step 1: Discover gone branches

Run the discovery script to fetch the latest remote state and identify gone branches:

```bash
bash scripts/clean-gone
```

[scripts/clean-gone](./scripts/clean-gone)

The script runs `git fetch --prune` first, then parses `git branch -vv` for branches marked `: gone]`.

If the script outputs `__NONE__`, report that no stale branches were found and stop.

### Step 2: Present branches and ask for confirmation

Show the user the list of branches that will be deleted, including their state:

```
These local branches have been deleted from the remote:

  - feature/old-thing (SYNCHRONIZED)
  - bugfix/resolved-issue (GONE)
  - experiment/abandoned (BEHIND)

Delete all of them? (y/n)
```

Wait for the user's answer using the platform's blocking question tool: `AskUserQuestion` in Claude Code (call `ToolSearch` with `select:AskUserQuestion` first if its schema is not loaded), `request_user_input` in Codex, `ask_user` in Gemini, `ask_user` in Pi (requires the `pi-ask-user` extension). Fall back to presenting the list in chat only when no blocking tool exists in the harness or the call errors (e.g., Codex edit modes) — not because a schema load is required. Never silently skip the question.

This is a yes-or-no decision on the entire list -- do not offer multi-selection or per-branch choices.

### Step 3: Delete confirmed branches

If the user confirms, delete each branch. For each branch:

1. Check if it has an associated worktree (`git worktree list | grep "\\[$branch\\]"`)
2. If a worktree exists and is not the main repo root, remove it first: `git worktree remove --force "$worktree_path"`
3. Delete the branch: `git branch -D "$branch"`

Report results as you go:

```
Removed worktree: .worktrees/feature/old-thing
Deleted branch: feature/old-thing
Deleted branch: bugfix/resolved-issue
Deleted branch: experiment/abandoned

Cleaned up 3 branches.
```

If the user declines, acknowledge and stop without deleting anything.

## Integration with ce-commit-push-pr

When `ce-commit-push-pr` completes a PR creation:

1. **If PR was just created** — Step 6 already offers local branch cleanup. If user accepts, use this skill's confirmation flow instead of raw `git branch -d`.

2. **If PR was merged** — detect via `gh pr view --json state` and offer to clean up:
   ```bash
   gh pr view <PR_NUMBER> --json state,headRefName --jq '"\(.state) \(.headRefName)"'
   # Output: "MERGED feature/my-branch"
   # Offer: "PR merged. Delete local branch feature/my-branch? (y/n)"
   ```

3. **After cleanup** — switch to default branch and prune remote refs:
   ```bash
   git checkout <default_branch>
   git fetch origin --prune
   ```
