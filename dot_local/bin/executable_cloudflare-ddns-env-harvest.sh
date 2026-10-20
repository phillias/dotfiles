#!/bin/sh
# cloudflare-ddns token harvest (2026-10-19).
# Source the bws-first login environment (zsh -l -> .zshenv -> load-keys.sh)
# as the phillias user and write the DDNS ini to /run/cloudflare-ddns/config.ini.
# The root cloudflare-ddns systemd units consume it via `cloudflare-ddns
# --config`, keeping the API token off the unit command line and off static
# disk. Same shape as nm-daemon-env-harvest.sh, adapted for a root system
# unit: the harvest runs as root, drops to phillias for the login environment,
# and the result is group-readable by the cloudflare-ddns service user.
# A definitive 401/403 on the zone lookup refuses to
# start the unit loudly (and removes the stale file); transient errors (5xx,
# network) do not block the start - the tool's own API call then fails loudly.
set -eu
umask 077
conf_dir=/run/cloudflare-ddns
conf_file="$conf_dir/config.ini"
record_name="${CLOUDFLARE_DDNS_RECORD:-*.phillias.us}"
harvest="$(runuser -u phillias -- zsh -lc 'printf "CLOUDFLARE_DDNS_API_TOKEN=%s\n" "$CLOUDFLARE_DDNS_API_TOKEN"')"
token="$(printf '%s\n' "$harvest" | sed -n 's/^CLOUDFLARE_DDNS_API_TOKEN=//p')"
if [ -z "$token" ]; then
  echo "cloudflare-ddns-env-harvest: empty harvest (load-keys.sh exported nothing - check bws)" >&2
  exit 1
fi
mkdir -p "$conf_dir"
chown root:cloudflare-ddns "$conf_dir"
chmod 0750 "$conf_dir"
printf '[ddns]\napi_token = %s\nrecord_name = %s\n' "$token" "$record_name" > "$conf_file"
chown root:cloudflare-ddns "$conf_file"
chmod 0640 "$conf_file"
# Fail-fast proof uses the zone lookup the tool itself performs first.
# The tokens/verify endpoint 401s for zone-scoped DDNS tokens, so it cannot
# be the liveness signal here; zones?name=<zone> is the definitive call.
zone="${record_name#*.}"
code="$(curl -s -m 10 -o /dev/null -w '%{http_code}' \
  "https://api.cloudflare.com/client/v4/zones?name=$zone" \
  -H "Authorization: Bearer $token" \
  )" || code=000
if [ "$code" = "401" ] || [ "$code" = "403" ]; then
  echo "cloudflare-ddns-env-harvest: Cloudflare rejected token ($code)" >&2
  rm -f "$conf_file"
  exit 1
fi
