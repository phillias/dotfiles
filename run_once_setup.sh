#!/usr/bin/env bash
# run_once_setup.sh — bootstrap chezmoi + dotfiles on a new server
# Usage: curl -fsSL https://raw.githubusercontent.com/phillias/dotfiles/master/run_once_setup.sh | bash
#
# Prerequisites: git, curl, unzip, expect
# Works on: Debian/Ubuntu/Kali, Fedora/RHEL, Alpine

set -euo pipefail

export PATH="$HOME/bin:$HOME/.local/bin:$PATH"
CHEZMOI_DIR="$HOME/.local/share/chezmoi"

echo "=== phillias/dotfiles bootstrap ==="

# ── 1. Install chezmoi ──────────────────────────────────────────────
if ! command -v chezmoi &>/dev/null; then
    echo "==> Installing chezmoi..."
    BINDIR="$HOME/bin" sh -c "$(curl -fsLS get.chezmoi.io)"
fi
echo "chezmoi: $(chezmoi --version 2>&1 | head -1)"

# ── 2. Install Bitwarden CLI ────────────────────────────────────────
if ! command -v bw &>/dev/null; then
    echo "==> Installing Bitwarden CLI..."
    tmpdir=$(mktemp -d)
    curl -fsSL -o "$tmpdir/bw.zip" \
        "https://github.com/bitwarden/clients/releases/download/cli-v2025.2.0/bw-linux-2025.2.0.zip"
    unzip -o "$tmpdir/bw.zip" -d "$tmpdir"
    chmod +x "$tmpdir/bw"
    mkdir -p "$HOME/bin"
    mv "$tmpdir/bw" "$HOME/bin/"
    rm -rf "$tmpdir"
fi
echo "bw: $(bw --version 2>&1)"

# ── 3. Clone dotfiles repo ──────────────────────────────────────────
if [ ! -d "$CHEZMOI_DIR" ]; then
    echo "==> Cloning dotfiles repo..."
    chezmoi init git@github.com:phillias/dotfiles.git
fi

# ── 4. Bitwarden login (interactive) ────────────────────────────────
echo ""
echo "==> Bitwarden login required (for API keys + SSH keys)"
bw login phillias@gmail.com
export BW_SESSION=$(bw unlock --raw)

# ── 5. First apply — renders Bitwarden templates (.zshrc) ───────────
echo "==> Applying dotfiles (Bitwarden secrets)..."
chezmoi apply

# ── 6. Decrypt age encryption key ───────────────────────────────────
#     The age passphrase is stored in your Bitwarden vault.
#     Open vault.bitwarden.com -> search "Age Encryption Passphrase"
#     or retrieve it from the Age Public Key field.
echo ""
echo "==> Age encryption setup"
echo "    The SSH private keys in this repo are age-encrypted."
echo "    You need the age passphrase to decrypt them."
echo "    Find it in Bitwarden: search 'Age Encryption Passphrase'"
echo "    (It's in a hidden field — click 'reveal' in the web vault)"
echo ""

# Prompt for the age passphrase
read -rsp "Enter age passphrase from Bitwarden: " AGE_PASSPHRASE
echo ""

if [ -n "$AGE_PASSPHRASE" ]; then
    AGE_KEY_FILE="$HOME/.config/chezmoi/key.txt"
    mkdir -p "$(dirname "$AGE_KEY_FILE")"

    if [ ! -f "$AGE_KEY_FILE" ]; then
        expect << EXPECTEOF
set timeout 10
spawn chezmoi age decrypt --passphrase --output "$AGE_KEY_FILE" "$CHEZMOI_DIR/age-key.txt.age"
expect "Enter passphrase:"
send "$AGE_PASSPHRASE\r"
expect "Confirm passphrase:"
send "$AGE_PASSPHRASE\r"
expect eof
EXPECTEOF
        chmod 600 "$AGE_KEY_FILE"
        echo "Age key decrypted"
    fi

    # Get public key from the encrypted file header or hardcode it
    AGE_PUB=$(chezmoi data 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    # Try to get from chezmoi data
    print(d.get('age', {}).get('recipient', ''))
except:
    pass
" 2>/dev/null || echo "")

    if [ -z "$AGE_PUB" ]; then
        # Fallback: extract public key from the age encrypted file
        # or just prompt
        read -rp "Enter age public key (or press Enter to skip): " AGE_PUB
    fi

    # Write chezmoi config
    if [ -n "$AGE_PUB" ]; then
        cat > "$HOME/.config/chezmoi/chezmoi.toml" << AGECONF
encryption = "age"
[age]
    identity = "~/.config/chezmoi/key.txt"
    recipient = "$AGE_PUB"
AGECONF
        echo "chezmoi.toml written"
    else
        echo "WARN: chezmoi.toml not written (no public key)"
    fi
else
    echo "WARN: No passphrase entered. SSH keys will not be decrypted."
    echo "      Run manually later:"
    echo "      chezmoi age decrypt --passphrase --output ~/.config/chezmoi/key.txt \\"
    echo "        ~/.local/share/chezmoi/age-key.txt.age"
fi

# ── 7. Full apply (age-decrypt SSH keys + render all templates) ─────
echo ""
echo "==> Full apply..."
export BW_SESSION=$(bw unlock --raw 2>/dev/null) || true
chezmoi apply

# ── 8. Verify ───────────────────────────────────────────────────────
echo ""
echo "=== Verification ==="
chezmoi verify 2>/dev/null && echo "OK: All files verified" || echo "WARN: Some files differ"
echo ""
echo "=== Managed files ==="
chezmoi managed
echo ""
echo "=== SSH key status ==="
for key in id_ed25519 id_ed25519_inspironkali id_ed25519_kali id_ed25519_oraclecloud id_ed25519_huggingface; do
    if [ -f ~/.ssh/$key ]; then
        perms=$(stat -c '%a' ~/.ssh/$key 2>/dev/null || stat -f '%Lp' ~/.ssh/$key 2>/dev/null)
        echo "  $key: present ($perms)"
    else
        echo "  $key: MISSING"
    fi
done
echo ""
echo "=== Bootstrap complete ==="
echo ""
echo "Daily commands:"
echo "  export BW_SESSION=\$(bw unlock --raw)   # unlock Bitwarden (for templates)"
echo "  chezmoi update                           # pull + apply latest"
echo "  chezmoi edit <file>                      # edit a managed file"
echo "  chezmoi diff                             # see pending changes"
echo "  chezmoi re-add <file>                    # adopt local changes to source"
