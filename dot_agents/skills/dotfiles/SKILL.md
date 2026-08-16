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
Deep reference (machine setup, run scripts, setup & recovery): read `refs/DESIGN.md`.

## Skills

skills[2]{name,description}:
  chezmoi-axi,Agent-friendly chezmoi wrapper with TOON output — status, list, diff, add, re-add, apply, verify, sync, commit
  no-mistakes,PR pipeline — review, push, and open a PR; this repo declares no_ci so the gate treats an empty checks response as passed

> **DEFAULT WORKFLOW**: Any dotfiles change that ships goes through the Commit and PR Flow below
> (no-mistakes, no-ci). `chezmoi-axi commit` is ONLY for trivial local-only direct-to-master fixes.

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

## What are you trying to do?

situations[11]{situation,go-to}:
  New config file to start tracking,Add a new file
  Edited tracked file on disk,Re-add a changed file
  File has secrets — need to encrypt,Encrypt a file
  View/edit encrypted file contents,Decrypt a file
  Changes not showing on another machine,Sync changes across machines
  Stop tracking a file,Remove a file
  Exclude files from chezmoi,Manage .chezmoiignore
  Run cleanup/setup scripts during apply,refs/DESIGN.md — Run scripts
  Encrypted files skipped during apply,refs/DESIGN.md — Setup & Recovery
  New machine,refs/DESIGN.md — Setup
  Broken SSH deploy key,refs/DESIGN.md — Setup & Recovery

---

## Procedures

### Add a new file

Before you begin: All configs ship from a topic branch off master. Secrets encrypted with age.

```
chezmoi-axi add ~/.tmux.conf                           # unencrypted
chezmoi-axi add --encrypt ~/.config/some-app/token     # encrypted
```

Verify: `chezmoi-axi diff` — no differences.

Ship: **run no-mistakes (no-ci)** per the Commit and PR Flow.

---

### Re-add a changed file

```
chezmoi-axi re-add ~/.bashrc      # single file
chezmoi-axi re-add --all          # all changed files
```

Verify: `chezmoi-axi diff` — should be clean.

Ship: **run no-mistakes (no-ci)** per the Commit and PR Flow.

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

Ship: **run no-mistakes (no-ci)** per the Commit and PR Flow.

Note: .groq-key removed 2026-07-18 (Groq free-tier TPM limits). Examples use .cloudflare-key.

---

### Decrypt a file

```
chezmoi cat ~/.config/opencode/.cloudflare-key         # view (stdout)
chezmoi edit ~/.config/opencode/.cloudflare-key        # edit (decrypts, opens editor, re-encrypts)
```

No ship for chezmoi cat (read-only). After chezmoi edit, **run no-mistakes (no-ci)** per the Commit and PR Flow.

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

## Commit and PR Flow

> **ALWAYS USE THIS** for any dotfiles change that ships (reaches other machines).

steps[6]{step,action}:
  1,"Gate 1 — `chezmoi-axi status` / `verify` / `diff`. ANY drift or unexpected diff: raise it, reconcile first — never proceed to add/re-add on unexplained state."
  2,"Branch — confirm on master (`chezmoi git -- branch`), then `chezmoi git -- checkout -b <topic>` off master."
  3,Track — `chezmoi-axi add`/`re-add` (`--encrypt` for secrets) so source state matches what you changed.
  4,"Ship — run `no-mistakes axi run --intent \"<what the change accomplishes>\"`. no-ci is declared in this repo's `.no-mistakes.yaml`. `chezmoi-axi commit` is ONLY for trivial local-only fixes on master."
  5,Gate 2 — `chezmoi-axi status` / `verify` / `diff` again before the PR lands; fix anything unexpected.
  6,"After merge — `chezmoi git -- checkout master && chezmoi git -- pull`, so the local repo always lands back on master and no future commit targets the wrong branch."

The no-mistakes pipeline opens the PR and owns branch cleanup and merge monitoring. Other machines pick up merged changes on next chezmoi update (cron every 30 min).

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
