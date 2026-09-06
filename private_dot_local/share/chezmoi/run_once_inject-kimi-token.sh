#!/bin/sh
# Inject CF AI Gateway token into kimi-code config
TOKEN_FILE="$HOME/.config/opencode/.cf-ai-gw-token"
KIMI_CONFIG="$HOME/.kimi-code/config.toml"

if [ -f "$TOKEN_FILE" ] && [ -f "$KIMI_CONFIG" ]; then
  TOKEN=$(cat "$TOKEN_FILE")
  sed -i "s/CF_AI_GW_TOKEN_PLACEHOLDER/$TOKEN/" "$KIMI_CONFIG"
fi
