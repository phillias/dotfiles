#!/bin/bash
set -euo pipefail

# mesh-ddns — Dynamic DNS for fleet mesh via Cloudflare Workers KV.
#
# Writes this node's WARP mesh IP to CF KV (FLEET_MESH_IPS namespace),
# reads all peers from KV, regenerates the mesh-hosts file, and reloads dnsmasq.
# KV stores mesh IPs (100.96.x.x) — the address WARP devices use to reach
# this node directly over the mesh. The LAN IP is used only for the
# dnsmasq listen-address (reachable via Cloudflare Tunnel private routes).
#
# Also deploys mesh.conf from the chezmoi-managed staging area
# (~/.config/dnsmasq/dnsmasq.d/mesh.conf) to /etc/dnsmasq.d/ if not present.
#
# Required env vars (sourced from load-keys.sh / BWS):
#   CLOUDFLARE_API_TOKEN  — API token with KV write/read on FLEET_MESH_IPS
#   CLOUDFLARE_ACCOUNT_ID — Cloudflare account ID
#
# Required commands:
#   ip, curl, jq

KV_NAMESPACE_ID="dee7605dc7c744eda094610fa6d0fb33"
HOSTNAME="$(hostname)"
CHEZMOI_SOURCE_DIR="${CHEZMOI_SOURCE_DIR:-${HOME}/.local/share/chezmoi}"
FLEET_TOML="${CHEZMOI_SOURCE_DIR}/.chezmoidata/fleet.toml"
DNSMASQ_ETC_DIR="/etc/dnsmasq.d"
DNSMASQ_DATA_DIR="/var/lib/dnsmasq"
MESH_HOSTS_FILE="${DNSMASQ_DATA_DIR}/mesh-hosts"
MESH_CONF_FILE="${DNSMASQ_ETC_DIR}/mesh.conf"
MESH_CONFIG_STATE_FILE="${DNSMASQ_DATA_DIR}/mesh-config-deployed"
STAGED_MESH_CONF="${HOME}/.config/dnsmasq/dnsmasq.d/mesh.conf"
STAGED_MESH_HOSTS="${HOME}/.config/dnsmasq/d/mesh-hosts"

# Source BWS vault loader for CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID
# shellcheck disable=SC1091
. "${HOME}/.agents/keys/load-keys.sh"

: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN must be set}"
: "${CLOUDFLARE_ACCOUNT_ID:?CLOUDFLARE_ACCOUNT_ID must be set}"

KV_BASE="https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/storage/kv/namespaces/${KV_NAMESPACE_ID}"

log() { printf 'mesh-ddns: %s\n' "$*"; }
die() { log "ERROR: $1" >&2; exit "${2:-1}"; }

resolve_mesh_ip() {
    local mesh_ip
    mesh_ip=$(ip -4 -o addr show dev CloudflareWARP 2>/dev/null | awk '{split($4, address, "/"); print address[1]; exit}')
    if [[ -z "$mesh_ip" ]]; then
        die "could not resolve WARP Mesh IP — is WARP connected?"
    fi
    valid_ip "$mesh_ip" || die "invalid WARP Mesh IP: ${mesh_ip}"
    printf '%s' "$mesh_ip"
}

resolve_lan_ip() {
    local lan_ip node_key
    node_key=$(fleet_key)
    if [[ -n "$node_key" && -f "$FLEET_TOML" ]]; then
        lan_ip=$(awk -v key="$node_key" '
            /^[[:space:]]*\[fleet\.nodes\.[^]]+\][[:space:]]*$/ {
                section=$0
                sub(/^[[:space:]]*/, "", section)
                sub(/^\[fleet\.nodes\./, "", section)
                sub(/\]$/, "", section)
                sub(/[[:space:]]*$/, "", section)
                current=section
            }
            /^[[:space:]]*lan_ip[[:space:]]*=/ {
                if (current == key) {
                    value=$0
                    sub(/^[^=]*=[[:space:]]*"/, "", value)
                    sub(/"[[:space:]]*$/, "", value)
                    print value
                    exit
                }
            }
        ' "$FLEET_TOML")
    fi
    if [[ -n "$lan_ip" && "$lan_ip" != "UNKNOWN" ]]; then
        valid_ip "$lan_ip" || die "invalid LAN IP from fleet.toml: ${lan_ip}"
        printf '%s' "$lan_ip"
        return
    fi
    lan_ip=$(ip -4 route get 1.1.1.1 oif CloudflareWARP 2>/dev/null | awk '/src/ {for (i=1; i<=NF; i++) if ($i == "src") {print $(i+1); exit}}')
    if [[ -z "$lan_ip" ]]; then
        lan_ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i=1; i<=NF; i++) if ($i == "src") {print $(i+1); exit}}')
    fi
    if [[ -z "$lan_ip" ]]; then
        die "could not resolve LAN IP — is a network route available?"
    fi
    valid_ip "$lan_ip" || die "invalid LAN IP: ${lan_ip}"
    printf '%s' "$lan_ip"
}

valid_ip() {
    awk -F. 'NF == 4 && $1 >= 0 && $1 <= 255 && $2 >= 0 && $2 <= 255 && $3 >= 0 && $3 <= 255 && $4 >= 0 && $4 <= 255 && $1 !~ /[^0-9]/ && $2 !~ /[^0-9]/ && $3 !~ /[^0-9]/ && $4 !~ /[^0-9]/ { ok=1 } END { exit !ok }' <<< "$1"
}

fleet_key() {
    [[ -f "$FLEET_TOML" ]] || die "fleet registry not found: ${FLEET_TOML}"
    awk -v hostname="$HOSTNAME" '
        /^[[:space:]]*\[fleet\.nodes\.[^]]+\][[:space:]]*$/ {
            section=$0
            sub(/^[[:space:]]*/, "", section)
            sub(/^\[fleet\.nodes\./, "", section)
            sub(/\]$/, "", section)
            sub(/[[:space:]]*$/, "", section)
            key=section
        }
        /^[[:space:]]*hostname[[:space:]]*=/ {
            value=$0
            sub(/^[^=]*=[[:space:]]*"/, "", value)
            sub(/"[[:space:]]*$/, "", value)
            if (value == hostname) { print key; exit }
        }
    ' "$FLEET_TOML"
}

kv_put() {
    local key="$1" value="$2" status
    if ! status=$(curl --silent --output /dev/null --write-out '%{http_code}' \
        -X PUT \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        --data-binary "$value" \
        "${KV_BASE}/values/${key}"); then
        die "KV PUT request failed for key=${key}"
    fi
    if [[ "$status" != "2"* ]]; then
        die "KV PUT failed for key=${key} (HTTP ${status})"
    fi
}

kv_list_keys() {
    local response status
    if ! response=$(curl --silent --write-out $'\n%{http_code}' \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        "${KV_BASE}/keys"); then
        die "KV key list request failed"
    fi
    status="${response##*$'\n'}"
    response="${response%$'\n'*}"
    [[ "$status" == "2"* ]] || die "KV key list failed (HTTP ${status})"
    jq -e '(.success == true) and (.result | type == "array") and all(.result[]; (.name | type == "string") and length > 0)' <<< "$response" >/dev/null || die "invalid KV key list response"
    jq -r '.result[].name' <<< "$response"
}

kv_get() {
    local key="$1" response status
    if ! response=$(curl --silent --write-out $'\n%{http_code}' \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        "${KV_BASE}/values/${key}"); then
        die "KV value request failed for key=${key}"
    fi
    status="${response##*$'\n'}"
    response="${response%$'\n'*}"
    [[ "$status" == "2"* ]] || die "KV value fetch failed for key=${key} (HTTP ${status})"
    [[ "$response" != *$'\n'* && "$response" != *$'\r'* ]] || die "invalid KV value for key=${key}"
    valid_ip "$response" || die "invalid KV value for key=${key}"
    printf '%s' "$response"
}

deploy_mesh_conf() {
    if [[ ! -f "$MESH_CONF_FILE" ]]; then
        if [[ ! -f "$STAGED_MESH_CONF" ]]; then
            log "no staged mesh.conf found at ${STAGED_MESH_CONF} — skipping deploy"
            return 1
        fi
        if ! sudo mkdir -p "$DNSMASQ_ETC_DIR" || ! sudo cp "$STAGED_MESH_CONF" "$MESH_CONF_FILE" || ! sudo chmod 644 "$MESH_CONF_FILE"; then
            log "ERROR: failed to deploy mesh.conf" >&2
            return 2
        fi
        log "deployed mesh.conf from chezmoi staging to ${MESH_CONF_FILE}"
    fi
    [[ -f "$MESH_CONFIG_STATE_FILE" ]] && return 1
    return 0
}

deploy_seed_hosts() {
    if [[ -f "$MESH_HOSTS_FILE" ]]; then
        return 0
    fi
    if [[ -f "$STAGED_MESH_HOSTS" ]]; then
        sudo mkdir -p "$DNSMASQ_DATA_DIR"
        sudo cp "$STAGED_MESH_HOSTS" "$MESH_HOSTS_FILE"
        sudo chmod 644 "$MESH_HOSTS_FILE"
        log "deployed seed mesh-hosts from chezmoi staging to ${MESH_HOSTS_FILE}"
    fi
}

regenerate_mesh_hosts() {
    local tmp_file key ip keys changed=0
    tmp_file=$(mktemp) || return 2

    if ! echo "# Mesh hosts — auto-generated by mesh-ddns. Do not edit." > "$tmp_file"; then
        rm -f "$tmp_file"
        return 2
    fi

    if ! keys=$(kv_list_keys); then
        rm -f "$tmp_file"
        return 2
    fi
    while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        if ! ip=$(kv_get "$key"); then
            rm -f "$tmp_file"
            return 2
        fi
        if ! printf '%s %s.mesh\n' "$ip" "$key" >> "$tmp_file"; then
            rm -f "$tmp_file"
            return 2
        fi
    done <<< "$keys"

    if [[ ! -f "$MESH_HOSTS_FILE" ]] || ! diff -q "$tmp_file" "$MESH_HOSTS_FILE" &>/dev/null; then
        sudo mkdir -p "$DNSMASQ_DATA_DIR"
        if ! sudo cp "$tmp_file" "$MESH_HOSTS_FILE" || ! sudo chmod 644 "$MESH_HOSTS_FILE"; then
            rm -f "$tmp_file"
            return 2
        fi
        changed=1
        log "mesh-hosts updated"
    else
        log "mesh-hosts unchanged"
    fi

    rm -f "$tmp_file"
    return $((1 - changed))
}

update_listen_address() {
    local mesh_ip="$1" lan_ip="$2" desired="listen-address=127.0.0.1,${1},${2}"
    [[ -f "$MESH_CONF_FILE" ]] || return 1
    if grep -qxF "$desired" "$MESH_CONF_FILE" 2>/dev/null; then
        return 1
    fi
    if grep -qE '^listen-address=127\.0\.0\.1(,[0-9.]+){1,2}$' "$MESH_CONF_FILE" 2>/dev/null || grep -q '^listen-address=' "$MESH_CONF_FILE" 2>/dev/null; then
        sudo sed -i "s|^listen-address=.*|${desired}|" "$MESH_CONF_FILE" || return 2
    else
        printf '%s\n' "$desired" | sudo tee -a "$MESH_CONF_FILE" >/dev/null || return 2
    fi
    log "listen-address updated to 127.0.0.1,${mesh_ip},${lan_ip}"
    return 0
}

restart_dnsmasq() {
    sudo mkdir -p "$DNSMASQ_DATA_DIR"
    sudo systemctl restart dnsmasq
    sudo touch "$MESH_CONFIG_STATE_FILE"
    sudo chmod 644 "$MESH_CONFIG_STATE_FILE"
    log "dnsmasq restarted"
}

reload_dnsmasq() {
    sudo systemctl reload dnsmasq
    log "dnsmasq reloaded"
}

main() {
    local mesh_ip lan_ip node_key config_changed=1 deploy_status regenerate_status update_status
    mesh_ip=$(resolve_mesh_ip)
    lan_ip=$(resolve_lan_ip)
    node_key=$(fleet_key)
    [[ -n "$node_key" ]] || die "hostname ${HOSTNAME} is not registered in fleet.toml"
    log "mesh IP: ${mesh_ip}"
    log "LAN IP: ${lan_ip}"

    kv_put "$node_key" "$mesh_ip"
    log "published ${node_key}=${mesh_ip} to KV"

    if deploy_mesh_conf; then
        config_changed=0
    else
        deploy_status=$?
        (( deploy_status == 1 )) || exit "$deploy_status"
    fi
    deploy_seed_hosts

    update_status=0
    update_listen_address "$mesh_ip" "$lan_ip" || update_status=$?
    if (( update_status == 0 )); then
        config_changed=0
    elif (( update_status != 1 )); then
        exit "$update_status"
    fi

    if regenerate_mesh_hosts; then
        :
    else
        regenerate_status=$?
        (( regenerate_status == 1 )) || exit "$regenerate_status"
    fi
    if (( config_changed == 0 )); then
        restart_dnsmasq
    elif systemctl is-active --quiet dnsmasq 2>/dev/null; then
        reload_dnsmasq
    elif [[ -f "$MESH_CONF_FILE" ]]; then
        restart_dnsmasq
    fi
}

main "$@"
