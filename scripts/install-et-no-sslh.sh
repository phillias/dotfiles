#!/bin/bash
# Install and harden Eternal Terminal with direct exposure (no sslh, no tunnel).
#
# Pattern (used on oci1): sshd stays on :22 for the SSH bootstrap, etserver
# listens directly on 0.0.0.0:2022, and both ports are exposed so moshi and
# the laptop connect straight to the host. Contrast with
# install-et-sslh-for-moshi.sh, which demuxes SSH/ET behind sslh on one port.
#
# What it does (idempotent; safe to re-run):
#   - installs etserver from the jgmath2000/et PPA
#   - deploys /etc/et.cfg and enables et.service
#   - deploys sshd hardening to /etc/ssh/sshd_config.d/99-et-hardening.conf
#     (deliberately NO ClientAlive* settings: they would drop idle
#     moshi/iTerm2 sessions)
#   - rate-limits new connections on :22 and :2022 with iptables `recent`
#     and persists the rules to /etc/iptables/rules.v4
#   - restarts sshd and et only when their config changed
#
# Prerequisites:
#   - Ubuntu/Debian with apt, sudo/root access
#   - cloud firewall (e.g. OCI NSG) already opens TCP/22 and TCP/2022
#
# Usage:
#   bash scripts/install-et-no-sslh.sh
#   SSH_USER=phillias bash scripts/install-et-no-sslh.sh   # custom

set -euo pipefail

SSH_PORT="${SSH_PORT:-22}"
ET_PORT="${ET_PORT:-2022}"
SSH_USER="${SSH_USER:-ubuntu}"
# Rate limit: at most RATE_HITS new connections per RATE_SECONDS per source IP
RATE_HITS="${RATE_HITS:-3}"
RATE_SECONDS="${RATE_SECONDS:-60}"

echo "  SSH port:   $SSH_PORT"
echo "  ET port:    $ET_PORT"
echo "  SSH user:   $SSH_USER"
echo "  Rate limit: ${RATE_HITS} new conns / ${RATE_SECONDS}s per source IP"
echo ""

if ! command -v apt-get &>/dev/null; then
    echo "  ERROR: apt-get not found; this script targets Ubuntu/Debian." >&2
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
    sudo mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" | sudo tee "$path" > /dev/null
    sudo chmod "$mode" "$path"
    echo "  wrote: $path"
}

# ---- Deploy /etc/et.cfg ----

et_changed=0
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
    et_changed=1
fi

# ---- Deploy sshd hardening ----

sshd_changed=0
if write_file /etc/ssh/sshd_config.d/99-et-hardening.conf "$(cat <<SSHDCFG
# ET direct-exposure hardening (managed by dotfiles install-et-no-sslh.sh)
# No ClientAliveInterval/ClientAliveCountMax: they would disconnect idle
# moshi/iTerm2 sessions.
AllowUsers ${SSH_USER}
MaxAuthTries 3
LoginGraceTime 20
PermitRootLogin no
X11Forwarding no
SSHDCFG
)"; then
    sshd_changed=1
fi

# Validate before any restart so a bad drop-in never locks us out
sudo sshd -t

# ---- iptables rate limiting ----

# Ensure persistence tooling exists without the interactive debconf prompt
if ! dpkg -s iptables-persistent &>/dev/null; then
    echo "  Installing iptables-persistent..."
    echo "iptables-persistent iptables-persistent/autosave_v4 boolean false" | sudo debconf-set-selections
    echo "iptables-persistent iptables-persistent/autosave_v6 boolean false" | sudo debconf-set-selections
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iptables-persistent
fi

# add_rule POS RULE...: insert RULE at INPUT position POS unless an identical
# rule already exists anywhere in INPUT
add_rule() {
    local pos="$1"
    shift
    if sudo iptables -C INPUT "$@" 2>/dev/null; then
        return 0
    fi
    sudo iptables -I INPUT "$pos" "$@"
    echo "  iptables: added INPUT $*"
}

# Rules go ahead of the distro defaults (OCI Ubuntu images end INPUT with a
# REJECT-all, so :2022 also needs an explicit ACCEPT). Per port, in order:
#   1. --set     record every new connection from the source
#   2. --update  DROP once it reaches RATE_HITS+1 within RATE_SECONDS
#   3. ACCEPT    the new connection otherwise
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
if [[ "$et_changed" == 1 ]] || ! systemctl is-active --quiet et.service; then
    sudo systemctl restart et.service
    echo "  restarted: et.service"
fi

if [[ "$sshd_changed" == 1 ]]; then
    # Ubuntu names the unit ssh.service; others use sshd.service
    if systemctl list-unit-files ssh.service &>/dev/null; then
        sudo systemctl restart ssh.service
    else
        sudo systemctl restart sshd.service
    fi
    echo "  restarted: sshd"
fi

# ---- Summary ----

cat <<INFO

=== ET (no sslh): installation complete ===

Configs deployed:
  - /etc/et.cfg                              (etserver on 0.0.0.0:${ET_PORT})
  - /etc/ssh/sshd_config.d/99-et-hardening.conf
  - /etc/iptables/rules.v4                   (rate limits on :${SSH_PORT}, :${ET_PORT})

Verify:

  sudo ss -tlnp | grep -E ':(${SSH_PORT}|${ET_PORT})\\b'
  sudo iptables -S INPUT | grep et-rl-

Connect from the laptop:

  et -u ${SSH_USER} et-oci1

INFO
