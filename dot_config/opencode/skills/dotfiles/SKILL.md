---
name: dotfiles
description: >
  General dotfiles maintenance operations — adding new files, encrypting secrets,
  managing branches, syncing changes across machines, and the day-to-day workflow
  of keeping a chezmoi-managed dotfiles repo healthy.
  Use when the user asks about adding a file to their dotfiles, encrypting a secret,
  syncing changes, managing profiles/branches, or general dotfiles housekeeping.
  NOT for fresh install/bootstrap troubleshooting (use dotfiles-chezmoi for that).
---

# dotfiles

General operations for maintaining a chezmoi-managed dotfiles repo across multiple machines.

## Adding a new file

To add a new dotfile to chezmoi management:

```bash
# Add an unencrypted file (e.g., a config file with no secrets)
chezmoi add ~/.tmux.conf

# Add a file with age encryption (e.g., API keys, tokens)
chezmoi add ~/.config/some-app/token --encrypt
```

This creates a file in the source state (`~/.local/share/chezmoi/`) with the appropriate naming convention. Unencrypted files get a `dot_` prefix (e.g., `dot_tmux.conf` → `~/.tmux.conf`). Encrypted files get an `encrypted_` prefix and `.age` suffix (e.g., `encrypted_dot_config_some-app_token.age` → decrypted to `~/.config/some-app/token`).

After adding, commit and push:

```bash
cd ~/.local/share/chezmoi
git add <new-file>
git commit -m "Add <description>"
git push
```

Other machines pick up the change on their next `chezmoi update` (cron runs every 30 min).

## Adding a file manually (without chezmoi add)

If you already have the file in the source state and just need to name it correctly:

| Target path | Source state filename |
|---|---|
| `~/.bashrc` | `dot_bashrc` |
| `~/.config/opencode/opencode.json` | `dot_config/opencode/opencode.json` |
| `~/.config/opencode/.groq-key` (encrypted) | `dot_config/opencode/encrypted_dot_groq-key.age` |
| `~/.ssh/id_ed25519` (encrypted) | `dot_ssh/encrypted_private_id_ed25519.age` |

The naming rules:
- Replace leading `.` with `dot_` in the filename
- Replace `/` with directory structure under `dot_` prefix
- For encrypted files: prefix with `encrypted_` and append `.age`
- For SSH private keys: use `encrypted_private_` prefix (chezmoi convention for SSH keys)

## Encrypting a file

If you have a plaintext file you want to encrypt into chezmoi:

```bash
# Encrypt an existing file into the source state
chezmoi add --encrypt ~/.config/opencode/.groq-key

# Or encrypt a file that's already in the source state
chezmoi reencrypt ~/.local/share/chezmoi/dot_config/opencode/encrypted_dot_groq-key.age
```

Encryption uses the age key configured in `~/.config/chezmoi/chezmoi.toml`. The recipient must match what's in the config. To check:

```bash
grep recipient ~/.config/chezmoi/chezmoi.toml
```

## Decrypting a file (to view or edit)

```bash
# View decrypted content (stdout)
chezmoi cat ~/.config/opencode/.groq-key

# Edit an encrypted file (decrypts, opens editor, re-encrypts on save)
chezmoi edit ~/.config/opencode/.groq-key
```

## Syncing changes across machines

Changes propagate through the normal git workflow:

1. **Commit and push** from the machine where you made changes
2. **Other machines pick it up** via `chezmoi update` (runs automatically via cron every 30 min)

`chezmoi update` does: `git pull` + `chezmoi apply`. To sync manually:

```bash
chezmoi update
```

To see what would change without applying:

```bash
chezmoi diff
```

## Managing profiles (branch strategy)

If using a branch-based profile system (e.g., master for shared configs, personal/work for machine-specific secrets):

### Keeping profile branches up to date

Profile branches need periodic rebasing onto master to pick up shared improvements:

```bash
# From the profile branch
git fetch origin
git rebase origin/master
# Resolve any conflicts, then:
git push --force-with-lease
```

### Checking which branch you're on

```bash
cd ~/.local/share/chezmoi && git branch
```

### What goes on which branch

- **Shared branch** (master): Shell configs, editor configs, gitconfig, tmux, screenrc — anything without secrets
- **Profile branches**: SSH keys, API tokens, machine-specific configs, encrypted secrets

## Viewing what chezmoi manages

```bash
# List all managed files
chezmoi managed

# Show differences between source state and installed files
chezmoi diff

# Verify all files are in sync
chezmoi verify
```

## Removing a file from chezmoi management

```bash
# Stop managing a file (leaves the installed copy in place)
chezmoi forget ~/.some-file

# Or remove entirely (deletes from source state and target)
chezmoi remove ~/.some-file
```

After forgetting/removing, commit the source state change:

```bash
cd ~/.local/share/chezmoi
git add -A
git commit -m "Remove <file> from chezmoi management"
git push
```

## Checking the inventory

If the repo has a node inventory (`.chezmoi-inventory.json`):

```bash
# View which machines are registered
gh repo view <owner>/<repo> --json files | jq -r '.files[] | select(.path == ".chezmoi-inventory.json") | .url'
```

The inventory is updated automatically during bootstrap and tracks hostname, OS, architecture, profile, and last sync time.

## Common maintenance tasks

### After editing a managed file directly

If you edit a file in `~/.local/share/chezmoi/` directly (not via `chezmoi add` or `chezmoi edit`):

```bash
cd ~/.local/share/chezmoi
git diff                     # review changes
git add <changed-file>
git commit -m "Update <description>"
git push
```

### After editing an installed file (the target, not the source)

If you edit `~/.bashrc` directly and want to capture those changes back into chezmoi:

```bash
chezmoi re-add ~/.bashrc
```

This updates the source state file with your changes. Then commit and push.

### Checking if all machines are in sync

```bash
# On each machine:
chezmoi diff          # shows pending changes
chezmoi managed       # shows what's managed
chezmoi verify        # exits 0 if everything matches
```

## Troubleshooting

### "chezmoi: <file>: encrypted, but age is not configured"

The age key is missing or `chezmoi.toml` doesn't have encryption configured. Fix:

```bash
# Check if config exists
cat ~/.config/chezmoi/chezmoi.toml

# If missing, recreate:
mkdir -p ~/.config/chezmoi
cat > ~/.config/chezmoi/chezmoi.toml << 'EOF'
encryption = "age"
[age]
    identity = "~/.config/chezmoi/key.txt"
    recipient = "<age-recipient>"
EOF
```

### Encrypted files are being skipped during apply

The age key file (`~/.config/chezmoi/key.txt`) is missing or the passphrase was wrong during bootstrap. Decrypt it:

```bash
chezmoi age decrypt --passphrase \
  -o ~/.config/chezmoi/key.txt \
  ~/.local/share/chezmoi/age-key.txt.age
```

Then re-apply:

```bash
chezmoi apply
```

### "could not decrypt" / "passphrase is incorrect"

The age passphrase is wrong. Find it in the password manager (search "Chezmoi Age Key" or similar). Make sure there's no whitespace in the pasted passphrase.

### Bitwarden templates not rendering

If `.tmpl` files use Bitwarden template variables and they're not rendering:

```bash
export BW_SESSION=$(bw unlock --raw)
BW_SESSION="$BW_SESSION" chezmoi apply
```

### SSH deploy key issues

If `chezmoi init` or `git push` fails with permission denied:

```bash
# Test the key
ssh -T git@github.com -i ~/.ssh/chezmoi-deploy-key

# If it fails, the key may not be registered on GitHub
gh repo deploy-key add ~/.ssh/chezmoi-deploy-key.pub \
  --repo <owner>/<repo> \
  --title "chezmoi@$(hostname)" \
  --allow-write
```