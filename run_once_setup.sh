#!/usr/bin/env bash
# run_once_setup.sh — bootstrap chezmoi + dotfiles on a new server
# Usage: curl -fsSL https://raw.githubusercontent.com/phillias/dotfiles/master/run_once_setup.sh | bash
#
# Prerequisites: git, curl, unzip, expect
# Works on: Debian/Ubuntu/Kali, Fedora/RHEL, Alpine

set -euo pipefail

export PATH="$HOME/bin:$HOME/.local/bin:$PATH"
CHEZMOI_DIR="$HOME/.local/share/chezmoi"
BW_ITEM_AGE="ff07b560-a406-4e56-ad99-b45b0167a9db"

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
echo "==> Bitwarden login required (for API keys + SSH age passphrase)"
bw login phillias@gmail.com
export BW_SESSION=$(bw unlock --raw)

# ── 5. First apply — renders Bitwarden templates (.zshrc) ───────────
echo "==> Applying dotfiles (Bitwarden secrets)..."
chezmoi apply

# ── 6. Decrypt age encryption key ───────────────────────────────────
#     The age private key (encrypted) is in the repo.
#     Get the passphrase from Bitwarden and decrypt it.
echo "==> Setting up age encryption..."
AGE_PASSPHRASE=$(bw get item "$BW_ITEM_AGE" | bw encode 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
for f in d.get('fields', []):
    if f['name'] == 'Age Passphrase':
        print(f['value'])
        break
" 2>/dev/null || bw get item "$BW_ITEM_AGE" --raw 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
for f in d.get('fields', []):
    if f['name'] == 'Age Passphrase':
        print(f['value'])
        break
")

# Try alternate method to get the passphrase
if [ -z "$AGE_PASSPHRASE" ]; then
    AGE_PASSPHRASE=$(export BW_SESSION=$(bw unlock --raw 2>/dev/null); bw get item "$BW_ITEM_AGE" 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
for f in d.get('fields', []):
    if f['name'] == 'Age Passphrase':
        print(f['value'])
        break
" 2>/dev/null)
fi

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

    # Get public key for chezmoi.toml
    AGE_PUB=$(bw get item "$BW_ITEM_AGE" 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
for f in d.get('fields', []):
    if f['name'] == 'Age Public Key':
        print(f['value'])
        break
" 2>/dev/null || echo "age1p5cu2lhvhjxq2rkzxlgk9ekknr3ang7n5nla5pst94ckm8jmmq9sp66mc5")

    # Write chezmoi config
    cat > "$HOME/.config/chezmoi/chezmoi.toml" << AGECONF
encryption = "age"
[age]
    identity = "~/.config/chezmoi/key.txt"
    recipient = "$AGE_PUB"
AGECONF
    echo "chezmoi.toml written"
else
    echo "WARN: Could not retrieve age passphrase from Bitwarden."
    echo "      SSH keys will not be decrypted. Run manually later:"
    echo "      bw login && export BW_SESSION=\$(bw unlock --raw)"
    echo "      chezmoi age decrypt --passphrase --output ~/.config/chezmoi/key.txt ~/.local/share/chezmoi/age-key.txt.age"
fi

# ── 7. Full apply (age-decrypt SSH keys + render all templates) ─────
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
echo "=== SSH private keys ==="
ls ~/.ssh/id_ed25519 2>/dev/null && echo "  id_ed25519: present" || echo "  id_ed25519: MISSING"
ls ~/.ssh/id_ed25519_inspironkali 2>/dev/null && echo "  id_ed25519_inspironkali: present" || echo "  id_ed25519_inspironkali: MISSING"
echo ""
echo "=== Bootstrap complete ==="
echo ""
echo "Daily commands:"
echo "  export BW_SESSION=\$(bw unlock --raw)   # unlock Bitwarden"
echo "  chezmoi update                           # pull + apply latest"
echo "  chezmoi edit <file>                      # edit a managed file"
echo "  chezmoi re-add <file>                    # adopt local changes to source"
