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

## Skills

skills[2]{name,description}:
  chezmoi-axi,Agent-friendly chezmoi wrapper with TOON output — status, list, diff, add, re-add, apply, verify, sync, commit
  /ce-commit-push-pr,Full PR workflow — branching, committing, PR creation, post-PR cleanup

## Health Check

Before any operation, assess current state:

```
chezmoi-axi status              # managed count, pending diffs, last sync
chezmoi-axi verify              # exits 0 if clean, 1 if drifted
chezmoi-axi diff                # show pending differences
```

- verify exits non-zero → files drifted. Run `chezmoi-axi diff`.
- diff shows unexpected changes → files modified outside chezmoi. See Re-add a changed file.
- diff is clean → repo in sync. Proceed.

---

## Bootstrap a New Machine

One-liner (installs chezmoi, tools, decrypts secrets, applies dotfiles):

```
curl -fsSL https://raw.githubusercontent.com/phillias/dotfiles/master/scripts/setup.sh | bash
```

What the script does:

steps[12]{n,action}:
  1,Install chezmoi (latest, updates if outdated)
  2,Install GitHub CLI (gh)
  3,Install Bitwarden CLI (bw)
  4,Install cloudflared
  5,Install opencode (user-local ~/.opencode via npm/bun)
  6,Set up PATH in .bashrc and .zshrc
  7,Generate SSH deploy key and register on GitHub
  8,Prompt for profile branch (master/personal/work)
  9,Clone dotfiles repo
  10,Authenticate Bitwarden and decrypt age key
  11,Apply dotfiles
  12,Set up cron auto-sync every 30 min

Interactive prompts you'll answer:

prompts[5]{item}:
  GitHub token (if gh not authenticated)
  Profile branch choice
  Bitwarden master password + 2FA
  Bitwarden API key (optional, for cron)
  Age key passphrase (auto-fetched from Bitwarden if available)

Prerequisites: curl, python3, ssh-keygen, Node.js or Bun, sudo (optional)

---

## What are you trying to do?

situations[10]{situation,go-to}:
  New config file to start tracking,Add a new file
  Edited tracked file on disk,Re-add a changed file
  File has secrets — need to encrypt,Encrypt a file
  View/edit encrypted file contents,Decrypt a file
  Changes not showing on another machine,Sync changes across machines
  Stop tracking a file,Remove a file
  Exclude files from chezmoi,Manage .chezmoiignore
  Run cleanup/setup scripts during apply,Run scripts
  Encrypted files skipped during apply,Troubleshoot: age key
  Permission denied on init/push,Troubleshoot: SSH deploy key

---

## Procedures

### Add a new file

Before you begin: All configs go on master. Secrets encrypted with age.

```
chezmoi-axi add ~/.tmux.conf                           # unencrypted
chezmoi-axi add --encrypt ~/.config/some-app/token     # encrypted
```

Verify: `chezmoi-axi diff` — no differences.

Commit: `chezmoi-axi commit "feat(app): add new config"` or load /ce-commit-push-pr.

---

### Re-add a changed file

```
chezmoi-axi re-add ~/.bashrc      # single file
chezmoi-axi re-add --all          # all changed files
```

Verify: `chezmoi-axi diff` — should be clean.

---

### Encrypt a file

Check age recipient is configured:
```
grep recipient ~/.config/chezmoi/chezmoi.toml
```

```
chezmoi add --encrypt ~/.config/opencode/.cloudflare-key
chezmoi reencrypt ~/.local/share/chezmoi/dot_config/opencode/encrypted_dot_cloudflare-key.age
```

Verify: `chezmoi cat ~/.config/opencode/.cloudflare-key` — shows decrypted content. `chezmoi diff` — clean.

Note: .groq-key removed 2026-07-18 (Groq free-tier TPM limits). Examples use .cloudflare-key.

---

### Decrypt a file

```
chezmoi cat ~/.config/opencode/.cloudflare-key         # view (stdout)
chezmoi edit ~/.config/opencode/.cloudflare-key        # edit (decrypts, opens editor, re-encrypts)
```

No commit for chezmoi cat (read-only). After chezmoi edit, commit with chezmoi-axi commit.

---

### Sync changes across machines

```
chezmoi-axi sync              # pull + apply
chezmoi-axi sync --preview    # see what's coming first
```

Verify: `chezmoi-axi verify` — should be clean.

Note: chezmoi update also runs automatically via cron every 30 min.

---

### Preview remote changes

```
chezmoi-axi sync --preview    # fetch + diff, no apply
```

Or manually:
```
chezmoi git -- fetch origin
chezmoi git -- log --oneline HEAD..origin/master
chezmoi git -- diff HEAD origin/master
```

To apply: `chezmoi-axi apply`

---

### Remove a file

```
chezmoi forget ~/.some-file    # stop managing (keeps installed copy)
chezmoi remove ~/.some-file    # remove entirely
```

Verify: `chezmoi-axi list | grep some-file` — nothing.

---

### View managed files

```
chezmoi-axi list              # all managed files
chezmoi-axi list --changed    # only files with pending diffs
chezmoi-axi list --encrypted  # only encrypted files
```

---

## Manage .chezmoiignore

The .chezmoiignore file at the source state root tells chezmoi to skip certain files during apply. Uses .gitignore pattern syntax.

Current patterns:

ignore[5]{pattern,reason}:
  .chezmoi.toml,Internal chezmoi files
  .chezmoiignore,Internal chezmoi files
  .chezmoi-inventory.json,Internal chezmoi files
  age-key.txt.age,Internal chezmoi files
  .gitconfig,Machine-specific git identity

When to edit:
- Adding machine-specific files that shouldn't sync
- Excluding build artifacts, caches, or temp files
- Ignoring files that exist on some machines but not others

Add a pattern:
```
echo "path/to/exclude" >> ~/.local/share/chezmoi/.chezmoiignore
```

Verify: `chezmoi diff` — ignored files no longer appear as pending.

---

## Run scripts

Chezmoi can run scripts automatically during chezmoi apply. Scripts use special name prefixes:

script-types[2]{prefix,runs,use-case}:
  run_once_,Once per machine (tracked in .run_once),One-time migrations, cleanup
  run_onchange_,When file content changes (hash tracked),Installs, updates, rebuilds

Scripts can have .tmpl suffix for templating.

Current run scripts:

run_once_cleanup-stale.sh.tmpl:
  rm -f ~/.config/opencode/oh-my-openagent.json  # replaced by .jsonc
  rm -f ~/.local/bin/oc                           # replaced by shell alias
  rm -rf ~/.config/opencode/profiles              # single-root config since Jul 2026

Adding a new run script:

1. Create in source state:
```
vim ~/.local/share/chezmoi/run_once_describe-what-it-does.sh
```

2. Make executable: `chmod +x`

3. Commit: `chezmoi-axi commit "chore: add run script for X"`

Re-run a run_once script:
```
rm ~/.local/share/chezmoi/.run_once/describe-what-it-does.sh
chezmoi-axi apply
```

Re-run a run_onchange script: just edit the file — chezmoi detects content change.

---

## Commit and PR Flow

Quick commit (stages, commits, pushes, opens PR):
```
chezmoi-axi commit "feat(app): add new config"
```

Full PR workflow: load /ce-commit-push-pr. Handles branching, committing, PR creation, cleanup.

Other machines pick up changes on next chezmoi update (cron every 30 min).

---

## Troubleshooting

### age key

Symptom: "chezmoi: <file>: encrypted, but age is not configured"

Fix:
```
cat ~/.config/chezmoi/chezmoi.toml
```

If missing, recreate:
```
mkdir -p ~/.config/chezmoi
cat > ~/.config/chezmoi/chezmoi.toml << 'EOF'
encryption = "age"
[age]
    identity = "~/.config/chezmoi/key.txt"
    recipient = "<age-recipient>"
EOF
```

Still broken? See passphrase incorrect.

---

### passphrase incorrect

Symptom: "could not decrypt" / "passphrase is incorrect"

Fix:
```
chezmoi age decrypt --passphrase \
  -o ~/.config/chezmoi/key.txt \
  ~/.local/share/chezmoi/age-key.txt.age
```

Find passphrase: search password manager for "Chezmoi Age Key". No leading/trailing whitespace.

Then re-apply: `chezmoi-axi apply`

---

### Bitwarden session

Symptom: .tmpl files show template syntax instead of values.

Fix:
```
export BW_SESSION=$(bw unlock --raw)
BW_SESSION="$BW_SESSION" chezmoi-axi apply
```

---

### SSH deploy key

Symptom: "Permission denied (publickey)" on chezmoi init or git push

Fix:
```
ssh -T git@github.com -i ~/.ssh/chezmoi-deploy-key
gh repo deploy-key add ~/.ssh/chezmoi-deploy-key.pub \
  --repo <owner>/<repo> \
  --title "chezmoi@$(hostname)" \
  --allow-write
```

---

## Naming Reference

naming[4]{target,source}:
  ~/.bashrc,dot_bashrc
  ~/.config/opencode/opencode.json,dot_config/opencode/opencode.json
  ~/.config/opencode/.cloudflare-key (encrypted),dot_config/opencode/encrypted_dot_cloudflare-key.age
  ~/.ssh/id_ed25519 (encrypted),dot_ssh/encrypted_private_id_ed25519.age

Rules:
- Replace leading . → dot_ prefix
- Preserve directory structure under dot_ prefix
- Encrypted files: prefix encrypted_ + suffix .age
- SSH private keys: use encrypted_private_ prefix (chezmoi convention)

Prefer `chezmoi add` over manual naming — it handles conventions automatically.
