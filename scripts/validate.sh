#!/usr/bin/env bash
# Deterministic config validation for the dotfiles repo.
# Picked up by the no-mistakes test/lint steps; no network, fails loudly.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0

echo "== chezmoi doctor (informational; hardlink check is environmental on tmpfs boxes)"
chezmoi doctor || echo "note: chezmoi doctor reported issues above — review, not gating"

echo "== render all .tmpl (syntax + data check)"
mkdir -p /tmp/opencode
while IFS= read -r -d '' f; do
  if ! chezmoi execute-template < "$f" > /dev/null 2> /tmp/opencode/tmpl.err; then
    echo "FAIL: $f: $(cat /tmp/opencode/tmpl.err)"
    fail=1
  fi
done < <(find . -name '*.tmpl' -not -path './.git/*' -print0)

echo "== JSON parse"
for j in dot_config/opencode/opencode.json dot_config/opencode/dispatch-rules.json; do
  [ -f "$j" ] || continue
  if ! jq empty "$j" 2> /tmp/opencode/jq.err; then
    echo "FAIL: invalid JSON: $j: $(cat /tmp/opencode/jq.err)"
    fail=1
  fi
done

if [ "$fail" -eq 0 ]; then
  echo "validate: all checks passed"
else
  echo "validate: FAILED"
fi
exit "$fail"
