#!/bin/bash
# go-pool-switch — Toggle between Go-pool and no-Go OpenCode configs
#
# Usage: go-pool-switch [go|nogo|status]
#
# go   — Switch to Go-pool config (best quality when sub is active)
# nogo — Switch to free-only config (no Go pool, avoids 429s when exhausted)

set -euo pipefail

CONF="$HOME/.config/opencode"
GO_CONF="$CONF/oh-my-openagent-go.json"
NOGO_CONF="$CONF/oh-my-openagent-nogo.json"
ACTIVE="$CONF/oh-my-openagent.json"

if [ ! -f "$GO_CONF" ]; then
    echo "ERROR: $GO_CONF not found. Back up your current config first:"
    echo "  cp $ACTIVE $GO_CONF"
    exit 1
fi

if [ ! -f "$NOGO_CONF" ]; then
    echo "ERROR: $NOGO_CONF not found."
    exit 1
fi

case "${1:-status}" in
    go)
        cp -f "$GO_CONF" "$ACTIVE"
        echo "✅ Switched to Go-pool config (quality-first)"
        ;;
    nogo)
        cp -f "$NOGO_CONF" "$ACTIVE"
        echo "✅ Switched to free-only config (no Go pool)"
        ;;
    status|*)
        current=$(file "$ACTIVE" 2>/dev/null | grep -o 'ASCII\|data' || echo "regular")
        if [[ "$current" == "data" ]]; then
            echo "Symbolic link detected"
        fi
        echo "Current config:"
        grep '"model"' "$ACTIVE" | head -3 | sed 's/^/  /'
        echo ""
        echo "Available:"
        echo "  go-pool-switch go    — Use Go-pool config"
        echo "  go-pool-switch nogo  — Use free-only config"
        ;;
esac

echo ""
echo "Restart or start new OpenCode session for changes to take effect."
