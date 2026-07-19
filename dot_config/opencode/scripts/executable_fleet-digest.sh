#!/usr/bin/env bash
# fleet-digest.sh — terse summary of recent fleet state.
#
# Reads ~/.local/state/opencode-fleet/{digest.txt,wake.log,state.json}
# and emits a single block Sisyphus can scan in one glance.
#
# Usage:
#   fleet-digest.sh              # show digest + wakes from last 30 minutes
#   fleet-digest.sh --since 60   # show wakes from last 60 minutes
#   fleet-digest.sh --wakes-only # just recent wake events
#   fleet-digest.sh --json       # raw state.json
#
# Output format (default):
#   == fleet state (ISO timestamp) ==
#   <key>\t<status>\t<type>\t<digest>\t<age> ago
#   ...
#
#   == wakes since 30m ago (cutoff ISO) ==
#   <ISO-timestamp>\t<type>\t<sessionID>\t<digest>
#   ...
#
# Zero LLM cost. Pure bash. Sisyphus reads via `bash fleet-digest.sh`.

set -euo pipefail

STATE_DIR="${HOME}/.local/state/opencode-fleet"
WAKE="${STATE_DIR}/wake.log"
DIGEST="${STATE_DIR}/digest.txt"
STATE="${STATE_DIR}/state.json"

SINCE_MIN=30
WAKES_ONLY=false
JSON_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)
      SINCE_MIN="$2"
      shift 2
      ;;
    --wakes-only)
      WAKES_ONLY=true
      shift
      ;;
    --json)
      JSON_ONLY=true
      shift
      ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      echo "unknown flag: $1" >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "$STATE_DIR" ]]; then
  echo "fleet: no state dir at $STATE_DIR"
  exit 0
fi

if $JSON_ONLY; then
  if [[ -s "$STATE" ]]; then cat "$STATE"; else echo "{}"; fi
  exit 0
fi

if ! $WAKES_ONLY; then
  echo "== fleet state ($(date -Iseconds)) =="
  if [[ -s "$DIGEST" ]]; then
    cat "$DIGEST"
  else
    echo "(empty — no dispatched tasks recorded yet)"
  fi
fi

if [[ -s "$WAKE" ]]; then
  cutoff=$(date -u -d "${SINCE_MIN} minutes ago" +%Y-%m-%dT%H:%M 2>/dev/null || true)
  if [[ -n "$cutoff" ]]; then
    recent=$(awk -F'\t' -v cut="$cutoff" '$1 >= cut' "$WAKE" | tail -20)
    if [[ -n "$recent" ]]; then
      echo ""
      echo "== wakes since ${SINCE_MIN}m ago (cutoff ${cutoff} UTC) =="
      printf '%s\n' "$recent"
    fi
  fi
fi