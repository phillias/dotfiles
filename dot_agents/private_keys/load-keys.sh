# shellcheck shell=sh
# Shared key loader for ~/.agents/keys/default profile
# Sourced by .zshenv (all zsh shells) and .profile (login shells)
#
# bws-first loading (2026-10 retirement): the migrated profile keys
# (38 exported here, 12 consumed by explicit reference only, 6
# decommissioned) are read from
# the Bitwarden Secrets Manager project named like the default profile.
# Auth comes from the per-profile .bws-token file (always re-read so a
# stale ambient token in a long-running shell cannot shadow the current
# fleet-managed token); the bws binary is resolved from BWS_BIN, PATH,
# or the mise latest alias. All bws calls use -t (access-token flag) to
# bypass the state-file session cache, which can go stale and shadow a
# valid token. One `bws secret list` call fetches every secret in the
# project; the project id is cached at ~/.agents/keys/.bws-project-
# <profile>.id (not a secret).
#
# Fallback (loud by design): when bws cannot supply a key — daemon
# unreachable, token missing/broken, or the secret absent — the loader
# age-decrypts the retired local copy at
# ~/.agents/keys/retired/<profile>/<key>.age (via `chezmoi decrypt`, or
# `age -d` with the chezmoi identity) and exports that instead. EVERY
# fallback appends one greppable line naming the exact key to
# ~/.agents/keys/.bws-fallback.log AND writes the same line to stderr:
#   BWS-FALLBACK <utc> profile=<p> key=<name> var=<VAR> reason=<why>
# A retired file that exists but will not decrypt logs the louder
#   BWS-FALLBACK-FAILED <utc> profile=<p> key=<name> var=<VAR> reason=retired-decrypt-failed
# The fallback is a tripwire that shows where references still need
# re-pointing to bws; it is never silent cover. Secret values are never
# printed or logged — key names and events only. A node whose bws token
# is missing or broken still boots a working environment via fallback.
#
# Recovery with age alone (no bws): age -d -i ~/.config/chezmoi/key.txt
# ~/.agents/keys/retired/<profile>/<key>.age
#
# Non-migrated keys are untouched: .bws-token (bws auth, stays on disk)
# and .google-tasks-token (binary/non-UTF-8, stays chezmoi age-encrypted
# in the active profile dir). Keys with no exported var (11 of 54) are
# recovery-only via age -d; consumers re-point to bws directly.

# Load keys from the default profile only (~/.agents/keys/default symlink)
# Non-default profiles are selected by consumers via explicit path, never auto-loaded.
_default_profile="$(readlink "$HOME/.agents/keys/default" 2>/dev/null)" || _default_profile=""
if [ -z "$_default_profile" ] || [ ! -d "$HOME/.agents/keys/$_default_profile" ]; then
    # Silently skip if no default profile - non-interactive shells must not emit noise
    unset _default_profile
    return 0 2>/dev/null || exit 0
fi

_keys_home="$HOME/.agents/keys"
_keys_profile_dir="$_keys_home/$_default_profile"
_keys_retired_dir="$_keys_home/retired/$_default_profile"
_keys_fallback_log="$_keys_home/.bws-fallback.log"

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

# --- fallback decrypt ---------------------------------------------------------
_keys_decrypt() {
    # $1 = retired .age file; prints decrypted value. chezmoi decrypt first
    # (uses the configured chezmoi age identity), then raw age as backstop.
    if command -v chezmoi >/dev/null 2>&1; then
        chezmoi decrypt "$1" 2>/dev/null && return 0
    elif [ -x "$HOME/.local/share/mise/installs/chezmoi/latest/chezmoi" ]; then
        "$HOME/.local/share/mise/installs/chezmoi/latest/chezmoi" decrypt "$1" 2>/dev/null && return 0
    fi
    if [ -r "$HOME/.config/chezmoi/key.txt" ]; then
        if [ -x "$HOME/.local/share/mise/installs/age/latest/age/age" ]; then
            "$HOME/.local/share/mise/installs/age/latest/age/age" -d -i "$HOME/.config/chezmoi/key.txt" "$1" 2>/dev/null
        elif command -v age >/dev/null 2>&1; then
            age -d -i "$HOME/.config/chezmoi/key.txt" "$1" 2>/dev/null
        fi
    fi
}

_keys_log_fallback() {
    # $1 = key name, $2 = env var, $3 = reason. Loud and greppable; values
    # are never logged. Appends to the durable log and mirrors to stderr.
    _lf_line="BWS-FALLBACK $(date -u +%Y-%m-%dT%H:%M:%SZ) profile=$_default_profile key=$1 var=$2 reason=$3"
    printf '%s\n' "$_lf_line" >> "$_keys_fallback_log" 2>/dev/null || true
    printf '%s\n' "$_lf_line" >&2
    unset _lf_line
}

# _keys_emit <key-name> <ENV_VAR>: export from bws, else from the retired
# age file with a loud fallback log line, else skip (graceful degradation).
_keys_emit() {
    _ke_name="$1"
    _ke_var="$2"
    _ke_val=""
    if [ -n "$_keys_bws_json" ]; then
        _ke_val="$(printf '%s' "$_keys_bws_json" \
            | "$JQ_BIN" -r --arg k "$_ke_name" '.[] | select(.key==$k) | .value' 2>/dev/null \
            | head -n 1)"
        if [ -n "$_ke_val" ]; then
            export "$_ke_var=$_ke_val"
            unset _ke_name _ke_var _ke_val
            return 0
        fi
        _ke_reason="bws-secret-missing"
    else
        _ke_reason="$_keys_bws_reason"
    fi
    if [ -r "$_keys_retired_dir/$_ke_name.age" ]; then
        _ke_val="$(_keys_decrypt "$_keys_retired_dir/$_ke_name.age")"
        if [ -n "$_ke_val" ]; then
            export "$_ke_var=$_ke_val"
            _keys_log_fallback "$_ke_name" "$_ke_var" "$_ke_reason"
            unset _ke_name _ke_var _ke_val _ke_reason
            return 0
        fi
        # Retired file exists but will not decrypt (missing identity/age/
        # chezmoi or corrupt file) — louder than a fallback, never silent.
        _lf_line="BWS-FALLBACK-FAILED $(date -u +%Y-%m-%dT%H:%M:%SZ) profile=$_default_profile key=$_ke_name var=$_ke_var reason=retired-decrypt-failed"
        printf '%s\n' "$_lf_line" >> "$_keys_fallback_log" 2>/dev/null || true
        printf '%s\n' "$_lf_line" >&2
        unset _lf_line
    fi
    unset _ke_name _ke_var _ke_val _ke_reason
    return 0
}

# --- exported key map (default profile) --------------------------------------
# Format per line: <key-file-name>:<ENV_VAR> (38 exported keys; 12 migrated
# keys have no exported var and stay recovery-only via age -d).
# Decommissioned 2026-10-15: .google-client-id/.google-client-secret (vault
# entries dropped; Google Workspace disengaged from hermes/opencode-serve).
# Decommissioned 2026-10-17: .google-vision-key (GOOGLE_VISION_API_KEY had
# zero consumers; vault entry dropped).
# Decommissioned 2026-10-18: .zen-key (OPENCODE_ZEN_API_KEY; zen surface
# is served by .opencode-key; vault entry dropped) and .treg-token
# (TREG_TOKEN; duplicate of .treg-key; vault entry dropped).
# Renamed 2026-10-18: .composio-key -> .composio-platform-key (the
# platform/SDK key; the For You ck_ key lives in .composio-for-you-key,
# reference-only, no exported var).
# Decommissioned 2026-10-18: .greptile-key (GREPTILE_API_KEY had zero
# dotfiles consumers; the rotated vault entry moved to the masculinecache
# bws project, which the default-profile loader never reads).
_keys_map='
.cf-ai-gw:CF_AI_GATEWAY_TOKEN
.treg-key:TREG_KEY
.abliteration-key:ABLITERATION_API_KEY
.tsfm-key:TSFM_API_KEY
.phoenixgrove-coding-plan-key:PHOENIXGROVE_CODING_PLAN_API_KEY
.groq-key:GROQ_API_KEY
.cerebras-key:CEREBRAS_API_KEY
.mistral-key:MISTRAL_API_KEY
.sambanova-key:SAMBANOVA_API_KEY
.google-key:GOOGLE_API_KEY
.together-key:TOGETHER_API_KEY
.cloudflare-key:CLOUDFLARE_API_KEY
.cloudflare-deploy-token:CLOUDFLARE_API_TOKEN
.command-code-key:COMMAND_CODE_API_KEY
.hf-key:HF_API_KEY
.nvidia-key:NVIDIA_API_KEY
.baseten-key:BASETEN_API_KEY
.intern-key:INTERN_API_KEY
.openrouter-key:OPENROUTER_API_KEY
.zai-key:ZHIPU_API_KEY
.fireworks-key:FIREWORKS_API_KEY
.exa-key:EXA_API_KEY
.composio-platform-key:COMPOSIO_API_KEY
.deepinfra-key:DEEPINFRA_API_KEY
.friendli-key:FRIENDLI_API_KEY
.qwen-key:QWEN_API_KEY
.kenari-key:KENARI_API_KEY
.synthetic-key:SYNTHETIC_API_KEY
.seevio-key:SEEVIO_API_KEY
.atlascloud-key:ATLASCLOUD_API_KEY
.vercel-gateway-key:AI_GATEWAY_API_KEY
.vercel-token:VERCEL_TOKEN
.agnes-key:AGNES_API_KEY
.opencode-key:OPENCODE_API_KEY
.phoenixgrove-key:PHOENIXGROVE_API_KEY
.telegram-key:TELEGRAM_API_KEY
.github-models-key:GITHUB_MODELS_API_KEY
.anthropic-key:ANTHROPIC_API_KEY
'

# Iterate the "name:var" map in the CURRENT shell (heredoc stdin, not a
# pipeline subshell) so the exports land in the sourcing shell.
while IFS= read -r _keys_line; do
    case "$_keys_line" in
        .*:*)
            _keys_emit "${_keys_line%%:*}" "${_keys_line#*:}"
            ;;
    esac
done <<EOF
$_keys_map
EOF

unset _default_profile _keys_home _keys_profile_dir _keys_retired_dir \
    _keys_fallback_log _keys_bws_json _keys_bws_reason _keys_bws_cache \
    _keys_map _keys_line
unset -f _keys_bws_project_id _keys_bws_fetch _keys_decrypt \
    _keys_log_fallback _keys_emit 2>/dev/null || true
