#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Fleet agent-state restic backup — distributed via chezmoi.
# Host-agnostic: all machine-specific values come from
# ~/.config/fleet-backup/restic-env, which is a chezmoi template
# (restic-env.tmpl) that sources two age-encrypted files:
#   - restic-shared-secrets  (AWS keys, ntfy token, OCI bucket base URL)
#   - restic-password-<node> (unique RESTIC_PASSWORD per fleet node)
# The template sets per-host RESTIC_REPOSITORY (bucket_base/<node>),
# BACKUP_PATHS, HOST_TAG, and EXCLUDES. Each host gets its own
# repo subpath and password so snapshots never collide.
#
# One-time bootstrap per host:
#   mkdir -p ~/.config/fleet-backup ~/.local/state/fleet-backup
#   chezmoi apply   # deploys restic-env + shared-secrets + per-host password
# Repository init is automatic: the script initializes it on first run.
# Then enable: systemctl --user enable --now fleet-backup.timer fleet-backup-watchdog.timer
#
# Schedule: daily 03:30 via fleet-backup.timer (+ watchdog 06:00)
# Retention: 7d/4w/12m. Notify: ntfy SelfHostNetSec (success = min, fail = urgent)
# ─────────────────────────────────────────────────────────────

RESTIC_ENV="${RESTIC_ENV:-$HOME/.config/fleet-backup/restic-env}"
STATE_DIR="${STATE_DIR:-$HOME/.local/state/fleet-backup}"
LOG_FILE="${STATE_DIR}/restic-backup.log"
STATUS_FILE="${STATE_DIR}/.backup-status.json"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
fail() { log "FATAL: $*"; exit 1; }

mkdir -p "$STATE_DIR"
[ -f "$RESTIC_ENV" ] || fail "${RESTIC_ENV} not found (see bootstrap comment in the script header)"
set +e +u
# shellcheck source=/dev/null
source "$RESTIC_ENV"
ENV_LOAD_STATUS=$?
set -euo pipefail
if [ "$ENV_LOAD_STATUS" -ne 0 ]; then
  fail "failed to source ${RESTIC_ENV}; check fleet node registration and per-host password deployment"
fi

HOST_TAG="${HOST_TAG:-}"
if [ -z "$HOST_TAG" ] || [ "$HOST_TAG" = "unknown" ]; then
  fail "host not registered in fleet.toml (HOST_TAG=${HOST_TAG:-unset}); re-render ${RESTIC_ENV} from dotfiles"
fi

case "${RESTIC_REPOSITORY:-}" in
  ""|*/unknown)
    fail "RESTIC_REPOSITORY is missing or points at an unknown fleet node (${RESTIC_REPOSITORY:-unset})"
    ;;
esac

if [ -z "${RESTIC_PASSWORD:-}" ]; then
  fail "RESTIC_PASSWORD is missing for ${HOST_TAG}; check restic-password-${HOST_TAG} deployment"
fi

log "=== Fleet agent-state backup started (${HOST_TAG}) ==="

# Required from the env file: RESTIC_REPOSITORY, RESTIC_PASSWORD,
# AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, BACKUP_PATHS (array).
: "${RESTIC_REPOSITORY:?}" "${RESTIC_PASSWORD:?}" "${AWS_ACCESS_KEY_ID:?}" "${AWS_SECRET_ACCESS_KEY:?}" "${HOST_TAG:?}" "${BACKUP_PATHS[*]:?}"

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

# ── Step 1: Restic backup (auto-init on exit 10, one retry) ─
log "--- Step 1: restic backup ---"

RESTIC_EXIT=0
restic backup --tag "${HOST_TAG}" "${EXCLUDES[@]}" "${EXISTING_PATHS[@]}" 2>&1 | tee -a "${LOG_FILE}" || RESTIC_EXIT=$?

if [ "$RESTIC_EXIT" -eq 10 ]; then
  log "  repository missing (exit 10) — initializing, then retrying backup once"
  if restic init 2>&1 | tee -a "${LOG_FILE}"; then
    RESTIC_EXIT=0
    restic backup --tag "${HOST_TAG}" "${EXCLUDES[@]}" "${EXISTING_PATHS[@]}" 2>&1 | tee -a "${LOG_FILE}" || RESTIC_EXIT=$?
  else
    RESTIC_EXIT=$?
    log "  restic init FAILED (exit ${RESTIC_EXIT})"
  fi
fi

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
  FORGET_EXIT=0
  log "  forget OK"
else
  FORGET_EXIT=$?
  log "  forget FAILED"
fi

# ── Step 3: Verify repository & snapshots ──────────────────
log "--- Step 3: verify repository ---"

VERIFY_EXIT=0
VERIFY_RESULT="unknown"

if [ "$RESTIC_EXIT" -eq 0 ]; then
  if restic check 2>&1 | tee -a "${LOG_FILE}"; then
    VERIFY_RESULT="ok"
    log "  verification passed (snapshot data is restorable)"
  else
    VERIFY_EXIT=$?
    VERIFY_RESULT="failed"
    log "  verification FAILED (exit ${VERIFY_EXIT})"
  fi
else
  VERIFY_RESULT="skipped"
  log "  verification skipped (backup exit ${RESTIC_EXIT})"
fi

if [ "$RESTIC_EXIT" -eq 0 ] && [ "$FORGET_EXIT" -eq 0 ] && [ "$VERIFY_EXIT" -eq 0 ]; then
  RESTIC_STATUS="success"
else
  RESTIC_STATUS="failed"
fi

# ── Step 4: Write status file ──────────────────────────────
log "--- Step 4: write status ---"

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

SNAP_ID=$(restic snapshots --json 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
if d: print(d[-1].get('id','unknown'))
" 2>/dev/null || echo "unknown")

LAST_STATUS="${RESTIC_STATUS}"

NOW=$(date -u +"%Y-%m-%dT%H:%M:%S")

if python3 -c "
import json
data = {
    'last_backup': '${NOW}',
    'snapshot_count': ${SNAP_COUNT},
    'total_size_human': '${SNAP_TOTAL}',
    'last_time': '${LAST_TIME}',
    'last_status': '${LAST_STATUS}',
    'verification': '${VERIFY_RESULT}',
    'snapshot_id': '${SNAP_ID}',
    'host': '${HOST_TAG}',
    'repo': '${RESTIC_REPOSITORY}',
}
with open('${STATUS_FILE}', 'w') as f:
    json.dump(data, f, indent=2)
" 2>>"${LOG_FILE}"; then
  log "  status written"
else
  log "  status write failed"
fi

# ── Step 5: ntfy notification ──────────────────────────────
log "--- Step 5: ntfy notification ---"

NTFY_URL="${NTFY_URL:-https://ntfy.phillias.cc/SelfHostNetSec}"

if [ "$LAST_STATUS" = "success" ]; then
  NTFY_PRIORITY="min"
  NTFY_TITLE="Backup OK — agent state (${HOST_TAG})"
  NTFY_BODY="${SNAP_COUNT} snapshots | ${SNAP_TOTAL} | Verify: OK | Snapshot: ${SNAP_ID:0:8} | Retention: 7d/4w/12m"
else
  NTFY_PRIORITY="urgent"
  NTFY_TITLE="Backup FAILED — agent state (${HOST_TAG})"
  NTFY_BODY="Snapshots: ${SNAP_COUNT} | Total: ${SNAP_TOTAL} | Verify: ${VERIFY_RESULT} | See ${LOG_FILE}"
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

for var in RESTIC_EXIT FORGET_EXIT VERIFY_EXIT; do
  eval "val=\$$var"
  if [ "$val" -eq 1 ] || [ "$val" -eq 3 ]; then
    eval "$var=0"
  fi
done
exit "$(( RESTIC_EXIT != 0 ? RESTIC_EXIT : FORGET_EXIT != 0 ? FORGET_EXIT : VERIFY_EXIT ))"
