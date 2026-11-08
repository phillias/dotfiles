#!/bin/bash
# Install and harden Eternal Terminal with direct exposure (no sslh, no tunnel)
# on the Kali/nasbox fleet node as user phillias.
#
# What it does (idempotent; safe to re-run):
#   - installs etserver from the jgmath2000/et PPA
#   - deploys /etc/et.cfg and the dotfiles-owned et.service
#   - deploys sshd hardening to /etc/ssh/sshd_config.d/99-et-hardening.conf
#   - deploys, but does not enable, the dotfiles-owned fallback sshd unit on
#     :10022; it deliberately has no Conflicts=ssh.service declaration
#   - rate-limits new connections on :22 and :2022 with iptables `recent`
#     and persists the rules to /etc/iptables/rules.v4
#   - removes the legacy sslh sshd listener on :55554
#   - restarts sshd and et after every successful run
#
# The fallback daemon is an independently managed safety net. Enable it only
# during a captain-approved migration window after verifying the router path.
#
# Prerequisites:
#   - Ubuntu/Debian with apt, sudo/root access
#   - cloud firewall (e.g. router/NSG) already opens TCP/22 and TCP/2022
#   - run this script from the dotfiles checkout so its unit sources are found
#
# Usage:
#   bash scripts/install-et-no-sslh-phillias.sh

set -euo pipefail

SSH_PORT=22
ET_PORT=2022
SSH_USER=phillias
LEGACY_SSH_PORT=55554
FALLBACK_SSH_PORT=10022
# Rate limit: at most RATE_HITS new connections per RATE_SECONDS per source IP
RATE_HITS=3
RATE_SECONDS=60
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
UNIT_SOURCE_DIR="${SCRIPT_DIR}/../systemd/system"

echo "  SSH port:   $SSH_PORT"
echo "  ET port:    $ET_PORT"
echo "  SSH user:   $SSH_USER"
echo "  Legacy sslh port: $LEGACY_SSH_PORT (removed)"
echo "  Fallback SSH port: $FALLBACK_SSH_PORT (installed, not enabled)"
echo "  Rate limit: ${RATE_HITS} new conns / ${RATE_SECONDS}s per source IP"
echo ""

if ! command -v apt-get &>/dev/null; then
    echo "  ERROR: apt-get not found; this script targets Ubuntu/Debian." >&2
    exit 1
fi

if [[ ! -f "${UNIT_SOURCE_DIR}/et.service" || ! -f "${UNIT_SOURCE_DIR}/sshd-fallback.service" ]]; then
    echo "  ERROR: dotfiles system unit sources not found at ${UNIT_SOURCE_DIR}" >&2
    exit 1
fi

# ---- Install etserver ----

if command -v etserver &>/dev/null; then
    echo "  etserver already installed"
else
    echo "  Installing etserver from ppa:jgmath2000/et..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq software-properties-common
    sudo add-apt-repository -y ppa:jgmath2000/et
    sudo apt-get update -qq
    sudo apt-get install -y -qq et
fi

# ---- Helper: write a file if content changed (returns 0 if written) ----
write_file() {
    local path="$1"
    local content="$2"
    local mode="${3:-644}"
    if [[ -f "$path" ]] && printf '%s\n' "$content" | sudo cmp -s - "$path"; then
        echo "  unchanged: $path"
        return 1
    fi
    if ! sudo mkdir -p "$(dirname "$path")"; then
        return 2
    fi
    if ! printf '%s\n' "$content" | sudo tee "$path" > /dev/null; then
        return 2
    fi
    if ! sudo chmod "$mode" "$path"; then
        return 2
    fi
    echo "  wrote: $path"
}

install_unit() {
    local unit="$1"
    local source="${UNIT_SOURCE_DIR}/${unit}"
    local destination="/etc/systemd/system/${unit}"
    if sudo cmp -s "$source" "$destination" 2>/dev/null; then
        echo "  unchanged: $destination"
        return 1
    fi
    if ! sudo install -D -m 0644 "$source" "$destination"; then
        return 2
    fi
    echo "  wrote: $destination"
}

# ---- Deploy /etc/et.cfg and system units ----

if write_file /etc/et.cfg "$(cat <<ETCFG
; et.cfg : Config file for Eternal Terminal (direct exposure, no sslh)
;

[Networking]
port = ${ET_PORT}
; bind_ip unset: etserver listens on 0.0.0.0
; bind_ip = 0.0.0.0

[Debug]
verbose = 1
silent = 0
logsize = 20971520
telemetry = false
logdirectory = /tmp
ETCFG
)"; then
    :
else
    write_status=$?
    if [[ "$write_status" -ne 1 ]]; then
        exit "$write_status"
    fi
fi

if write_file /etc/ssh/sshd_config_fallback "$(cat <<SSHDFALLBACK
# Dotfiles-managed fallback sshd for captain-approved migration windows.
# This is intentionally separate from the primary sshd configuration.
Port ${FALLBACK_SSH_PORT}
ListenAddress 0.0.0.0
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AllowUsers ${SSH_USER}
UsePAM yes
PidFile /run/sshd-fallback.pid
SSHDFALLBACK
)"; then
    :
else
    write_status=$?
    if [[ "$write_status" -ne 1 ]]; then
        exit "$write_status"
    fi
fi

for unit in et.service sshd-fallback.service; do
    if install_unit "$unit"; then
        :
    else
        install_status=$?
        if [[ "$install_status" -ne 1 ]]; then
            exit "$install_status"
        fi
    fi
done
sudo systemctl daemon-reload

# ---- Deploy sshd hardening ----

if write_file /etc/ssh/sshd_config.d/99-et-hardening.conf "$(cat <<SSHDCFG
# ET direct-exposure hardening (managed by dotfiles install-et-no-sslh-phillias.sh)
# No ClientAliveInterval/ClientAliveCountMax: they would disconnect idle
# Eternal Terminal sessions.
AllowUsers ${SSH_USER}
MaxAuthTries 3
LoginGraceTime 20
PermitRootLogin no
X11Forwarding no
SSHDCFG
)"; then
    :
else
    write_status=$?
    if [[ "$write_status" -ne 1 ]]; then
        exit "$write_status"
    fi
fi

# Validate before any restart so a bad drop-in never locks us out. The old
# sslh pattern exposed a second sshd listener on :55554. Remove only an exact
# active Port directive, retaining a backup for a later rollback.
if sudo grep -Eq "^[[:space:]]*Port[[:space:]]+${LEGACY_SSH_PORT}[[:space:]]*(#.*)?$" /etc/ssh/sshd_config; then
    sudo cp -an /etc/ssh/sshd_config /etc/ssh/sshd_config.et-no-sslh.bak
    sudo sed -i -E "/^[[:space:]]*Port[[:space:]]+${LEGACY_SSH_PORT}[[:space:]]*(#.*)?$/d" /etc/ssh/sshd_config
    echo "  removed: /etc/ssh/sshd_config Port ${LEGACY_SSH_PORT}"
fi
sudo sshd -t

# ---- iptables rate limiting ----

if ! dpkg -s iptables-persistent &>/dev/null; then
    echo "  Installing iptables-persistent..."
    echo "iptables-persistent iptables-persistent/autosave_v4 boolean false" | sudo debconf-set-selections
    echo "iptables-persistent iptables-persistent/autosave_v6 boolean false" | sudo debconf-set-selections
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iptables-persistent
fi

add_rule() {
    local pos="$1"
    shift
    while sudo iptables -C INPUT "$@" 2>/dev/null; do
        sudo iptables -D INPUT "$@"
    done
    sudo iptables -I INPUT "$pos" "$@"
    echo "  iptables: added INPUT $*"
}

pos=1
for port in "$SSH_PORT" "$ET_PORT"; do
    name="et-rl-${port}"
    add_rule "$pos" -p tcp --dport "$port" -m conntrack --ctstate NEW \
        -m recent --name "$name" --set
    add_rule "$((pos + 1))" -p tcp --dport "$port" -m conntrack --ctstate NEW \
        -m recent --name "$name" --update --seconds "$RATE_SECONDS" \
        --hitcount "$((RATE_HITS + 1))" -j DROP
    add_rule "$((pos + 2))" -p tcp --dport "$port" -m conntrack --ctstate NEW -j ACCEPT
    pos=$((pos + 3))
done

sudo mkdir -p /etc/iptables
sudo sh -c 'iptables-save > /etc/iptables/rules.v4'
echo "  persisted: /etc/iptables/rules.v4"

# ---- Enable and (re)start services ----

sudo systemctl enable et.service >/dev/null 2>&1 || true
sudo systemctl restart et.service
echo "  restarted: et.service"

if systemctl list-unit-files ssh.service &>/dev/null; then
    sudo systemctl restart ssh.service
else
    sudo systemctl restart sshd.service
fi
echo "  restarted: sshd"

cat <<INFO

=== ET (no sslh): installation complete ===

Configs deployed:
  - /etc/et.cfg                              (etserver on 0.0.0.0:${ET_PORT})
  - /etc/ssh/sshd_config.d/99-et-hardening.conf
  - /etc/ssh/sshd_config_fallback            (sshd on 0.0.0.0:${FALLBACK_SSH_PORT})
  - /etc/systemd/system/et.service
  - /etc/systemd/system/sshd-fallback.service (installed, not enabled)
  - /etc/iptables/rules.v4                   (rate limits on :${SSH_PORT}, :${ET_PORT})

Verify:

  sudo ss -tlnp | grep -E ':(${SSH_PORT}|${ET_PORT})\\b'
  sudo iptables -S INPUT | grep et-rl-
  systemctl is-enabled et.service

Connect from the laptop:

  et -u ${SSH_USER} <DIRECT-HOST-OR-IP>

INFO
