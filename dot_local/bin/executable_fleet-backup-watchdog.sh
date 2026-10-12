#!/bin/bash
# Alerts via ntfy if the last fleet agent-state backup is older
# than 26 hours, failed, or has never run. Shared the machine's
# fleet-backup env for the ntfy token; status lives in
# ~/.local/state/fleet-backup/.backup-status.json.

RESTIC_ENV="${RESTIC_ENV:-$HOME/.config/fleet-backup/restic-env}"
STATE_DIR="${STATE_DIR:-$HOME/.local/state/fleet-backup}"
STATUS_FILE="${STATE_DIR}/.backup-status.json"
SHARED_SECRETS="${SHARED_SECRETS:-$HOME/.config/fleet-backup/restic-shared-secrets}"

ENV_LOAD_STATUS=0
if [ -f "$RESTIC_ENV" ]; then
  # shellcheck source=/dev/null
  source "$RESTIC_ENV" || ENV_LOAD_STATUS=$?
else
  ENV_LOAD_STATUS=1
fi

if [ "$ENV_LOAD_STATUS" -ne 0 ] || [ -z "${NTFY_TOKEN:-}" ]; then
  # shellcheck source=/dev/null
  [ -f "$SHARED_SECRETS" ] && source "$SHARED_SECRETS"
fi

NTFY_URL="${NTFY_URL:-https://ntfy.phillias.cc/SelfHostNetSec}"
HOST_TAG="${HOST_TAG:-unknown}"
MAX_AGE_H=26

alert() {
  if [ -z "${NTFY_TOKEN:-}" ]; then
    echo "Backup watchdog could not send alert: NTFY_TOKEN is not set. Alert body: $1" >&2
    exit 1
  fi
  if curl -sf \
    -H "Authorization: Bearer ${NTFY_TOKEN}" \
    -H "Title: Backup watchdog - agent state (${HOST_TAG})" \
    -H "Priority: urgent" \
    -d "$1" \
    "${NTFY_URL}" >/dev/null 2>&1; then
    echo "Backup watchdog alert sent: $1" >&2
  else
    echo "Backup watchdog failed to send ntfy alert. Alert body: $1" >&2
    exit 1
  fi
  exit 0
}

if [ "$ENV_LOAD_STATUS" -ne 0 ]; then
  alert "Backup env could not be loaded from ${RESTIC_ENV}; host may not be registered in fleet.toml."
fi

if [ -z "$HOST_TAG" ] || [ "$HOST_TAG" = "unknown" ]; then
  alert "Host not registered in fleet.toml (HOST_TAG=${HOST_TAG:-unset}); backup env rendered an invalid fleet node."
fi

if [ -z "${RESTIC_PASSWORD:-}" ]; then
  alert "Backup env did not load a per-host RESTIC_PASSWORD for ${HOST_TAG}; check restic-password-${HOST_TAG} deployment."
fi

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
