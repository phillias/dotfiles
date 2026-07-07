#!/bin/bash
# ~/.local/bin/hermes-env-check.sh — chezmoi-managed, executable, in $PATH
# Hermes+Honcho installation health check.
# Run manually:   hermes-env-check.sh
# Runs daily via: honcho job (hermes-env-check)
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
    ((PASS++))
  else
    echo -e "  ${RED}✗${NC} $label"
    ((FAIL++))
  fi
}

echo "=== Hermes+Honcho Environment Check ==="
echo ""

echo " Binaries:"
check "hermes           " "command -v hermes"
check "honcho           " "command -v honcho"

echo ""
echo " Repo:"
check "mybrain repo     " "test -d ${MYBRAIN_HOME:-$HOME/mybrain}/.git"
check "hermes scripts   " "ls ${MYBRAIN_HOME:-$HOME/mybrain}/scripts/hermes/mybrain-daily.sh &>/dev/null"

echo ""
echo " Services:"
check "hermes-cron.timer" "systemctl --user is-active hermes-cron.timer &>/dev/null"
check "hermes-honcho.timer" "systemctl --user is-active hermes-honcho.timer &>/dev/null"

echo ""
echo " Config:"
check "hermes config    " "test -f $HOME/.config/hermes/config.yaml"
check "honcho jobs      " "test -f $HOME/.config/honcho/jobs.yaml"
check "env file         " "test -f $HOME/.hermes-env"

echo ""
echo " Data:"
check "brain.db         " "test -f ${MYBRAIN_DB_PATH:-$HOME/mybrain/data/brain.db}"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL
