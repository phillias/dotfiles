#!/bin/bash
# Alerts via ntfy if the last fleet agent-state backup is older
# than 26 hours, failed, or has never run. Shared the machine's
# fleet-backup env for the ntfy token; status lives in
# ~/.local/state/fleet-backup/.backup-status.json.

RESTIC_ENV="${RESTIC_ENV:-$HOME/.config/fleet-backup/restic-env}"
STATE_DIR="${STATE_DIR:-$HOME/.local/state/fleet-backup}"
STATUS_FILE="${STATE_DIR}/.backup-status.json"

# shellcheck source=/dev/null
[ -f "$RESTIC_ENV" ] && source "$RESTIC_ENV"

NTFY_URL="${NTFY_URL:-https://ntfy.phillias.cc/SelfHostNetSec}"
HOME_TAG="${HOST_TAG:-$(hostname -s)}"
MAX_AGE_H=26

alert() {
  if [ -n "${NTFY_TOKEN:-}" ]; then
    curl -sf \
      -H "Authorization: Bearer ${NTFY_TOKEN}" \
      -H "Title: Backup watchdog — agent state (${HOME_TAG})" \
      -H "Priority: urgent" \
      -d "$1" \
      "${NTFY_URL}" >/dev/null 2>&1 || true
  fi
  exit 0
}

[ -n "${NTFY_TOKEN:-}" ] || exit 0

if [ ! -f "$STATUS_FILE" ]; then
  alert "No backup status file exists — backup has never run. See ${STATE_DIR}"
fi

LAST=$(python3 -c "import json; print(json.load(open('${STATUS_FILE}'))['last_backup'])" 2>/dev/null)
STATUS=$(python3 -c "import json; print(json.load(open('${STATUS_FILE}'))['last_status'])" 2>/dev/null)

[ -n "${LAST:-}" ] || alert "Status file unreadable: ${STATUS_FILE}"

AGE_H=$(( ( $(date -u +%s) - $(date -u -d "${LAST}" +%s) ) / 3600 ))

if [ "${STATUS:-unknown}" != "ok" ]; then
  alert "Last backup FAILED (at ${LAST}). See ${STATE_DIR}/restic-backup.log"
elif [ "$AGE_H" -gt "$MAX_AGE_H" ]; then
  alert "Last backup is ${AGE_H}h old (> ${MAX_AGE_H}h). See ${STATE_DIR}/restic-backup.log"
fi

exit 0
