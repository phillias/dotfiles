#!/bin/sh
# no-mistakes daemon token harvest (2026-10-16).
# Source the bws-first login environment (zsh -l -> .zshenv -> load-keys.sh)
# and write CF_AI_GATEWAY_TOKEN + AI_GATEWAY_API_KEY + OPENROUTER_API_KEY
# to the daemon env file. pi resolves $OPENROUTER_API_KEY at process start
# for the openrouter-direct lane, so pipeline-spawned pi needs it here.
# A definitive 401 from either gateway (or openrouter) refuses to start
# the unit loudly — systemd shows it failed instead of running a pipeline
# that cannot reach any lane. Transient errors (5xx, network) do not block
# the start.
# Replaces direct decryption of the retired age fallbacks, which went stale
# after the vault rotation and silently 401'd every pipeline step for ~2 days.
set -eu
umask 077
env_file="${1:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/no-mistakes-daemon.env}"
harvest="$(zsh -lc 'printf "CF_AI_GATEWAY_TOKEN=%s\nAI_GATEWAY_API_KEY=%s\nOPENROUTER_API_KEY=%s\n" "$CF_AI_GATEWAY_TOKEN" "$AI_GATEWAY_API_KEY" "$OPENROUTER_API_KEY"')"
cf_token="$(printf '%s\n' "$harvest" | sed -n 's/^CF_AI_GATEWAY_TOKEN=//p')"
vl_token="$(printf '%s\n' "$harvest" | sed -n 's/^AI_GATEWAY_API_KEY=//p')"
or_token="$(printf '%s\n' "$harvest" | sed -n 's/^OPENROUTER_API_KEY=//p')"
if [ -z "$cf_token" ] || [ -z "$vl_token" ] || [ -z "$or_token" ]; then
  echo "nm-daemon-env-harvest: empty harvest (load-keys.sh exported nothing — check bws)" >&2
  exit 1
fi
printf 'CF_AI_GATEWAY_TOKEN=%s\nAI_GATEWAY_API_KEY=%s\nOPENROUTER_API_KEY=%s\n' "$cf_token" "$vl_token" "$or_token" > "$env_file"
chmod 0600 "$env_file"
fail=0
code="$(curl -s -m 10 -o /dev/null -w '%{http_code}' \
  -X POST 'https://gateway.ai.cloudflare.com/v1/a7fa198dd5b359a187c671064fe6b36e/opencode/compat/chat/completions' \
  -H "Authorization: Bearer $cf_token" \
  -H 'Content-Type: application/json' \
  -d '{"model":"dynamic/pr-gate","messages":[{"role":"user","content":"healthcheck"}],"max_tokens":1}' \
)" || code=000
if [ "$code" = "401" ]; then
  echo "nm-daemon-env-harvest: Cloudflare gateway rejected token (401)" >&2
  fail=1
fi
code="$(curl -s -m 10 -o /dev/null -w '%{http_code}' \
  -X POST 'https://ai-gateway.vercel.sh/v1/chat/completions' \
  -H "Authorization: Bearer $vl_token" \
  -H 'Content-Type: application/json' \
  -d '{"model":"router/pr-gate","messages":[{"role":"user","content":"healthcheck"}],"max_tokens":1}' \
)" || code=000
if [ "$code" = "401" ]; then
  echo "nm-daemon-env-harvest: Vercel gateway rejected token (401)" >&2
  fail=1
fi
code="$(curl -s -m 10 -o /dev/null -w '%{http_code}' \
  'https://openrouter.ai/api/v1/key' \
  -H "Authorization: Bearer $or_token" \
  )" || code=000
if [ "$code" = "401" ]; then
  echo "nm-daemon-env-harvest: OpenRouter rejected token (401)" >&2
  fail=1
fi
exit "$fail"
