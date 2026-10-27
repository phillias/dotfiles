#!/bin/sh
# tokentelemetry token harvest (Wave A2, 2026-10-27).
# Reads the live Anthropic key from the bws vault at every unit start so
# rotations propagate without re-encrypting anything. The vault key is the
# env-shaped ANTHROPIC_KEY (which stays in the phillias project); it is
# mapped to ANTHROPIC_API_KEY for the app. If the vault fetch fails, falls
# back to age-decrypting the retired on-disk copy (.anthropic-key.age); a
# successful response without ANTHROPIC_KEY is an error.
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
vault_output=""
vault_fetch_succeeded=0
if [ -r "$token_file" ]; then
    if [ -z "${BWS_BIN:-}" ] || [ ! -x "$BWS_BIN" ]; then
        if command -v bws >/dev/null 2>&1; then
            BWS_BIN="$(command -v bws)"
        elif [ -x "$HOME/.local/share/mise/installs/bitwarden-secrets-manager/latest/bws" ]; then
            BWS_BIN="$HOME/.local/share/mise/installs/bitwarden-secrets-manager/latest/bws"
        fi
    fi
    if [ -n "${BWS_BIN:-}" ] && [ -x "$BWS_BIN" ] && command -v jq >/dev/null 2>&1; then
        vault_output="$(timeout 10 "$BWS_BIN" -t "$(cat "$token_file")" secret list "$project_id" -o json 2>/dev/null || true)"
        case "$vault_output" in
            \[*)
                vault_fetch_succeeded=1
                value="$(printf '%s' "$vault_output" | jq -r '.[] | select(.key=="ANTHROPIC_KEY" and (.value // "") != "") | .value' 2>/dev/null || true)"
                ;;
        esac
    fi
fi
if [ "$vault_fetch_succeeded" -eq 1 ] && [ -z "$value" ]; then
    echo "tokentelemetry-env-harvest: ANTHROPIC_KEY missing from successful vault response" >&2
    exit 1
fi
if [ -z "$value" ]; then
    value="$("$HOME/.local/share/mise/installs/age/latest/age/age" -d -i "$HOME/.config/chezmoi/key.txt" \
        "$HOME/.agents/keys/retired/phillias/.anthropic-key.age" 2>/dev/null || true)"
fi
if [ -z "$value" ]; then
    echo "tokentelemetry-env-harvest: no Anthropic key available (vault unreachable and age fallback missing)" >&2
    exit 1
fi
printf 'ANTHROPIC_API_KEY=%s\n' "$value" > "$env_file"
chmod 0600 "$env_file"
