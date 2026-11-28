#!/bin/sh
# Fleet opencode units: enable serve; retire the autossh tunnel units.
#
# WARP mesh is the primary inter-node transport: every node reaches another
# node's opencode serve at <node>.mesh:4096 (TCP/4096 opened by
# run_onchange_fleet-firewall.sh.tmpl). The autossh opencode-tunnel-* units
# are retired and no longer shipped; this script runs on every apply, disables
# and removes any tunnel unit still deployed on this host, reloads the user
# manager, and enables+starts opencode-serve. Idempotent: enable --now is a
# no-op for a running unit. A deployed opencode unit that is still disabled
# fails the apply, so a shipped-but-never-enabled unit cannot stay silent.

set -eu

SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"

command -v systemctl >/dev/null 2>&1 || exit 0

cleanup_failed=0
for legacy_unit in \
	opencode-tunnel-primary55522.service \
	opencode-tunnel-ssh.phillias.cc.service \
	opencode-tunnel-primary.service \
	opencode-tunnel-kali.service \
	opencode-tunnel-kalione.service \
	opencode-tunnel-oci1.service
do
	legacy_path="${SYSTEMD_USER_DIR}/${legacy_unit}"
	if [ -f "$legacy_path" ]; then
		if systemctl --user disable --now "$legacy_unit" 2>/dev/null; then
			rm -f "$legacy_path"
		else
			echo "ERROR: failed to stop retired unit ${legacy_unit}; preserving it for retry" >&2
			cleanup_failed=1
		fi
	fi
done

systemctl --user daemon-reload 2>/dev/null || true

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

if [ "$cleanup_failed" -ne 0 ]; then
	exit 1
fi
