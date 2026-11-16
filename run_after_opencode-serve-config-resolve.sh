#!/usr/bin/env bash
# Resolve {env:VAR} and {file:path} patterns in opencode config after chezmoi
# renders it. opencode serve mode (1.19.0) does not resolve {env:VAR}
# interpolation in provider apiKey fields — it sends the literal pattern as the
# bearer token and the gateway 401s. TUI mode resolves natively.
#
# The same resolve logic runs as ExecStartPre in opencode-serve.service, but
# a chezmoi apply that re-renders opencode.json after the serve has started
# overwrites the resolved values with raw patterns. This run_after hook closes
# that gap by re-resolving immediately after every apply.
#
# Skipped gracefully when the harvest env file is missing (serve never started)
# or when the config has no patterns to resolve.
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
CONFIG="$CONFIG_DIR/opencode.json"

[[ -f "$CONFIG" ]] || exit 0
grep -q '{env:' "$CONFIG" 2>/dev/null || exit 0

ENV_FILE="/run/user/$(id -u)/opencode-serve.env"
if [[ -f "$ENV_FILE" ]]; then
  source "$ENV_FILE"
fi

TMPL="$CONFIG_DIR/opencode.json.tmpl"

cp "$CONFIG" "$TMPL"

python3 - "$TMPL" "$CONFIG" <<'PYEOF'
import sys, os, re, json

tmpl_path, out_path = sys.argv[1], sys.argv[2]

with open(tmpl_path, "r") as f:
    content = f.read()

def resolve_env(match):
    var = match.group(1)
    return os.environ.get(var, "")

def resolve_file(match):
    path = match.group(1)
    try:
        with open(path, "r") as f:
            return f.read().strip()
    except Exception:
        return ""

content = re.sub(r"\{env:([^}]+)\}", resolve_env, content)
content = re.sub(r"\{file:([^}]+)\}", resolve_file, content)

try:
    json.loads(content)
except json.JSONDecodeError as e:
    print(f"[opencode-config-resolve] Resolved config is invalid JSON: {e}", file=sys.stderr)
    sys.exit(1)

with open(out_path, "w") as f:
    f.write(content)
PYEOF

chmod 600 "$CONFIG" 2>/dev/null || true

echo "[opencode-config-resolve] Resolved {env:} patterns after chezmoi apply"
