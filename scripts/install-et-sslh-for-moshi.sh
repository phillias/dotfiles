#!/bin/bash
# Manual bootstrap: install and configure ET + sslh for Moshi mobile SSH.
#
# Prerequisites:
#   - etserver already installed (eternalterminal.dev)
#   - sudo/root access
#
# After this script completes, run:
#   chezmoi apply
#   # or if chezmoi is not yet set up:
#   bash ~/.local/share/chezmoi/run_onchange_moshi-system-config.sh
#
# This script detects dynamic values (SSH port, user, etc.) so it works
# on any machine regardless of base SSH configuration.

set -euo pipefail

# ---- Detect dynamic values ----

# Main SSH port: read from the running sshd process
MAIN_SSH_PORT=$(sudo ss -tlnp | awk '/sshd/ {for(i=1;i<=NF;i++) if($i ~ /:/){split($i,a,":"); print a[2]; exit}}' 2>/dev/null || echo "")

# If ss didn't find it, check sshd_config
if [[ -z "$MAIN_SSH_PORT" ]]; then
    MAIN_SSH_PORT=$(sudo grep -i '^Port\s' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1 || echo "")
fi

# Fall back to default
MAIN_SSH_PORT="${MAIN_SSH_PORT:-22}"

echo "  Detected main SSH port: $MAIN_SSH_PORT"

# Port for Moshi's SSH/ET demux — the single port Moshi connects to
MOSHI_PORT="${MOSHI_PORT:-2022}"

# Internal port for etserver (localhost only)
ET_PORT="${ET_PORT:-20220}"

# User Moshi will SSH in as
REMOTE_USER="${REMOTE_USER:-$USER}"

# sslh system user
SSLH_USER="${SSLH_USER:-sslh}"

echo "  Moshi demux port:      $MOSHI_PORT"
echo "  etserver internal port: $ET_PORT"
echo "  Remote user:           $REMOTE_USER"
echo "  sslh system user:      $SSLH_USER"
echo ""

# ---- Install dependencies ----

install_sslh() {
    if command -v sslh &>/dev/null || command -v sslh-select &>/dev/null; then
        echo "  sslh already installed"
        return 0
    fi
    echo "  Installing sslh..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y -qq sslh
    elif command -v brew &>/dev/null; then
        brew install sslh
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y sslh
    else
        echo "  WARNING: sslh not found and package manager unknown."
        echo "  Install manually from https://github.com/yrutschle/sslh"
    fi
}

install_sslh

# ---- Ensure sslh system user exists ----
if ! id "$SSLH_USER" &>/dev/null; then
    sudo useradd --system --no-create-home --shell /usr/sbin/nologin "$SSLH_USER"
    echo "  Created system user: $SSLH_USER"
fi

# ---- Runtime directories ----
sudo mkdir -p /run/sslh /var/run/sslh
sudo chown "$SSLH_USER:$SSLH_USER" /run/sslh /var/run/sslh 2>/dev/null || true

# ---- Summary and next steps ----

cat <<INFO

=== Moshi + ET + sslh: installation complete ===

Dependencies installed. System user created. Runtime dirs ready.

Next step — deploy config files:

  Method A (chezmoi):
    chezmoi apply

  Method B (standalone, no chezmoi):
    bash ~/.local/share/chezmoi/run_onchange_moshi-system-config.sh

After configs are deployed, verify:

  sudo ss -tlnp | grep -E '${MOSHI_PORT}|${ET_PORT}|${MAIN_SSH_PORT}'

You should see:
  - sshd on 0.0.0.0:${MAIN_SSH_PORT}   (main SSH, unchanged)
  - sslh on 0.0.0.0:${MOSHI_PORT}       (protocol demux)
  - etserver on 127.0.0.1:${ET_PORT}    (ET protocol)

Configure Moshi with:
  Host:     (your server hostname)
  Port:     ${MOSHI_PORT}
  User:     ${REMOTE_USER}
  Key:      your id_ed25519_inspironkali private key
  Protocol: ET

INFO
