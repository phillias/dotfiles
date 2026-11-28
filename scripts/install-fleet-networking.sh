#!/bin/bash
# Install and harden fleet networking services: Eternal Terminal with direct
# exposure (no sslh, no tunnel) plus sshd hardening.
#
# Consolidates install-et-no-sslh.sh (oci1/primary, user ubuntu) and
# install-et-no-sslh-phillias.sh (kali/kalione, user phillias). The login
# user selects the variant:
#   ubuntu    etserver from the PPA with the distro et.service
#   phillias  additionally deploys the dotfiles-owned et.service and the
#             :10022 fallback sshd (installed, NOT enabled), and removes the
#             legacy sslh sshd listener on :55554
#
# What it does (idempotent; safe to re-run):
#   - installs etserver from the jgmath2000/et PPA
#   - deploys /etc/et.cfg (etserver on 0.0.0.0:2022)
#   - deploys sshd hardening to /etc/ssh/sshd_config.d/99-et-hardening.conf
#     (deliberately NO ClientAlive* settings: they would drop idle
#     moshi/iTerm2/ET sessions)
#   - restarts sshd and et after every successful run
#
# Firewall rules are NOT managed here. The chezmoi hook
# run_onchange_fleet-firewall.sh.tmpl owns the iptables INPUT rules for every
# port in .chezmoidata/fleet.toml (.fleet.ports): rate limits on :22/:2022,
# ACCEPT on :4096. Run `chezmoi apply` after first boot.
#
# The fallback daemon is an independently managed safety net. Enable it only
# during a captain-approved migration window after verifying the router path.
#
# Prerequisites:
#   - Ubuntu/Debian with apt, sudo/root access
#   - cloud firewall (e.g. OCI NSG / router) already opens TCP/22 and TCP/2022
#   - run this script from the dotfiles checkout so its unit sources are found
#
# Usage:
#   bash scripts/install-fleet-networking.sh

set -euo pipefail

SSH_PORT=22
ET_PORT=2022
LEGACY_SSH_PORT=55554
FALLBACK_SSH_PORT=10022
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
UNIT_SOURCE_DIR="${SCRIPT_DIR}/../systemd/system"

# Run as the login user (sudo is used per command); under `sudo bash` fall
# back to the invoking user.
SSH_USER="${SUDO_USER:-$(id -un)}"
case "$SSH_USER" in
    ubuntu|phillias) ;;
    *)
        echo "  ERROR: unsupported fleet user '${SSH_USER}' (expected ubuntu on oci1/primary or phillias on kali/kalione)." >&2
        exit 1
        ;;
esac

echo "  SSH user:   $SSH_USER"
echo "  SSH port:   $SSH_PORT"
echo "  ET port:    $ET_PORT"
if [[ "$SSH_USER" == "phillias" ]]; then
    echo "  Legacy sslh port: $LEGACY_SSH_PORT (removed)"
    echo "  Fallback SSH port: $FALLBACK_SSH_PORT (installed, not enabled)"
fi
echo "  Firewall:   managed by chezmoi (run_onchange_fleet-firewall.sh.tmpl)"
echo ""

if ! command -v apt-get &>/dev/null; then
    echo "  ERROR: apt-get not found; this script targets Ubuntu/Debian." >&2
    exit 1
fi

if [[ "$SSH_USER" == "phillias" ]] && [[ ! -f "${UNIT_SOURCE_DIR}/et.service" || ! -f "${UNIT_SOURCE_DIR}/sshd-fallback.service" ]]; then
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

# write_file_checked PATH CONTENT: write_file, treating "unchanged" as success
write_file_checked() {
    local write_status=0
    write_file "$@" || write_status=$?
    if [[ "$write_status" -ne 0 && "$write_status" -ne 1 ]]; then
        exit "$write_status"
    fi
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

# ---- Deploy /etc/et.cfg ----

write_file_checked /etc/et.cfg "$(cat <<ETCFG
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
)"

# ---- phillias variant: fallback sshd config and dotfiles-owned units ----

if [[ "$SSH_USER" == "phillias" ]]; then
    write_file_checked /etc/ssh/sshd_config_fallback "$(cat <<SSHDFALLBACK
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
)"

    for unit in et.service sshd-fallback.service; do
        install_status=0
        install_unit "$unit" || install_status=$?
        if [[ "$install_status" -ne 0 && "$install_status" -ne 1 ]]; then
            exit "$install_status"
        fi
    done
    sudo systemctl daemon-reload
fi

# ---- Deploy sshd hardening ----

write_file_checked /etc/ssh/sshd_config.d/99-et-hardening.conf "$(cat <<SSHDCFG
# ET direct-exposure hardening (managed by dotfiles install-fleet-networking.sh)
# No ClientAliveInterval/ClientAliveCountMax: they would disconnect idle
# moshi/iTerm2/Eternal Terminal sessions.
AllowUsers ${SSH_USER}
MaxAuthTries 3
LoginGraceTime 20
PermitRootLogin no
X11Forwarding no
SSHDCFG
)"

# The old sslh pattern exposed a second sshd listener on :55554. Remove only
# an exact active Port directive, retaining a backup for a later rollback.
if [[ "$SSH_USER" == "phillias" ]] && sudo grep -Eq "^[[:space:]]*Port[[:space:]]+${LEGACY_SSH_PORT}[[:space:]]*(#.*)?$" /etc/ssh/sshd_config; then
    sudo cp -an /etc/ssh/sshd_config /etc/ssh/sshd_config.et-no-sslh.bak
    sudo sed -i -E "/^[[:space:]]*Port[[:space:]]+${LEGACY_SSH_PORT}[[:space:]]*(#.*)?$/d" /etc/ssh/sshd_config
    echo "  removed: /etc/ssh/sshd_config Port ${LEGACY_SSH_PORT}"
fi

# Validate before any restart so a bad drop-in never locks us out
sudo sshd -t

# ---- Enable and (re)start services ----

sudo systemctl enable et.service >/dev/null 2>&1 || true
sudo systemctl restart et.service
echo "  restarted: et.service"

# Ubuntu names the unit ssh.service; others use sshd.service
if systemctl list-unit-files ssh.service &>/dev/null; then
    sudo systemctl restart ssh.service
else
    sudo systemctl restart sshd.service
fi
echo "  restarted: sshd"

# ---- Summary ----

cat <<INFO

=== Fleet networking (${SSH_USER}): installation complete ===

Configs deployed:
  - /etc/et.cfg                              (etserver on 0.0.0.0:${ET_PORT})
  - /etc/ssh/sshd_config.d/99-et-hardening.conf
INFO
if [[ "$SSH_USER" == "phillias" ]]; then
    cat <<INFO
  - /etc/ssh/sshd_config_fallback            (sshd on 0.0.0.0:${FALLBACK_SSH_PORT})
  - /etc/systemd/system/et.service
  - /etc/systemd/system/sshd-fallback.service (installed, not enabled)
INFO
fi
cat <<INFO

Firewall: iptables rules are NOT set by this script. They are owned by the
chezmoi hook run_onchange_fleet-firewall.sh.tmpl (ports from
.chezmoidata/fleet.toml). Run \`chezmoi apply\` after first boot so :${SSH_PORT},
:${ET_PORT} (rate-limited) and :4096 are accepted and persisted to
/etc/iptables/rules.v4.

Verify:

  sudo ss -tlnp | grep -E ':(${SSH_PORT}|${ET_PORT})\\b'
  sudo iptables -S INPUT | grep -E '127.0.0.0/8|172.16.0.0|et-rl-|4096'
  systemctl is-enabled et.service

Connect from the laptop:

  et -u ${SSH_USER} <DIRECT-HOST-OR-IP>

INFO
