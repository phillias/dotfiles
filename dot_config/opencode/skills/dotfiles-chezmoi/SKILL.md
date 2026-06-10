---
name: dotfiles-chezmoi
description: >
  Skill for managing chezmoi-based dotfiles with age encryption, Bitwarden integration,
  GitHub deploy keys, and multi-profile branch setup (master/personal/work).
  Use when the user asks about setting up dotfiles on a fresh machine, troubleshooting
  "encryption not configured" errors, age key decryption failures, chezmoi apply issues,
  Bitwarden session problems, or SSH deploy key setup.
---

# dotfiles-chezmoi

Skill for chezmoi dotfiles management.

## Architecture

```
GitHub (phillias/dotfiles)
  └── chezmoi init (via deploy key)
        └── ~/.local/share/chezmoi/  (source state)
              ├── age-key.txt.age       (encrypted age key)
              ├── dot_* files           (managed dotfiles)
              ├── scripts/setup.sh      (bootstrap script)
              ├── .chezmoiignore        (ignores internal files)
              └── .chezmoi-inventory.json  (node registry, auto-pushed)

Manual config:
  ~/.config/chezmoi/chezmoi.toml        (runtime config, machine-local)
  ~/.config/chezmoi/key.txt             (decrypted age key, machine-local)
```

Key points:
- **Runtime config** is at `~/.config/chezmoi/chezmoi.toml` — this is NOT managed by chezmoi itself
  (it's listed in `.chezmoiignore`). It must be created during bootstrap.
- **Age key** is stored encrypted as `age-key.txt.age` in the source state. The passphrase
  is in Bitwarden (search "Chezmoi Age Key", password field).
- **Profiles**: `master` (shared configs only), `personal` (personal SSH/API keys),
  `work` (work SSH/API keys). Encrypted files per profile are on different branches.

## Fresh Install Flow

Canonical setup:

```bash
curl -fsSL https://raw.githubusercontent.com/phillias/dotfiles/master/scripts/setup.sh | bash
```

The script steps: install deps (chezmoi, gh, bw, cloudflared) → generate SSH deploy key →
gh auth → register deploy key → select profile (master/personal/work) → Bitwarden login →
clone dotfiles → first apply → age key decrypt (3 attempts) → **write chezmoi.toml** →
second apply → **register in inventory** (creates `.chezmoi-inventory.json` if missing,
commits and pushes host entry to master via deploy key) → cron setup.

## Common Troubleshooting

### "encryption not configured"

**Root cause**: `~/.config/chezmoi/chezmoi.toml` missing or lacks `encryption = "age"`.

**Fix**:
```bash
mkdir -p ~/.config/chezmoi
cat > ~/.config/chezmoi/chezmoi.toml << 'EOF'
encryption = "age"
[age]
    identity = "~/.config/chezmoi/key.txt"
    recipient = "age1p5cu2lhvhjxq2rkzxlgk9ekknr3ang7n5nla5pst94ckm8jmmq9sp66mc5"
EOF
```

Then `chezmoi apply --keep-going`.

### Age key decryption fails (all 3 attempts)

Use `--keep-going` to apply unencrypted files and skip encrypted ones:
```bash
chezmoi apply --keep-going
```

Decrypt later:
```bash
chezmoi age decrypt --passphrase \
  -o ~/.config/chezmoi/key.txt \
  ~/.local/share/chezmoi/age-key.txt.age
```

### "age: could not decrypt" / "passphrase is incorrect"

Passphrase is in Bitwarden → search "Chezmoi Age Key" → password field.
Check: no whitespace, file exists at `~/.local/share/chezmoi/age-key.txt.age`,
output dir `~/.config/chezmoi/` exists, use `--passphrase` flag.

### Bitwarden templates not rendering

```bash
export BW_SESSION=$(bw unlock --raw)
BW_SESSION="$BW_SESSION" chezmoi apply
```

### SSH permission denied on `chezmoi init`

```bash
ssh -T git@github.com -i ~/.ssh/chezmoi-deploy-key
gh repo deploy-key add ~/.ssh/chezmoi-deploy-key.pub \
  --repo phillias/dotfiles \
  --title "chezmoi@$(hostname)" \
  --allow-write
```

## Key Files

| File | Purpose |
|---|---|
| `~/.local/share/chezmoi/scripts/setup.sh` | Bootstrap script |
| `~/.local/share/chezmoi/.chezmoi-inventory.json` | Node registry (JSON, auto-committed + pushed) |
| `~/.config/chezmoi/chezmoi.toml` | Runtime config (encryption, age) |
| `~/.config/chezmoi/key.txt` | Decrypted age private key |
| `~/.local/share/chezmoi/age-key.txt.age` | Encrypted age key |
| `~/.ssh/chezmoi-deploy-key` | SSH deploy key for GitHub |

## Inventory System

The file `.chezmoi-inventory.json` at the root of the source state tracks every machine
that has run `setup.sh`. It is listed in `.chezmoiignore` so chezmoi does not try to
install it as a dotfile — it lives purely in the git repo as shared infrastructure.

**Format** (version 1):
```json
{
  "version": 1,
  "servers": {
    "HOSTNAME": {
      "hostname": "HOSTNAME",
      "username": "phillias",
      "os": "linux",
      "arch": "x86_64",
      "profile": "master|personal|work",
      "first_seen": "ISO8601",
      "last_sync": "ISO8601",
      "status": "active"
    }
  }
}
```

**Bootstrap behavior** (step 16 of `setup.sh`):
1. If the inventory file does not exist locally, it is created with `version: 1` and an empty `servers` object.
2. The current host's entry is **always updated** (sets `last_sync`, preserves `first_seen`).
3. The change is committed and pushed to `origin/master` via the deploy key.
4. If the push fails (e.g., no network), the script warns and moves on — the change will be picked up next sync.

**View current inventory:**
```bash
gh repo view phillias/dotfiles --json files | jq -r '.files[] | select(.path == ".chezmoi-inventory.json") | .url'
# or browse: https://github.com/phillias/dotfiles/blob/master/.chezmoi-inventory.json
```

## Verification

```bash
chezmoi --version && chezmoi verify && chezmoi managed
for k in id_ed25519 id_ed25519_inspironkali id_ed25519_kali id_ed25519_oraclecloud id_ed25519_huggingface; do
  [ -f "$HOME/.ssh/$k" ] && echo "  $k: OK" || echo "  $k: MISSING"
done
```
