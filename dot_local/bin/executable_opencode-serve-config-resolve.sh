#!/usr/bin/env bash
# opencode-serve-config-resolve.sh
# Resolves {env:VAR} and {file:path} patterns in opencode config for serve mode.
# opencode 1.19.0 serve mode does not resolve {env:VAR} interpolation (TUI mode does).
# This script creates opencode.json from opencode.json.tmpl on every serve start.
set -euo pipefail

# Source harvested env vars (systemd loads EnvironmentFile before ExecStartPre,
# but the harvest script that writes it also runs as ExecStartPre — so on first
# boot the vars may not be in the process env yet. Source directly to be safe.)
ENV_FILE="/run/user/$(id -u)/opencode-serve.env"
if [[ -f "$ENV_FILE" ]]; then
  source "$ENV_FILE"
fi

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
CONFIG="$CONFIG_DIR/opencode.json"
TMPL="$CONFIG_DIR/opencode.json.tmpl"

# If config still has {env: patterns (e.g. after chezmoi apply overwrote it),
# refresh the template to pick up any new or changed patterns.
if [[ -f "$CONFIG" ]] && grep -q '{env:' "$CONFIG" 2>/dev/null; then
  cp "$CONFIG" "$TMPL"
fi

# Ensure template exists
if [[ ! -f "$TMPL" ]]; then
  if [[ -f "$CONFIG" ]]; then
    cp "$CONFIG" "$TMPL"
  else
    echo "No opencode.json or opencode.json.tmpl found in $CONFIG_DIR" >&2
    exit 1
  fi
fi

# Resolve {env:VAR} and {file:path} patterns using python3
python3 - "$TMPL" "$CONFIG" <<'PYEOF'
import sys, os, re, json

tmpl_path, out_path = sys.argv[1], sys.argv[2]

with open(tmpl_path, 'r') as f:
    content = f.read()

def resolve_env(match):
    var = match.group(1)
    return os.environ.get(var, '')

def resolve_file(match):
    path = match.group(1)
    try:
        with open(path, 'r') as f:
            return f.read().strip()
    except Exception:
        return ''

content = re.sub(r'\{env:([^}]+)\}', resolve_env, content)
content = re.sub(r'\{file:([^}]+)\}', resolve_file, content)

# Validate JSON
try:
    json.loads(content)
except json.JSONDecodeError as e:
    print(f"Resolved config is invalid JSON: {e}", file=sys.stderr)
    sys.exit(1)

with open(out_path, 'w') as f:
    f.write(content)
PYEOF

# Restrict permissions (config may contain resolved secrets)
chmod 600 "$CONFIG" 2>/dev/null || true

echo "Config resolved: $TMPL -> $CONFIG"
