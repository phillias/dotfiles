#!/usr/bin/env bash
# run_once_setup.sh — bootstrap chezmoi + dotfiles on a new machine
# Usage: curl -fsSL https://raw.githubusercontent.com/phillias/dotfiles/master/run_once_setup.sh | bash
# Works on: macOS (Homebrew), Debian/Ubuntu/Kali (apt), Fedora/RHEL (dnf), Alpine (apk)

set -euo pipefail

export PATH="$HOME/bin:$HOME/.local/bin:$PATH"
CHEZMOI_DIR="$HOME/.local/share/chezmoi"
DEPLOY_KEY="$HOME/.ssh/chezmoi-deploy-key"
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
IS_MAC=false
if [ "$OS" = "darwin" ]; then
    IS_MAC=true
    # Ensure Homebrew paths are available
    if [ -d /opt/homebrew/bin ]; then
        export PATH="/opt/homebrew/bin:$PATH"
    elif [ -d /usr/local/bin ]; then
        export PATH="/usr/local/bin:$PATH"
    fi
fi

echo "=== phillias/dotfiles bootstrap ($(hostname)) ==="

# ── 1. Install chezmoi ──────────────────────────────────────────────
if ! command -v chezmoi &>/dev/null; then
    echo "==> Installing chezmoi..."
    if $IS_MAC && command -v brew &>/dev/null; then
        brew install chezmoi
    else
        BINDIR="$HOME/bin" sh -c "$(curl -fsLS get.chezmoi.io)"
    fi
fi
echo "chezmoi: $(chezmoi --version 2>&1 | head -1)"

# ── 2. Install GitHub CLI ───────────────────────────────────────────
if ! command -v gh &>/dev/null; then
    echo "==> Installing GitHub CLI..."
    if $IS_MAC && command -v brew &>/dev/null; then
        brew install gh
    elif command -v apt-get &>/dev/null; then
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
        sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
        sudo apt-get update -qq && sudo apt-get install -y -qq gh 2>/dev/null
    fi
    if ! command -v gh &>/dev/null; then
        arch=$(uname -m)
        if [ "$IS_MAC" = true ]; then
            gh_arch="apple-darwin"
            ext="zip"
        else
            case "$arch" in
                x86_64)  gh_arch="linux-amd64" ;;
                aarch64) gh_arch="linux-arm64" ;;
                *)       gh_arch="linux-amd64" ;;
            esac
            ext="tar.gz"
        fi
        tmpdir=$(mktemp -d)
        if [ "$IS_MAC" = true ]; then
            curl -fsSL -L -o "$tmpdir/gh.zip" \
                "https://github.com/cli/cli/releases/latest/download/gh_2.76.0_${gh_arch}.${ext}" || \
            curl -fsSL -L -o "$tmpdir/gh.zip" \
                "https://github.com/cli/cli/releases/latest/download/gh_2.75.0_${gh_arch}.${ext}" || \
            curl -fsSL -L -o "$tmpdir/gh.zip" \
                "https://github.com/cli/cli/releases/latest/download/gh_2.74.0_${gh_arch}.${ext}"
            unzip -o "$tmpdir/gh.zip" -d "$tmpdir"
        else
            curl -fsSL -L -o "$tmpdir/gh.tar.gz" \
                "https://github.com/cli/cli/releases/latest/download/gh_2.76.0_${gh_arch}.${ext}" || \
            curl -fsSL -L -o "$tmpdir/gh.tar.gz" \
                "https://github.com/cli/cli/releases/latest/download/gh_2.75.0_${gh_arch}.${ext}" || \
            curl -fsSL -L -o "$tmpdir/gh.tar.gz" \
                "https://github.com/cli/cli/releases/latest/download/gh_2.74.0_${gh_arch}.${ext}"
            tar xzf "$tmpdir/gh.tar.gz" -C "$tmpdir"
        fi
        mkdir -p "$HOME/bin"
        find "$tmpdir" -name "gh" -type f -exec cp {} "$HOME/bin/" \;
        rm -rf "$tmpdir"
    fi
fi
echo "gh: $(gh --version 2>&1 | head -1)"

# ── 3. Install Bitwarden CLI ────────────────────────────────────────
if ! command -v bw &>/dev/null; then
    echo "==> Installing Bitwarden CLI..."
    if $IS_MAC && command -v brew &>/dev/null; then
        brew install bitwarden-cli
    else
        tmpdir=$(mktemp -d)
        BW_TAG=$(curl -fsSL https://api.github.com/repos/bitwarden/clients/releases/latest 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)[\x27tag_name\x27])" 2>/dev/null || echo "cli-v2025.2.0")
        echo "==> Bitwarden CLI: ${BW_TAG}"
        curl -fsSL -o "$tmpdir/bw.zip" "https://github.com/bitwarden/clients/releases/download/${BW_TAG}/bw-linux-${BW_TAG#cli-}.zip"
        unzip -o "$tmpdir/bw.zip" -d "$tmpdir"
        chmod +x "$tmpdir/bw"
        mkdir -p "$HOME/bin"
        mv "$tmpdir/bw" "$HOME/bin/"
        rm -rf "$tmpdir"
    fi
fi
echo "bw: $(bw --version 2>&1)"

# ── 4. Install cloudflared ──────────────────────────────────────────
if ! command -v cloudflared &>/dev/null; then
    echo "==> Installing cloudflared..."
    if $IS_MAC && command -v brew &>/dev/null; then
        brew install cloudflared
    else
        arch=$(uname -m)
        case "$arch" in
            x86_64)  cf_arch="amd64" ;;
            aarch64) cf_arch="arm64" ;;
            armv7l)  cf_arch="arm" ;;
            *)       cf_arch="amd64" ;;
        esac
        tmpdir=$(mktemp -d)
        curl -fsSL -o "$tmpdir/cloudflared" \
            "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cf_arch}"
        chmod +x "$tmpdir/cloudflared"
        if command -v sudo &>/dev/null; then
            sudo mv "$tmpdir/cloudflared" /usr/bin/cloudflared
        else
            mkdir -p "$HOME/bin"
            mv "$tmpdir/cloudflared" "$HOME/bin/cloudflared"
        fi
        rm -rf "$tmpdir"
    fi
    echo "cloudflared: $(cloudflared --version 2>&1 | head -1)"
fi

# ── 5. Generate deploy key ──────────────────────────────────────────
if [ ! -f "$DEPLOY_KEY" ]; then
    echo "==> Generating deploy key..."
    mkdir -p "$(dirname "$DEPLOY_KEY")"
    ssh-keygen -t ed25519 -f "$DEPLOY_KEY" -N "" -C "chezmoi@$(hostname)"
    chmod 600 "$DEPLOY_KEY"
    chmod 644 "${DEPLOY_KEY}.pub"
    echo "Deploy key: $(ssh-keygen -l -f "${DEPLOY_KEY}.pub" | awk '{print $2}')"
fi

# ── 6. Authenticate gh (one-time) ───────────────────────────────────
if ! gh auth status &>/dev/null; then
    echo ""
    echo "==> GitHub authentication required"
    echo "    Create a PAT at: https://github.com/settings/tokens"
    echo "    Required scopes: repo (full)"
    echo ""
    gh auth login --with-token
fi

# ── 7. Register deploy key on GitHub ────────────────────────────────
echo "==> Registering deploy key on GitHub..."
DEPLOY_TITLE="chezmoi@$(hostname)"
DEPLOY_FP=$(ssh-keygen -l -f "${DEPLOY_KEY}.pub" | awk '{print $2}')
gh repo deploy-key add "${DEPLOY_KEY}.pub" \
    --repo phillias/dotfiles \
    --title "$DEPLOY_TITLE" \
    --allow-write 2>/dev/null || echo "Key may already be registered"

# ── 8. Clone dotfiles repo ──────────────────────────────────────────
if [ ! -d "$CHEZMOI_DIR" ]; then
    echo "==> Cloning dotfiles repo..."
    GIT_SSH_COMMAND="ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes" \
        chezmoi init git@github.com:phillias/dotfiles.git
fi

# ── 9. Bitwarden login (interactive) ────────────────────────────────
echo ""
echo "==> Bitwarden login required"
bw login phillias@gmail.com
export BW_SESSION=$(bw unlock --raw)

# ── 10. Apply dotfiles ─────────────────────────────────────────────
echo "==> Applying dotfiles..."
BW_SESSION="$BW_SESSION" chezmoi apply

# ── 11. Decrypt age encryption key ──────────────────────────────────
echo ""
echo "==> Age encryption setup"
echo "    Find the passphrase in Bitwarden: search 'Chezmoi Age Key'"
echo ""

AGE_KEY_FILE="$HOME/.config/chezmoi/key.txt"

if [ ! -f "$AGE_KEY_FILE" ]; then
    read -rp "Enter age passphrase from Bitwarden: " AGE_PP
    if [ -n "$AGE_PP" ]; then
        mkdir -p "$(dirname "$AGE_KEY_FILE")"
        if $IS_MAC; then
            # macOS: use script to fake TTY for expect
            if command -v expect &>/dev/null; then
                expect << EXPECTEOF
set timeout 10
spawn chezmoi age decrypt --passphrase --output "$AGE_KEY_FILE" "$CHEZMOI_DIR/age-key.txt.age"
expect "Enter passphrase:"
send "$AGE_PP\r"
expect "Confirm passphrase:"
send "$AGE_PP\r"
expect eof
EXPECTEOF
            else
                echo "WARN: 'expect' not found on macOS. Install with: brew install expect"
                echo "      Then run: chezmoi age decrypt --passphrase -o $AGE_KEY_FILE $CHEZMOI_DIR/age-key.txt.age"
            fi
        else
            expect << EXPECTEOF
set timeout 10
spawn chezmoi age decrypt --passphrase --output "$AGE_KEY_FILE" "$CHEZMOI_DIR/age-key.txt.age"
expect "Enter passphrase:"
send "$AGE_PP\r"
expect "Confirm passphrase:"
send "$AGE_PP\r"
expect eof
EXPECTEOF
        fi
        chmod 600 "$AGE_KEY_FILE"
        echo "Age key decrypted"
    else
        echo "WARN: No passphrase entered. Decrypt manually later."
    fi
else
    echo "Age key already present, skipping"
fi

# ── 12. Write chezmoi config ────────────────────────────────────────
if [ -f "$AGE_KEY_FILE" ]; then
    AGE_PUB=$(chezmoi data --format=json 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('chezmoi', {}).get('config', {}).get('age', {}).get('recipient', ''))
" 2>/dev/null || echo "")
    if [ -z "$AGE_PUB" ]; then
        AGE_PUB="age1p5cu2lhvhjxq2rkzxlgk9ekknr3ang7n5nla5pst94ckm8jmmq9sp66mc5"
    fi
    mkdir -p "$HOME/.config/chezmoi"
    cat > "$HOME/.config/chezmoi/chezmoi.toml" << AGECONF
encryption = "age"
[age]
    identity = "~/.config/chezmoi/key.txt"
    recipient = "$AGE_PUB"
AGECONF
    echo "chezmoi.toml written"
fi

# ── 13. Full apply ──────────────────────────────────────────────────
echo ""
echo "==> Full apply..."
BW_SESSION=$(bw unlock --raw) chezmoi apply

# ── 14. Register in inventory ───────────────────────────────────────
if [ -f "$CHEZMOI_DIR/.chezmoi-inventory.json" ]; then
    python3 -c "
import json, subprocess, datetime
inv_file = '$CHEZMOI_DIR/.chezmoi-inventory.json'
with open(inv_file) as f:
    inv = json.load(f)
hostname = subprocess.check_output(['hostname']).decode().strip()
now = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
inv.setdefault('servers', {})[hostname] = {
    'hostname': hostname,
    'username': subprocess.check_output(['whoami']).decode().strip(),
    'os': subprocess.check_output(['uname', '-s']).decode().strip().lower(),
    'arch': subprocess.check_output(['uname', '-m']).decode().strip(),
    'deploy_key_title': 'chezmoi@' + hostname,
    'deploy_key_fp': '$DEPLOY_FP',
    'first_seen': inv.get('servers', {}).get(hostname, {}).get('first_seen', now),
    'last_sync': now,
    'status': 'active'
}
with open(inv_file, 'w') as f:
    json.dump(inv, f, indent=2)
print('Inventory updated: ' + hostname)
"
fi

# ── 15. Install cron job (Linux only, macOS uses launchd) ───────────
if $IS_MAC; then
    echo "==> Auto-sync on macOS requires launchd (not cron)."
    echo "    Manual setup: create a LaunchAgent that runs 'chezmoi update' periodically."
    echo "    Or simply run 'chezmoi update' when you want to sync."
else
    CRON_LINE="*/30 * * * * export PATH=\$HOME/bin:\$HOME/.local/bin:\$PATH; export BW_SESSION=\$(bw unlock --raw 2>/dev/null); chezmoi update >> \$HOME/.local/share/chezmoi/.chezmoi-sync.log 2>&1"
    if ! crontab -l 2>/dev/null | grep -q "chezmoi update"; then
        (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
        echo "Cron job installed: chezmoi update every 30 minutes"
    else
        echo "Cron job already installed"
    fi
fi

# ── 16. Verify ──────────────────────────────────────────────────────
echo ""
echo "=== Verification ==="
if chezmoi verify 2>/dev/null; then
    echo "OK: All files verified"
else
    echo "WARN: Some files differ"
fi

echo ""
echo "=== Managed files ==="
chezmoi managed

echo ""
echo "=== SSH keys ==="
for k in id_ed25519 id_ed25519_inspironkali id_ed25519_kali id_ed25519_oraclecloud id_ed25519_huggingface; do
    [ -f "$HOME/.ssh/$k" ] && echo "  $k: OK" || echo "  $k: MISSING"
done

echo ""
echo "=== Bootstrap complete ==="
echo ""
echo "Daily commands:"
echo "  BW_SESSION=\$(bw unlock --raw) chezmoi update"
echo "  chezmoi edit <file>"
echo "  chezmoi re-add <file>"
echo "  bash scripts/chezmoi-deploy-key.sh inventory"
