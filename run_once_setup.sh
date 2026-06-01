#!/usr/bin/env bash
# run_once_setup.sh — bootstrap chezmoi + dotfiles on a new machine
# Usage: curl -fsSL https://raw.githubusercontent.com/phillias/dotfiles/master/run_once_setup.sh | bash
# Works on: macOS (Homebrew), Debian/Ubuntu/Kali (apt)

set -euo pipefail

export PATH="$HOME/bin:$HOME/.local/bin:$PATH"
CHEZMOI_DIR="$HOME/.local/share/chezmoi"
DEPLOY_KEY="$HOME/.ssh/chezmoi-deploy-key"
IS_MAC=false
if [ "$(uname -s)" = "Darwin" ]; then
    IS_MAC=true
    [ -d /opt/homebrew/bin ] && export PATH="/opt/homebrew/bin:$PATH"
    [ -d /usr/local/bin ] && export PATH="/usr/local/bin:$PATH"
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
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
            sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
        sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
            sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
        sudo apt-get update -qq && sudo apt-get install -y -qq gh 2>/dev/null
    fi
    if ! command -v gh &>/dev/null; then
        # Binary fallback: get latest tag from API, construct download URL
        GH_TAG=$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest 2>/dev/null |
            python3 -c "import sys,json; print(json.load(sys.stdin)['27tag_name'$27])" 2>/dev/null ||
            echo "v2.76.0")
        echo "==> gh: downloading ${GH_TAG}"
        ARCH=$(uname -m)
        if $IS_MAC; then
            case "$ARCH" in arm64) GA="macOS_arm64.zip" ;; *) GA="macOS_amd64.zip" ;; esac
        else
            case "$ARCH" in x86_64) GA="linux_amd64.tar.gz" ;; aarch64) GA="linux_arm64.tar.gz" ;; *) GA="linux_amd64.tar.gz" ;; esac
        fi
        TMP=$(mktemp -d)
        curl -fsSL -o "$TMP/gh.bin" "https://github.com/cli/cli/releases/download/${GH_TAG}/gh_${GH_TAG#v}_${GA}"
        if [[ "$GA" == *.zip ]]; then unzip -o "$TMP/gh.bin" -d "$TMP"
        else tar xzf "$TMP/gh.bin" -C "$TMP"; fi
        find "$TMP" -name "gh" -type f -exec cp {} "$HOME/bin/" \;
        rm -rf "$TMP"
    fi
fi
echo "gh: $(gh --version 2>&1 | head -1)"

# ── 3. Install Bitwarden CLI ────────────────────────────────────────
if ! command -v bw &>/dev/null; then
    echo "==> Installing Bitwarden CLI..."
    if $IS_MAC && command -v brew &>/dev/null; then
        brew install bitwarden-cli
    else
        TMP=$(mktemp -d)
        BW_TAG=$(curl -fsSL https://api.github.com/repos/bitwarden/clients/releases/latest 2>/dev/null |
            python3 -c "import sys,json; print(json.load(sys.stdin)['27tag_name'$27])" 2>/dev/null ||
            echo "cli-v2025.2.0")
        echo "==> Bitwarden CLI: ${BW_TAG}"
        curl -fsSL -o "$TMP/bw.zip" "https://github.com/bitwarden/clients/releases/download/${BW_TAG}/bw-linux-${BW_TAG#cli-}.zip"
        unzip -o "$TMP/bw.zip" -d "$TMP"
        chmod +x "$TMP/bw"
        mkdir -p "$HOME/bin"
        mv "$TMP/bw" "$HOME/bin/"
        rm -rf "$TMP"
    fi
fi
echo "bw: $(bw --version 2>&1)"

# ── 4. Install cloudflared ──────────────────────────────────────────
if ! command -v cloudflared &>/dev/null; then
    echo "==> Installing cloudflared..."
    if $IS_MAC && command -v brew &>/dev/null; then
        brew install cloudflared
    else
        ARCH=$(uname -m)
        case "$ARCH" in x86_64) CA="amd64" ;; aarch64) CA="arm64" ;; armv7l) CA="arm" ;; *) CA="amd64" ;; esac
        curl -fsSL -o /tmp/cloudflared "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CA}"
        chmod +x /tmp/cloudflared
        if command -v sudo &>/dev/null; then sudo mv /tmp/cloudflared /usr/bin/cloudflared
        else mkdir -p "$HOME/bin" && mv /tmp/cloudflared "$HOME/bin/cloudflared"; fi
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
    echo "Key: $(ssh-keygen -l -f "${DEPLOY_KEY}.pub" | awk '{print $2}')"
fi

# ── 6. Authenticate gh (one-time) ───────────────────────────────────
if ! gh auth status &>/dev/null; then
    echo ""
    echo "==> GitHub auth required (PAT with repo scope)"
    gh auth login --with-token
fi

# ── 7. Register deploy key on GitHub ────────────────────────────────
echo "==> Registering deploy key..."
gh repo deploy-key add "${DEPLOY_KEY}.pub" --repo phillias/dotfiles \
    --title "chezmoi@$(hostname)" --allow-write 2>/dev/null || echo "Key may already exist"

# ── 8. Clone dotfiles repo ──────────────────────────────────────────
if [ ! -d "$CHEZMOI_DIR" ]; then
    echo "==> Cloning dotfiles..."
    GIT_SSH_COMMAND="ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes" \
        chezmoi init git@github.com:phillias/dotfiles.git
fi

# ── 9. Bitwarden login ─────────────────────────────────────────────
echo ""
echo "==> Bitwarden login required"
bw login phillias@gmail.com
BW_SESSION=$(bw unlock --raw)

# ── 10. Apply dotfiles ─────────────────────────────────────────────
echo "==> Applying dotfiles..."
BW_SESSION="$BW_SESSION" chezmoi apply

# ── 11. Decrypt age encryption key ─────────────────────────────────
AGE_KEY_FILE="$HOME/.config/chezmoi/key.txt"
if [ ! -f "$AGE_KEY_FILE" ]; then
    echo ""
    echo "==> Age encryption (Bitwarden: 'Chezmoi Age Key')"
    read -rp "Enter age passphrase: " AGE_PP
    if [ -n "$AGE_PP" ]; then
        mkdir -p "$(dirname "$AGE_KEY_FILE")"
        expect << XEOF
set timeout 10
spawn chezmoi age decrypt --passphrase --output "$AGE_KEY_FILE" "$CHEZMOI_DIR/age-key.txt.age"
expect "Enter passphrase:"
send "$AGE_PP\r"
expect "Confirm passphrase:"
send "$AGE_PP\r"
expect eof
XEOF
        chmod 600 "$AGE_KEY_FILE"
        echo "Age key decrypted"
    fi
else
    echo "Age key already present"
fi

# ── 12. Write chezmoi config ────────────────────────────────────────
if [ -f "$AGE_KEY_FILE" ]; then
    AGE_PUB=$(chezmoi data --format=json 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('chezmoi',{}).get('config',{}).get('age',{}).get('recipient',''))
" 2>/dev/null || echo "age1p5cu2lhvhjxq2rkzxlgk9ekknr3ang7n5nla5pst94ckm8jmmq9sp66mc5")
    mkdir -p "$HOME/.config/chezmoi"
    cat > "$HOME/.config/chezmoi/chezmoi.toml" <<- AEOF
encryption = "age"
[age]
    identity = "~/.config/chezmoi/key.txt"
    recipient = "$AGE_PUB"
AEOF
    echo "chezmoi.toml written"
fi

# ── 13. Full apply ──────────────────────────────────────────────────
echo ""
echo "==> Full apply..."
BW_SESSION=$(bw unlock --raw) chezmoi apply

# ── 14. Register in inventory ───────────────────────────────────────
if [ -f "$CHEZMOI_DIR/.chezmoi-inventory.json" ]; then
    python3 -c "
import json,subprocess,datetime
f='$CHEZMOI_DIR/.chezmoi-inventory.json'
with open(f) as fh: inv=json.load(fh)
h=subprocess.check_output(['hostname']).decode().strip()
n=datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
s=subprocess.check_output
inv.setdefault('servers',{})[h]={'hostname':h,'username':s(['whoami']).decode().strip(),'os':s(['uname','-s']).decode().strip().lower(),'arch':s(['uname','-m']).decode().strip(),'deploy_key_title':'chezmoi@'+h,'first_seen':inv.get('servers',{}).get(h,{}).get('first_seen',n),'last_sync':n,'status':'active'}
with open(f,'w') as fh: json.dump(inv,f,indent=2)
print('Inventory: '+h)
"
fi

# ── 15. Auto-sync (cron on Linux, note on macOS) ────────────────────
if $IS_MAC; then
    echo "===> macOS: use launchd for auto-sync (or run chezmoi update manually)"
else
    L="*/30 * * * * export PATH=\$HOME/bin:\$HOME/.local/bin:\$PATH; export BW_SESSION=\$(bw unlock --raw 2>/dev/null); chezmoi update >> \$HOME/.local/share/chezmoi/.chezmoi-sync.log 2>&1"
    if ! crontab -l 2>/dev/null | grep -q "chezmoi update"; then
        (crontab -l 2>/dev/null; echo "$L") | crontab -
        echo "Cron: chezmoi update every 30 min"
    fi
fi

# ── 16. Verify ──────────────────────────────────────────────────────
echo ""
echo "=== Verification ==="
chezmoi verify 2>/dev/null && echo "OK" || echo "WARN: differences"
echo ""
chezmoi managed
echo ""
for k in id_ed25519 id_ed25519_inspironkali id_ed25519_kali id_ed25519_oraclecloud id_ed25519_huggingface; do
    [ -f "$HOME/.ssh/$k" ] && echo "  $k: OK" || echo "  $k: MISSING"
done
echo ""
echo "=== Done ==="
