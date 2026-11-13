#!/bin/bash
set -euo pipefail

# Install WARP client, enroll in Zero Trust via MDM service token, and verify Mesh IP.
# Idempotent — safe to re-run.
#
# Prerequisites:
#   - bws CLI authenticated (BWS_ACCESS_TOKEN set) for project 'phillias'
#   - Captain has created CIDR route + Access private app + Gateway allow rule
#     for this node's LAN IP in CF Zero Trust dashboard
#   - Captain has confirmed Service Auth device enrollment rule in dashboard
#
# Usage:
#   ./install-warp-fleet.sh          # normal enrollment
#   ./install-warp-fleet.sh --dry-run  # show what would happen

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

BWS_PROJECT="phillias"
MDM_DIR="/var/lib/cloudflare-warp"
MDM_FILE="${MDM_DIR}/mdm.xml"
APT_SOURCE_FILE="/etc/apt/sources.list.d/cloudflare-client.list"
KEYRING_FILE="/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg"

run() {
  if $DRY_RUN; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

# --- Check if already enrolled ---
if command -v warp-cli &>/dev/null && warp-cli status 2>/dev/null | grep -q "Connected"; then
  echo "warp-fleet: already enrolled and connected"
  warp-cli settings 2>/dev/null | head -5 || true
  exit 0
fi

# --- Add cloudflareclient apt source ---
if [[ ! -f "$APT_SOURCE_FILE" ]]; then
  echo "warp-fleet: adding cloudflareclient apt source (bookworm)"
  run curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | run sudo gpg --dearmor -o "$KEYRING_FILE"
  run sudo mkdir -p /etc/apt/sources.list.d
  echo "deb [signed-by=${KEYRING_FILE}] https://pkg.cloudflareclient.com/ bookworm main" | run sudo tee "$APT_SOURCE_FILE"
  run sudo apt-get update -qq
else
  echo "warp-fleet: apt source already present"
fi

# --- Install cloudflare-warp ---
if ! dpkg -s cloudflare-warp &>/dev/null; then
  echo "warp-fleet: installing cloudflare-warp"
  run sudo apt-get install -y cloudflare-warp
else
  echo "warp-fleet: cloudflare-warp already installed"
fi

# --- Extract service token from bws ---
if ! command -v bws &>/dev/null; then
  echo "warp-fleet: ERROR — bws CLI not found. Install and set BWS_ACCESS_TOKEN."
  exit 1
fi

CLIENT_ID=$(bws secret list "$BWS_PROJECT" 2>/dev/null | grep -i "WARP_FLEET_ENROLLMENT_CLIENT_ID" | awk '{print $2}' || true)
CLIENT_SECRET=$(bws secret list "$BWS_PROJECT" 2>/dev/null | grep -i "WARP_FLEET_ENROLLMENT_CLIENT_SECRET" | awk '{print $2}' || true)

if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" ]]; then
  echo "warp-fleet: ERROR — could not find WARP_FLEET_ENROLLMENT_CLIENT_ID/SECRET in bws project '${BWS_PROJECT}'"
  exit 1
fi

# --- Write MDM file ---
echo "warp-fleet: writing MDM enrollment file"
run sudo mkdir -p "$MDM_DIR"
run sudo tee "$MDM_FILE" > /dev/null <<EOF
<dict>
  <key>warp_fleet_enrollment_client_id</key>
  <string>${CLIENT_ID}</string>
  <key>warp_fleet_enrollment_client_secret</key>
  <string>${CLIENT_SECRET}</string>
</dict>
EOF
run sudo chmod 600 "$MDM_FILE"

# --- Enroll ---
echo "warp-fleet: enrolling in phillias Zero Trust organization"
if ! $DRY_RUN; then
  if ! warp-cli registration new phillias 2>&1; then
    echo "warp-fleet: enrollment failed — check CF Zero Trust dashboard has Service Auth device enrollment rule"
    echo "warp-fleet: also verify the rule saved correctly (first save sometimes doesn't persist)"
    exit 1
  fi
fi

# --- Verify ---
echo "warp-fleet: verifying enrollment"
if ! $DRY_RUN; then
  sleep 2
  warp-cli status
  echo "---"
  if command -v warp-axi &>/dev/null; then
    warp-axi status
  else
    echo "warp-axi not installed (optional: mise use -g npm:@masculinecache/warp-axi)"
  fi
fi

echo "warp-fleet: done"
