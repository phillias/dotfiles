#!/usr/bin/env bash
# scripts/setup.sh — one-time bootstrap for a new server
# Usage: curl -fsSL https://raw.githubusercontent.com/phillias/dotfiles/master/scripts/setup.sh | bash
# NOTE: This is a ONE-TIME setup script, NOT a chezmoi-managed file.
#
# Phase structure:
#   0. Environment setup (PATH, OS detection)
#   1. Tool installation (chezmoi, gh, cloudflared, bw)
#   2. GitHub auth + deploy key
#   3. Profile selection
#   4. chezmoi init (clone dotfiles repo)
#   5. Bitwarden login + unlock
#   6. Age key decryption (auto from Bitwarden, fallback to manual)
#   7. chezmoi config + apply
#   8. Post-setup (inventory, cron, verify)

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

# Ensure ~/bin is in PATH permanently for future shells
if ! grep -q 'HOME/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
fi
if ! grep -q 'HOME/bin' "$HOME/.zshrc" 2>/dev/null; then
    echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.zshrc"
fi

# ═══════════════════════════════════════════════════════════════════
# Phase 1 — Tool installation
# ═══════════════════════════════════════════════════════════════════

# ── 1. Determine install method on macOS ──────────────────────────
BREW_OK=false
BREW_USER_PREFIX="$HOME/homebrew"
if $IS_MAC; then
    if [ -x "$BREW_USER_PREFIX/bin/brew" ]; then
        BREW_OK=true
        export PATH="$BREW_USER_PREFIX/bin:$PATH"
        echo "==> Using user-local Homebrew at $BREW_USER_PREFIX"
    elif command -v brew &>/dev/null; then
        BREW_PREFIX=$(brew --prefix 2>/dev/null || echo "/opt/homebrew")
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

# ── 2. Install chezmoi ───────────────────────────────────────────
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

# ── 3. Install GitHub CLI ────────────────────────────────────────
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
if command -v gh &>/dev/null; then
    echo "gh: $(gh --version 2>&1 | head -1)"
else
    echo "ERROR: gh install failed. Downloading binary directly..."
    GH_TAG=$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])" 2>/dev/null || echo "v2.76.0")
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  GA="linux_amd64.tar.gz" ;;
        aarch64) GA="linux_arm64.tar.gz" ;;
        *)       GA="linux_amd64.tar.gz" ;;
    esac
    TMP=$(mktemp -d)
    curl -fsSL -o "$TMP/gh.tar.gz" "https://github.com/cli/cli/releases/download/${GH_TAG}/gh_${GH_TAG#v}_${GA}"
    tar xzf "$TMP/gh.tar.gz" -C "$TMP"
    mkdir -p "$HOME/bin"
    cp "$TMP/gh" "$HOME/bin/"
    chmod +x "$HOME/bin/gh"
    rm -rf "$TMP"
    echo "gh: $(gh --version 2>&1 | head -1)"
fi

# ── 4. Install Bitwarden CLI ─────────────────────────────────────
if ! command -v bw &>/dev/null; then
    echo "==> Installing Bitwarden CLI..."
    if $BREW_OK; then
        brew install bitwarden-cli
    else
        ARCH=$(uname -m)
        BW_TAG=$(curl -fsSL "https://api.github.com/repos/bitwarden/clients/releases?per_page=10" 2>/dev/null | python3 -c "
import sys,json
for r in json.load(sys.stdin):
    if r['tag_name'].startswith('cli-'):
        print(r['tag_name'])
        break
" 2>/dev/null || echo "")
        if [ -n "$BW_TAG" ]; then
            BW_VERSION="${BW_TAG#cli-}"
            BW_VERSION="${BW_VERSION#v}"
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

# ── 5. Install cloudflared ───────────────────────────────────────
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

# ═══════════════════════════════════════════════════════════════════
# Phase 2 — GitHub auth + deploy key
# ═══════════════════════════════════════════════════════════════════

# ── 6. Generate deploy key ───────────────────────────────────────
if [ ! -f "$DEPLOY_KEY" ]; then
    echo "==> Generating deploy key..."
    mkdir -p "$(dirname "$DEPLOY_KEY")"
    ssh-keygen -t ed25519 -f "$DEPLOY_KEY" -N "" -C "chezmoi@$(hostname)"
    chmod 600 "$DEPLOY_KEY"
    chmod 644 "${DEPLOY_KEY}.pub"
    echo "Key: $(ssh-keygen -l -f "${DEPLOY_KEY}.pub" | awk '{print $2}')"
fi

# ── 7. Authenticate gh (one-time) ────────────────────────────────
if ! command -v gh &>/dev/null; then
    echo "ERROR: gh is not installed. This should not happen."
    exit 1
fi
GH_AUTHENTICATED=false
if gh auth status &>/dev/null 2>&1; then
    GH_AUTHENTICATED=true
elif [ -f "$HOME/.config/gh/hosts.yml" ] && grep -qE "oauth_token|user:" "$HOME/.config/gh/hosts.yml" 2>/dev/null; then
    GH_AUTHENTICATED=true
fi
if $GH_AUTHENTICATED; then
    echo "==> GitHub already authenticated"
else
    echo ""
    echo "==> GitHub auth required"
    echo ""
    echo "Option A: Run 'gh auth login' in another terminal first, then re-run this script."
    echo "  $ gh auth login --scopes repo"
    echo ""
    echo "Option B: Paste a PAT or OAuth token below."
    echo "  Create at: https://github.com/settings/tokens (scope: repo)"
    echo ""
    read -rp "Paste GitHub token (or press Ctrl+C to skip): " GH_TOKEN </dev/tty
    if [ -n "$GH_TOKEN" ]; then
        echo "$GH_TOKEN" | gh auth login --with-token 2>/dev/null || {
            echo "WARN: gh auth failed. You can authenticate later with: gh auth login"
        }
    else
        echo "WARN: Skipping GitHub auth. Run 'gh auth login' later."
    fi
fi

# ── 8. Register deploy key on GitHub ─────────────────────────────
echo "==> Registering deploy key..."
gh repo deploy-key add "${DEPLOY_KEY}.pub" --repo phillias/dotfiles --title "chezmoi@$(hostname)" --allow-write 2>/dev/null || echo "  Key may already exist"

# ═══════════════════════════════════════════════════════════════════
# Phase 3 — Profile selection
# ═══════════════════════════════════════════════════════════════════

# ── 9. Select profile branch ─────────────────────────────────────
echo ""
echo "Which profile do you want to use?"
echo "  1) master  — shared configs only (no SSH keys or API keys)"
echo "  2) personal — personal SSH keys and API keys"
echo "  3) work     — work SSH keys and API keys"
read -rp "Enter choice [1-3]: " BRANCH_CHOICE </dev/tty
BRANCH="master"
case "${BRANCH_CHOICE}" in
    1)  BRANCH="master" ;;
    2)  BRANCH="personal" ;;
    3)  BRANCH="work" ;;
    *)  BRANCH="master" ;;
esac
echo "Using branch: $BRANCH"

# ═══════════════════════════════════════════════════════════════════
# Phase 4 — chezmoi init (clone dotfiles repo)
# ═══════════════════════════════════════════════════════════════════

# ── 10. Clone dotfiles repo ─────────────────────────────────────
if [ ! -d "$CHEZMOI_DIR" ]; then
    echo "==> Cloning dotfiles..."
    GIT_SSH_COMMAND="ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes" chezmoi init git@github.com:phillias/dotfiles.git
fi

# ── 11. Register deploy key for SSH access ───────────────────────
DEPLOY_PUB=$(cat "${DEPLOY_KEY}.pub")
if ! grep -qF "$DEPLOY_PUB" ~/.ssh/authorized_keys 2>/dev/null; then
    echo "$DEPLOY_PUB" >> ~/.ssh/authorized_keys
    echo "  Deploy key added to authorized_keys"
fi

# ═══════════════════════════════════════════════════════════════════
# Phase 5 — Bitwarden login + unlock
# ═══════════════════════════════════════════════════════════════════
#
# Key fix: bw unlock --raw output is captured via temp file instead
# of $() to avoid TTY buffering issues (double-Enter + ghost prompt).
# bw status is checked first to skip login if already authenticated.

# ── 12. Bitwarden authentication ────────────────────────────────
echo ""
echo "==> Bitwarden authentication"
echo ""

unset BW_SESSION

# Check if already logged in (non-interactive, safe for $())
BW_STATUS=$(bw status 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unauthenticated'))" 2>/dev/null || echo "unauthenticated")

if [ "$BW_STATUS" = "unauthenticated" ]; then
    echo "--> Logging in to Bitwarden..."
    echo "    You will be prompted for:"
    echo "      1. Master password"
    echo "      2. Verification code (sent to phillias@gmail.com)"
    echo ""
    # Run bw login in the foreground — user interacts directly via /dev/tty
    bw login phillias@gmail.com || {
        echo "WARN: Bitwarden login failed. You can set it up later with:"
        echo "  bw login phillias@gmail.com"
        echo "  export BW_SESSION=\$(bw unlock --raw)"
        echo ""
    }
else
    echo "--> Already logged in to Bitwarden"
fi

# ── 12b. For CRON automation: Bitwarden API key login (non-interactive)
# The cron runs 'bw unlock --raw' which needs a persisted session.
# Standard login expires; use an API key for permanent non-interactive access.
# Get API key from: Bitwarden Web Vault → Settings → Security → Keys → View API Key
echo ""
echo "==> For automated cron sync (non-interactive):"
echo "    The cron uses 'bw unlock --raw' which requires a persisted login."
echo "    Standard login expires; use 'bw login --apikey' for permanent access."
echo ""
echo "    Get API key from:"
echo "      Bitwarden Web Vault → Settings → Security → Keys → View API Key"
echo ""
echo "    Then run ONCE on this machine:"
echo "      bw logout          # if already logged in with master password"
echo "      bw login --apikey  # paste the API key when prompted"
echo ""
echo "    After this, 'bw unlock --raw' works in cron without TTY/password."
echo ""
read -rp "Configure API key login now? [y/N]: " CONFIG_APIKEY </dev/tty
if [ "$CONFIG_APIKEY" = "y" ] || [ "$CONFIG_APIKEY" = "Y" ]; then
    echo "--> Logging out existing session (if any)..."
    bw logout 2>/dev/null || true
    echo "--> Logging in with API key..."
    bw login --apikey
    echo "--> Testing unlock..."
    BW_SESSION=$(bw unlock --raw) || true
    if [ -n "$BW_SESSION" ]; then
        echo "  ✓ API key login configured and working"
    else
        echo "  WARN: API key login may not be working; check credentials"
    fi
fi

# Unlock vault — capture session key via temp file, NOT $()
# This avoids the stdin buffering that causes double-Enter and ghost prompts.
echo "--> Unlocking vault..."
BW_SESSION_FILE=$(mktemp /tmp/bw-session-XXXXXXXX)
# bw unlock --raw reads password/2FA from /dev/tty directly (interactive)
# stdout (session key) → temp file, stderr → terminal (prompts visible)
bw unlock --raw > "$BW_SESSION_FILE" || true
BW_SESSION=$(head -1 "$BW_SESSION_FILE" 2>/dev/null | tr -d '\n\r' || true)
rm -f "$BW_SESSION_FILE"

if [ -z "$BW_SESSION" ]; then
    echo ""
    echo "WARN: Bitwarden unlock failed. Templates using bw_secret will not render."
    echo "      Fix it later with:"
    echo "        export BW_SESSION=\$(bw unlock --raw)"
    echo "        BW_SESSION=\"\$BW_SESSION\" chezmoi apply"
    echo ""
fi

# ═══════════════════════════════════════════════════════════════════
# Phase 6 — Age key decryption
# ═══════════════════════════════════════════════════════════════════
#
# The age key (age-key.txt.age) is stored encrypted in the repo.
# Passphrase is in Bitwarden (item: "Chezmoi Age Key", password field).
# If Bitwarden is available, fetch the passphrase automatically.
# Otherwise, prompt the user manually.

# ── 13. Decrypt age encryption key ──────────────────────────────
AGE_KEY_FILE="$HOME/.config/chezmoi/key.txt"
if [ ! -f "$AGE_KEY_FILE" ]; then
    echo ""
    echo "==> Age encryption key"
    echo "    The age key is encrypted in the dotfiles repo."
    echo "    Passphrase is in Bitwarden: search 'Chezmoi Age Key'"
    echo ""

    mkdir -p "$(dirname "$AGE_KEY_FILE")"
    DECRYPTED=false

    # Auto-fetch passphrase from Bitwarden if logged in
    if [ -n "${BW_SESSION:-}" ]; then
        echo "--> Fetching passphrase from Bitwarden..."
        FETCHED_PP=$(BW_SESSION="$BW_SESSION" bw list items --search "Chezmoi Age Key" 2>/dev/null | python3 -c "
import sys, json
try:
    for item in json.load(sys.stdin):
        pwd = item.get('login', {}).get('password', '')
        name = item.get('name', '')
        if pwd and ('chezmoi' in name.lower() or 'age' in name.lower()):
            print(pwd)
            break
except: pass
" 2>/dev/null) || true
        if [ -n "$FETCHED_PP" ]; then
            if printf '%s\n' "$FETCHED_PP" | chezmoi age decrypt --passphrase --output "$AGE_KEY_FILE" "$CHEZMOI_DIR/age-key.txt.age" 2>/dev/null; then
                chmod 600 "$AGE_KEY_FILE"
                DECRYPTED=true
                echo "  Age key decrypted (passphrase from Bitwarden)"
            else
                echo "  Auto-decrypt failed (passphrase in Bitwarden may be incorrect)"
                [ -f "$AGE_KEY_FILE" ] && rm -f "$AGE_KEY_FILE"
            fi
        else
            echo "  Item not found in vault (expected name: 'Chezmoi Age Key')"
        fi
    fi

    # Fallback: manual passphrase entry
    if ! $DECRYPTED; then
        echo "  Enter passphrase manually (or press Enter to skip):"
        for attempt in 1 2 3; do
            read -rp "  Passphrase (attempt $attempt/3): " AGE_PP </dev/tty
            AGE_PP="$(echo "$AGE_PP" | tr -d '[:space:]')"
            if [ -z "$AGE_PP" ]; then
                echo "  Skipped. Decrypt later:"
                echo "    chezmoi age decrypt --passphrase -o ~/.config/chezmoi/key.txt ~/.local/share/chezmoi/age-key.txt.age"
                break
            fi
            if printf '%s\n' "$AGE_PP" | chezmoi age decrypt --passphrase --output "$AGE_KEY_FILE" "$CHEZMOI_DIR/age-key.txt.age" 2>/dev/null; then
                chmod 600 "$AGE_KEY_FILE"
                DECRYPTED=true
                echo "  Age key decrypted"
                break
            else
                echo "  Incorrect passphrase."
                AGE_PP=""
                [ -f "$AGE_KEY_FILE" ] && rm -f "$AGE_KEY_FILE"
            fi
        done
    fi

    if ! $DECRYPTED; then
        echo ""
        echo "WARN: Age key not decrypted. Encrypted dotfiles will be skipped."
        echo "      Decrypt later:"
        echo "        chezmoi age decrypt --passphrase -o ~/.config/chezmoi/key.txt"
        echo "          ~/.local/share/chezmoi/age-key.txt.age"
        echo "        chmod 600 ~/.config/chezmoi/key.txt"
        echo "        # Then re-run: chezmoi apply"
    fi
else
    echo "Age key already present, skipping"
fi

# ═══════════════════════════════════════════════════════════════════
# Phase 7 — chezmoi config + apply
# ═══════════════════════════════════════════════════════════════════
#
# chezmoi.toml is written with encryption config conditionally:
# identity line only added when key.txt exists.

# ── 14. Write chezmoi config ─────────────────────────────────────
echo ""
mkdir -p "$HOME/.config/chezmoi"
if [ -f "$AGE_KEY_FILE" ]; then
    cat > "$HOME/.config/chezmoi/chezmoi.toml" << 'EOF'
encryption = "age"
[age]
    identity = "~/.config/chezmoi/key.txt"
    recipient = "age1p5cu2lhvhjxq2rkzxlgk9ekknr3ang7n5nla5pst94ckm8jmmq9sp66mc5"
EOF
    echo "==> chezmoi.toml written (age encryption enabled)"
else
    cat > "$HOME/.config/chezmoi/chezmoi.toml" << 'EOF'
# Age encryption is not configured — identity file not yet decrypted.
# To enable: chezmoi age decrypt --passphrase -o ~/.config/chezmoi/key.txt
#   ~/.local/share/chezmoi/age-key.txt.age
# Then uncomment the lines below and re-run chezmoi apply.
#
# encryption = "age"
# [age]
#     identity = "~/.config/chezmoi/key.txt"
#     recipient = "age1p5cu2lhvhjxq2rkzxlgk9ekknr3ang7n5nla5pst94ckm8jmmq9sp66mc5"
EOF
    echo "==> chezmoi.toml written (age encryption disabled — key not decrypted)"
fi

# ── 15. Apply dotfiles ───────────────────────────────────────────
echo ""
echo "==> Applying dotfiles..."

CHEZMOI_APPLY_OPTS=""
if [ ! -f "$AGE_KEY_FILE" ]; then
    echo "  (age key not decrypted — encrypted files will be skipped)"
    CHEZMOI_APPLY_OPTS="--keep-going"
fi

if [ -n "${BW_SESSION:-}" ]; then
    echo "  (Bitwarden session available — bw_secret templates will render)"
    BW_SESSION="$BW_SESSION" chezmoi apply $CHEZMOI_APPLY_OPTS
else
    chezmoi apply $CHEZMOI_APPLY_OPTS
fi

# ═══════════════════════════════════════════════════════════════════
# Phase 8 — Post-setup
# ═══════════════════════════════════════════════════════════════════

# ── 16. Register in inventory ────────────────────────────────────
echo ""
echo "==> Registering this host in inventory..."
INVENTORY_FILE="$CHEZMOI_DIR/.chezmoi-inventory.json"
python3 -c "
import json, subprocess, datetime, os

f = '$INVENTORY_FILE'
h = subprocess.check_output(['hostname']).decode().strip()
u = subprocess.check_output(['whoami']).decode().strip()
os_str = subprocess.check_output(['uname', '-s']).decode().strip().lower()
arch = subprocess.check_output(['uname', '-m']).decode().strip()
n = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
branch = '$BRANCH'

if os.path.exists(f):
    with open(f) as fh:
        inv = json.load(fh)
else:
    inv = {'version': 1, 'servers': {}}

entry = inv.setdefault('servers', {}).get(h, {})
first_seen = entry.get('first_seen', n)

inv['servers'][h] = {
    'hostname': h,
    'username': u,
    'os': os_str,
    'arch': arch,
    'profile': branch,
    'first_seen': first_seen,
    'last_sync': n,
    'status': 'active'
}

with open(f, 'w') as fh:
    json.dump(inv, fh, indent=2)
print('  Host: ' + h)
"

# Commit and push inventory change back to master via deploy key
GIT_SSH_COMMAND="ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes" \
    git -C "$CHEZMOI_DIR" add .chezmoi-inventory.json
GIT_SSH_COMMAND="ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes" \
    git -C "$CHEZMOI_DIR" -c user.name="phillias" -c user.email="phillias@gmail.com" \
    commit -m "Register $(hostname) in inventory" 2>/dev/null || true
GIT_SSH_COMMAND="ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes" \
    git -C "$CHEZMOI_DIR" push origin HEAD:master 2>/dev/null || \
    echo "WARN: inventory push failed (will retry on next sync)"

# ── 17. Auto-sync ────────────────────────────────────────────────
if $IS_MAC; then
    echo "==> macOS: use launchd for auto-sync"
else
    L="*/30 * * * * export PATH=\$HOME/bin:\$HOME/.local/bin:\$PATH; export BW_SESSION=\$(bw unlock --raw 2>/dev/null); chezmoi update >> \$HOME/.local/share/chezmoi/.chezmoi-sync.log 2>&1"
    if ! crontab -l 2>/dev/null | grep -q "chezmoi update"; then
        (crontab -l 2>/dev/null; echo "$L") | crontab -
        echo "==> Cron: chezmoi update every 30 min"
    fi
fi

# ── 18. Verify ───────────────────────────────────────────────────
echo ""
echo "=== Verification ==="
if chezmoi verify 2>/dev/null; then echo "  OK"; else echo "  WARN: differences found"; fi
echo ""
chezmoi managed
echo ""
for k in id_ed25519 id_ed25519_inspironkali id_ed25519_kali id_ed25519_oraclecloud id_ed25519_huggingface; do
    [ -f "$HOME/.ssh/$k" ] && echo "  $k: OK" || echo "  $k: MISSING"
done
echo ""
echo "=== Done ==="
