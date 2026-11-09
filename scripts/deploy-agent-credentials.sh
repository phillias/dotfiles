#!/usr/bin/env bash
# deploy-agent-credentials.sh — seed portable agent CLI credential files
# from Bitwarden Secrets Manager project phillias.
#
# Manifest (beside this script): agent-credentials.conf
#   tool<TAB>secret_key<TAB>$HOME-relative path<TAB>mode
#
# Deploy-once: an existing regular file is left in place.
# --force is required to overwrite one, because a live CLI holds newer
# refresh tokens than any vault snapshot. --force copies the current file
# to <target>.bak.<UTC timestamp> in the same directory, then replaces it.
#
# A missing or unusable secret fails that row only. Later rows still run.
# The process exits nonzero if any row failed. BWS authentication failure
# stops the run before any write.
#
# The human catalog, including the unverified grok row, is scripts/README.md.
set -euo pipefail
unset CDPATH

usage() {
    cat <<'EOF'
usage: deploy-agent-credentials.sh [--force]

Seed portable agent credential files from BWS project phillias using
scripts/agent-credentials.conf (tool, secret key, $HOME-relative path, mode).

  --force   overwrite an existing credential after a timestamped backup
            beside the target. Required for a live file: the local CLI
            holds newer refresh tokens than any vault snapshot.

Each row prints one stdout line: tool status path sha256-prefix.
status is deployed, skipped, missing, or error.
sha256-prefix is 12 hex characters, or - when no file was hashed.
Row failures also print "error code=<code> tool=<tool> ..." on stderr
and do not stop later rows. A missing secret is code=missing-secret.
The process exits nonzero if any row failed.
BWS authentication failure (code=bws-auth) stops the run before any write.

Parents are created with mkdir -p, including dot directories such as
.claude/ and nested paths such as .local/share/opencode/.

Env:
  BWS_ACCESS_TOKEN   machine-account token (or BWS_TOKEN_FILE)
  BWS_TOKEN_FILE     file to read the token from when the env var is unset
  BWS_PROJECT_ID     override the pinned phillias project id
  BWS_BIN            bws binary (else PATH, else the mise latest alias)

Catalog, including grok (not seeded): scripts/README.md.
EOF
}

# Structured failure that aborts the whole run (auth, usage, missing tools).
die() {
    printf 'error code=%s tool=- detail=%s\n' "$1" "$2" >&2
    exit 1
}

force=0
while [ $# -gt 0 ]; do
    case "$1" in
        --force) force=1 ;;
        -h | --help) usage; exit 0 ;;
        *) usage >&2; die usage "unknown argument: $1" ;;
    esac
    shift
done

command -v jq >/dev/null 2>&1 || die missing-jq "jq is required"
command -v base64 >/dev/null 2>&1 || die missing-base64 "base64 is required"
command -v sha256sum >/dev/null 2>&1 || die missing-sha256sum "sha256sum is required"

if [ -z "${HOME:-}" ] || [ ! -d "$HOME" ]; then
    die bad-home "HOME must be set to an existing directory"
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
manifest="${script_dir}/agent-credentials.conf"
[ -f "$manifest" ] || die bad-manifest "manifest not found beside this script"

# Same pin as scripts/setup.sh and the keys loader. Ids are stable; names are not.
project_id="${BWS_PROJECT_ID:-fe9eea09-9eaf-45e6-a72f-b45e0150b29d}"
if ! printf '%s' "$project_id" | grep -Eq '^[0-9a-fA-F-]{36}$'; then
    die bad-project "BWS_PROJECT_ID is not a project id"
fi

umask 077

if [ -z "${BWS_ACCESS_TOKEN:-}" ] && [ -n "${BWS_TOKEN_FILE:-}" ]; then
    [ -r "$BWS_TOKEN_FILE" ] || die bws-auth "BWS_TOKEN_FILE is not readable"
    BWS_ACCESS_TOKEN=$(<"$BWS_TOKEN_FILE") || die bws-auth "cannot read BWS_TOKEN_FILE"
    BWS_ACCESS_TOKEN=${BWS_ACCESS_TOKEN%$'\n'}
fi
[ -n "${BWS_ACCESS_TOKEN:-}" ] || die bws-auth "no bws access token (set BWS_ACCESS_TOKEN or BWS_TOKEN_FILE)"
export BWS_ACCESS_TOKEN

bws_bin="${BWS_BIN:-}"
if [ -z "$bws_bin" ] || [ ! -x "$bws_bin" ]; then
    bws_bin=$(command -v bws || true)
fi
if [ -z "$bws_bin" ] || [ ! -x "$bws_bin" ]; then
    bws_bin="${HOME}/.local/share/mise/installs/bitwarden-secrets-manager/latest/bws"
fi
[ -x "$bws_bin" ] || die missing-bws "bws binary not found (set BWS_BIN)"

# -t bypasses the stale ~/.config/bws/state cache (fleet loader contract).
# The token is an argument because bws has no other way to ignore that cache.
bws_err=$(mktemp) || die temp "cannot create a temp file"
active_tmp=
# shellcheck disable=SC2329  # invoked indirectly via the EXIT trap below
cleanup() {
    rm -f -- "$bws_err"
    if [ -n "${active_tmp:-}" ]; then
        rm -f -- "$active_tmp"
    fi
}
trap cleanup EXIT

# One list for the project. Values stay in this variable and are never printed.
# shellcheck disable=SC2312
if ! secrets_json=$("$bws_bin" -t "$BWS_ACCESS_TOKEN" -c no -o json secret list "$project_id" 2>"$bws_err"); then
    detail=$(head -n 1 -- "$bws_err" | tr -d '\r' | tr '\n' ' ' | cut -c 1-180 || true)
    detail=${detail:-bws secret list failed}
    # Drop anything that looks like a machine-account token.
    detail=$(printf '%s' "$detail" | sed -E 's/0\.[0-9A-Fa-f-]{8,}\.[^[:space:]]+/[redacted]/g')
    die bws-auth "$detail"
fi
if ! jq -e 'type == "array"' >/dev/null <<<"$secrets_json"; then
    die bws-auth "bws secret list did not return a JSON array"
fi

sha256_prefix() {
    local sum
    sum=$(sha256sum -- "$1") || return 1
    printf '%s\n' "${sum:0:12}"
}

# Print a row failure. Does not exit. Caller returns nonzero.
row_error() {
    local code="$1"
    local tool="$2"
    local relpath="$3"
    local detail="$4"
    printf 'error code=%s tool=%s key=%s path=%s detail=%s\n' \
        "$code" "$tool" "${5:-}" "$relpath" "$detail" >&2
    printf '%s error %s -\n' "$tool" "$relpath"
}

deploy_one() {
    local tool="$1"
    local key="$2"
    local relpath="$3"
    local mode="$4"
    local dest parent tmp value count prefix ts backup home_real parent_real

    if ! printf '%s' "$tool" | grep -Eq '^[a-z][a-z0-9_-]*$'; then
        row_error bad-tool "$tool" "$relpath" "tool name is not a safe token" "$key"
        return 1
    fi
    if ! printf '%s' "$key" | grep -Eq '^[A-Z][A-Z0-9_]*$'; then
        row_error bad-key "$tool" "$relpath" "secret key is not an uppercase token" "$key"
        return 1
    fi
    if ! printf '%s' "$mode" | grep -Eq '^0[0-7]{3}$'; then
        row_error bad-mode "$tool" "$relpath" "mode must be a four-digit octal string" "$key"
        return 1
    fi
    case "$relpath" in
        /* | .. | ../* | */.. | */../* | *//*)
            row_error bad-path "$tool" "$relpath" "path must be a relative path under HOME" "$key"
            return 1
            ;;
    esac

    dest="${HOME}/${relpath}"
    parent=$(dirname -- "$dest")

    if [ -L "$dest" ]; then
        row_error symlink "$tool" "$relpath" "target is a symlink; refusing to follow it" "$key"
        return 1
    fi
    if [ -e "$dest" ] && [ ! -f "$dest" ]; then
        row_error not-a-file "$tool" "$relpath" "target exists and is not a regular file" "$key"
        return 1
    fi

    # Deploy-once. Do not read the vault when the live file is already there.
    if [ -f "$dest" ] && [ "$force" -eq 0 ]; then
        prefix=$(sha256_prefix "$dest") || {
            row_error hash "$tool" "$relpath" "cannot hash the existing file" "$key"
            return 1
        }
        printf '%s skipped %s %s\n' "$tool" "$relpath" "$prefix"
        return 0
    fi

    count=$(jq -r --arg k "$key" '[.[] | select(.key == $k)] | length' <<<"$secrets_json") || {
        row_error bws-parse "$tool" "$relpath" "cannot read the secret list" "$key"
        return 1
    }
    if [ "$count" -eq 0 ]; then
        printf 'error code=missing-secret tool=%s key=%s path=%s detail=%s\n' \
            "$tool" "$key" "$relpath" "secret is not in the BWS project" >&2
        printf '%s missing %s -\n' "$tool" "$relpath"
        return 1
    fi
    if [ "$count" -gt 1 ]; then
        row_error ambiguous-secret "$tool" "$relpath" "more than one secret uses this key" "$key"
        return 1
    fi
    value=$(jq -r --arg k "$key" '[.[] | select(.key == $k)][0].value // empty' <<<"$secrets_json") || {
        row_error bws-parse "$tool" "$relpath" "cannot read the secret value" "$key"
        return 1
    }
    if [ -z "$value" ]; then
        printf 'error code=missing-secret tool=%s key=%s path=%s detail=%s\n' \
            "$tool" "$key" "$relpath" "secret value is empty" >&2
        printf '%s missing %s -\n' "$tool" "$relpath"
        return 1
    fi

    # Leading-dot parents (.claude) and nested parents (.local/share/opencode)
    # are created as given. Do not strip a leading dot from any segment.
    if ! mkdir -p -- "$parent"; then
        row_error mkdir "$tool" "$relpath" "cannot create the parent directory" "$key"
        return 1
    fi
    home_real=$(readlink -f -- "$HOME") || {
        row_error path-escape "$tool" "$relpath" "cannot resolve HOME" "$key"
        return 1
    }
    parent_real=$(readlink -f -- "$parent") || {
        row_error path-escape "$tool" "$relpath" "cannot resolve the parent directory" "$key"
        return 1
    }
    case "$parent_real" in
        "$home_real" | "$home_real"/*) ;;
        *)
            row_error path-escape "$tool" "$relpath" "parent resolved outside HOME" "$key"
            return 1
            ;;
    esac

    tmp=$(mktemp "${parent}/.agent-credential.XXXXXX") || {
        row_error temp "$tool" "$relpath" "cannot create a temp file beside the target" "$key"
        return 1
    }
    active_tmp=$tmp
    if ! printf '%s' "$value" | tr -d '[:space:]' | base64 -d >"$tmp"; then
        rm -f -- "$tmp"
        active_tmp=
        row_error bad-base64 "$tool" "$relpath" "secret value is not valid base64" "$key"
        return 1
    fi
    # Drop the secret material from the shell before any further logging.
    value=
    if ! jq empty "$tmp" >/dev/null 2>&1; then
        rm -f -- "$tmp"
        active_tmp=
        row_error bad-json "$tool" "$relpath" "decoded secret is not JSON" "$key"
        return 1
    fi
    if ! chmod "$mode" -- "$tmp"; then
        rm -f -- "$tmp"
        active_tmp=
        row_error chmod "$tool" "$relpath" "cannot set the manifest mode" "$key"
        return 1
    fi

    backup=
    if [ -f "$dest" ]; then
        ts=$(date -u +%Y%m%dT%H%M%SZ)
        backup="${dest}.bak.${ts}"
        if [ -e "$backup" ]; then
            rm -f -- "$tmp"
            active_tmp=
            row_error backup-exists "$tool" "$relpath" "timestamped backup already exists" "$key"
            return 1
        fi
        if ! cp -a -- "$dest" "$backup"; then
            rm -f -- "$tmp"
            active_tmp=
            row_error backup "$tool" "$relpath" "cannot back up the live credential" "$key"
            return 1
        fi
    fi
    if ! mv -f -- "$tmp" "$dest"; then
        rm -f -- "$tmp"
        active_tmp=
        if [ -n "$backup" ] && [ -f "$dest" ]; then
            rm -f -- "$backup"
        fi
        row_error install "$tool" "$relpath" "cannot move the credential into place" "$key"
        return 1
    fi
    active_tmp=
    prefix=$(sha256_prefix "$dest") || {
        row_error hash "$tool" "$relpath" "installed but cannot hash the file" "$key"
        return 1
    }
    printf '%s deployed %s %s\n' "$tool" "$relpath" "$prefix"
    return 0
}

line_no=0
data_rows=0
any_fail=0
while IFS= read -r line || [ -n "$line" ]; do
    line_no=$((line_no + 1))
    line=${line%$'\r'}
    trimmed=${line#"${line%%[![:space:]]*}"}
    case "$trimmed" in
        '' | \#*) continue ;;
    esac
    data_rows=$((data_rows + 1))
    IFS=$'\t' read -r tool key relpath mode extra <<<"$trimmed"
    if [ -n "${extra:-}" ] || [ -z "${tool:-}" ] || [ -z "${key:-}" ] || [ -z "${relpath:-}" ] || [ -z "${mode:-}" ]; then
        printf 'error code=bad-manifest tool=- key=- path=- detail=line %s is not four tab-separated fields\n' "$line_no" >&2
        printf -- '- error manifest-line-%s -\n' "$line_no"
        any_fail=1
        continue
    fi
    if ! deploy_one "$tool" "$key" "$relpath" "$mode"; then
        any_fail=1
    fi
done <"$manifest"

if [ "$data_rows" -eq 0 ]; then
    die empty-manifest "manifest has no credential rows"
fi

if [ "$any_fail" -ne 0 ]; then
    exit 1
fi
exit 0
