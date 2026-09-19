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

# Ensure user-local bin directories are in PATH permanently for future shells
PATH_EXPORT='export PATH="$HOME/.local/bin:$HOME/bin:$PATH"'

for shell_rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$shell_rc" ]; then
        if ! grep -q '$HOME/.local/bin' "$shell_rc" 2>/dev/null; then
            echo "$PATH_EXPORT" >> "$shell_rc"
            echo "==> Updated PATH in $(basename "$shell_rc")"
        fi
    fi
done

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

# ── 2. cloudflared and chezmoi (mise-managed) ───────────────────
# Both tools are installed via mise from the committed manifest
# (dot_config/mise/config.toml). Bootstrap ordering: mise itself
# (Phase 1) comes first; cloudflared and chezmoi resolve via mise
# shims after manifest apply. Cleanup runs AFTER mise bootstrap
# to ensure the replacements are available.

# ── 3. Bootstrap mise — the one installer for manifest-managed CLIs ──
# gh, bw (@bitwarden/cli), wrangler, cloudflared, and chezmoi are installed
# and versioned by mise from the committed manifest (dot_config/mise/config.toml →
# ~/.config/mise/config.toml via chezmoi apply). mise itself must bootstrap
# first because the manifest apply depends on it.
if ! command -v mise &>/dev/null; then
    echo "==> Installing mise..."
    # Stated precedence: official installer first; brew only as a fallback
    # when the installer route can't run on the platform.
    if ! curl -fsSL https://mise.run | sh; then
        echo "WARNING: mise.run installer failed; trying brew fallback" >&2
    fi
    if ! command -v mise &>/dev/null && $BREW_OK; then
        brew install mise 2>/dev/null || true
    fi
    if ! command -v mise &>/dev/null; then
        echo "ERROR: mise install failed via mise.run and brew; later 'mise use -g' steps will fail. Install mise manually (curl -fsSL https://mise.run | sh) and re-run." >&2
    fi
fi
# mise shims first: manifest-managed tools (gh, bw, wrangler, ...) resolve here
export PATH="$HOME/.local/share/mise/shims:$PATH"
echo "mise: $(mise --version 2>&1 | head -1)"

# ── 3b. mise-managed tools (gh, bw, wrangler) ────────────────────
# Inline Phase-1 pins mirror the committed manifest exactly. Guarded by a
# grep of the existing global config so re-runs on a manifest-managed host
# never rewrite ~/.config/mise/config.toml; after Phase 7 applies chezmoi the
# committed manifest is the sole owner and replaces that file wholesale.
_mise_cfg="$HOME/.config/mise/config.toml"
_ensure_mise() {
    # _ensure_mise "<mise tool spec>" "<config.toml key regex>"
    if [ -f "$_mise_cfg" ] && grep -qE "$2 *=" "$_mise_cfg"; then
        echo "==> $1 already manifest-managed, skipping pin"
        return 0
    fi
    MISE_NPM__SHELL_OUT=true mise use -g --pin "$1"
}
_ensure_mise "gh@2.100.0" '^(gh|"github:cli/cli")'
_ensure_mise "npm:@bitwarden/cli@2026.5.0" '^"npm:@bitwarden/cli"'
_ensure_mise "npm:wrangler@4.125.0" '^"npm:wrangler"'
_ensure_mise "cloudflared@2025.9.0" '^cloudflared'
_ensure_mise "chezmoi@2.70.4" '^chezmoi'
echo "gh: $(gh --version 2>&1 | head -1)"
echo "bw: $(bw --version 2>&1 | head -1)"
echo "wrangler: $(wrangler --version 2>&1 | head -1)"
echo "cloudflared: $(cloudflared --version 2>&1 | head -1 || echo 'pending mise install')"
echo "chezmoi: $(chezmoi --version 2>&1 | head -1 || echo 'pending mise install')"

# Cleanup of pre-mise hand-installed copies — approved for all mise-managed tools
# (gh, bw, wrangler, cloudflared, chezmoi). Run AFTER mise bootstrap ensures
# replacements are available. System/OS-owned copies (dpkg/brew system prefixes)
# are never touched. Handle permission failures gracefully — don't abort setup.
for _old in "$HOME/bin/gh" "$HOME/bin/bw" "$HOME/bin/wrangler" \
             "$HOME/bin/cloudflared" "$HOME/bin/chezmoi" \
             "/usr/local/bin/cloudflared" "/usr/local/bin/chezmoi"; do
    if [ -f "$_old" ]; then
        if rm -f "$_old" 2>/dev/null; then
            echo "==> removed old hand-installed $(basename "$_old") (mise-managed now)"
        else
            echo "WARNING: could not remove $_old (may need sudo); it may remain as fallback" >&2
        fi
    fi
done

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

# ── 8b. Provision per-repo GitHub deploy keys (pirate, selfhost) ──
# Each additional repo (pirate, selfhost) gets its own minted ed25519 deploy
# key registered on its repo, plus a matching Host block managed in
# dot_ssh/config.tmpl (applied by chezmoi before this point). Extensible:
# append repos to DEPLOY_KEY_REPOS.
if gh auth status &>/dev/null 2>&1 && [ -d "$HOME/.ssh" ]; then
    DEPLOY_KEY_REPOS=(pirate selfhost)
    for REPO in "${DEPLOY_KEY_REPOS[@]}"; do
        RKEY="$HOME/.ssh/${REPO}-deploy-key"
        if [ ! -f "$RKEY" ]; then
            ssh-keygen -t ed25519 -f "$RKEY" -N "" -C "github-${REPO}-deploy-key@$(hostname)" >/dev/null
            chmod 600 "$RKEY"
            chmod 644 "${RKEY}.pub"
            echo "==> Minted $RKEY"
        fi
        local_res="$(grep -c "$(cut -d' ' -f2 "${RKEY}.pub")" < <(gh api "repos/phillias/${REPO}/keys" --jq '.[]?.key' 2>/dev/null) || true)"
        if [ "${local_res:-0}" -gt 0 ]; then
            echo "==> Deploy key for phillias/${REPO} already registered"
            continue
        fi
        if gh api "repos/phillias/${REPO}/keys" -f "key=$(cat "${RKEY}.pub")" -F read_only=false >/dev/null 2>&1 \
            || gh api "repos/phillias/${REPO}/keys" -f "key=$(cat "${RKEY}.pub")" -F read_only=false 2>&1 | grep -q "already in use"; then
            echo "==> Deploy key for phillias/${REPO} registered"
        else
            echo "WARN: could not register deploy key for phillias/${REPO} (retry later)"
        fi
    done
fi


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

# ── 10b. Pin deploy key for all future git operations ────────────
# Without this, chezmoi update / git fetch falls back to SSH config
# defaults which may use a different key without push access.
git -C "$CHEZMOI_DIR" config core.sshCommand "ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes"

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
    L="*/30 * * * * export PATH=\$HOME/bin:\$HOME/.local/bin:\$PATH; chezmoi-sync-cron"
    { { crontab -l 2>/dev/null || true; } | grep -Eiv 'chezmoi-sync-cron|chezmoi-axi sync.*chezmoi-sync\.log|chezmoi update >>.*chezmoi-sync\.log' || true; echo "$L"; } | crontab -
    echo "==> Cron: chezmoi-sync-cron every 30 min"
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
