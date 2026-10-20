# shellcheck shell=sh
# Shared key loader for ~/.agents/keys/default profile
# Sourced by .zshenv (all zsh shells) and .profile (login shells)
#
# Pattern-driven vault export (2026-10 leak remediation): one `bws secret
# list` call fetches every secret in the Bitwarden Secrets Manager project
# named like the default profile, and the loader exports EVERY secret whose
# key already looks like an environment variable name: ^[A-Z][A-Z0-9_]+$.
# Adding a vault secret with an env-shaped key auto-exports it on the next
# source; decommissioning a key is a vault-side action. There is no
# hardcoded map and no per-key knowledge in this file (58 env-var-named
# keys today).
#
# Excluded namespaces (never exported here):
#   BWS_* — selfhost compose stack secrets, consumed by docker-compose and
#     bws-axi at deploy time; never shell-exported.
#   BYS_* — typo-guard: BYS_MYLAR3_HTTP_PASSWORD is a known typo'd selfhost
#     secret (MYLAR3 with a Y) guarded here until the vault key is
#     corrected; its pirate-box consumer is untouched by this loader.
#
# Auth comes from the per-profile .bws-token file (always re-read so a
# stale ambient token in a long-running shell cannot shadow the current
# fleet-managed token); the bws binary is resolved from BWS_BIN, PATH, or
# the mise latest alias. All bws calls use -t (access-token flag) to bypass
# the state-file session cache, which can go stale and shadow a valid
# token. The project id is cached at ~/.agents/keys/.bws-project-<profile>.id
# (not a secret).
#
# Fail-soft, no local fallback: values from the retired .age files are
# BURNED (2026-10-15 leak) — this loader never reads, decrypts, or
# exports them. When bws is unreachable and no fresh cache exists, the
# loader prints ONE warning naming the reason and leaves the vault env
# vars unset; shells still boot. A fresh (<= 5 min) fetch cache at
# ~/.agents/keys/.bws-cache-<profile>.json is honored without contacting
# bws. A fetch that yields zero env-shaped keys is an anomaly and also
# warns once. In every failure mode, at most ONE warning line per source.
#
# Secret values are never printed or logged — key names and events only.
#
# Non-migrated keys are untouched: .bws-token (bws auth, stays on disk) and
# .google-tasks-token (binary/non-UTF-8, stays chezmoi age-encrypted in the
# active profile dir). Dot-prefixed and other non-env-shaped vault keys are
# not exported by this loader; consumers reference them via bws directly.

# Clear the retired name before any early return so inherited sessions cannot
# override Claude's native login (2026-10-19).
unset ANTHROPIC_API_KEY

# Load keys from the default profile only (~/.agents/keys/default symlink)
# Non-default profiles are selected by consumers via explicit path, never auto-loaded.
_default_profile="$(readlink "$HOME/.agents/keys/default" 2>/dev/null)" || _default_profile=""
if [ -z "$_default_profile" ] || [ ! -d "$HOME/.agents/keys/$_default_profile" ]; then
    # Silently skip if no default profile - non-interactive shells must not emit noise
    unset _default_profile
    # Dual-mode file: return when sourced, exit when executed.
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi

_keys_home="$HOME/.agents/keys"
_keys_profile_dir="$_keys_home/$_default_profile"

# Bitwarden Secrets Manager — machine-account token (never locks, unlike
# bw/bws login sessions). The token file stays live on disk post-retirement.
# BWS_TOKEN_FILE is the bws-axi wrapper contract; BWS_ACCESS_TOKEN is what
# the plain bws CLI reads (it ignores BWS_TOKEN_FILE, verified against bws
# 2.1.0). The file is always re-read so a stale ambient token in a
# long-running shell (e.g. an agent session) is replaced by the current
# fleet-managed token on every source.
if [ -r "$_keys_profile_dir/.bws-token" ]; then
    BWS_TOKEN_FILE="$_keys_profile_dir/.bws-token" && export BWS_TOKEN_FILE
    BWS_ACCESS_TOKEN="$(cat "$BWS_TOKEN_FILE")" && export BWS_ACCESS_TOKEN
fi

# bws binary — resolution order per the retirement design: BWS_BIN, PATH,
# then the mise latest alias (never pin versioned install dirs). BWS_BIN is
# exported so bws-axi and scripts reach bws even when the PATH shim is unset.
if [ -z "${BWS_BIN:-}" ] || [ ! -x "$BWS_BIN" ]; then
    if command -v bws >/dev/null 2>&1; then
        BWS_BIN="$(command -v bws)" && export BWS_BIN
    elif [ -x "$HOME/.local/share/mise/installs/bitwarden-secrets-manager/latest/bws" ]; then
        BWS_BIN="$HOME/.local/share/mise/installs/bitwarden-secrets-manager/latest/bws" && export BWS_BIN
    fi
fi

# jq resolution — zshenv may run before ~/.local/bin is on PATH.
JQ_BIN=""
if command -v jq >/dev/null 2>&1; then
    JQ_BIN="$(command -v jq)"
else
    for _keys_jq_candidate in "$HOME/.local/bin/jq" /usr/bin/jq /bin/jq; do
        if [ -x "$_keys_jq_candidate" ]; then
            JQ_BIN="$_keys_jq_candidate"
            break
        fi
    done
fi

# --- bws project fetch -------------------------------------------------------
# One secret-list call per shell, cached for 5 minutes at
# ~/.agents/keys/.bws-cache-<profile>.json to avoid a network round-trip
# on every non-interactive shell (ET terminals, scripts, daemons).
# _keys_bws_json holds the raw JSON array; _keys_bws_reason records why bws
# is unavailable when it is (empty when ok).
_keys_bws_json=""
_keys_bws_reason=""
_keys_bws_cache="$_keys_home/.bws-cache-$_default_profile.json"

_keys_bws_project_id() {
    # Resolve the bws project id for the default profile, cached at
    # ~/.agents/keys/.bws-project-<profile>.id (id is not a secret).
    # Pinned ids ship here so vault project renames cannot break shell logins;
    # dynamic name lookup stays the fallback for unpinned profiles.
    _pid_cache="$_keys_home/.bws-project-$_default_profile.id"
    _pid=""
    if [ -r "$_pid_cache" ]; then
        _pid="$(cat "$_pid_cache" 2>/dev/null)"
    fi
    if [ -z "$_pid" ]; then
        case "$_default_profile" in
            phillias) _pid="fe9eea09-9eaf-45e6-a72f-b45e0150b29d" ;;
        esac
    fi
    if [ -z "$_pid" ]; then
        # -t bypasses the bws state-file session cache (state can go stale
        # and shadow a valid token; verified against bws 2.1.0).
        # shellcheck disable=SC2016  # jq program: $p is a jq variable, not shell
        _pid="$(timeout 5 "$BWS_BIN" -t "$BWS_ACCESS_TOKEN" project list -o json 2>/dev/null \
            | "$JQ_BIN" -r --arg p "$_default_profile" '.[] | select(.name==$p) | .id' 2>/dev/null \
            | head -n 1)"
    fi
    if [ -n "$_pid" ]; then
        ( umask 077 && printf '%s\n' "$_pid" > "$_pid_cache" ) 2>/dev/null || true
    fi
    printf '%s' "$_pid"
    unset _pid_cache _pid
}

_keys_bws_fetch() {
    # $1 = project id; prints the secret-list JSON array on success.
    # -t bypasses the state-file session cache (see _keys_bws_project_id).
    timeout 5 "$BWS_BIN" -t "$BWS_ACCESS_TOKEN" secret list "$1" -o json 2>/dev/null
}

if [ -z "${BWS_ACCESS_TOKEN:-}" ]; then
    _keys_bws_reason="bws-token-missing"
elif [ -z "${BWS_BIN:-}" ] || [ ! -x "$BWS_BIN" ]; then
    _keys_bws_reason="bws-binary-missing"
elif [ -z "$JQ_BIN" ]; then
    _keys_bws_reason="jq-missing"
else
    # Check cache freshness (5-minute TTL) before hitting the network.
    # Cache avoids a 0.8s bws round-trip on every non-interactive shell
    # (ET terminals, scripts, daemons) that sources .zshenv.
    if [ -r "$_keys_bws_cache" ]; then
        _keys_cache_age=$(( $(date +%s 2>/dev/null || echo 0) - $(stat -c %Y "$_keys_bws_cache" 2>/dev/null || stat -f %m "$_keys_bws_cache" 2>/dev/null || echo 0) ))
        if [ "${_keys_cache_age:-999999}" -le 300 ]; then
            _keys_bws_json="$(cat "$_keys_bws_cache" 2>/dev/null)"
            case "$_keys_bws_json" in
                \[*) : ;;
                *) _keys_bws_json="" ;;
            esac
        fi
        unset _keys_cache_age
    fi
    # Live fetch only on cache miss
    if [ -z "$_keys_bws_json" ]; then
        _keys_project_id="$(_keys_bws_project_id)"
        if [ -z "$_keys_project_id" ]; then
            _keys_bws_reason="bws-project-unresolved"
        else
            _keys_bws_json="$(_keys_bws_fetch "$_keys_project_id")"
            case "$_keys_bws_json" in
                \[*) : ;;
                *)
                    # Cached project id may be stale: refresh once and retry.
                    rm -f "$_keys_home/.bws-project-$_default_profile.id" 2>/dev/null || true
                    _keys_project_id="$(_keys_bws_project_id)"
                    if [ -n "$_keys_project_id" ]; then
                        _keys_bws_json="$(_keys_bws_fetch "$_keys_project_id")"
                    fi
                    case "$_keys_bws_json" in
                        \[*) : ;;
                        *) _keys_bws_json=""; _keys_bws_reason="bws-fetch-failed" ;;
                    esac
                    ;;
            esac
        fi
        unset _keys_project_id
        # Write cache on successful live fetch
        if [ -n "$_keys_bws_json" ]; then
            ( umask 077 && printf '%s' "$_keys_bws_json" > "$_keys_bws_cache" ) 2>/dev/null || true
        fi
    fi
fi

# --- pattern export loop ------------------------------------------------------
# One jq pass turns the fetched JSON array into `export NAME='value'` lines
# for every env-shaped key, excluding the BWS_/BYS_ namespaces (see header).
#   - key names are filtered to the strict charset ^[A-Z][A-Z0-9_]+$, so no
#     shell metacharacter can appear in an exported name;
#   - values are @sh-quoted by jq, so the generated text is fully quoted;
#   - eval therefore only ever sees a controlled, well-quoted export list.
# eval runs in the sourcing shell (no pipeline subshell) so exports land
# here; multi-line values are preserved and the last entry wins on
# duplicate keys.
if [ -n "$_keys_bws_json" ]; then
    _keys_export_lines="$(printf '%s' "$_keys_bws_json" \
        | "$JQ_BIN" -r '.[]
            | select((.key // "") | test("^[A-Z][A-Z0-9_]+$"))
            | select(((.key | startswith("BWS_")) or (.key | startswith("BYS_"))) | not)
            | "export \(.key)=\((.value // "") | @sh)"' 2>/dev/null)"
    if [ -n "$_keys_export_lines" ]; then
        # Safe by construction: key names are charset-validated
        # (^[A-Z][A-Z0-9_]+$) and values are jq-@sh-quoted above, so eval
        # only sees a controlled, fully-quoted export list.
        eval "$_keys_export_lines"
    else
        # Healthy fetch that exports nothing: fail loud once, never silent.
        printf '%s\n' "load-keys: bws fetch carried no env-shaped keys (reason=no-env-shaped-keys); nothing exported" >&2
    fi
else
    # Fail-soft: bws unavailable and no fresh cache. ONE warning; vault env
    # vars stay unset. The retired .age fallback is GONE — those values are
    # burned and must never resurface through this loader.
    printf '%s\n' "load-keys: bws unavailable (reason=${_keys_bws_reason:-bws-unavailable}); vault env keys not exported; no local fallback exists" >&2
fi

# Clear the retired name after every export attempt so stale cache entries
# cannot override Claude's native login.
unset ANTHROPIC_API_KEY

unset _default_profile _keys_home _keys_profile_dir \
    _keys_bws_json _keys_bws_reason _keys_bws_cache _keys_export_lines \
    _keys_jq_candidate
unset -f _keys_bws_project_id _keys_bws_fetch 2>/dev/null || true
