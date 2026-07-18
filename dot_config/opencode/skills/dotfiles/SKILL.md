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

## Agent-Friendly Interface: chezmoi-axi

For agent contexts, use `chezmoi-axi` — an AXI-compliant wrapper around chezmoi that provides token-efficient TOON output (~40% savings over plain text) with structured errors and contextual help hints.

```bash
# Quick status check
chezmoi-axi status

# List managed files (minimal schema)
chezmoi-axi list
chezmoi-axi list --changed   # only files with pending diffs
chezmoi-axi list --encrypted # only encrypted files

# Review diffs
chezmoi-axi diff
chezmoi-axi diff ~/.bashrc   # specific file

# Add/re-add files
chezmoi-axi add ~/.config/app/config.json
chezmoi-axi add --encrypt ~/.config/app/secret.key
chezmoi-axi re-add ~/.bashrc
chezmoi-axi re-add --all     # re-add all changed files

# Apply and verify
chezmoi-axi apply
chezmoi-axi apply --preview  # dry run
chezmoi-axi verify

# Sync remote changes
chezmoi-axi sync
chezmoi-axi sync --preview   # fetch + diff, no apply

# Commit, push, and open PR
chezmoi-axi commit
chezmoi-axi commit "feat(app): add new config"
```

The script is at `~/.local/bin/chezmoi-axi`. All output uses TOON format per [AXI principles](https://axi.md).

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

## Bootstrap a New Machine

**Use this when**: Setting up dotfiles on a fresh server or VM.

**One-liner** (installs chezmoi, tools, decrypts secrets, applies dotfiles):

```bash
curl -fsSL https://raw.githubusercontent.com/phillias/dotfiles/master/scripts/setup.sh | bash
```

**What the script does:**
1. Installs chezmoi (latest version, updates if outdated)
2. Installs GitHub CLI (`gh`)
3. Installs Bitwarden CLI (`bw`)
4. Installs cloudflared
5. Installs opencode (user-local to `~/.opencode`, via npm/bun — NOT OS package manager)
6. Sets up PATH in `.bashrc` and `.zshrc` (`~/.opencode/bin`, `~/.local/bin`, `~/bin`)
7. Generates SSH deploy key and registers it on GitHub
8. Prompts for profile branch (master/personal/work)
9. Clones dotfiles repo
10. Authenticates Bitwarden and decrypts age key
11. Applies dotfiles
12. Sets up cron auto-sync every 30 min

**Interactive prompts you'll answer:**
- GitHub token (if `gh` not authenticated)
- Profile branch choice
- Bitwarden master password + 2FA
- Bitwarden API key (optional, for cron)
- Age key passphrase (auto-fetched from Bitwarden if available)

**Prerequisites:**
- `curl`, `python3`, `ssh-keygen`
- Node.js or Bun (for opencode install)
- `sudo` (optional — falls back to user-local installs)

**After bootstrap:**
```bash
# Verify everything is applied
chezmoi verify

# Check installed tools
chezmoi managed | head -20
```

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
| I want agent-friendly output for chezmoi operations | → [Agent-Friendly Interface: chezmoi-axi](#agent-friendly-interface-chezmoi-axi) |

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

**Note**: `chezmoi diff` compares local source state against installed files. It does NOT show changes on the remote git repository that haven't been pulled yet.

---

### Preview remote changes before applying

**Use this when**: You want to see what changes exist on the remote before pulling them down.

`chezmoi update` does `git pull` + `chezmoi apply` in one shot. To inspect what's coming first:

```bash
# 1. Fetch remote without changing anything
chezmoi git -- fetch origin

# 2. See commits on remote master that you don't have
chezmoi git -- log --oneline HEAD..origin/master

# 3. See what files changed
chezmoi git -- diff --stat HEAD origin/master

# 4. See actual diff content
chezmoi git -- diff HEAD origin/master
```

**To preview how those changes would affect installed files:**

```bash
# Fast-forward source state only (safe, doesn't touch installed files)
chezmoi git -- merge --ff-only origin/master

# Now chezmoi diff shows remote vs installed
chezmoi diff

# If happy, apply:
chezmoi apply

# If not, undo the fast-forward:
chezmoi git -- reset --hard HEAD
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

**Quick alternative**: `chezmoi-axi commit` automates this entire flow — stages all changes, commits, pushes to a feature branch, and opens a PR:

```bash
chezmoi-axi commit "feat(app): add new config"
```

**Manual flow** (when you need more control):

```bash
cd ~/.local/share/chezmoi

# 1. Review changes
git status
git diff --stat

# 2. Stage and commit
git add <changed-file(s)>
git commit -m "<type>(<scope>): <description>"

# 3. Create a feature branch and push
git checkout -b update-$(date +%Y%m%d-%H%M%S)
git push -u origin $(git branch --show-current)

# 4. Open a pull request
gh pr create \
  --title "$(git log -1 --pretty=%s)" \
  --body "$(git log -1 --pretty=%b)" \
  --base master

# 5. Switch branch back to masster
git checkout master

# 6. Delete local branch
git branch -d update-$(date +%Y%m%d-%H%M%S)
```

> **Note**: The repo is at `~/.local/share/chezmoi`. Other machines pick up changes on their next `chezmoi update` (cron runs every 30 min). Prefer PRs for traceability; if branch protection prevents direct push, the agent should handle it flexibly.

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
