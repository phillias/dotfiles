#!/usr/bin/env bash
# swarm-lint.sh — flag open fleet issues with no swarm/* label that show work
# activity (assignee, or >=2 comments). Those are thin cards being picked up
# without promotion to a charter.
#
# Silent when conforming (every open issue is either labeled or inactive), so
# it is usable as an fm-check script: stdout lines become watcher wakes, and
# silence is a proven no-op.
#
# Config:
#   SWARM_LINT_REPOS        space-separated repos (default: phillias/dotfiles
#                           phillias/selfhost)
#   SWARM_LINT_MIN_COMMENTS comment threshold (default: 2)
set -u

REPOS=${SWARM_LINT_REPOS:-phillias/dotfiles phillias/selfhost}
MIN_COMMENTS=${SWARM_LINT_MIN_COMMENTS:-2}

command -v gh >/dev/null 2>&1 || { echo "swarm-lint: gh missing"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "swarm-lint: jq missing"; exit 0; }

for repo in $REPOS; do
  gh api "repos/$repo/issues?state=open&per_page=100" 2>/dev/null |
    jq -r --arg repo "$repo" --argjson minc "$MIN_COMMENTS" '
      .[] | select(.pull_request == null)
      | select(([.labels[].name] | map(select(startswith("swarm/"))) | length) == 0)
      | select((.comments >= $minc) or ((.assignees | length) > 0))
      | [(.assignees | length), .comments, .number, .title]
      | "\($repo)#\(.[2])\tlabel=MISSING\tactivity=\(if .[0] > 0 then "assigned," else "" end)comments:\(.[1])\t\(.[3])"
    '
done

exit 0
