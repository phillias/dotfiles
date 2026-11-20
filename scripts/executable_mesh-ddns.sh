#!/bin/bash
set -euo pipefail

# mesh-ddns — Dynamic DNS for fleet mesh via Cloudflare Workers KV.
#
# Writes this node's current WARP Mesh IP to CF KV (FLEET_MESH_IPS namespace),
# reads all peers from KV, regenerates the mesh-hosts file, and reloads dnsmasq.
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
    valid_mesh_ip "$mesh_ip" || die "invalid WARP Mesh IP: ${mesh_ip}"
    printf '%s' "$mesh_ip"
}

valid_mesh_ip() {
    awk -F. 'NF == 4 && $1 == 100 && $2 >= 96 && $2 <= 111 && $3 >= 0 && $3 <= 255 && $4 >= 0 && $4 <= 255 && $2 !~ /[^0-9]/ && $3 !~ /[^0-9]/ && $4 !~ /[^0-9]/ { ok=1 } END { exit !ok }' <<< "$1"
}

fleet_key() {
    [[ -f "$FLEET_TOML" ]] || die "fleet registry not found: ${FLEET_TOML}"
    awk -v hostname="$HOSTNAME" '
        /^\[fleet\.nodes\.[^]]+\]$/ {
            section=$0
            sub(/^\[fleet\.nodes\./, "", section)
            sub(/\]$/, "", section)
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
    status=$(curl --silent --output /dev/null --write-out '%{http_code}' \
        -X PUT \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        --data "$value" \
        "${KV_BASE}/values/${key}")
    if [[ "$status" != "2"* ]]; then
        die "KV PUT failed for key=${key} (HTTP ${status})"
    fi
}

kv_list_keys() {
    local response status
    response=$(curl --silent --write-out $'\n%{http_code}' \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        "${KV_BASE}/keys")
    status="${response##*$'\n'}"
    response="${response%$'\n'*}"
    [[ "$status" == "2"* ]] || die "KV key list failed (HTTP ${status})"
    jq -e '(.success == true) and (.result | type == "array") and all(.result[]; (.name | type == "string") and length > 0)' <<< "$response" >/dev/null || die "invalid KV key list response"
    jq -r '.result[].name' <<< "$response"
}

kv_get() {
    local key="$1" response status
    response=$(curl --silent --write-out $'\n%{http_code}' \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        "${KV_BASE}/values/${key}")
    status="${response##*$'\n'}"
    response="${response%$'\n'*}"
    [[ "$status" == "2"* ]] || die "KV value fetch failed for key=${key} (HTTP ${status})"
    [[ "$response" != *$'\n'* && "$response" != *$'\r'* ]] || die "invalid KV value for key=${key}"
    valid_mesh_ip "$response" || die "invalid KV value for key=${key}"
    printf '%s' "$response"
}

deploy_mesh_conf() {
    if [[ -f "$MESH_CONF_FILE" ]]; then
        return 1
    fi
    if [[ -f "$STAGED_MESH_CONF" ]]; then
        sudo mkdir -p "$DNSMASQ_ETC_DIR"
        sudo cp "$STAGED_MESH_CONF" "$MESH_CONF_FILE"
        sudo chmod 644 "$MESH_CONF_FILE"
        log "deployed mesh.conf from chezmoi staging to ${MESH_CONF_FILE}"
        return 0
    else
        log "no staged mesh.conf found at ${STAGED_MESH_CONF} — skipping deploy"
        return 1
    fi
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
    tmp_file=$(mktemp)

    echo "# Mesh hosts — auto-generated by mesh-ddns. Do not edit." > "$tmp_file"

    keys=$(kv_list_keys)
    while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        ip=$(kv_get "$key")
        printf '%s %s.mesh\n' "$ip" "$key" >> "$tmp_file"
    done <<< "$keys"

    if [[ ! -f "$MESH_HOSTS_FILE" ]] || ! diff -q "$tmp_file" "$MESH_HOSTS_FILE" &>/dev/null; then
        sudo mkdir -p "$DNSMASQ_DATA_DIR"
        sudo cp "$tmp_file" "$MESH_HOSTS_FILE"
        sudo chmod 644 "$MESH_HOSTS_FILE"
        changed=1
        log "mesh-hosts updated"
    else
        log "mesh-hosts unchanged"
    fi

    rm -f "$tmp_file"
    return $((1 - changed))
}

restart_dnsmasq() {
    sudo systemctl restart dnsmasq
    log "dnsmasq restarted"
}

reload_dnsmasq() {
    sudo systemctl reload dnsmasq
    log "dnsmasq reloaded"
}

main() {
    local mesh_ip node_key config_changed=1 hosts_changed=1
    mesh_ip=$(resolve_mesh_ip)
    node_key=$(fleet_key)
    [[ -n "$node_key" ]] || die "hostname ${HOSTNAME} is not registered in fleet.toml"
    log "mesh IP: ${mesh_ip}"

    kv_put "$node_key" "$mesh_ip"
    log "published ${node_key}=${mesh_ip} to KV"

    if deploy_mesh_conf; then config_changed=0; fi
    deploy_seed_hosts

    if regenerate_mesh_hosts; then hosts_changed=0; fi
    if (( config_changed == 0 )); then
        restart_dnsmasq
    elif (( hosts_changed == 0 )); then
        reload_dnsmasq
    fi
}

main "$@"
