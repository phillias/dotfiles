#!/bin/bash
# WARP firewall bypass — idempotent nftables + routing fix for Cloudflare edge IPs.
# Adds accept rules to cloudflare-warp nftables table and bypass routes to table 65743.
# Must run as root. Exits 0 if cloudflare-warp table doesn't exist yet (systemd retries).

set -euo pipefail

# Cloudflare edge IPv4 CIDR ranges (15 ranges)
CF_EDGE_CIDRS=(
    "173.245.48.0/20"
    "103.21.244.0/22"
    "103.22.200.0/22"
    "103.31.4.0/22"
    "141.101.64.0/18"
    "108.162.192.0/18"
    "190.93.240.0/20"
    "188.114.96.0/20"
    "197.234.240.0/22"
    "198.41.128.0/17"
    "162.158.0.0/15"
    "104.16.0.0/13"
    "104.24.0.0/14"
    "172.64.0.0/13"
    "131.0.72.0/22"
)

WARP_TABLE="65743"
NFT_TABLE="inet cloudflare-warp"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Root check
if [ "$(id -u)" -ne 0 ]; then
    log "ERROR: must run as root"
    exit 1
fi

# Check nftables table exists (WARP may not be fully started)
if ! nft list table "$NFT_TABLE" >/dev/null 2>&1; then
    log "cloudflare-warp nftables table not ready; exiting 0 for systemd retry"
    exit 0
fi

# Detect default gateway and LAN interface dynamically
DEFAULT_ROUTE=$(ip route show default | head -n1)
if [ -z "$DEFAULT_ROUTE" ]; then
    log "ERROR: no default route found"
    exit 1
fi

GATEWAY=$(echo "$DEFAULT_ROUTE" | awk '{print $3}')
INTERFACE=$(echo "$DEFAULT_ROUTE" | awk '{print $5}')

if [ -z "$GATEWAY" ] || [ -z "$INTERFACE" ]; then
    log "ERROR: could not parse gateway/interface from default route: $DEFAULT_ROUTE"
    exit 1
fi

log "Detected gateway: $GATEWAY, interface: $INTERFACE"

# Add nftables accept rules (idempotent: only if not present)
for cidr in "${CF_EDGE_CIDRS[@]}"; do
    # INPUT chain
    if ! nft list chain "$NFT_TABLE" input | grep -q "ip saddr $cidr accept"; then
        log "Adding nftables INPUT rule for $cidr"
        nft add rule "$NFT_TABLE" input ip saddr "$cidr" accept
    fi
    # OUTPUT chain
    if ! nft list chain "$NFT_TABLE" output | grep -q "ip daddr $cidr accept"; then
        log "Adding nftables OUTPUT rule for $cidr"
        nft add rule "$NFT_TABLE" output ip daddr "$cidr" accept
    fi
done

# Add bypass routes to WARP routing table (idempotent: only if not present)
for cidr in "${CF_EDGE_CIDRS[@]}"; do
    if ! ip route show table "$WARP_TABLE" | grep -q "^$cidr "; then
        log "Adding bypass route for $cidr via $GATEWAY dev $INTERFACE table $WARP_TABLE"
        ip route add "$cidr" via "$GATEWAY" dev "$INTERFACE" table "$WARP_TABLE"
    fi
done

log "WARP firewall bypass applied successfully"
exit 0