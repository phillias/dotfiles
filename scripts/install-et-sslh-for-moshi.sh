#!/bin/bash
# Install and configure ET + sslh for Moshi mobile SSH.
#
# One script, everything: installs dependencies, deploys all system configs
# (/etc/et.cfg, /etc/ssh/sshd_moshi_config, /etc/ssh/moshi_authorized_keys,
# /etc/default/sslh, systemd units), creates the sslh system user, and
# enables/starts both services.
#
# Prerequisites:
#   - etserver already installed (eternalterminal.dev)
#   - sudo/root access
#
# Ports are abstracted as variables (see below). MAIN_SSH_PORT is
# auto-detected from the running sshd; override any of them per machine.
#
# Usage:
#   bash scripts/install-et-sslh-for-moshi.sh
#   MAIN_SSH_PORT=22 bash scripts/install-et-sslh-for-moshi.sh   # custom

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

# Port Moshi connects to (sslh listens here, demuxes SSH vs ET)
MOSHI_PORT="${MOSHI_PORT:-2022}"

# Internal port for etserver (localhost only, not externally reachable)
ET_PORT="${ET_PORT:-20220}"

# User Moshi will SSH in as
REMOTE_USER="${REMOTE_USER:-$USER}"

# sslh system user
SSLH_USER="${SSLH_USER:-sslh}"

echo "  Detected main SSH port: $MAIN_SSH_PORT"
echo "  Moshi demux port:       $MOSHI_PORT"
echo "  etserver internal port: $ET_PORT"
echo "  Remote user:            $REMOTE_USER"
echo "  sslh system user:       $SSLH_USER"
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

# ---- Helper: write a file if content changed ----
write_file() {
    local path="$1"
    local content="$2"
    local mode="${3:-644}"
    if [[ -f "$path" ]] && echo "$content" | cmp -s - "$path" 2>/dev/null; then
        echo "  unchanged: $path"
        return 0
    fi
    echo "$content" | sudo tee "$path" > /dev/null
    sudo chmod "$mode" "$path"
    echo "  wrote: $path"
}

# ---- Deploy configs ----

write_file /etc/et.cfg "$(cat <<ETCFG
; et.cfg : Config file for Eternal Terminal
;

[Networking]
port = ${ET_PORT}
bind_ip = 127.0.0.1

[Debug]
verbose = 1
silent = 0
logsize = 20971520
telemetry = true
logdirectory = /tmp
ETCFG
)"

write_file /etc/ssh/sshd_moshi_config "$(cat <<SSHDCFG
# Minimal sshd config for Moshi mobile SSH on port ${MOSHI_PORT}
# Independent from the main SSH server on port ${MAIN_SSH_PORT}

Port ${MOSHI_PORT}
ListenAddress 0.0.0.0

HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key

PubkeyAuthentication yes
PasswordAuthentication no
AuthenticationMethods publickey

AuthorizedKeysFile /etc/ssh/moshi_authorized_keys

UsePAM no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
LogLevel VERBOSE
SSHDCFG
)"

write_file /etc/ssh/moshi_authorized_keys "$(cat <<AUTHKEYS
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDCdvLo1rdj4w7KCaGQtvSvwUSn/sXe3MspxQ11nftZe phillias@inspironkali
AUTHKEYS
)" 600

write_file /etc/default/sslh "$(cat <<SSLCFG
# sslh configuration - protocol demultiplexer for port ${MOSHI_PORT}
# SSH traffic -> 127.0.0.1:${MAIN_SSH_PORT} (OpenSSH, untouched)
# ET protocol -> 127.0.0.1:${ET_PORT} (etserver, localhost only)

DAEMON=/usr/sbin/sslh
DAEMON_OPTS="-u sslh -p 0.0.0.0:${MOSHI_PORT} --ssh 127.0.0.1:${MAIN_SSH_PORT} --anyprot 127.0.0.1:${ET_PORT} --on-timeout 127.0.0.1:${ET_PORT}"
SSLCFG
)"

write_file /lib/systemd/system/sshd-moshi.service "$(cat <<SERVICE
[Unit]
Description=SSH server for Moshi mobile on port ${MOSHI_PORT}
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/sshd -D -f /etc/ssh/sshd_moshi_config -E /var/log/sshd_moshi.log
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
SERVICE
)" 755

write_file /lib/systemd/system/sslh.service "$(cat <<SSHSERVICE
[Unit]
Description=SSL/SSH multiplexer for Moshi (port ${MOSHI_PORT})
After=network.target

[Service]
ExecStart=/usr/sbin/sslh -u sslh -p 0.0.0.0:${MOSHI_PORT} --ssh 127.0.0.1:${MAIN_SSH_PORT} --anyprot 127.0.0.1:${ET_PORT} --on-timeout 127.0.0.1:${ET_PORT} --pidfile /run/sslh/sslh.pid
PIDFile=/run/sslh/sslh.pid
Type=forking
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SSHSERVICE
)" 755

# ---- Ensure sslh system user exists ----
if ! id "$SSLH_USER" &>/dev/null; then
    sudo useradd --system --no-create-home --shell /usr/sbin/nologin "$SSLH_USER"
    echo "  Created system user: $SSLH_USER"
fi

# ---- Runtime directories ----
sudo mkdir -p /run/sslh /var/run/sslh
sudo chown "$SSLH_USER:$SSLH_USER" /run/sslh /var/run/sslh 2>/dev/null || true

# ---- Enable and restart services ----
for svc in sshd-moshi.service sslh.service; do
    if systemctl is-enabled "$svc" &>/dev/null; then
        sudo systemctl enable "$svc" 2>/dev/null || true
    fi
    sudo systemctl restart "$svc" 2>/dev/null || echo "  warning: $svc restart failed (may already be running on port)"
done

# ---- Summary ----

cat <<INFO

=== Moshi + ET + sslh: installation complete ===

Configs deployed:
  - /etc/et.cfg               (etserver on 127.0.0.1:${ET_PORT})
  - /etc/ssh/sshd_moshi_config (dedicated sshd on port ${MOSHI_PORT})
  - /etc/ssh/moshi_authorized_keys (key-restricted, mode 600)
  - /etc/default/sslh         (protocol demux on port ${MOSHI_PORT})
  - /lib/systemd/system/sshd-moshi.service
  - /lib/systemd/system/sslh.service

Verify:

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
