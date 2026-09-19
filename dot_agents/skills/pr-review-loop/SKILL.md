---
name: pr-review-loop
description: Loop on a PR, addressing bot comments (CodeRabbit, Greptile, etc.) and merge when all bots are satisfied. Use when asked to iterate on a PR until bot approval.
user-invocable: true
---

# pr-review-loop

Iteratively address bot review comments on a PR until all automated reviewers are satisfied, then merge.

## When to Use

When the captain asks you to:
- "Loop on PR#XXX until CodeRabbit approves"
- "Address bot comments and merge when ready"
- "Iterate on PR until all bots are satisfied"

## Standard Instruction Pattern

Tell the captain to use:

```
Loop on PR#XXX every 5 minutes for up to <timeout>, addressing all bot comments.
Merge when: unresolved=0, all checks pass, mergeStateStatus=CLEAN.
```

Example:
```
Loop on PR#313 every 5 minutes for up to 90 minutes, addressing all CodeRabbit comments.
Merge when CodeRabbit has no unresolved issues and all checks pass.
```

## Bot Satisfaction Detection

### Signal Checklist

All must be true before merge:

1. **Unresolved bot comments = 0**

   ```bash
   gh api "repos/$REPO/pulls/$PR/comments?per_page=100" | \
     jq '[.[] | select(.user.login | test("coderabbitai|greptile")) | 
          select(.body | contains("🎯") or contains("Critical") or contains("Major") or contains("Minor")) | 
          select(.body | contains("✅") | not)] | length'
   ```

   Result must be: **0**

2. **All CI checks passing**

   ```bash
   gh pr checks $PR --repo $REPO
   ```

   All lines must show: **pass**

3. **Merge state is CLEAN**

   ```bash
   gh pr view $PR --repo $REPO --json mergeable,mergeStateStatus
   ```

   Must return: `"mergeable": true`, `"mergeStateStatus": "CLEAN"`

### CodeRabbit-Specific Notes

- Reviews stay in **"COMMENTED"** state even when satisfied (not "APPROVED")
- Look for absence of new 🎯 emoji comments after your commit
- Wait ~5 minutes after push before checking again
- Check that latest review commit_id matches your latest commit

### Greptile Notes

- Greptile may have credit limits (50 credits for trial accounts)
- Check for explicit approval or absence of critical findings

## Workflow

1. **Fetch latest bot comments**

   ```bash
   gh api "repos/$REPO/pulls/$PR/comments?per_page=100" | \
     jq -r '.[] | select(.user.login | test("coderabbitai|greptile")) | 
          select(.body | contains("🎯") or contains("Critical") or contains("Major")) | 
          select(.body | contains("✅") | not)'
   ```

2. **If comments found:**
   - Parse comment body for issue description
   - Fix the issue in the code
   - Commit with descriptive message referencing the feedback
   - Push to PR branch
   - Reply to comment: `✅ Fixed in commit <sha>`
   - Wait 5 minutes for bot to re-review

3. **If no unresolved comments:**
   - Verify all checks passing
   - Verify mergeStateStatus is CLEAN
   - Merge the PR:

     ```bash
     gh pr merge $PR --repo $REPO --merge
     ```

4. **After merge:**
   - Pull latest master/main
   - Verify merge commit exists
   - Report success to captain

## Timeout Handling

If timeout reached but PR is mergeable:
- Stop and report current status
- Ask captain: "Timeout reached. PR is mergeable with all checks passing. Should I merge?"

If timeout reached with unresolved comments:
- Stop and report which comments remain
- Ask captain for guidance

## Detection Script

Save as `~/.local/bin/pr-ready-check`:

```bash
#!/bin/bash
set -euo pipefail

PR=${1:?Usage: pr-ready-check PR_NUMBER [REPO]}
REPO=${2:-phillias/dotfiles}

# Unresolved bot comments
UNRESOLVED=$(gh api "repos/$REPO/pulls/$PR/comments?per_page=100" 2>/dev/null | \
  jq '[.[] | select(.user.login | test("coderabbitai|greptile")) | 
       select(.body | test("🎯|Critical|Major|Minor")) | 
       select(.body | contains("✅") | not)] | length' 2>/dev/null || echo "error")

if [ "$UNRESOLVED" = "error" ]; then
  echo "ERROR: Failed to fetch comments"
  exit 2
fi

# All checks passing
CHECKS_OUTPUT=$(gh pr checks $PR --repo $REPO 2>&1 || true)
if echo "$CHECKS_OUTPUT" | grep -q "fail\|pending"; then
  CHECKS="fail"
else
  CHECKS="pass"
fi

# Mergeable state
MERGEABLE=$(gh pr view $PR --repo $REPO --json mergeable,mergeStateStatus 2>/dev/null | \
  jq -r '.mergeable, .mergeStateStatus' | tr '\n' ' ')

if [ "$UNRESOLVED" -eq 0 ] && [ "$CHECKS" = "pass" ] && echo "$MERGEABLE" | grep -q "true.*CLEAN"; then
  echo "READY TO MERGE"
  echo "  Unresolved: $UNRESOLVED"
  echo "  Checks: $CHECKS"
  echo "  Mergeable: $MERGEABLE"
  exit 0
else
  echo "NOT READY"
  echo "  Unresolved: $UNRESOLVED"
  echo "  Checks: $CHECKS"
  echo "  Mergeable: $MERGEABLE"
  exit 1
fi
```

Make executable: `chmod +x ~/.local/bin/pr-ready-check`

## Common Bot Comment Patterns

### CodeRabbit

- **Critical**: `🔴 Critical` - Must fix before merge
- **Major**: `🟠 Major` - Should fix, blocks approval
- **Minor**: `🟡 Minor` - Nice to have, may not block
- **Resolved**: Look for `✅ Addressed in commit` replies

### Greptile

- Comments typically in plain text
- Check for explicit "approved" or absence of blocking issues
- May hit credit limits (50 credits for trial)

## Example Session

```bash
# Captain: "Loop on PR#313 every 5 minutes for up to 90 minutes"

# Check 1: Unresolved comments found
gh api repos/phillias/dotfiles/pulls/313/comments | \
  jq -r '.[] | select(.user.login == "coderabbitai[bot]") | .body' | head -20
# → Found: "Remove the unmatched `fi` from dot_bashrc"

# Fix issue
vim ~/.local/share/chezmoi/dot_bashrc
git commit -am "fix: remove extra fi per CodeRabbit"
git push

# Reply to comment
gh api repos/phillias/dotfiles/pulls/313/comments/12345/replies \
  -X POST -f body="✅ Fixed in commit abc1234"

# Wait 5 minutes
sleep 300

# Check 2: No unresolved, all checks pass, CLEAN
pr-ready-check 313 phillias/dotfiles
# → READY TO MERGE

# Merge
gh pr merge 313 --repo phillias/dotfiles --merge

# Verify
gh pr view 313 --repo phillias/dotfiles --json state,mergedAt
# → {"mergedAt":"2026-09-19T02:24:49Z","state":"MERGED"}
```

## Integration with no-mistakes

This skill complements `no-mistakes` for post-PR creation iteration:
- `no-mistakes` handles: code → validation → PR creation
- `pr-review-loop` handles: PR → bot feedback → fixes → merge

Use both together for complete ship-to-merge flow.
