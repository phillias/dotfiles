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
#   5. Bitwarden Secrets Manager (bws machine token)
#   6. Age key decryption (auto from BWS, fallback to manual)
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
    echo "==> GitHub auth required (PAT only)"
    echo "Create at: https://github.com/settings/tokens (scope: repo)"
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
BRANCH="master"
echo "Using profile: master"

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
# Phase 5 — Bitwarden Secrets Manager (bws)
# ═══════════════════════════════════════════════════════════════════
#
# Uses bws machine tokens for authentication instead of bw login/unlock.
# Token is stored at ~/.agents/keys/default/.bws-token for reuse.

# ── 12. Bitwarden Secrets Manager authentication ────────────────
echo ""
echo "==> Bitwarden Secrets Manager authentication"
echo ""

BWS_TOKEN_FILE="$HOME/.agents/keys/default/.bws-token"
BWS_AUTHENTICATED=false

# Check if token file exists and is non-empty
if [ -f "$BWS_TOKEN_FILE" ] && [ -s "$BWS_TOKEN_FILE" ]; then
    export BWS_ACCESS_TOKEN=$(cat "$BWS_TOKEN_FILE")
    if bws project list 2>/dev/null | head -1 | grep -q .; then
        BWS_AUTHENTICATED=true
    fi
fi

if $BWS_AUTHENTICATED; then
    echo "Bitwarden Secrets Manager: authenticated"
else
    read -rp "Paste BWS machine token (or press Ctrl+C to skip): " BWS_TOKEN </dev/tty
    if [ -n "$BWS_TOKEN" ]; then
        mkdir -p ~/.agents/keys/default
        printf '%s' "$BWS_TOKEN" > "$BWS_TOKEN_FILE"
        chmod 600 "$BWS_TOKEN_FILE"
        export BWS_ACCESS_TOKEN="$BWS_TOKEN"
        if bws project list 2>/dev/null | head -1 | grep -q .; then
            BWS_AUTHENTICATED=true
            echo "Bitwarden Secrets Manager: authenticated"
        else
            echo "WARN: BWS token verification failed. Age key decryption will fall back to manual prompt."
        fi
    else
        echo "WARN: Skipping Bitwarden Secrets Manager. Age key decryption will fall back to manual prompt."
    fi
fi

# ═══════════════════════════════════════════════════════════════════
# Phase 6 — Age key decryption
# ═══════════════════════════════════════════════════════════════════
#
# The age key (age-key.txt.age) is stored encrypted in the repo.
# Passphrase is fetched from Bitwarden Secrets Manager (bws).
# If bws is unavailable, prompt the user manually.

# ── 13. Decrypt age encryption key ──────────────────────────────
AGE_KEY_FILE="$HOME/.config/chezmoi/key.txt"
if [ ! -f "$AGE_KEY_FILE" ]; then
    echo ""
    echo "==> Age encryption key"
    echo "    The age key is encrypted in the dotfiles repo."
    echo "    Passphrase is fetched from Bitwarden Secrets Manager."
    echo ""

    mkdir -p "$(dirname "$AGE_KEY_FILE")"
    DECRYPTED=false

    # Auto-fetch passphrase from BWS if authenticated
    if [ -n "${BWS_ACCESS_TOKEN:-}" ]; then
        echo "--> Fetching passphrase from Bitwarden Secrets Manager..."
        BWS_PP=$(bws secret list fe9eea09-9eaf-45e6-a72f-b45e0150b29d 2>/dev/null | jq -r '.[] | select(.key | test("chezmoi.*age|age.*key"; "i")) | .value' 2>/dev/null | head -1) || true
        if [ -n "$BWS_PP" ]; then
            if DECRYPT_ERR=$(printf '%s\n' "$BWS_PP" | chezmoi age decrypt --passphrase --no-tty --output "$AGE_KEY_FILE" "$CHEZMOI_DIR/age-key.txt.age" 2>&1); then
                chmod 600 "$AGE_KEY_FILE"
                DECRYPTED=true
                echo "  Age key decrypted (passphrase from BWS)"
            else
                echo "  Auto-decrypt failed (passphrase in BWS may be incorrect)"
                echo "  Falling back to manual passphrase entry; decrypt reported:" >&2
                echo "  ${DECRYPT_ERR:-<no error output>}" >&2
                [ -f "$AGE_KEY_FILE" ] && rm -f "$AGE_KEY_FILE"
            fi
        else
            echo "  Secret not found in BWS project"
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
            if printf '%s\n' "$AGE_PP" | chezmoi age decrypt --passphrase --no-tty --output "$AGE_KEY_FILE" "$CHEZMOI_DIR/age-key.txt.age" 2>/dev/null; then
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
# Phase 6b — Fleet registration (self-service via PR)
# ═══════════════════════════════════════════════════════════════════
#
# chezmoi fail-closes on hosts missing from .chezmoidata/fleet.toml
# (.fleet.nodes). A new host registers itself here: a fleet.toml node
# entry plus its per-host restic password file are committed to a
# branch and opened as a PR against phillias/dotfiles. The captain's
# merge is the approval gate; setup waits for the merge, then falls
# through to chezmoi apply.
#
# Credentials: git push uses the per-host deploy key; PR creation uses
# the fine-grained GitHub token stored in BWS (project phillias,
# DOTFILES_SETUP_FLEET_REGISTRATION). The token is never echoed and is
# used only via the GH_TOKEN environment variable.

HN="$(hostname)"
FLEET_TOML="$CHEZMOI_DIR/.chezmoidata/fleet.toml"

if grep -qF "hostname = \"$HN\"" "$FLEET_TOML" 2>/dev/null; then
    echo "==> Fleet registry: $HN already registered"
else
    echo ""
    echo "==> Fleet registry: $HN is not registered yet"
    echo "    Setup will open a PR against phillias/dotfiles registering this"
    echo "    host; it must be merged before dotfiles can apply here."

    if [ ! -f "$AGE_KEY_FILE" ]; then
        echo "ERROR: age key is not decrypted; cannot encrypt this host's restic password." >&2
        echo "       Decrypt it first (Phase 6), then re-run setup.sh." >&2
        exit 1
    fi

    # ── PR credentials: BWS token, fallback to manual paste ────────
    GH_REG_TOKEN=""
    if [ -n "${BWS_ACCESS_TOKEN:-}" ]; then
        GH_REG_TOKEN=$(bws secret list fe9eea09-9eaf-45e6-a72f-b45e0150b29d 2>/dev/null \
            | jq -r '.[] | select(.key == "DOTFILES_SETUP_FLEET_REGISTRATION") | .value' 2>/dev/null \
            | head -1) || true
        if [ -n "$GH_REG_TOKEN" ] \
            && ! GH_TOKEN="$GH_REG_TOKEN" gh api user --jq .login &>/dev/null; then
            echo "WARN: BWS registration token rejected by GitHub" >&2
            GH_REG_TOKEN=""
        fi
    fi
    if [ -z "$GH_REG_TOKEN" ] && ! gh auth status &>/dev/null 2>&1; then
        echo "==> No BWS registration token; paste a GitHub PAT (repo scope):" >&2
        read -rp "GitHub token (or Ctrl+C to abort): " GH_REG_TOKEN </dev/tty
    fi
    if [ -z "$GH_REG_TOKEN" ] && ! gh auth status &>/dev/null 2>&1; then
        echo "ERROR: no GitHub credentials available for PR creation." >&2
        exit 1
    fi
    _gh() { if [ -n "$GH_REG_TOKEN" ]; then GH_TOKEN="$GH_REG_TOKEN" gh "$@"; else gh "$@"; fi; }

    # ── DNS domain for this host (data-driven mapping) ────────────
    read -rp "DNS domain for this host (e.g. phillias.net): " DNS_DOMAIN </dev/tty
    DNS_DOMAIN="$(echo "$DNS_DOMAIN" | tr -d '[:space:]')"
    if [ -z "$DNS_DOMAIN" ]; then
        echo "ERROR: DNS domain is required." >&2
        exit 1
    fi

    # ── Branch + fleet.toml entry ─────────────────────────────────
    BR_REG="fm/fleet-register-$HN"
    git -C "$CHEZMOI_DIR" checkout -B "$BR_REG" master
    printf '\n[fleet.nodes.%s]\nhostname = "%s"\ndns_domain = "%s"\n' "$HN" "$HN" "$DNS_DOMAIN" >> "$FLEET_TOML"

    # ── Per-host restic password (age-encrypted, armored) ─────────
    RECIPIENT=$(grep -oE 'recipient = "[^"]+"' "$CHEZMOI_DIR/.chezmoi.toml.tmpl" | head -1 | sed 's/.*"\(.*\)"/\1/')
    PW_ENC="$CHEZMOI_DIR/dot_config/private_fleet-backup/encrypted_private_restic-password-$HN.age"
    if [ ! -f "$PW_ENC" ]; then
        mkdir -p "$(dirname "$PW_ENC")"
        PW_TMP=$(mktemp)
        head -c 24 /dev/urandom | base64 | tr -d '\n' > "$PW_TMP"
        chmod 600 "$PW_TMP"
        if ! chezmoi age encrypt -r "$RECIPIENT" -o "$PW_ENC" "$PW_TMP" 2>/dev/null \
            && ! age -a -r "$RECIPIENT" -o "$PW_ENC" "$PW_TMP" 2>/dev/null; then
            rm -f "$PW_TMP" "$PW_ENC"
            echo "ERROR: could not age-encrypt the restic password." >&2
            exit 1
        fi
        rm -f "$PW_TMP"
        if ! grep -q "BEGIN AGE ENCRYPTED FILE" "$PW_ENC"; then
            echo "ERROR: encrypted password file is not armored; refusing to continue." >&2
            exit 1
        fi
        chmod 600 "$PW_ENC"
    fi

    # ── Commit, push, open PR ─────────────────────────────────────
    git -C "$CHEZMOI_DIR" add .chezmoidata/fleet.toml \
        "dot_config/private_fleet-backup/encrypted_private_restic-password-$HN.age"
    if ! git -C "$CHEZMOI_DIR" -c user.name="phillias" -c user.email="phillias@gmail.com" \
        commit -m "feat(fleet): register $HN in fleet registry" 2>/dev/null; then
        echo "ERROR: nothing to commit; registration edits failed." >&2
        exit 1
    fi
    if ! GIT_SSH_COMMAND="ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes" \
        git -C "$CHEZMOI_DIR" push -u origin "$BR_REG" 2>&1; then
        echo "ERROR: push failed. Re-run setup.sh after fixing; the local branch $BR_REG holds the registration." >&2
        exit 1
    fi

    PR_URL=$(_gh pr list --repo phillias/dotfiles --head "$BR_REG" --state open \
        --json url --jq '.[0].url' 2>/dev/null || true)
    if [ -z "$PR_URL" ]; then
        PR_URL=$(_gh pr create --repo phillias/dotfiles --base master --head "$BR_REG" \
            --title "feat(fleet): register $HN in fleet registry" \
            --body "Auto-registration from setup.sh on host $HN. Adds the fleet.toml node entry (hostname + dns_domain) and the per-host restic password file. Merging lets setup continue on the host." 2>&1) \
            || { echo "ERROR: PR creation failed: $PR_URL" >&2; exit 1; }
    fi
    echo "==> Registration PR: $PR_URL"

    # ── Wait for merge (captain approval gate) ────────────────────
    MERGED=false
    for _i in $(seq 1 60); do
        sleep 30
        STATE=$(_gh pr view "$PR_URL" --repo phillias/dotfiles --json state --jq .state 2>/dev/null || echo "")
        case "$STATE" in
            MERGED) MERGED=true; break ;;
            CLOSED) echo "ERROR: registration PR was closed without merging." >&2; exit 1 ;;
        esac
    done
    if ! $MERGED; then
        echo "ERROR: registration PR not merged within 30 minutes." >&2
        echo "       Re-run setup.sh once it is merged: $PR_URL" >&2
        exit 1
    fi
    echo "==> Registration PR merged"

    git -C "$CHEZMOI_DIR" checkout master
    git -C "$CHEZMOI_DIR" pull --no-edit
    git -C "$CHEZMOI_DIR" push origin --delete "$BR_REG" 2>/dev/null || true
    unset GH_REG_TOKEN
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

chezmoi apply $CHEZMOI_APPLY_OPTS

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
    L="*/30 * * * * /bin/sh -c \". \$HOME/.profile; chezmoi-sync-cron\""
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

# ── 19. Agent harness logins ─────────────────────────────────────
echo ""
echo "=== Agent harness logins ==="
echo "The fleet's dispatch pool expects these agent CLIs authenticated."
echo "Headless login commands are printed for any that still need one."
echo ""

MISSING_LOGINS=""

if command -v codex >/dev/null 2>&1; then
    if codex login status 2>&1 | grep -q "Not logged in"; then
        echo "  codex: NOT LOGGED IN — run: codex login"
        MISSING_LOGINS="$MISSING_LOGINS codex"
    else
        echo "  codex: OK"
    fi
else
    echo "  codex: not installed (skipped)"
fi

if command -v claude >/dev/null 2>&1; then
    if claude auth status 2>/dev/null | grep -q '"loggedIn": *true'; then
        echo "  claude: OK"
    else
        echo "  claude: NOT LOGGED IN — run: claude auth login"
        MISSING_LOGINS="$MISSING_LOGINS claude"
    fi
else
    echo "  claude: not installed (skipped)"
fi

if command -v muse >/dev/null 2>&1; then
    MUSE_AUTH="${XDG_CONFIG_HOME:-$HOME/.config}/muse/auth.json"
    if [ -n "$META_API_KEY" ] || [ -f "$MUSE_AUTH" ]; then
        echo "  muse: OK"
    else
        echo "  muse: NO CREDENTIALS — run: muse login (approve code in browser) or set META_API_KEY"
        MISSING_LOGINS="$MISSING_LOGINS muse"
    fi
else
    echo "  muse: not installed (skipped)"
fi

if command -v agy >/dev/null 2>&1; then
    AGY_TIMEOUT=""
    command -v timeout >/dev/null 2>&1 && AGY_TIMEOUT="timeout 20"
    if $AGY_TIMEOUT agy models 2>&1 | grep -qi "please sign in"; then
        echo "  agy: NOT SIGNED IN — run: agy (launch once and approve the browser auth URL)"
        MISSING_LOGINS="$MISSING_LOGINS agy"
    else
        echo "  agy: OK"
    fi
else
    echo "  agy: not installed (skipped)"
fi

if command -v kimi >/dev/null 2>&1; then
    if [ -f "$HOME/.kimi-code/credentials/kimi-code.json" ]; then
        echo "  kimi: OK"
    else
        echo "  kimi: NOT LOGGED IN — run: kimi login (device-code flow)"
        MISSING_LOGINS="$MISSING_LOGINS kimi"
    fi
else
    echo "  kimi: not installed (skipped)"
fi

if command -v grok >/dev/null 2>&1; then
    if [ -f "${GROK_HOME:-$HOME/.grok}/auth.json" ]; then
        echo "  grok: OK"
    else
        echo "  grok: NOT LOGGED IN — run: grok login"
        MISSING_LOGINS="$MISSING_LOGINS grok"
    fi
else
    echo "  grok: not installed (skipped)"
fi

echo ""
if [ -n "$MISSING_LOGINS" ]; then
    echo "  REQUIRED LOGINS PENDING:$MISSING_LOGINS"
    echo "  Complete them before dispatching crew work on this host."
else
    echo "  All installed harnesses authenticated."
fi
echo ""
echo "=== Done ==="
