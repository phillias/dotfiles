#!/usr/bin/env bash
# fleet-note.sh — record a durable decision + rationale for a fleet task key.
#
# The fleet state sidecar (~/.local/state/opencode-fleet/) is written by the
# fleet-state-writer plugin and by this script. Decisions are authored by
# whichever agent orchestrates the work — firstmate, Sisyphus, or any other
# harness — at dispatch time (why run) and at terminal outcome (merged, PR,
# discarded). The record is harness-agnostic: a plain CLI, no plugin involved.
#
# Usage:
#   fleet-note.sh <key> --decision "<text>" [--rationale "<text>"] [--type <dispatch|merge|teardown|other>]
#
#   <key>       a fleet task key: ses_... or bg_...
#   --decision  required, non-empty — the decision
#   --rationale optional supporting context
#   --type      defaults to "other"
#
# Writes:
#   wake.log       one append:  <ISO>\tfleet.decision\t<key>\tdecision=... rationale=...
#   decisions.tsv  sidecar:     <key>\t<ISO>\t<type>\t<decision>\t<rationale>
#
# Never touches state.json: the plugin owns that whole-file rewrite and this
# script's appends must not race it. Appends are flock-guarded. Exit non-zero
# without writing on bad arguments (fail-closed, like fm-send).
set -eu

STATE_DIR="${FLEET_STATE_DIR:-${HOME}/.local/state/opencode-fleet}"
WAKE_LOG="${STATE_DIR}/wake.log"
DECISIONS_TSV="${STATE_DIR}/decisions.tsv"
LOCK="${STATE_DIR}/.fleet-note.lock"

key=""
decision=""
rationale=""
type="other"

usage() {
  sed -n '2,22p' "$0"
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --decision)
      decision="${2:-}"
      shift 2
      ;;
    --rationale)
      rationale="${2:-}"
      shift 2
      ;;
    --type)
      type="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    -*)
      echo "unknown flag: $1" >&2
      exit 2
      ;;
    *)
      if [[ -z "$key" ]]; then
        key="$1"
      else
        echo "unexpected argument: $1" >&2
        exit 2
      fi
      shift
      ;;
  esac
done

# Fail closed: refuse unresolved keys and empty decisions.
case "$key" in
  ses_*|bg_*)
    ;;
  *)
    echo "error: key must look like ses_... or bg_... (got: ${key:-<empty>})" >&2
    exit 1
    ;;
esac
if [[ -z "$decision" ]]; then
  echo "error: --decision is required and must be non-empty" >&2
  exit 1
fi

mkdir -p "$STATE_DIR"

# Sanitize: tabs and newlines cannot live in TSV fields.
clean() { printf '%s' "$1" | tr '\t\n' '  '; }
decision_c="$(clean "$decision")"
rationale_c="$(clean "$rationale")"
type_c="$(clean "$type")"

iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

{
  flock 9
  printf '%s\tfleet.decision\t%s\tdecision=%s rationale=%s\n' \
    "$iso" "$key" "$decision_c" "$rationale_c" >> "$WAKE_LOG"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$key" "$iso" "$type_c" "$decision_c" "$rationale_c" >> "$DECISIONS_TSV"
} 9>"$LOCK"

echo "recorded fleet decision for $key"
