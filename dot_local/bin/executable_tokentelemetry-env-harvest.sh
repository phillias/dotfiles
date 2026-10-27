#!/bin/sh
# tokentelemetry token harvest (Wave A2, 2026-10-27).
# Reads the live Anthropic key from the bws vault at every unit start so
# rotations propagate without re-encrypting anything. The vault key is the
# env-shaped ANTHROPIC_KEY (which stays in the phillias project); it is
# mapped to ANTHROPIC_API_KEY for the app. If bws is unreachable or returns
# nothing, falls back to age-decrypting the retired on-disk copy
# (.anthropic-key.age) — that copy is fallback-only now, never the primary.
# Writes ANTHROPIC_API_KEY=<value> to the env file given as $1 (default
# $XDG_RUNTIME_DIR/tokentelemetry.env), loaded by the unit via
# EnvironmentFile. Exits 1 only when BOTH sources are unavailable: the unit
# cannot start without a key.
# Read via direct bws+jq, not a login shell: load-keys.sh deliberately
# never exports ANTHROPIC_API_KEY (it clears it to protect Claude native
# login), so the login-env harvest pattern cannot supply this variable.
set -eu
umask 077
env_file="${1:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/tokentelemetry.env}"
token_file="$HOME/.agents/keys/default/.bws-token"
project_id="fe9eea09-9eaf-45e6-a72f-b45e0150b29d"
value=""
if [ -r "$token_file" ]; then
    if [ -z "${BWS_BIN:-}" ] || [ ! -x "$BWS_BIN" ]; then
        if command -v bws >/dev/null 2>&1; then
            BWS_BIN="$(command -v bws)"
        elif [ -x "$HOME/.local/share/mise/installs/bitwarden-secrets-manager/latest/bws" ]; then
            BWS_BIN="$HOME/.local/share/mise/installs/bitwarden-secrets-manager/latest/bws"
        fi
    fi
    if [ -n "${BWS_BIN:-}" ] && [ -x "$BWS_BIN" ] && command -v jq >/dev/null 2>&1; then
        value="$(timeout 10 "$BWS_BIN" -t "$(cat "$token_file")" secret list "$project_id" -o json 2>/dev/null \
            | jq -r '.[] | select(.key=="ANTHROPIC_KEY") | .value' 2>/dev/null || true)"
    fi
fi
if [ -z "$value" ]; then
    # bws unreachable / key missing: age fallback (retired on-disk copy).
    value="$("$HOME/.local/share/mise/installs/age/latest/age/age" -d -i "$HOME/.config/chezmoi/key.txt" \
        "$HOME/.agents/keys/retired/phillias/.anthropic-key.age" 2>/dev/null || true)"
fi
if [ -z "$value" ]; then
    echo "tokentelemetry-env-harvest: no Anthropic key available (vault unreachable and age fallback missing)" >&2
    exit 1
fi
printf 'ANTHROPIC_API_KEY=%s\n' "$value" > "$env_file"
chmod 0600 "$env_file"
