#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Fleet agent-state restic backup — distributed via chezmoi.
# Host-agnostic: all machine-specific values (repo URL, restic
# password, OCI S3 HMAC keys, ntfy token, BACKUP_PATHS, EXCLUDES)
# come from ~/.config/fleet-backup/restic-env (age-encrypted in
# the dotfiles source — chezmoi add --encrypt). The target OCI
# bucket is fleet-shared; each host uses its own repo subpath and
# password so snapshots never collide.
#
# One-time bootstrap per host (NOT done by this script):
#   mkdir -p ~/.config/fleet-backup ~/.local/state/fleet-backup
#   # author restic-env (keys from vault/bws, unique RESTIC_PASSWORD)
#   source "$HOME/.config/fleet-backup/restic-env" && restic init
# Then enable: systemctl --user enable --now fleet-backup.timer fleet-backup-watchdog.timer
#
# Schedule: daily 03:30 via fleet-backup.timer (+ watchdog 06:00)
# Retention: 7d/4w/12m. Notify: ntfy SelfHostNetSec (ok = min, fail = urgent)
# ─────────────────────────────────────────────────────────────

RESTIC_ENV="${RESTIC_ENV:-$HOME/.config/fleet-backup/restic-env}"
STATE_DIR="${STATE_DIR:-$HOME/.local/state/fleet-backup}"
LOG_FILE="${STATE_DIR}/restic-backup.log"
STATUS_FILE="${STATE_DIR}/.backup-status.json"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
fail() { log "FATAL: $*"; exit 1; }

[ -f "$RESTIC_ENV" ] || fail "${RESTIC_ENV} not found (see bootstrap comment in the script header)"
# shellcheck source=/dev/null
source "$RESTIC_ENV"
mkdir -p "$STATE_DIR"

HOST_TAG="${HOST_TAG:-$(hostname -s)}"

log "=== Fleet agent-state backup started (${HOST_TAG}) ==="

# Required from the env file: RESTIC_REPOSITORY, RESTIC_PASSWORD,
# AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, BACKUP_PATHS (array).
: "${RESTIC_REPOSITORY:?}" "${RESTIC_PASSWORD:?}" "${AWS_ACCESS_KEY_ID:?}" "${AWS_SECRET_ACCESS_KEY:?}" "${BACKUP_PATHS[*]:?}"

# Only paths that exist — self-healing when a dir is later removed.
EXISTING_PATHS=()
for p in "${BACKUP_PATHS[@]}"; do
  if [ -e "$p" ]; then
    EXISTING_PATHS+=("$p")
  else
    log "  SKIP $p (does not exist)"
  fi
done
[ "${#EXISTING_PATHS[@]}" -gt 0 ] || fail "no backup paths exist"

# Optional excludes from the env file (default empty).
EXCLUDES=("${EXCLUDES[@]:-}")

# ── Step 1: Restic backup ──────────────────────────────────
log "--- Step 1: restic backup ---"

RESTIC_EXIT=0
restic backup --tag "${HOST_TAG}" "${EXCLUDES[@]}" "${EXISTING_PATHS[@]}" 2>&1 | tee -a "${LOG_FILE}" || RESTIC_EXIT=$?

if [ "$RESTIC_EXIT" -eq 0 ]; then
  log "  backup OK"
elif [ "$RESTIC_EXIT" -eq 1 ] || [ "$RESTIC_EXIT" -eq 3 ]; then
  # restic: 1 = warnings, 3 = snapshot saved but some source files unread.
  # In both cases the snapshot exists and is restorable.
  log "  backup OK with warnings (exit ${RESTIC_EXIT} — snapshot saved)"
else
  log "  backup FAILED (exit code: ${RESTIC_EXIT})"
fi

# ── Step 2: Forget & prune ─────────────────────────────────
log "--- Step 2: forget --prune ---"

if restic forget \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 12 \
  --prune 2>&1 | tee -a "${LOG_FILE}"; then
  log "  forget OK"
else
  log "  forget FAILED"
fi

# ── Step 3: Write status file ──────────────────────────────
log "--- Step 3: write status ---"

SNAP_COUNT=$(restic snapshots --json 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

SNAP_TOTAL=$(restic stats --mode raw-data --json 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
b = d.get('total_size', 0)
for u in ['B','KiB','MiB','GiB','TiB']:
    if b < 1024: print(f'{b:.1f} {u}'); break
    b /= 1024
" 2>/dev/null || echo "unknown")

LAST_TIME=$(restic snapshots --json 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
if d: print(d[-1].get('time','unknown')[:19])
" 2>/dev/null || echo "unknown")

if [ "${SNAP_COUNT:-0}" -gt 0 ]; then
  LAST_STATUS="ok"
else
  LAST_STATUS="failed"
fi

NOW=$(date -u +"%Y-%m-%dT%H:%M:%S")

python3 -c "
import json
data = {
    'last_backup': '${NOW}',
    'snapshot_count': ${SNAP_COUNT},
    'total_size_human': '${SNAP_TOTAL}',
    'last_time': '${LAST_TIME}',
    'last_status': '${LAST_STATUS}',
    'host': '${HOST_TAG}',
    'repo': '${RESTIC_REPOSITORY}',
}
with open('${STATUS_FILE}', 'w') as f:
    json.dump(data, f, indent=2)
" 2>>"${LOG_FILE}" && log "  status written" || log "  status write failed"

# ── Step 4: ntfy notification ──────────────────────────────
log "--- Step 4: ntfy notification ---"

NTFY_URL="${NTFY_URL:-https://ntfy.phillias.cc/SelfHostNetSec}"

if [ "$LAST_STATUS" = "ok" ]; then
  NTFY_PRIORITY="min"
  NTFY_TITLE="Backup OK — agent state (${HOST_TAG})"
  NTFY_BODY="${SNAP_COUNT} snapshots | ${SNAP_TOTAL} | Retention: 7d/4w/12m"
else
  NTFY_PRIORITY="urgent"
  NTFY_TITLE="Backup FAILED — agent state (${HOST_TAG})"
  NTFY_BODY="Snapshots: ${SNAP_COUNT} | Total: ${SNAP_TOTAL} | See ${LOG_FILE}"
fi

if [ -n "${NTFY_TOKEN:-}" ]; then
  if curl -sf \
    -H "Authorization: Bearer ${NTFY_TOKEN}" \
    -H "Title: ${NTFY_TITLE}" \
    -H "Priority: ${NTFY_PRIORITY}" \
    -d "${NTFY_BODY}" \
    "${NTFY_URL}" >/dev/null 2>&1; then
    log "  ntfy sent: ${NTFY_TITLE}"
  else
    log "  ntfy failed (non-critical)"
  fi
fi

log "=== Fleet agent-state backup completed ==="
