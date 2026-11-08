#!/bin/sh
# Fleet opencode units: enable serve and every installed tunnel unit.
#
# The tunnel units are hostname-gated via .chezmoiignore (each host applies
# only the units targeting OTHER nodes). This script runs on every apply,
# reloads the user manager, and enables+starts opencode-serve plus whatever
# tunnel units exist on this host. Idempotent: enable --now is a no-op for
# running units. A deployed opencode unit that is still disabled fails the
# apply, so a shipped-but-never-enabled unit cannot stay silent.
#
# autossh is a system prerequisite (apt), not mise-pinnable; tunnel units
# carry ConditionFileIsExecutable=/usr/bin/autossh so a host without it stays
# quiet instead of restart-looping. Serve does not need autossh.

set -eu

SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"

command -v systemctl >/dev/null 2>&1 || exit 0

systemctl --user daemon-reload 2>/dev/null || true

for unit in "${SYSTEMD_USER_DIR}"/opencode-tunnel-*.service; do
	[ -f "$unit" ] || continue
	systemctl --user enable --now "$(basename "$unit")" 2>/dev/null || true
done

if [ -f "${SYSTEMD_USER_DIR}/opencode-serve.service" ]; then
	systemctl --user enable --now opencode-serve.service 2>/dev/null || true
fi

failed=0
for unit in "${SYSTEMD_USER_DIR}"/opencode-*.service; do
	[ -f "$unit" ] || continue
	name=$(basename "$unit")
	if ! systemctl --user is-enabled "$name" >/dev/null 2>&1; then
		echo "ERROR: ${name} is deployed but not enabled" >&2
		failed=1
	fi
done
if [ "$failed" -ne 0 ]; then
	exit 1
fi
