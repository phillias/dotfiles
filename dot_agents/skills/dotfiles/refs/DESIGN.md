---
# dotfiles design reference

Deep reference behind the `dotfiles` skill. Day-to-day operations live in `SKILL.md`;
this file owns machine setup, run scripts, and setup/recovery detail.

## Setup

### Initial machine setup

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

Fresh-install bootstrap troubleshooting (first-time setup failing) → load `dotfiles-chezmoi`.
The `scripts/` directory also holds standalone one-off installers (setup.sh, setup-omp.sh,
install-hermes-honcho.sh, install-et-sslh-for-moshi.sh) — they are NOT chezmoi run scripts.

---

## Run scripts

Chezmoi can run scripts automatically during `chezmoi apply`. Scripts use special name prefixes:

script-types[2]{prefix,runs,use-case}:
  run_once_,Once per machine (tracked in .run_once),One-time migrations, cleanup
  run_onchange_,When file content changes (hash tracked),Installs, updates, rebuilds

Scripts can have a .tmpl suffix for templating. Template expressions re-evaluate on every apply,
so a template that embeds live state (e.g. a `find | sha256sum` fingerprint) re-triggers the
script when that state changes — this is how cleanup self-maintains across machines.

### Current inventory (source state root)

run_onchange_cleanup-and-sync.sh.tmpl — consolidated housekeeping, runs whenever its rendered
content changes (and on every machine):
  responsibilities: remove stale files, prune session-generated + deprecated skills, report
    source-repo branch/drift health, print `chezmoi add` suggestions for unmanaged files
  managed dirs: ~/.agents → dot_agents/, ~/.config/opencode → dot_config/opencode/,
    ~/.config/systemd/user → dot_config/systemd/user/
  fingerprints: agents, opencode, systemd, cleanup — each embeds a live `find | sha256sum`;
    any drift re-triggers the script on the next apply
  constraint: can never call `chezmoi add` itself (runs while chezmoi holds the state lock) —
    it prints the add commands instead

Legacy note: an older SKILL.md listed `run_once_cleanup-stale.sh.tmpl`; that script no longer
exists — its cleanup job moved into the consolidated run_onchange above.

### Adding a new run script

1. Create in source state:
```
vim ~/.local/share/chezmoi/run_once_describe-what-it-does.sh
```

2. Make executable: `chmod +x`

3. Ship through no-mistakes (no-ci) per the SKILL.md Commit and PR Flow.

### Re-run mechanics

Re-run a run_once script:
```
rm ~/.local/share/chezmoi/.run_once/describe-what-it-does.sh
chezmoi-axi apply
```

Re-run a run_onchange script: just edit the file — chezmoi detects the content change.

---

## Setup & Recovery

Initial-setup concerns and the fixes when a machine's secrets or access break. Presented as
symptom → fix.

setup-recovery[4]{symptom,fix}:
  "encrypted, but age is not configured",Recreate ~/.config/chezmoi/chezmoi.toml with encryption = "age" + identity + recipient
  "could not decrypt" / "passphrase is incorrect",Re-decrypt the age key from age-key.txt.age using the passphrase
  .tmpl files show template syntax instead of values,Export BW_SESSION then re-apply
  "Permission denied (publickey)" on init/push,Verify the SSH deploy key against GitHub

### age not configured

Symptom: "chezmoi: <file>: encrypted, but age is not configured"

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

### passphrase incorrect

Symptom: "could not decrypt" / "passphrase is incorrect"

```
chezmoi age decrypt --passphrase \
  -o ~/.config/chezmoi/key.txt \
  ~/.local/share/chezmoi/age-key.txt.age
```

Find passphrase: search password manager for "Chezmoi Age Key". No leading/trailing whitespace.

Then re-apply: `chezmoi-axi apply`

### Bitwarden session

Symptom: .tmpl files show template syntax instead of values.

```
export BW_SESSION=$(bw unlock --raw)
BW_SESSION="$BW_SESSION" chezmoi-axi apply
```

### SSH deploy key

Symptom: "Permission denied (publickey)" on chezmoi init or git push.

```
ssh -T git@github.com -i ~/.ssh/chezmoi-deploy-key
gh repo deploy-key add ~/.ssh/chezmoi-deploy-key.pub \
  --repo <owner>/<repo> \
  --title "chezmoi@$(hostname)" \
  --allow-write
```
