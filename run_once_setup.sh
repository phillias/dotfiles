#!/usr/bin/env bash
# run_once_setup.sh — bootstrap chezmoi + dotfiles on a new server
# Usage: curl -fsSL https://raw.githubusercontent.com/phillias/dotfiles/master/run_once_setup.sh | bash

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
echo "==> Bitwarden login required"
bw login phillias@gmail.com
export BW_SESSION=$(bw unlock --raw)

# ── 5. First apply — renders Bitwarden templates ────────────────────
echo "==> Applying dotfiles..."
BW_SESSION="$BW_SESSION" chezmoi apply

# ── 6. Decrypt age encryption key ───────────────────────────────────
echo ""
echo "==> Age encryption setup"
echo "    SSH private keys are age-encrypted."
echo "    Find the passphrase in Bitwarden: search 'Chezmoi Age Key'"
echo ""

AGE_KEY_FILE="$HOME/.config/chezmoi/key.txt"

if [ ! -f "$AGE_KEY_FILE" ]; then
    # Prompt user for passphrase (serial console friendly)
    read -rp "Enter age passphrase from Bitwarden: " AGE_PP

    if [ -n "$AGE_PP" ]; then
        mkdir -p "$(dirname "$AGE_KEY_FILE")"
        expect << EXPECTEOF
set timeout 10
spawn chezmoi age decrypt --passphrase --output "$AGE_KEY_FILE" "$CHEZMOI_DIR/age-key.txt.age"
expect "Enter passphrase:"
send "$AGE_PP\r"
expect "Confirm passphrase:"
send "$AGE_PP\r"
expect eof
EXPECTEOF
        chmod 600 "$AGE_KEY_FILE"
        echo "Age key decrypted"
    else
        echo "WARN: No passphrase entered. You must decrypt manually later:"
        echo "  chezmoi age decrypt --passphrase -o ~/.config/chezmoi/key.txt ~/.local/share/chezmoi/age-key.txt.age"
    fi
else
    echo "Age key already present, skipping"
fi

# ── 7. Write chezmoi config ─────────────────────────────────────────
if [ -f "$AGE_KEY_FILE" ]; then
    # Extract public key from the unencrypted private key
    AGE_PUB=$(age-keygen -y "$AGE_KEY_FILE" 2>/dev/null || echo "")

    if [ -z "$AGE_PUB" ]; then
        # Fallback: try chezmoi data
        AGE_PUB=$(chezmoi data --format=json 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('age', {}).get('recipient', ''))
" 2>/dev/null || echo "")
    fi

    if [ -n "$AGE_PUB" ]; then
        mkdir -p "$HOME/.config/chezmoi"
        cat > "$HOME/.config/chezmoi/chezmoi.toml" << AGECONF
encryption = "age"
[age]
    identity = "~/.config/chezmoi/key.txt"
    recipient = "$AGE_PUB"
AGECONF
        echo "chezmoi.toml written (recipient: $AGE_PUB)"
    fi
fi

# ── 8. Full apply (age-decrypt SSH keys + render all templates) ─────
echo ""
echo "==> Full apply..."
BW_SESSION=$(bw unlock --raw) chezmoi apply

# ── 9. Verify ───────────────────────────────────────────────────────
echo ""
echo "=== Verification ==="
if chezmoi verify 2>/dev/null; then
    echo "OK: All files verified"
else
    echo "WARN: Some files differ (may need a re-apply)"
fi

echo ""
echo "=== SSH keys ==="
for k in id_ed25519 id_ed25519_inspironkali id_ed25519_kali id_ed25519_oraclecloud id_ed25519_huggingface; do
    [ -f "$HOME/.ssh/$k" ] && echo "  $k: present" || echo "  $k: MISSING"
done

echo ""
echo "=== Bootstrap complete ==="
echo ""
echo "Daily commands:"
echo "  BW_SESSION=\$(bw unlock --raw) chezmoi update    # pull + apply"
echo "  chezmoi edit <file>                               # edit a managed file"
echo "  chezmoi re-add <file>                             # adopt local changes"
