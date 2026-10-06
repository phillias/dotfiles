#!/usr/bin/env bash
# Daily free-GLM lane scan (provider-catalog companion).
# Detects changes in free GLM lanes across gateway providers and NIM.
# Writes state to ~/.local/state/opencode-fleet/glm-free-scan.state and
# notifies via ntfy only when ~/.config/opencode/glm-scan.ntfy.env exists
# (NTFY_URL=... NTFY_TOKEN=... lines, user-readable only) AND the state
# changed since the previous run. Without that env file it is silent except
# for stdout (journald captures it).
# Free-lane conventions differ per provider:
#   openrouter -> ids ending in ":free"    (zen listing works via curl even
#   zen        -> ids ending in "-free"     though serving is app-gated)
#   NIM        -> presence only (free-ness is a catalog fact, not in listing)
set -uo pipefail

STATE_DIR="$HOME/.local/state/opencode-fleet"
STATE="$STATE_DIR/glm-free-scan.state"
NTFY_ENV="$HOME/.config/opencode/glm-scan.ntfy.env"
GW="${CF_AI_GATEWAY_TOKEN:-$(cat "$HOME/.agents/keys/default/.cf-ai-gw" 2>/dev/null || true)}"
BASE="https://gateway.ai.cloudflare.com/v1/a7fa198dd5b359a187c671064fe6b36e/opencode"

mkdir -p "$STATE_DIR"

scan_gateway() { # $1=segment $2=label $3=grep -E regex
  local body out
  body="$(curl -sS --max-time 30 \
    -H "Authorization: Bearer $GW" -H "cf-aig-gateway-id: opencode" \
    "$BASE/$1/models" 2>/dev/null)"
  if [ -z "$GW" ] || [ -z "$body" ] \
    || ! jq -e '(.data? | length) >= 0' >/dev/null 2>&1 <<<"$body"; then
    echo "$2: fetch-failed"
    return
  fi
  out="$(jq -r '.data[]?.id // empty' <<<"$body" \
    | grep -iE "$3" | sort -u | tr '\n' ' ')"
  echo "$2: ${out:-none}"
}

nim_key="$(jq -r '.provider.nvidia.options.apiKey // empty' \
  "$HOME/.config/opencode/opencode.json" 2>/dev/null || true)"
nim_out="key-unavailable"
if [ -n "$nim_key" ]; then
  nim_out="$(curl -sS --max-time 30 \
    -H "Authorization: Bearer $nim_key" \
    https://integrate.api.nvidia.com/v1/models 2>/dev/null \
    | jq -r '.data[]?.id // empty' 2>/dev/null \
    | grep -iE 'glm' | sort -u | tr '\n' ' ')"
  [ -n "$nim_out" ] || nim_out="none"
fi

audit_last="$(grep -o '"served_model":"[^"]*glm[^"]*"' \
  "$STATE_DIR/dynamic-audit.jsonl" 2>/dev/null | tail -1 || true)"

{
  scan_gateway 'openrouter/v1' 'openrouter-free-glm' 'glm-[0-9].*:free'
  scan_gateway 'custom-opencode-zen/v1' 'zen-free-glm' 'glm-.*-free'
  echo "nim-glm: $nim_out"
  echo "audit-glm-served-last: ${audit_last:-none}"
} > "$STATE.new"

echo "glm-free-lane-scan $(date -Is)"
if [ ! -f "$STATE" ]; then
  mv "$STATE.new" "$STATE"
  cat "$STATE"
  echo "state seeded (first run)"
  exit 0
fi
if cmp -s "$STATE" "$STATE.new"; then
  rm -f "$STATE.new"
  echo "no change"
  exit 0
fi
cp "$STATE" "$STATE.prev"
echo "--- state changed:"
diff "$STATE.prev" "$STATE.new" || true
mv "$STATE.new" "$STATE"
if [ -f "$NTFY_ENV" ]; then
  # shellcheck disable=SC1090
  . "$NTFY_ENV"
  if [ -n "${NTFY_URL:-}" ] && [ -n "${NTFY_TOKEN:-}" ]; then
    summary="$(diff "$STATE.prev" "$STATE" | tr '\n' ';' | cut -c1-380)"
    curl -sS --max-time 15 \
      -H "Authorization: Bearer $NTFY_TOKEN" \
      -d "GLM free-lane change on $(hostname -s): $summary" \
      "$NTFY_URL" >/dev/null 2>&1 || echo "ntfy notify failed"
  fi
fi
echo "state changed"
exit 1
