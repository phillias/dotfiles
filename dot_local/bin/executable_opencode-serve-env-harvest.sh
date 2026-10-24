#!/bin/sh
# opencode-serve token harvest (2026-10-17; config fold 2026-10-24).
# Source the bws-first login environment (zsh -l -> .zshenv -> load-keys.sh)
# and write CF_AI_GATEWAY_TOKEN to the serve runtime env file. The serve
# shared opencode config tree references only
# this token ({env:CF_AI_GATEWAY_TOKEN}); the five direct provider keys the
# old static env file carried (GOOGLE, CEREBRAS, MISTRAL, SAMBANOVA,
# TOGETHER) were dead lanes rendered from retired age files - dropped, not
# harvested.
# 2026-10-24 fold: opencode serve mode (verified on 1.18.29 and 1.19.0)
# never interpolates {env:VAR} in provider apiKey - it sends the literal
# pattern as the bearer token and the gateway 401s (TUI resolves natively).
# So the harvest also resolves that one pattern in the chezmoi-rendered
# opencode.json in place, with the token this run just validated. A
# chezmoi apply re-renders the file back to patterns and the next serve
# start resolves it again.
# A definitive 401 from the gateway refuses to start the unit loudly -
# systemd shows it failed instead of serving a token-dead API. Transient
# errors (5xx, network) do not block the start.
# Same treatment as the no-mistakes daemon harvest (2026-10-16, PR #442),
# which replaced direct decryption of retired age fallbacks that went stale
# after the vault rotation and silently 401'd the fleet.
set -eu
umask 077
env_file="${1:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/opencode-serve.env}"
cf_token="$(zsh -lc 'printf "%s" "$CF_AI_GATEWAY_TOKEN"')"
if [ -z "$cf_token" ]; then
  echo "opencode-serve-env-harvest: empty harvest (load-keys.sh exported nothing - check bws)" >&2
  exit 1
fi
printf 'CF_AI_GATEWAY_TOKEN=%s\n' "$cf_token" > "$env_file"
chmod 0600 "$env_file"
code="$(curl -s -m 10 -o /dev/null -w '%{http_code}' \
  -X POST 'https://gateway.ai.cloudflare.com/v1/a7fa198dd5b359a187c671064fe6b36e/opencode/compat/chat/completions' \
  -H "Authorization: Bearer $cf_token" \
  -H 'Content-Type: application/json' \
  -d '{"model":"dynamic/pr-gate","messages":[{"role":"user","content":"healthcheck"}],"max_tokens":1}' \
  )" || code=000
if [ "$code" = "401" ]; then
  echo "opencode-serve-env-harvest: Cloudflare gateway rejected token (401)" >&2
  exit 1
fi

# Fold: resolve the {env:CF_AI_GATEWAY_TOKEN} pattern in the rendered
# opencode.json in place with the token this run just validated. Idempotent -
# skip when no pattern is present (already resolved, or config missing).
config="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json"
if [ -f "$config" ] && grep -q '{env:CF_AI_GATEWAY_TOKEN}' "$config"; then
  CF_AI_GATEWAY_TOKEN="$cf_token" python3 - "$config" <<'PYEOF'
import json
import os
import sys

path = sys.argv[1]
token = os.environ["CF_AI_GATEWAY_TOKEN"]
with open(path) as fh:
    content = fh.read()
resolved = content.replace("{env:CF_AI_GATEWAY_TOKEN}", token)
json.loads(resolved)
with open(path, "w") as fh:
    fh.write(resolved)
PYEOF
  chmod 600 "$config"
fi
