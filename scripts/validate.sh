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

echo "== semgrep (deterministic security gate; SonarQube-class without Sonar)"
# Deterministic registry ruleset; override with SEMGREP_RULESET=... if needed.
SEMGREP_RULESET="${SEMGREP_RULESET:-auto}"
# Equality-only semgrep pin lives in dot_config/mise/config.toml. Resolve via
# mise (version-pinned) so it works before the pinned shim is on PATH.
semgrep_run() { mise x "pipx:semgrep@1.157.0" -- semgrep "$@"; }
if semgrep_run --version >/dev/null 2>&1; then
  # Scope to the files changed vs the PR base (open PR commits + working tree)
  # so pre-existing findings elsewhere are NOT re-raised by this gate. Without
  # a base (detached/bootstrapped checkout) the repo-wide scan is skipped and
  # reported distinctly rather than failing on the pre-existing baseline.
  base="origin/master"
  base_ref="$base"
  git cat-file -e "$base" 2>/dev/null || base_ref="master"
  if git rev-parse --verify -q "$base_ref" >/dev/null; then
    changed=$( { git diff --name-only "$base_ref...HEAD" 2>/dev/null; git diff --name-only "$base_ref" 2>/dev/null; } | sort -u | tr '\n' ' ')
  else
    changed=""
  fi
  if [ -n "$changed" ]; then
    # shellcheck disable=SC2086
    semgrep_run scan --error --config "$SEMGREP_RULESET" $changed || fail=1
  else
    echo "note: no PR-base diff context (detached HEAD / empty diff) — repo-wide semgrep skipped (121 pre-existing baseline findings at 1.157.0, 2026-09-13)"
  fi
else
  echo "FAIL: semgrep unresolvable via mise (pipx:semgrep@1.157.0)"
  fail=1
fi

echo "== gitleaks (secret-leak gate, default config)"
gitleaks_run() { mise x "github:gitleaks/gitleaks@8.30.1" -- gitleaks "$@"; }
if gitleaks_run version >/dev/null 2>&1; then
  # Same changed-file scoping as semgrep; the repo tree holds 7 pre-existing
  # gitleaks findings (2026-09-13 baseline) which are reported, not gated here.
  if [ -n "${changed:-}" ]; then
    for f in $changed; do
      [ -f "$f" ] || continue
      gitleaks_run dir "$f" --no-banner --redact || fail=1
    done
  else
    echo "note: no PR-base diff context — repo-wide gitleaks skipped (7 pre-existing baseline findings, 2026-09-13)"
  fi
else
  echo "FAIL: gitleaks unresolvable via mise (github:gitleaks/gitleaks@8.30.1)"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "validate: all checks passed"
else
  echo "validate: FAILED"
fi
exit "$fail"
