#!/usr/bin/env bash
# fm-drift-pr.sh — capture drift-applied chezmoi files and PR them to dotfiles.
#
# The catalog-drift gate applies auto-writes to chezmoi-managed files
# (opencode-fallback.jsonc, models.snapshot.json, opencode-omo-config SKILL.md,
# ...). After applying, the gate runs this script so every such update is
# re-added into the chezmoi source tree and lands as a pull request against
# the dotfiles default branch.
#
# Usage: fm-drift-pr.sh [--dry-run] [<dest-file> ...]
#   No args = use the default drift-affected paths.
#   The script never discards work: it commits the given files on a fresh
#   branch from the dotfiles default branch, pushes, and opens a PR.

set -euo pipefail

CHEZMOI_SRC="${CHEZMOI_SRC:-$HOME/.local/share/chezmoi}"
STATE_DIR="$HOME/.local/state/opencode-fleet"
DRIFT_JSON="$STATE_DIR/catalog-drift.json"

DEFAULT_FILES=(
  "$HOME/.config/opencode/opencode-fallback.jsonc"
  "$HOME/.agents/skills/opencode-omo-config/models.snapshot.json"
  "$HOME/.agents/skills/opencode-omo-config/SKILL.md"
)

DRY_RUN=0
FILES=()
MESSAGE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --message) MESSAGE="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    -*) echo "error: unknown flag $1" >&2; exit 2 ;;
    *) FILES+=("$1"); shift ;;
  esac
done
if [ "${#FILES[@]}" -eq 0 ]; then
  FILES=("${DEFAULT_FILES[@]}")
fi

if [ ! -d "$CHEZMOI_SRC/.git" ]; then
  echo "error: $CHEZMOI_SRC is not a git repo" >&2
  exit 2
fi

export GIT_AUTHOR_NAME="${OPENCODE_MODEL:-firstmate}@$(hostname -s)"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"

BASE_BRANCH=$(git -C "$CHEZMOI_SRC" rev-parse --abbrev-ref refs/remotes/origin/HEAD | sed 's|^origin/||')
BRANCH="fm/catalog-drift-$(date +%Y%m%d-%H%M%S)"

summary="$MESSAGE"
if [ -z "$summary" ]; then
  summary="catalog drift update"
  if [ -f "$DRIFT_JSON" ]; then
    d=$(node -e "try{const d=require('$DRIFT_JSON');const x=d.drift||{};process.stdout.write(''+x.added.length+' added, '+x.removed.length+' removed, '+x.price.length+' price>=25%')}catch(e){process.stdout.write('catalog drift')}" 2>/dev/null || true)
    [ -n "$d" ] && summary="$d"
  fi
fi

git -C "$CHEZMOI_SRC" fetch origin -q

STAGED=()
for f in "${FILES[@]}"; do
  [ -e "$f" ] || { echo "skip (missing): $f" >&2; continue; }
  chezmoi re-add "$f" >/dev/null 2>&1 || true
  src=$(chezmoi source-path "$f" 2>/dev/null || true)
  if [ -n "$src" ] && [ -e "$src" ]; then
    STAGED+=("$src")
  else
    echo "warning: no source path for $f" >&2
  fi
done

if [ "${#STAGED[@]}" -eq 0 ]; then
  echo "error: nothing to PR — no chezmoi-managed source paths resolved" >&2
  exit 2
fi

git -C "$CHEZMOI_SRC" add -- "${STAGED[@]}"

if [ "$DRY_RUN" -eq 1 ]; then
  git -C "$CHEZMOI_SRC" diff --cached --stat
  echo "dry-run: would branch fm/catalog-drift-* from origin/$BASE_BRANCH and PR 'chore(opencode): $summary'"
  git -C "$CHEZMOI_SRC" reset -q
  exit 0
fi

if ! git -C "$CHEZMOI_SRC" switch -c "$BRANCH" "origin/$BASE_BRANCH" 2>/dev/null; then
  echo "error: cannot create branch from origin/$BASE_BRANCH — working tree conflicts; commit or stash unrelated changes first" >&2
  exit 2
fi

git -C "$CHEZMOI_SRC" commit -q -m "chore(opencode): $summary" || { echo "error: nothing staged after re-add" >&2; exit 2; }

git -C "$CHEZMOI_SRC" push -q -u origin "$BRANCH"
PR_URL=$(gh pr create --repo phillias/dotfiles --base "$BASE_BRANCH" --head "$BRANCH" \
  --title "chore(opencode): $summary" \
  --body "Automated catalog-drift update from the runtime-fallback system.

- Re-added chezmoi-managed files: ${STAGED[*]##*/}
- $summary
- Gate criteria: captain-approved 2026-08-08 (removals auto; >=25% blended tokens-per-dollar two-sided; strict-domination new models; proposals for cross-tier / primary / known-failure changes).")
echo "PR: $PR_URL"
