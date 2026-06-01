#!/usr/bin/env bash
# chezmoi-deploy-key.sh — manage per-server deploy keys for the dotfiles repo
# Usage:
#   chezmoi-deploy-key.sh generate   — generate a new deploy key
#   chezmoi-deploy-key.sh register   — add deploy key to GitHub repo
#   chezmoi-deploy-key.sh inventory  — show registered servers
#   chezmoi-deploy-key.sh status     — show this server's deploy key status
#   chezmoi-deploy-key.sh sync       — update last_sync timestamp
#   chezmoi-deploy-key.sh cron       — install cron job for auto-sync

set -euo pipefail

CHEZMOI_DIR="$HOME/.local/share/chezmoi"
INVENTORY="$CHEZMOI_DIR/.chezmoi-inventory.json"
DEPLOY_KEY="$HOME/.ssh/chezmoi-deploy-key"
DEPLOY_KEY_PUB="${DEPLOY_KEY}.pub"
REPO="phillias/dotfiles"
HOSTNAME=$(hostname)
USERNAME=$(whoami)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

ensure_inventory() {
    if [ ! -f "$INVENTORY" ]; then
        echo '{"servers":{}}' > "$INVENTORY"
    fi
}

cmd_generate() {
    if [ -f "$DEPLOY_KEY" ]; then
        echo "Deploy key already exists: $DEPLOY_KEY"
        ssh-keygen -l -f "$DEPLOY_KEY_PUB"
        return 0
    fi
    mkdir -p "$(dirname "$DEPLOY_KEY")"
    ssh-keygen -t ed25519 -f "$DEPLOY_KEY" -N "" -C "chezmoi@${HOSTNAME}"
    chmod 600 "$DEPLOY_KEY"
    chmod 644 "$DEPLOY_KEY_PUB"
    echo "Generated: $DEPLOY_KEY"
    ssh-keygen -l -f "$DEPLOY_KEY_PUB"
}

cmd_register() {
    if [ ! -f "$DEPLOY_KEY_PUB" ]; then
        echo "No deploy key found. Run: $0 generate"
        exit 1
    fi
    if ! gh auth status &>/dev/null; then
        echo "GitHub CLI not authenticated. Run: gh auth login"
        exit 1
    fi
    local title="chezmoi@${HOSTNAME}"
    local fp=$(ssh-keygen -l -f "$DEPLOY_KEY_PUB" | awk '{print $2}')
    echo "Adding deploy key '${title}' to ${REPO}..."
    gh repo deploy-key add "$DEPLOY_KEY_PUB" --repo "$REPO" --title "$title" --allow-write
    echo "Deploy key registered."
    ensure_inventory
    python3 -c "
import json
with open('$INVENTORY') as f:
    inv = json.load(f)
inv.setdefault('servers', {})['$HOSTNAME'] = {
    'hostname': '$HOSTNAME',
    'username': '$USERNAME',
    'os': '$OS',
    'arch': '$ARCH',
    'deploy_key_title': '$title',
    'deploy_key_fp': '$fp',
    'first_seen': inv.get('servers', {}).get('$HOSTNAME', {}).get('first_seen', '$NOW'),
    'last_sync': '$NOW',
    'status': 'active'
}
with open('$INVENTORY', 'w') as f:
    json.dump(inv, f, indent=2)
"
    echo "Inventory updated."
}

cmd_inventory() {
    ensure_inventory
    python3 -c "
import json
from datetime import datetime
with open('$INVENTORY') as f:
    inv = json.load(f)
servers = inv.get('servers', {})
if not servers:
    print('No servers registered.')
    exit()
print(f\"{'Hostname':<25} {'User':<12} {'OS':<8} {'Arch':<8} {'Status':<10} {'Last Sync'}\")
print('-' * 90)
for name, info in sorted(servers.items()):
    ls = info.get('last_sync', 'never')
    if ls != 'never':
        try:
            dt = datetime.fromisoformat(ls.replace('Z', '+00:00'))
            ls = dt.strftime('%Y-%m-%d %H:%M')
        except:
            pass
    print(f\"{name:<25} {info.get('username','?'):<12} {info.get('os','?'):<8} {info.get('arch','?'):<8} {info.get('status','?'):<10} {ls}\")
"
}

cmd_status() {
    echo "=== This Server ==="
    echo "Hostname:  $HOSTNAME"
    echo "Username:  $USERNAME"
    echo "OS:        $OS ($ARCH)"
    echo ""
    if [ -f "$DEPLOY_KEY" ]; then
        echo "Deploy key: $DEPLOY_KEY"
        ssh-keygen -l -f "$DEPLOY_KEY_PUB"
    else
        echo "Deploy key: NOT GENERATED"
    fi
}

cmd_sync() {
    ensure_inventory
    python3 -c "
import json
with open('$INVENTORY') as f:
    inv = json.load(f)
if '$HOSTNAME' in inv.get('servers', {}):
    inv['servers']['$HOSTNAME']['last_sync'] = '$NOW'
    with open('$INVENTORY', 'w') as f:
        json.dump(inv, f, indent=2)
    print('Sync timestamp updated.')
else:
    print('Not in inventory. Run: $0 register')
"
}

cmd_cron() {
    local cron_line="*/30 * * * * export PATH=\$HOME/bin:\$HOME/.local/bin:\$PATH; export BW_SESSION=\$(bw unlock --raw 2>/dev/null); chezmoi update >> \$HOME/.local/share/chezmoi/.chezmoi-sync.log 2>&1"
    if crontab -l 2>/dev/null | grep -q "chezmoi update"; then
        echo "Cron job already installed."
        return 0
    fi
    (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
    echo "Cron job installed: chezmoi update every 30 minutes"
    echo "Log: ~/.local/share/chezmoi/.chezmoi-sync.log"
}

case "${1:-help}" in
    generate)  cmd_generate ;;
    register)  cmd_register ;;
    inventory) cmd_inventory ;;
    status)    cmd_status ;;
    sync)      cmd_sync ;;
    cron)      cmd_cron ;;
    help|*)
        echo "Usage: $0 {generate|register|inventory|status|sync|cron}"
        echo ""
        echo "  generate  - Generate ED25519 deploy key for this server"
        echo "  register  - Add deploy key to GitHub + update inventory"
        echo "  inventory - List all registered servers"
        echo "  status    - Show this server's deploy key status"
        echo "  sync      - Update last_sync timestamp"
        echo "  cron      - Install cron job for automatic chezmoi sync"
        ;;
esac
