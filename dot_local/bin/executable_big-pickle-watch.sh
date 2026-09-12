#!/usr/bin/env bash
# big-pickle-watch.sh — per-minute availability probe for opencode-zen/big-pickle.
# Probes two routes (direct zen API + Cloudflare AI Gateway BYOK lane) with a
# 1-token chat completion and appends one CSV line per test per route.
#
# Log: /tmp/big-pickle-availability.csv (never rotated, by design).
# Columns:
#   ts            ISO-8601 UTC timestamp of the test
#   route         direct | gateway
#   http_code     HTTP status (000 = transport error/timeout)
#   result        ok | limited | error | timeout
#   latency_ms    round-trip milliseconds
#   model         model id probed
#   err_type      error type field from body when present (e.g. FreeUsageLimitError)
#   retry_after_s retry-after header seconds when present
#   rate_headers  any x-ratelimit-*/ratelimit headers, ';'-joined (often empty)
#   detail        short sanitized body/detail snippet
#
# Secrets (zen key, gateway token) are read at runtime and never logged.
set -u

CSV=/tmp/big-pickle-availability.csv
MODEL=big-pickle
ZEN_KEY=$(python3 -c "import json;print(json.load(open('$HOME/.local/share/opencode/auth.json'))['opencode']['key'])" 2>/dev/null || true)
GW_TOKEN=${CF_AI_GATEWAY_TOKEN:-}
GW_URL='https://gateway.ai.cloudflare.com/v1/a7fa198dd5b359a187c671064fe6b36e/opencode/custom-opencode-zen/v1/chat/completions'
DIRECT_URL='https://opencode.ai/zen/v1/chat/completions'

mkdir -p /tmp
exec 9>"$CSV.lock"
flock -n 9 || exit 0

if [ ! -e "$CSV" ]; then
  printf 'ts,route,http_code,result,latency_ms,model,err_type,retry_after_s,rate_headers,detail\n' > "$CSV"
  chmod 644 "$CSV"
fi

sanitize() {
  # CSV-safe: strip commas/quotes/newlines, collapse spaces, cap length.
  printf '%s' "$1" | tr -d '",\n\r' | tr -s ' ' | cut -c1-160
}

probe() {
  local route=$1 url=$2 tok=$3 extra_hdr=$4
  local ts code latency body hdr err_type retry rate detail result rc
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  hdr=$(mktemp) ; body=$(mktemp)

  if [ -z "$tok" ]; then
    printf '%s,%s,000,error,0,%s,missing_token,,,no_token_available\n' "$ts" "$route" "$MODEL" >> "$CSV"
    rm -f "$hdr" "$body"; return
  fi

  code=$(curl -sS -o "$body" -D "$hdr" -w '%{http_code} %{time_total}' --max-time 20 -X POST "$url" \
    -H "Authorization: Bearer $tok" $extra_hdr -H 'Content-Type: application/json' \
    -d "{\"model\":\"$MODEL\",\"max_tokens\":1,\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}]}" 2>/dev/null)
  rc=$?
  latency=$(printf '%s' "$code" | awk '{printf "%.0f", $2*1000}')
  code=$(printf '%s' "$code" | awk '{print $1}')

  if [ "$rc" -ne 0 ]; then
    result=timeout ; code=000 ; err_type="curl_err_$rc" ; detail="curl exit $rc"
  else
    retry=$(grep -i '^retry-after:' "$hdr" | tail -1 | tr -dc '0-9')
    rate=$(grep -iE '^(x-ratelimit|ratelimit)' "$hdr" | tr -d '\r' | paste -sd';' -)
    err_type=$(python3 -c "import json;print(json.load(open('$body')).get('error',{}).get('type',''))" 2>/dev/null || true)
    if [ "$code" = "200" ]; then
      result=ok
      detail="finish=$(python3 -c "import json;print(json.load(open('$body'))['choices'][0]['finish_reason'])" 2>/dev/null || true)"
    elif [ "$code" = "429" ] || [ "$err_type" = "FreeUsageLimitError" ]; then
      result=limited
      detail=$(python3 -c "import json;print(json.load(open('$body')).get('error',{}).get('message',''))" 2>/dev/null || true)
    else
      result=error ; detail=$(head -c 200 "$body")
    fi
  fi

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$ts" "$route" "${code:-000}" "$result" "${latency:-0}" "$MODEL" \
    "$(sanitize "${err_type:-}")" "${retry:-}" "$(sanitize "${rate:-}")" "$(sanitize "${detail:-}")" >> "$CSV"
  rm -f "$hdr" "$body"
}

probe direct  "$DIRECT_URL" "$ZEN_KEY" ""
probe gateway "$GW_URL"     "$GW_TOKEN" "-H cf-aig-gateway-id:opencode"
