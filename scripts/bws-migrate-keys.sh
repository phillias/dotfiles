#!/usr/bin/env bash
# bws-migrate-keys.sh — migrate ~/.agents/keys profile key files into
# Bitwarden Secrets Manager (bws) projects.
#
# Migration scheme (see dot_agents/private_keys/README.md): one bws project
# per key profile, project named exactly like the profile (phillias,
# masculinecache), each project accessed by a machine account whose token
# never locks. Free-tier math: 3 projects / 3 machine accounts total; the
# selfhost token for project selfhost-Dev consumes one account, so the
# remaining two are per-persona, not per-node.
#
# Phase 2 of the migration: the captain mints the machine accounts + access
# tokens in the Bitwarden web vault (bws CLI cannot create them), places each
# token at ~/.agents/keys/<profile>/.bws-token (age-encrypted repo copy at
# dot_agents/private_keys/private_<profile>/encrypted_private_dot_bws-token.age),
# then this script creates one bws secret per key file in the right project.
#
# Hygiene contract:
#   - Secret VALUES are read from the live files at execution time only.
#   - Values are never printed, logged, or committed (bws -o none suppresses
#     the create response; dry-run prints key names + byte sizes only).
#   - The access token is taken from BWS_ACCESS_TOKEN or BWS_TOKEN_FILE
#     (both exported by the keys loader); it is never a CLI argument.
#
# Usage:
#   bws-migrate-keys.sh [--dry-run] [--profile <name>]... [--keys-dir <dir>]
#
#   --dry-run         Plan only: print what would be created/skipped, create nothing.
#   --profile <name>  Migrate only this profile (repeatable; default: phillias masculinecache).
#   --keys-dir <dir>  Live keys root (default: ~/.agents/keys).
#
# Examples:
#   bws-migrate-keys.sh --dry-run
#   bws-migrate-keys.sh
#   bws-migrate-keys.sh --profile masculinecache
set -euo pipefail

usage() {
    cat <<'EOF'
usage: bws-migrate-keys.sh [--dry-run] [--profile <name>]... [--keys-dir <dir>]

Migrate ~/.agents/keys profile key files into Bitwarden Secrets Manager:
one bws project per key profile, project named exactly like the profile
(defaults: phillias masculinecache). One bws secret per key file; secrets
whose key name already exists in the project are skipped (idempotent).
Secret values are read at execution time and never printed or logged.

  --dry-run         plan only; create nothing
  --profile <name>  migrate only this profile (repeatable)
  --keys-dir <dir>  live keys root (default: ~/.agents/keys, or BWS_KEYS_DIR)

Auth: BWS_ACCESS_TOKEN or BWS_TOKEN_FILE (both exported by the keys loader).
bws binary: BWS_BIN, else PATH, else the mise latest-alias install.
EOF
}

die() {
    echo "bws-migrate-keys: $*" >&2
    exit 1
}

dry_run=0
profiles=()
keys_dir="${BWS_KEYS_DIR:-$HOME/.agents/keys}"

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) dry_run=1 ;;
        --profile)
            [ $# -ge 2 ] || die "--profile needs a value"
            profiles+=("$2")
            shift
            ;;
        --keys-dir)
            [ $# -ge 2 ] || die "--keys-dir needs a value"
            keys_dir="$2"
            shift
            ;;
        -h | --help) usage; exit 0 ;;
        *) usage >&2; die "unknown argument: $1" ;;
    esac
    shift
done
[ ${#profiles[@]} -gt 0 ] || profiles=(phillias masculinecache)

[ -d "$keys_dir" ] || die "keys dir not found: $keys_dir (set --keys-dir or BWS_KEYS_DIR)"
command -v jq >/dev/null 2>&1 || die "jq is required (house standard, used by scripts/validate.sh)"

# ---- auth: token from env or token file, never a CLI argument -----------
# Plain bws reads BWS_ACCESS_TOKEN only (it ignores BWS_TOKEN_FILE, verified
# against bws 2.1.0); the loader exports both.
if [ -z "${BWS_ACCESS_TOKEN:-}" ] && [ -n "${BWS_TOKEN_FILE:-}" ] && [ -r "$BWS_TOKEN_FILE" ]; then
    BWS_ACCESS_TOKEN="$(cat "$BWS_TOKEN_FILE")"
fi
[ -n "${BWS_ACCESS_TOKEN:-}" ] || die "no bws access token (source the keys loader, or set BWS_ACCESS_TOKEN / BWS_TOKEN_FILE)"
export BWS_ACCESS_TOKEN

# ---- bws binary: BWS_BIN -> PATH -> mise latest alias ---------------------
bws_bin="${BWS_BIN:-}"
if [ ! -x "$bws_bin" ]; then
    bws_bin="$(command -v bws || true)"
fi
if [ -z "$bws_bin" ] || [ ! -x "$bws_bin" ]; then
    bws_bin="$HOME/.local/share/mise/installs/bitwarden-secrets-manager/latest/bws"
fi
[ -x "$bws_bin" ] || die "bws binary not found (set BWS_BIN or install via the dot_config/mise/config.toml pin)"
"$bws_bin" --version >/dev/null 2>&1 || die "bws binary not runnable: $bws_bin"

# ---- project resolution: one project per profile, same name --------------
projects_json="$("$bws_bin" project list -o json)" || die "cannot list bws projects (token valid? machine account has project access?)"

project_id() {
    jq -r --arg name "$1" '.[] | select(.name == $name) | .id' <<<"$projects_json" | head -n 1
}

# ---- migrate one profile --------------------------------------------------
total_created=0
total_skipped=0
total_failed=0

for profile in "${profiles[@]}"; do
    profile_dir="$keys_dir/$profile"
    if [ ! -d "$profile_dir" ]; then
        echo "== $profile: no key dir at $profile_dir — skipped"
        continue
    fi

    pid="$(project_id "$profile")"
    [ -n "$pid" ] || die "no bws project named '$profile' (create it in the web vault, or pass --profile with the project's name)"

    # Idempotency set: key names already present in the project.
    secrets_json="$("$bws_bin" secret list "$pid" -o json)" || die "cannot list secrets in project '$profile' (machine account access?)"
    mapfile -t existing < <(jq -r '.[].key' <<<"$secrets_json")
    has_key() {
        local k
        for k in "${existing[@]}"; do [ "$k" = "$1" ] && return 0; done
        return 1
    }

    created=0 skipped=0 failed=0
    echo "== $profile: project id $pid, ${#existing[@]} existing secret(s)"

    while IFS= read -r -d '' keyfile; do
        key="$(basename "$keyfile")"
        if has_key "$key"; then
            echo "  skip  $profile/$key (already in project)"
            skipped=$((skipped + 1))
            continue
        fi
        size="$(wc -c <"$keyfile")"
        if [ "$dry_run" -eq 1 ]; then
            echo "  dry   $profile/$key -> project $profile (${size}B)"
            created=$((created + 1))
            continue
        fi
        # Value passes through argv to `bws secret create` (bws 2.1.0 offers no
        # stdin option); it is never echoed, and -o none suppresses the create
        # response so the value cannot reach stdout or logs.
        if value="$(cat "$keyfile")" && "$bws_bin" secret create "$key" "$value" "$pid" -o none >/dev/null; then
            echo "  created  $profile/$key"
            created=$((created + 1))
        else
            echo "  FAIL  $profile/$key (see bws error above)" >&2
            failed=$((failed + 1))
        fi
    done < <(find "$profile_dir" -maxdepth 1 -type f -name '.*' -print0 | sort -z)

    echo "== $profile: done — $created created, $skipped skipped, $failed failed"
    total_created=$((total_created + created))
    total_skipped=$((total_skipped + skipped))
    total_failed=$((total_failed + failed))
done

verb="created"
[ "$dry_run" -eq 1 ] && verb="would create"
echo "bws-migrate-keys: $verb $total_created, skipped $total_skipped, failed $total_failed"
[ "$total_failed" -eq 0 ] || exit 1
