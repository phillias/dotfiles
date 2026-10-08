#!/bin/sh
# Fleet opencode tunnels: enable every installed tunnel unit.
#
# The tunnel units are hostname-gated via .chezmoiignore (each host applies
# only the units targeting OTHER nodes). This script runs on every apply,
# reloads the user manager, and enables+starts whatever tunnel units exist
# on this host. Idempotent: enable --now is a no-op for running units.
#
# autossh is a system prerequisite (apt), not mise-pinnable; units carry
# ConditionFileIsExecutable=/usr/bin/autossh so a host without it stays
# quiet instead of restart-looping.

set -eu

SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"

command -v systemctl >/dev/null 2>&1 || exit 0

systemctl --user daemon-reload 2>/dev/null || true

for unit in "${SYSTEMD_USER_DIR}"/opencode-tunnel-*.service; do
	[ -f "$unit" ] || continue
	systemctl --user enable --now "$(basename "$unit")" 2>/dev/null || true
done
