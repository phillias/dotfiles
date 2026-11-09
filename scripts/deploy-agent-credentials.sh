#!/usr/bin/env bash
# deploy-agent-credentials.sh — seed portable CLI credential files from BWS.
#
# Manifest format, how to add a tool, the refresh-staleness caveat, and the
# laptop-login + scp fallback: scripts/README (same directory).
#
# Deploy-once: write a target only when it is absent. --force overwrites
# after a timestamped backup beside the target. The vault value is a
# first-login seed; the host CLI refreshes tokens after that.
#
# Stdout is one line per entry: tool status path sha256-prefix
# (status is deployed or skipped; the prefix is 12 hex chars).
# Failures print `tool error code` on stdout and exit nonzero.
# Secret values are never printed. Do not run this script under bash -x.
#
# Usage:
#   deploy-agent-credentials.sh [--force] [--manifest <path>]
#
# Auth: an already-set BWS_ACCESS_TOKEN wins, else BWS_TOKEN_FILE, else
# ~/.agents/keys/default/.bws-token when that file is readable.
# A token file never replaces an ambient BWS_ACCESS_TOKEN.
# Project: BWS_PROJECT_ID or the phillias pin used by scripts/setup.sh
# (fe9eea09-9eaf-45e6-a72f-b45e0150b29d). That pin is a project id.
# A secret id is not a project id; `bws secret get` receives the secret id
# only after the manifest key is resolved. bws 2.1.0 get accepts an id only.
#
# --force is required to overwrite a live credential. The local CLI holds
# newer refresh tokens than any vault snapshot. --force writes a timestamped
# backup beside the target, then replaces the file.
#
# Chezmoi applies scripts/* to ~/scripts/ at mode 0664, without the
# executable bit. Invoke the source copy
# ~/.local/share/chezmoi/scripts/deploy-agent-credentials.sh, or
# `bash ~/scripts/deploy-agent-credentials.sh`.
#
# bws lookup honors BWS_BIN when that path runs. Otherwise it uses `bws` on
# PATH when `bws --version` succeeds. A mise shim that errors (synthetic
# HOME: config files are not trusted) is treated as missing. The script then
# retries <shim-dir>/../installs/bitwarden-secrets-manager/latest/bws, which
# does not consult mise's HOME-relative trust database.
#
# OpenCode's ~/.local/share/opencode/auth.json is not chezmoi-managed.
# A host still holding the old age-encrypted copy must move that file aside
# and re-seed per host; the encrypted copy is a stale snapshot. See scripts/README.
# commandcode whoami can hang on kali; prefer quota-axi for an auth proof.
set -euo pipefail
umask 077

usage() {
    cat <<'EOF'
usage: deploy-agent-credentials.sh [--force] [--manifest <path>]

Seed credential files listed in scripts/agent-credentials.conf from the
phillias BWS project. Manifest format, adding a tool, refresh staleness,
and the laptop-login + scp fallback are documented in scripts/README.

  --force            overwrite a live credential after a timestamped backup.
                     The local CLI holds newer refresh tokens than any snapshot.
  --manifest <path>  manifest to read (default: beside this script)

Chezmoi installs this file to ~/scripts/ mode 0664 (not executable).
Run ~/.local/share/chezmoi/scripts/deploy-agent-credentials.sh, or
bash ~/scripts/deploy-agent-credentials.sh.

deploy-once: an existing target is left in place with the message
"deploy-once: exists, skipping (use --force)". Stdout prints one line
per entry, `tool status path sha256-prefix`, and never prints file contents.
EOF
}

# Structured failure. $1 tool, $2 code. Optional human text is already on stderr.
fail() {
    printf '%s error %s\n' "$1" "$2"
    exit 1
}

# One manifest row failed. Later rows still run. The process exits 1 at the end.
any_fail=0
entry_fail() {
    printf '%s error %s\n' "$1" "$2"
    any_fail=1
}

note() {
    printf '%s\n' "$*" >&2
}

force=0
manifest=""

while [ $# -gt 0 ]; do
    case "$1" in
        --force) force=1 ;;
        --manifest)
            [ $# -ge 2 ] || { note "--manifest needs a value"; fail deploy-agent-credentials bad-args; }
            manifest="$2"
            shift
            ;;
        -h | --help) usage; exit 0 ;;
        *)
            usage >&2
            note "unknown argument: $1"
            fail deploy-agent-credentials bad-args
            ;;
    esac
    shift
done

script_dir="$(dirname "$(readlink -f "$0")")"
if [ -z "$manifest" ]; then
    manifest="$script_dir/agent-credentials.conf"
fi
[ -f "$manifest" ] || { note "manifest not found: $manifest"; fail deploy-agent-credentials bad-manifest; }

command -v jq >/dev/null 2>&1 || { note "jq is required"; fail deploy-agent-credentials jq-missing; }
command -v base64 >/dev/null 2>&1 || { note "base64 is required"; fail deploy-agent-credentials base64-missing; }
command -v sha256sum >/dev/null 2>&1 || { note "sha256sum is required"; fail deploy-agent-credentials sha256sum-missing; }

# phillias project pin, same id scripts/setup.sh and load-keys.sh hardcode.
project_id="${BWS_PROJECT_ID:-fe9eea09-9eaf-45e6-a72f-b45e0150b29d}"

# True when the path is executable and does not depend on a HOME-trusted mise config.
bws_runnable() {
    [ -n "${1:-}" ] && [ -x "$1" ] && "$1" --version >/dev/null 2>&1
}

bws_bin=""
if bws_runnable "${BWS_BIN:-}"; then
    bws_bin="$BWS_BIN"
else
    bws_candidate="$(command -v bws || true)"
    if bws_runnable "$bws_candidate"; then
        bws_bin="$bws_candidate"
    else
        # Shim on PATH but `bws --version` failed. The real binary lives next
        # to the shim directory, not under a synthetic HOME.
        if [ -n "$bws_candidate" ]; then
            bws_shim_dir="$(dirname -- "$bws_candidate")"
            bws_derived="$(cd -- "$bws_shim_dir/.." && pwd)/installs/bitwarden-secrets-manager/latest/bws"
            if bws_runnable "$bws_derived"; then
                bws_bin="$bws_derived"
            fi
        fi
        if [ -z "$bws_bin" ]; then
            bws_passwd_home="$(getent passwd "$(id -un)" 2>/dev/null | awk -F: 'NR==1 { print $6 }' || true)"
            if [ -n "$bws_passwd_home" ] && bws_runnable "$bws_passwd_home/.local/share/mise/installs/bitwarden-secrets-manager/latest/bws"; then
                bws_bin="$bws_passwd_home/.local/share/mise/installs/bitwarden-secrets-manager/latest/bws"
            elif bws_runnable "$HOME/.local/share/mise/installs/bitwarden-secrets-manager/latest/bws"; then
                bws_bin="$HOME/.local/share/mise/installs/bitwarden-secrets-manager/latest/bws"
            fi
        fi
    fi
fi
[ -n "$bws_bin" ] || { note "bws binary not found or not runnable (set BWS_BIN)"; fail deploy-agent-credentials bws-missing; }

# Env wins. A readable default token file must not clobber BWS_ACCESS_TOKEN.
if [ -z "${BWS_ACCESS_TOKEN:-}" ] && [ -n "${BWS_TOKEN_FILE:-}" ]; then
    [ -r "$BWS_TOKEN_FILE" ] || { note "BWS_TOKEN_FILE is not readable"; fail deploy-agent-credentials bws-auth; }
    BWS_ACCESS_TOKEN="$(<"$BWS_TOKEN_FILE")"
elif [ -z "${BWS_ACCESS_TOKEN:-}" ] && [ -r "$HOME/.agents/keys/default/.bws-token" ]; then
    BWS_ACCESS_TOKEN="$(<"$HOME/.agents/keys/default/.bws-token")"
fi
[ -n "${BWS_ACCESS_TOKEN:-}" ] || { note "no bws access token (set BWS_ACCESS_TOKEN or BWS_TOKEN_FILE)"; fail deploy-agent-credentials bws-auth; }
export BWS_ACCESS_TOKEN

tmp=""
errfile=""
raw=""
b64_value=""
id_map=""
cleanup() {
    [ -n "$tmp" ] && rm -f -- "$tmp"
    [ -n "$errfile" ] && rm -f -- "$errfile"
    unset raw b64_value id_map BWS_ACCESS_TOKEN || true
}
trap cleanup EXIT

sha_prefix() {
    sha256sum -- "$1" | awk 'NR==1 { print substr($1, 1, 12) }'
}

# bws stderr can echo request details. Classify it; never reprint it.
bws_fail() {
    local tool="$1" code="bws-error"
    if [ -n "$errfile" ] && [ -f "$errfile" ] && grep -Eqi 'access token|unauthorized|invalid_client|invalid access|401|forbidden' "$errfile"; then
        code="bws-auth"
    fi
    if [ "$code" = "bws-auth" ]; then
        note "bws authentication failed"
    else
        note "bws request failed"
    fi
    fail "$tool" "$code"
}

bws_call() {
    # Remaining args are the bws subcommand and its arguments.
    # -t bypasses the stale state-file session cache (bws 2.1.0).
    errfile="$(mktemp)"
    raw=""
    if ! raw="$("$bws_bin" -t "$BWS_ACCESS_TOKEN" -c no "$@" -o json 2>"$errfile")"; then
        unset raw
        bws_fail deploy-agent-credentials
    fi
    rm -f -- "$errfile"
    errfile=""
}

tools=()
keys=()
relpaths=()
modes=()

while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    trim="${line#"${line%%[![:space:]]*}"}"
    case "$trim" in
        '' | \#*) continue ;;
    esac
    IFS=$'\t' read -r tool key relpath mode extra <<<"$trim"
    if [ -n "${extra:-}" ] || [ -z "${tool:-}" ] || [ -z "${key:-}" ] || [ -z "${relpath:-}" ] || [ -z "${mode:-}" ]; then
        note "manifest line needs exactly four tab-separated fields"
        fail deploy-agent-credentials bad-manifest
    fi
    if ! [[ "$tool" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
        note "invalid tool name: $tool"
        fail deploy-agent-credentials bad-manifest
    fi
    if ! [[ "$key" =~ ^[A-Za-z0-9._-]+$ ]]; then
        note "invalid secret key for $tool"
        fail deploy-agent-credentials bad-manifest
    fi
    case "$relpath" in
        /* | .. | ../* | */.. | */../*)
            note "target path must stay under \$HOME: $relpath"
            fail deploy-agent-credentials bad-manifest
            ;;
    esac
    if ! [[ "$mode" =~ ^0[0-7]{3}$ ]]; then
        note "mode must be four-digit octal: $mode"
        fail deploy-agent-credentials bad-manifest
    fi
    tools+=("$tool")
    keys+=("$key")
    relpaths+=("$relpath")
    modes+=("$mode")
done <"$manifest"

[ "${#tools[@]}" -gt 0 ] || { note "manifest has no entries"; fail deploy-agent-credentials empty-manifest; }

# Resolve every key to an id. Drop list payloads immediately: `secret list`
# returns values, and this script must not keep them.
bws_call secret list "$project_id"
if ! id_map="$(printf '%s' "$raw" | jq -ce 'if type == "array" then map({key, id}) else error("not-array") end' 2>/dev/null)"; then
    unset raw
    note "bws secret list was not a JSON array"
    fail deploy-agent-credentials bws-error
fi
unset raw

uuid_re='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

for i in "${!tools[@]}"; do
    tool="${tools[$i]}"
    key="${keys[$i]}"
    relpath="${relpaths[$i]}"
    mode="${modes[$i]}"
    target="$HOME/$relpath"

    if [[ "$key" =~ $uuid_re ]]; then
        secret_id="$key"
    else
        secret_id="$(printf '%s' "$id_map" | jq -r --arg k "$key" 'first(.[] | select(.key == $k) | .id) // empty' 2>/dev/null)"
    fi
    if [ -z "$secret_id" ] || [ "$secret_id" = "null" ]; then
        note "secret not found in project: $key"
        entry_fail "$tool" missing-secret
        continue
    fi

    if [ -e "$target" ] || [ -L "$target" ]; then
        if [ ! -f "$target" ]; then
            note "target exists and is not a file: $relpath"
            entry_fail "$tool" not-a-file
            continue
        fi
        if [ "$force" -ne 1 ]; then
            note "deploy-once: exists, skipping (use --force)"
            prefix="$(sha_prefix "$target")"
            if ! [[ "$prefix" =~ ^[0-9a-f]{12}$ ]]; then
                entry_fail "$tool" hash
                continue
            fi
            printf '%s skipped %s %s\n' "$tool" "$relpath" "$prefix"
            continue
        fi
    fi

    # Fetch by id. bws 2.1.0 has no stdin secret read and get does not take a key.
    errfile="$(mktemp)"
    if ! raw="$("$bws_bin" -t "$BWS_ACCESS_TOKEN" -c no secret get "$secret_id" -o json 2>"$errfile")"; then
        unset raw
        if [ -f "$errfile" ] && grep -Eqi 'access token|unauthorized|invalid_client|invalid access|401|forbidden' "$errfile"; then
            bws_fail "$tool"
        fi
        rm -f -- "$errfile"
        errfile=""
        note "bws request failed for $key"
        entry_fail "$tool" bws-error
        continue
    fi
    rm -f -- "$errfile"
    errfile=""
    if ! b64_value="$(printf '%s' "$raw" | jq -er '.value' 2>/dev/null)"; then
        unset raw b64_value
        note "bws secret get returned no value"
        entry_fail "$tool" bws-error
        continue
    fi
    unset raw

    dir="$(dirname -- "$target")"
    # Keep a leading dot (.claude) and nested parents (.local/share/opencode).
    if ! mkdir -p -- "$dir"; then
        unset b64_value
        note "cannot create parent directory: $relpath"
        entry_fail "$tool" mkdir
        continue
    fi
    tmp="$(mktemp "$dir/.${tool}.credential.XXXXXX")"
    if ! printf '%s' "$b64_value" | base64 -d >"$tmp"; then
        unset b64_value
        rm -f -- "$tmp"
        tmp=""
        note "secret value is not valid base64"
        entry_fail "$tool" bad-base64
        continue
    fi
    unset b64_value
    if ! jq empty "$tmp" >/dev/null 2>&1; then
        rm -f -- "$tmp"
        tmp=""
        note "decoded secret is not JSON"
        entry_fail "$tool" invalid-json
        continue
    fi
    if ! chmod "$mode" "$tmp"; then
        rm -f -- "$tmp"
        tmp=""
        note "cannot set mode on $relpath"
        entry_fail "$tool" chmod
        continue
    fi

    if [ -e "$target" ] || [ -L "$target" ]; then
        stamp="$(date -u +%Y%m%dT%H%M%SZ)"
        backup_rel="${relpath}.bak.${stamp}"
        backup="$HOME/$backup_rel"
        if [ -e "$backup" ]; then
            backup_rel="${backup_rel}.$$"
            backup="$HOME/$backup_rel"
        fi
        mkdir -p -- "$(dirname -- "$backup")"
        if ! cp -p -- "$target" "$backup"; then
            rm -f -- "$tmp"
            tmp=""
            note "cannot back up $relpath"
            entry_fail "$tool" backup
            continue
        fi
        note "backup: $backup_rel"
    fi

    if ! mv -f -- "$tmp" "$target"; then
        rm -f -- "$tmp"
        tmp=""
        note "cannot install $relpath"
        entry_fail "$tool" install
        continue
    fi
    tmp=""
    if ! jq empty "$target" >/dev/null 2>&1; then
        note "deployed file is not JSON"
        entry_fail "$tool" invalid-json
        continue
    fi
    prefix="$(sha_prefix "$target")"
    if ! [[ "$prefix" =~ ^[0-9a-f]{12}$ ]]; then
        entry_fail "$tool" hash
        continue
    fi
    printf '%s deployed %s %s\n' "$tool" "$relpath" "$prefix"
done

if [ "$any_fail" -ne 0 ]; then
    exit 1
fi
