#!/usr/bin/env bash
# scripts/setup.sh — one-time bootstrap for a new server
# Usage: curl -fsSL https://raw.githubusercontent.com/phillias/dotfiles/master/scripts/setup.sh | bash
# NOTE: This is a ONE-TIME setup script, NOT a chezmoi-managed file.

set -euo pipefail

export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH"
CHEZMOI_DIR="$HOME/.local/share/chezmoi"
DEPLOY_KEY="$HOME/.ssh/chezmoi-deploy-key"
IS_MAC=false
if [ "$(uname -s)" = "Darwin" ]; then
    IS_MAC=true
    [ -d /opt/homebrew/bin ] && export PATH="/opt/homebrew/bin:$PATH"
    [ -d /usr/local/bin ] && export PATH="/usr/local/bin:$PATH"
fi

echo "=== phillias/dotfiles bootstrap ($(hostname)) ==="

# ── 1. Determine install method on macOS ─────────────────────────────
# Prefer the current user's own Homebrew. Fall back to binary downloads.
# Never sudo-chown another user's Homebrew — that breaks multi-user setups.
BREW_OK=false
BREW_USER_PREFIX="$HOME/homebrew"
if $IS_MAC; then
    # Check for user-local homebrew first
    if [ -x "$BREW_USER_PREFIX/bin/brew" ]; then
        BREW_OK=true
        export PATH="$BREW_USER_PREFIX/bin:$PATH"
        echo "==> Using user-local Homebrew at $BREW_USER_PREFIX"
    elif command -v brew &>/dev/null; then
        BREW_PREFIX=$(brew --prefix 2>/dev/null || echo "/opt/homebrew")
        # Only use system homebrew if current user owns it
        if [ -w "$BREW_PREFIX/Cellar" ]; then
            BREW_OK=true
            echo "==> Using system Homebrew at $BREW_PREFIX"
        else
            echo "==> System Homebrew exists but Cellar is owned by another user."
            echo "    → Installing tools via binary download instead (no brew needed)."
            echo "    → Optionally, set up your own Homebrew later: https://brew.sh"
        fi
    fi
fi

# ── 2. Install chezmoi ──────────────────────────────────────────────
if ! command -v chezmoi &>/dev/null; then
    echo "==> Installing chezmoi..."
    if $BREW_OK; then
        brew install chezmoi
    else
        TMP=$(mktemp -d)
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64)  CZ_ARCH="amd64" ;;
            aarch64) CZ_ARCH="arm64" ;;
            armv7l)  CZ_ARCH="armhf" ;;
            *)       CZ_ARCH="amd64" ;;
        esac
        CZ_TAG=$(curl -fsSL https://api.github.com/repos/twpayne/chezmoi/releases/latest 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])" 2>/dev/null || echo "v2.70.4")
        CZ_DEB="chezmoi_${CZ_TAG#v}_linux_${CZ_ARCH}.deb"
        echo "==> Installing chezmoi ${CZ_TAG}..."
        if curl -fsSL -o "$TMP/chezmoi.deb" "https://github.com/twpayne/chezmoi/releases/download/${CZ_TAG}/${CZ_DEB}" 2>/dev/null; then
            if command -v sudo &>/dev/null; then
                sudo dpkg -i "$TMP/chezmoi.deb" 2>/dev/null || sudo apt-get install -f -y 2>/dev/null
            else
                dpkg -i "$TMP/chezmoi.deb" 2>/dev/null || apt-get install -f -y 2>/dev/null
            fi
        fi
        # Fallback to binary download if dpkg not available
        if ! command -v chezmoi &>/dev/null; then
            echo "  Falling back to binary download..."
            for attempt in 1 2 3; do
                if BINDIR="$HOME/bin" sh -c "$(curl -fsLS get.chezmoi.io)" 2>/dev/null; then
                    break
                fi
                echo "  Retry $attempt/3..."
                sleep 2
            done
        fi
        rm -rf "$TMP"
    fi
fi
echo "chezmoi: $(chezmoi --version 2>&1 | head -1)"

# ── 3. Install GitHub CLI ───────────────────────────────────────────
if ! command -v gh &>/dev/null; then
    echo "==> Installing GitHub CLI..."
    if $BREW_OK; then
        brew install gh
    else
        GH_TAG=$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])" 2>/dev/null || echo "v2.76.0")
        echo "==> gh: downloading ${GH_TAG}"
        ARCH=$(uname -m)
        if [ "$IS_MAC" = true ]; then
            case "$ARCH" in arm64) GA="macOS_arm64.zip" ;; *) GA="macOS_amd64.zip" ;; esac
            TMP=$(mktemp -d)
            curl -fsSL -o "$TMP/gh.zip" "https://github.com/cli/cli/releases/download/${GH_TAG}/gh_${GH_TAG#v}_${GA}"
            unzip -o "$TMP/gh.zip" -d "$TMP"
            find "$TMP" -name "gh" -type f -exec cp {} "$HOME/bin/" \;
            rm -rf "$TMP"
        else
            case "$ARCH" in
                x86_64)  GH_DEB="amd64" ;;
                aarch64) GH_DEB="arm64" ;;
                armv7l)  GH_DEB="armv6" ;;
                *)       GH_DEB="amd64" ;;
            esac
            GH_DEB_FILE="gh_${GH_TAG#v}_linux_${GH_DEB}.deb"
            TMP=$(mktemp -d)
            if curl -fsSL -o "$TMP/gh.deb" "https://github.com/cli/cli/releases/download/${GH_TAG}/${GH_DEB_FILE}" 2>/dev/null; then
                if command -v sudo &>/dev/null; then
                    sudo dpkg -i "$TMP/gh.deb" 2>/dev/null || sudo apt-get install -f -y 2>/dev/null
                else
                    dpkg -i "$TMP/gh.deb" 2>/dev/null
                fi
            fi
            rm -rf "$TMP"
        fi
    fi
fi
echo "gh: $(gh --version 2>&1 | head -1)"

# ── 4. Install Bitwarden CLI ────────────────────────────────────────
if ! command -v bw &>/dev/null; then
    echo "==> Installing Bitwarden CLI..."
    if $BREW_OK; then
        brew install bitwarden-cli
    else
        ARCH=$(uname -m)
        # Get the latest CLI-specific release (tag starts with cli-)
        BW_TAG=$(curl -fsSL "https://api.github.com/repos/bitwarden/clients/releases?per_page=10" 2>/dev/null | python3 -c "
import sys,json
for r in json.load(sys.stdin):
    if r['tag_name'].startswith('cli-'):
        print(r['tag_name'])
        break
" 2>/dev/null || echo "")
        if [ -n "$BW_TAG" ]; then
            BW_VERSION="${BW_TAG#cli-}"
            BW_VERSION="${BW_VERSION#v}"  # Strip leading v if present
            echo "==> bw: downloading ${BW_VERSION}"
            TMP=$(mktemp -d)
            if [ "$IS_MAC" = true ]; then
                case "$ARCH" in arm64) BW_FILE="bw-macos-arm64-${BW_VERSION}.zip" ;; *) BW_FILE="bw-macos-${BW_VERSION}.zip" ;; esac
            else
                case "$ARCH" in aarch64) BW_FILE="bw-linux-arm64-${BW_VERSION}.zip" ;; *) BW_FILE="bw-linux-${BW_VERSION}.zip" ;; esac
            fi
            if curl -fsSL -o "$TMP/bw.zip" "https://github.com/bitwarden/clients/releases/download/${BW_TAG}/${BW_FILE}" 2>/dev/null; then
                unzip -o "$TMP/bw.zip" -d "$TMP" 2>/dev/null
                if [ -f "$TMP/bw" ]; then
                    chmod +x "$TMP/bw"
                    mkdir -p "$HOME/bin"
                    mv "$TMP/bw" "$HOME/bin/"
                    rm -rf "$TMP"
                    echo "==> bw: installed"
                else
                    rm -rf "$TMP"
                    echo "==> bw: binary not found in archive"
                fi
            else
                rm -rf "$TMP" 2>/dev/null
                echo "==> bw: download failed"
            fi
        fi
        if ! command -v bw &>/dev/null; then
            if command -v npm &>/dev/null; then
                echo "==> bw: installing via npm @bitwarden/cli"
                npm install -g @bitwarden/cli
            elif command -v bun &>/dev/null; then
                echo "==> bw: installing via bun @bitwarden/cli"
                bun add -g @bitwarden/cli
            else
                echo "==> bw: ERROR — install npm or bun first"
                exit 1
            fi
        fi
    fi
fi
echo "bw: $(bw --version 2>&1)"

# ── 5. Install cloudflared ──────────────────────────────────────────
if ! command -v cloudflared &>/dev/null; then
    echo "==> Installing cloudflared..."
    if $BREW_OK; then
        brew install cloudflared
    else
        ARCH=$(uname -m)
        if [ "$IS_MAC" = true ]; then
            case "$ARCH" in arm64) CF_FILE="cloudflared-darwin-arm64.tgz" ;; *) CF_FILE="cloudflared-darwin-amd64.tgz" ;; esac
            echo "==> cloudflared: downloading ${CF_FILE}"
            TMP=$(mktemp -d)
            curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/${CF_FILE}" | tar xzf - -C "$TMP"
            chmod +x "$TMP/cloudflared"
            mkdir -p "$HOME/bin"
            mv "$TMP/cloudflared" "$HOME/bin/"
            rm -rf "$TMP"
        else
            case "$ARCH" in
                x86_64)  CF_DEB="cloudflared-linux-amd64.deb" ;;
                aarch64) CF_DEB="cloudflared-linux-arm64.deb" ;;
                armv7l)  CF_DEB="cloudflared-linux-armhf.deb" ;;
                *)       CF_DEB="cloudflared-linux-amd64.deb" ;;
            esac
            echo "==> cloudflared: installing ${CF_DEB}"
            TMP=$(mktemp -d)
            if curl -fsSL -o "$TMP/cloudflared.deb" "https://github.com/cloudflare/cloudflared/releases/latest/download/${CF_DEB}" 2>/dev/null; then
                if command -v sudo &>/dev/null; then
                    sudo dpkg -i "$TMP/cloudflared.deb" 2>/dev/null || sudo apt-get install -f -y 2>/dev/null
                else
                    dpkg -i "$TMP/cloudflared.deb" 2>/dev/null
                fi
            fi
            rm -rf "$TMP"
            # Fallback to binary download if dpkg not available
            if ! command -v cloudflared &>/dev/null; then
                echo "  Falling back to binary download..."
                CF_BIN="cloudflared-linux-${CF_DEB##*-}"
                curl -fsSL -o "$HOME/bin/cloudflared" "https://github.com/cloudflare/cloudflared/releases/latest/download/${CF_BIN}" 2>/dev/null
                chmod +x "$HOME/bin/cloudflared" 2>/dev/null
            fi
        fi
    fi
    echo "cloudflared: $(cloudflared --version 2>&1 | head -1)"
fi

# ── 6. Generate deploy key ──────────────────────────────────────────
if [ ! -f "$DEPLOY_KEY" ]; then
    echo "==> Generating deploy key..."
    mkdir -p "$(dirname "$DEPLOY_KEY")"
    ssh-keygen -t ed25519 -f "$DEPLOY_KEY" -N "" -C "chezmoi@$(hostname)"
    chmod 600 "$DEPLOY_KEY"
    chmod 644 "${DEPLOY_KEY}.pub"
    echo "Key: $(ssh-keygen -l -f "${DEPLOY_KEY}.pub" | awk '{print $2}')"
fi

# ── 7. Authenticate gh (one-time) ───────────────────────────────────
if ! gh auth status &>/dev/null; then
    echo ""
    echo "==> GitHub auth required"
    echo ""
    echo "Option A (recommended): Run 'gh auth login' on a machine with a browser,"
    echo "  then paste the token here (never expires):"
    echo "  $ gh auth login --scopes repo"
    echo ""
    echo "Option B: Create a PAT at https://github.com/settings/tokens"
    echo "  Required scopes: repo (full control)"
    echo ""
    echo ""
    gh auth login --with-token
fi

# ── 8. Register deploy key on GitHub ────────────────────────────────
echo "==> Registering deploy key..."
gh repo deploy-key add "${DEPLOY_KEY}.pub" --repo phillias/dotfiles --title "chezmoi@$(hostname)" --allow-write 2>/dev/null || echo "Key may already exist"

# ── 9. Select profile branch ────────────────────────────────────────
echo ""
echo "Which profile do you want to use?"
echo "  1) master  — shared configs only (no SSH keys or API keys)"
echo "  2) personal — personal SSH keys and API keys"
echo "  3) work     — work SSH keys and API keys"
read -rp "Enter choice [1-3]: " BRANCH_CHOICE
case "$BRANCH_CHOICE" in
    1) BRANCH="master" ;;
    2) BRANCH="personal" ;;
    3) BRANCH="work" ;;
    *) echo "Invalid choice, defaulting to master"; BRANCH="master" ;;
esac
echo "Using branch: $BRANCH"

# ── 10. Bitwarden login (interactive) ────────────────────────────────
echo ""
echo "==> Bitwarden login required"
bw login phillias@gmail.com
export BW_SESSION=$(bw unlock --raw)

# ── 11. Clone dotfiles repo ─────────────────────────────────────────
if [ ! -d "$CHEZMOI_DIR" ]; then
    echo "==> Cloning dotfiles (branch: $BRANCH)..."
    GIT_SSH_COMMAND="ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes" chezmoi init --branch "$BRANCH" git@github.com:phillias/dotfiles.git
fi

# ── 12. Register deploy key for SSH access ──────────────────────────
DEPLOY_PUB=$(cat "${DEPLOY_KEY}.pub")
if ! grep -qF "$DEPLOY_PUB" ~/.ssh/authorized_keys 2>/dev/null; then
    echo "$DEPLOY_PUB" >> ~/.ssh/authorized_keys
    echo "Deploy key added to authorized_keys"
fi

# ── 13. Apply dotfiles ─────────────────────────────────────────────
echo "==> Applying dotfiles..."
BW_SESSION="$BW_SESSION" chezmoi apply

# ── 14. Decrypt age encryption key ─────────────────────────────────
AGE_KEY_FILE="$HOME/.config/chezmoi/key.txt"
if [ ! -f "$AGE_KEY_FILE" ]; then
    echo ""
    echo "==> Age encryption (Bitwarden: Chezmoi Age Key)"
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
    echo "Age key already present, skipping"
fi

# ── 15. Write chezmoi config ────────────────────────────────────────
if [ -f "$AGE_KEY_FILE" ]; then
    AGE_PUB=$(chezmoi data --format=json 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('chezmoi',{}).get('config',{}).get('age',{}).get('recipient',''))
" 2>/dev/null || echo "age1p5cu2lhvhjxq2rkzxlgk9ekknr3ang7n5nla5pst94ckm8jmmq9sp66mc5")
    mkdir -p "$HOME/.config/chezmoi"
    cat > "$HOME/.config/chezmoi/chezmoi.toml" << AGEEOF
encryption = "age"
[age]
    identity = "~/.config/chezmoi/key.txt"
    recipient = "$AGE_PUB"
AGEEOF
    echo "chezmoi.toml written"
fi

# ── 16. Full apply ──────────────────────────────────────────────────
echo ""
echo "==> Full apply..."
BW_SESSION=$(bw unlock --raw) chezmoi apply

# ── 17. Register in inventory ───────────────────────────────────────
if [ -f "$CHEZMOI_DIR/.chezmoi-inventory.json" ]; then
    python3 -c "
import json,subprocess,datetime
f='$CHEZMOI_DIR/.chezmoi-inventory.json'
with open(f) as fh: inv=json.load(fh)
h=subprocess.check_output(['hostname']).decode().strip()
n=datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
s=subprocess.check_output
inv.setdefault('servers',{})[h]={'hostname':h,'username':s(['whoami']).decode().strip(),'os':s(['uname','-s']).decode().strip().lower(),'arch':s(['uname','-m']).decode().strip(),'deploy_key_title':'chezmoi@'+h,'first_seen':inv.get('servers',{}).get(h,{}).get('first_seen',n),'last_sync':n,'status':'active'}
with open(f,'w') as fh: json.dump(inv,fh,indent=2)
print('Inventory: '+h)
"
fi

# ── 18. Auto-sync ───────────────────────────────────────────────────
if $IS_MAC; then
    echo "===> macOS: use launchd for auto-sync"
else
    L="*/30 * * * * export PATH=\$HOME/bin:\$HOME/.local/bin:\$PATH; export BW_SESSION=\$(bw unlock --raw 2>/dev/null); chezmoi update >> \$HOME/.local/share/chezmoi/.chezmoi-sync.log 2>&1"
    if ! crontab -l 2>/dev/null | grep -q "chezmoi update"; then
        (crontab -l 2>/dev/null; echo "$L") | crontab -
        echo "Cron: chezmoi update every 30 min"
    fi
fi

# ── 19. Verify ──────────────────────────────────────────────────────
echo ""
echo "=== Verification ==="
if chezmoi verify 2>/dev/null; then echo "OK"; else echo "WARN: differences"; fi
echo ""
chezmoi managed
echo ""
for k in id_ed25519 id_ed25519_inspironkali id_ed25519_kali id_ed25519_oraclecloud id_ed25519_huggingface; do
    [ -f "$HOME/.ssh/$k" ] && echo "  $k: OK" || echo "  $k: MISSING"
done
echo ""
echo "=== Done ==="
