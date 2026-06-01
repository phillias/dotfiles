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

# ── 3. Install cloudflared (needed for SSH tunnel hosts) ─────────────
if ! command -v cloudflared &>/dev/null; then
    echo "==> Installing cloudflared..."
    arch=$(uname -m)
    case "$arch" in
        x86_64)  cf_arch="amd64" ;;
        aarch64) cf_arch="arm64" ;;
        armv7l)  cf_arch="arm" ;;
        *)       cf_arch="amd64" ;;
    esac
    curl -fsSL -o /tmp/cloudflared \
        "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cf_arch}"
    chmod +x /tmp/cloudflared
    if command -v sudo &>/dev/null; then
        sudo mv /tmp/cloudflared /usr/bin/cloudflared
    else
        mkdir -p "$HOME/bin"
        mv /tmp/cloudflared "$HOME/bin/cloudflared"
    fi
    echo "cloudflared: $(cloudflared --version 2>&1 | head -1)"
fi

# ── 4. Clone dotfiles repo ──────────────────────────────────────────
if [ ! -d "$CHEZMOI_DIR" ]; then
    echo "==> Cloning dotfiles repo..."
    chezmoi init git@github.com:phillias/dotfiles.git
fi

# ── 5. Bitwarden login (interactive) ────────────────────────────────
echo ""
echo "==> Bitwarden login required"
bw login phillias@gmail.com
export BW_SESSION=$(bw unlock --raw)

# ── 6. First apply — renders Bitwarden templates ────────────────────
echo "==> Applying dotfiles..."
BW_SESSION="$BW_SESSION" chezmoi apply

# ── 7. Decrypt age encryption key ───────────────────────────────────
echo ""
echo "==> Age encryption setup"
echo "    SSH private keys are age-encrypted."
echo "    Find the passphrase in Bitwarden: search 'Chezmoi Age Key'"
echo ""

AGE_KEY_FILE="$HOME/.config/chezmoi/key.txt"

if [ ! -f "$AGE_KEY_FILE" ]; then
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
        echo "WARN: No passphrase entered. Decrypt manually later:"
        echo "  chezmoi age decrypt --passphrase -o ~/.config/chezmoi/key.txt ~/.local/share/chezmoi/age-key.txt.age"
    fi
else
    echo "Age key already present, skipping"
fi

# ── 8. Write chezmoi config ─────────────────────────────────────────
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

# ── 9. Full apply (age-decrypt SSH keys + render all templates) ─────
echo ""
echo "==> Full apply..."
BW_SESSION=$(bw unlock --raw) chezmoi apply

# ── 10. Verify ──────────────────────────────────────────────────────
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
