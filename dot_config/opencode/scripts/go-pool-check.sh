#!/bin/bash
# go-pool-check.sh — Check Go pool status and print recommended config
# Run before starting OpenCode to decide which config to use

set -euo pipefail

# Try to detect pool status from OpenCode's own state
# OpenCode stores session data and error state we can inspect

CONFIG_DIR="$HOME/.config/opencode"
STATE_DIR="$HOME/.opencode/state"

echo "=== Go Pool Status Check ==="
echo ""

# Check 1: Look for recent 429/rate-limit errors in opencode logs
RECENT_ERRORS=""
if command -v journalctl &>/dev/null; then
  RECENT_ERRORS=$(journalctl -u opencode --since "1 hour ago" 2>/dev/null | \
    grep -i "429\|rate.limit\|usage.limit\|exhausted\|gousagelimit\|freeusagelimit" | \
    tail -5 || true)
fi

# Check 2: Check if opencode-go API responds (indirect test)
# Hit a Go pool model endpoint and check for 429
API_STATUS="unknown"
TIMEOUT=10

# Use the Go pool endpoint (same one OpenCode uses)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  --connect-timeout "$TIMEOUT" \
  "https://opencode.ai/zen/go/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"kimi-k2.6","messages":[],"max_tokens":1}' 2>/dev/null || echo "000")

case "$HTTP_CODE" in
  429)
    API_STATUS="EXHAUSTED (429 rate limited)"
    ;;
  200|400|401|403)
    # 200 = active, 400/401/403 = endpoint exists but auth/model issue = likely active
    API_STATUS="ACTIVE (HTTP $HTTP_CODE)"
    ;;
  000)
    API_STATUS="UNKNOWN (no response)"
    ;;
  *)
    API_STATUS="UNKNOWN (HTTP $HTTP_CODE)"
    ;;
esac

echo "API Check: $API_STATUS"
echo ""

# Check 3: Recent errors from logs
if [ -n "$RECENT_ERRORS" ]; then
  echo "Recent rate-limit errors found:"
  echo "$RECENT_ERRORS" | head -3
  echo ""
  HAS_RECENT_ERRORS=true
else
  echo "No recent rate-limit errors in logs."
  HAS_RECENT_ERRORS=false
fi

echo ""

# Recommendation
case "$API_STATUS" in
  EXHAUSTED)
    echo "⚠️  Go pool appears EXHAUSTED."
    echo ""
    echo "Recommended: Use no-Go config"
    echo "  Run: ln -sf $CONFIG_DIR/oh-my-openagent-nogo.json $CONFIG_DIR/oh-my-openagent.json"
    echo ""
    echo "The free-primary config will be used automatically if you have it set up."
    ;;
  ACTIVE)
    if [ "$HAS_RECENT_ERRORS" = true ]; then
      echo "🔶 Pool is ACTIVE but recent errors detected."
      echo "Monitor — if errors persist, switch to no-Go config."
    else
      echo "✅ Go pool is ACTIVE and healthy."
      echo "Recommended: Use Go-pool config for best quality."
    fi
    ;;
  *)
    echo "❓ Cannot determine pool status."
    echo "Defaulting to Go-pool config (will fallback to free on exhaustion)."
    ;;
esac
