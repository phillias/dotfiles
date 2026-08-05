#!/usr/bin/env bash
# Self-improvement drain driver. Deterministic gate first (zero tokens when
# nothing to do); only when a queue is non-empty does it pay for a headless
# opencode run that actually harvests.
# Gate: cues.tsv non-empty OR skills_review.tsv non-empty OR review-pending.tsv absent-but-flagged
set -eu
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/opencode-selflearning"
CUES="$STATE/cues.tsv"
REVIEW="$STATE/skills_review.tsv"
LOG="$STATE/selfimprove-drain.log"

needs_run=0
[ -s "$CUES" ] && needs_run=1
[ -s "$REVIEW" ] && needs_run=1
[ "$needs_run" -eq 0 ] && exit 0

mkdir -p "$STATE"
{
  echo "== $(date -u +%FT%TZ) drain start =="
  opencode run --pure --agent self-improve "Run your full self-improvement drain procedure now." --format json 2>&1 || echo "drain failed: $?"
  echo "== $(date -u +%FT%TZ) drain end =="
} >> "$LOG" 2>&1
