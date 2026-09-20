#!/bin/bash
# ~/.local/bin/hermes-env-check.sh — chezmoi-managed, executable, in $PATH
# Hermes deployment health check. The units below are owned by hermes' own
# installer (divested from dotfiles in #195); the honcho scheduler is retired.
# Run manually:   hermes-env-check.sh
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
PASS=0
FAIL=0

check() {
  local label="$1" cmd="$2"
  if eval "$cmd" &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} $label"
    ((++PASS))
  else
    echo -e "  ${RED}✗${NC} $label"
    ((++FAIL))
  fi
}

echo "=== Hermes Deployment Environment Check ==="
echo ""

echo " Services:"
check "hermes-gateway  " "systemctl --user is-active hermes-gateway.service &>/dev/null"
check "gateway-mybiz   " "systemctl --user is-active hermes-gateway-mybiz.service &>/dev/null"
check "gateway-mybrain " "systemctl --user is-active hermes-gateway-mybrain.service &>/dev/null"
check "hermes-dashboard" "systemctl --user is-active hermes-dashboard.service &>/dev/null"
check "opencode-proxy  " "systemctl --user is-active opencode-proxy.service &>/dev/null"

echo ""
echo " Deployment:"
check "hermes config   " "test -f $HOME/.hermes/config.yaml"
check "agent venv      " "test -x $HOME/.hermes/hermes-agent/venv/bin/python"
check "profile mybiz   " "test -d $HOME/.hermes/profiles/mybiz"
check "profile mybrain " "test -d $HOME/.hermes/profiles/mybrain"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL
