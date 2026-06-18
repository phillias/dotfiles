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

Runbook for maintaining a chezmoi-managed dotfiles repo across multiple machines.

## Health Check

Before any operation, assess current state:

```bash
# Verify all files match source state (exits 0 if clean)
chezmoi verify

# Show pending differences between source state and installed files
chezmoi diff

# List all managed files
chezmoi managed
```

- **`verify` exits non-zero** → some files have drifted. Run `chezmoi diff` to see what.
- **`diff` shows unexpected changes** → files were modified outside chezmoi. See [I edited a file directly — capture the changes](#re-add-a-changed-file).
- **`diff` is clean** → repo is in sync. Proceed with your operation.

---

## What are you trying to do?

| Situation | Go to |
|---|---|
| I have a new config file to start tracking | → [Add a new file](#add-a-new-file) |
| I edited a tracked file on disk and want to capture the changes | → [Re-add a changed file](#re-add-a-changed-file) |
| A file has secrets — I need to encrypt it | → [Encrypt a file](#encrypt-a-file) |
| I want to view or edit an encrypted file's contents | → [Decrypt a file](#decrypt-a-file) |
| Changes I made on one machine aren't showing up on another | → [Sync changes across machines](#sync-changes-across-machines) |
| I want to stop tracking a file | → [Remove a file](#remove-a-file) |
| Encrypted files are being skipped during `chezmoi apply` | → [Troubleshoot: age key](#troubleshoot-age-key) |
| `chezmoi init` or `git push` fails with permission denied | → [Troubleshoot: SSH deploy key](#troubleshoot-ssh-deploy-key) |
| Bitwarden template variables aren't rendering | → [Troubleshoot: Bitwarden session](#troubleshoot-bitwarden-session) |
| I just want a quick overview of what chezmoi manages | → [View managed files](#view-managed-files) |

---

## Procedures

### Add a new file

**Use this when**: You have a config file on disk that isn't yet chezmoi-managed.

**Before you begin**: All configs go on `master`. Secrets are encrypted with age, so they're safe on the shared branch — no need for separate profile branches.

**Steps**:

1. Add the file to chezmoi's source state:
   ```bash
   # Unencrypted (no secrets)
   chezmoi add ~/.tmux.conf

   # Encrypted (API keys, tokens, private keys)
   chezmoi add --encrypt ~/.config/some-app/token
   ```

2. Review the source state file was created:
   ```bash
   ls ~/.local/share/chezmoi/dot_*
   ```

3. **Verify**: run `chezmoi diff` — should show no differences between source and installed file.

4. Commit and push using the [standard commit flow](#standard-commit-flow).

---

### Re-add a changed file

**Use this when**: You edited a tracked file directly on disk (e.g., `~/.bashrc`) and want to capture those changes back into chezmoi's source state.

**Steps**:

1. ```bash
   chezmoi re-add ~/.bashrc
   ```

2. **Verify**: run `chezmoi diff` — should now be clean.

3. Commit and push using the [standard commit flow](#standard-commit-flow).

> **Note**: This also works for files that were added to the source state manually (without `chezmoi add`) but need their content synced.

---

### Encrypt a file

**Use this when**: You have a plaintext file in chezmoi that should be encrypted, or you're adding a new file that contains secrets.

**Before you begin**: Check the age recipient is configured:
```bash
grep recipient ~/.config/chezmoi/chezmoi.toml
```

**Steps**:

```bash
# Encrypt an existing file into the source state
chezmoi add --encrypt ~/.config/opencode/.groq-key

# Encrypt a file that's already in the source state
chezmoi reencrypt ~/.local/share/chezmoi/dot_config/opencode/encrypted_dot_groq-key.age
```

**Verify**: Run `chezmoi cat ~/.config/opencode/.groq-key` — should show decrypted content. Run `chezmoi diff` — should be clean.

Commit and push using the [standard commit flow](#standard-commit-flow).

---

### Decrypt a file

**Use this when**: You need to view the plaintext contents of an encrypted file, or edit one.

**Steps**:

```bash
# View decrypted content (stdout)
chezmoi cat ~/.config/opencode/.groq-key

# Edit an encrypted file (decrypts, opens editor, re-encrypts on save)
chezmoi edit ~/.config/opencode/.groq-key
```

No commit needed for `chezmoi cat` (read-only). After `chezmoi edit`, commit and push using the [standard commit flow](#standard-commit-flow).

---

### Sync changes across machines

**Use this when**: Changes committed and pushed from machine A aren't appearing on machine B.

**Before you begin**: Ensure the changes were pushed to the remote (check `git log origin/master..master` on the source machine).

**Steps**:

`chezmoi update` runs automatically via cron every 30 min on each machine. To sync immediately:

```bash
chezmoi update
```

This does: `git pull` + `chezmoi apply`.

**Verify**: Run `chezmoi diff` and `chezmoi verify` — both should be clean. Check that the expected file changes are present.

To preview without applying:

```bash
chezmoi diff
```

---

### Remove a file

**Use this when**: You want to stop managing a file with chezmoi.

**Steps**:

```bash
# Stop managing (leaves the installed copy on disk)
chezmoi forget ~/.some-file

# Remove entirely (deletes from source state AND the installed copy)
chezmoi remove ~/.some-file
```

**Verify**: Run `chezmoi managed | grep some-file` — should return nothing.

Commit and push using the [standard commit flow](#standard-commit-flow).

---

### View managed files

**Use this when**: You want a quick overview of what chezmoi is tracking, or what the sync state looks like.

**Steps**:

```bash
# List all managed files
chezmoi managed

# Show differences between source state and installed files
chezmoi diff

# Quick health check
chezmoi verify  # exits 0 if everything matches
```

---

## Standard commit flow

This is the standard way to commit and push source state changes. Used by most procedures above.

```bash
cd ~/.local/share/chezmoi
git status                    # review what changed
git add <changed-file(s)>     # stage changes
git commit -m "Update <description>"
git push origin master        # push to shared branch
```

> **Note**: The repo is at `~/.local/share/chezmoi`. Other machines pick up changes on their next `chezmoi update` (cron runs every 30 min).

---

## Troubleshooting

### Troubleshoot: age key

**Symptom**: `chezmoi apply` skips encrypted files with the error `"chezmoi: <file>: encrypted, but age is not configured"`.

**Diagnosis**: The age key file is missing, or `chezmoi.toml` doesn't have encryption configured.

**Fix**:

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

**Still broken?** → See [passphrase incorrect](#troubleshoot-passphrase-incorrect).

---

### Troubleshoot: passphrase incorrect

**Symptom**: `"could not decrypt"` / `"passphrase is incorrect"`.

**Diagnosis**: The age passphrase used during bootstrap was wrong, or the key file needs to be decrypted.

**Fix**:

```bash
# Decrypt the age key from chezmoi source
chezmoi age decrypt --passphrase \
  -o ~/.config/chezmoi/key.txt \
  ~/.local/share/chezmoi/age-key.txt.age
```

**Find the passphrase**: Search your password manager for "Chezmoi Age Key" or similar. Make sure there's no leading/trailing whitespace in the pasted passphrase.

Then re-apply:

```bash
chezmoi apply
```

---

### Troubleshoot: Bitwarden session

**Symptom**: `.tmpl` files that use Bitwarden template variables are not rendering (showing template syntax instead of values).

**Diagnosis**: The `BW_SESSION` environment variable is not set, so chezmoi can't access Bitwarden.

**Fix**:

```bash
export BW_SESSION=$(bw unlock --raw)
BW_SESSION="$BW_SESSION" chezmoi apply
```

---

### Troubleshoot: SSH deploy key

**Symptom**: `chezmoi init` or `git push` fails with `Permission denied (publickey)`.

**Diagnosis**: The SSH deploy key (`~/.ssh/chezmoi-deploy-key`) is missing, not loaded, or not registered on GitHub.

**Fix**:

```bash
# Test the key
ssh -T git@github.com -i ~/.ssh/chezmoi-deploy-key

# If it fails, register the key on GitHub
gh repo deploy-key add ~/.ssh/chezmoi-deploy-key.pub \
  --repo <owner>/<repo> \
  --title "chezmoi@$(hostname)" \
  --allow-write
```

---

## Naming Reference

Use this when you need to manually name a file in the source state (`~/.local/share/chezmoi/`):

| Target path | Source state filename |
|---|---|
| `~/.bashrc` | `dot_bashrc` |
| `~/.config/opencode/opencode.json` | `dot_config/opencode/opencode.json` |
| `~/.config/opencode/.groq-key` (encrypted) | `dot_config/opencode/encrypted_dot_groq-key.age` |
| `~/.ssh/id_ed25519` (encrypted) | `dot_ssh/encrypted_private_id_ed25519.age` |

Rules:
- Replace leading `.` → `dot_` prefix
- Preserve directory structure under `dot_` prefix
- Encrypted files: prefix `encrypted_` + suffix `.age`
- SSH private keys: use `encrypted_private_` prefix (chezmoi convention)

> **Prefer `chezmoi add` over manual naming** — it handles naming conventions automatically.
