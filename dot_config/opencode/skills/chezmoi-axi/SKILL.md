---
name: chezmoi-axi
description: >
  Agent-ergonomic chezmoi wrapper with TOON output for token-efficient dotfiles management.
  Use when managing chezmoi dotfiles from an agent — list managed files, check status,
  review diffs, add/re-add files, and apply changes with structured, minimal output.
  Load when working with dotfiles, chezmoi, or config management in agent context.
---

# chezmoi-axi

Agent-ergonomic wrapper around chezmoi following the [AXI 10 principles](https://axi.md).
Wraps chezmoi commands with TOON output for ~40% token savings over plain text.

## Installation

The `chezmoi-axi` script lives at `~/.local/bin/chezmoi-axi`. Ensure `~/.local/bin` is on PATH.

## Commands

### `chezmoi-axi status`

Home view — shows current state at a glance. No arguments = live content (Principle 8).

```
chezmoi-axi status
```

Output: managed count, pending diffs count, last sync time, encrypted count.

### `chezmoi-axi list`

List managed files with minimal schema (Principle 2). Default: path + type + encrypted flag.

```
chezmoi-axi list              # all managed files
chezmoi-axi list --changed    # only files with pending diffs
chezmoi-axi list --encrypted  # only encrypted files
```

### `chezmoi-axi diff`

Show differences between source state and installed files.

```
chezmoi-axi diff              # all diffs
chezmoi-axi diff <file>       # diff for specific file
```

Output: TOON-formatted diff summary with file path, change type, line counts.

### `chezmoi-axi add <file>`

Add a file to chezmoi source state. Idempotent — no error if already tracked (Principle 6).

```
chezmoi-axi add ~/.config/app/config.json
chezmoi-axi add --encrypt ~/.config/app/secret.key
```

### `chezmoi-axi re-add <file>`

Capture on-disk changes back to source state. Idempotent (Principle 6).

```
chezmoi-axi re-add ~/.bashrc
chezmoi-axi re-add --all      # re-add all changed files
```

### `chezmoi-axi apply`

Apply source state to installed files. Structured errors on failure (Principle 6).

```
chezmoi-axi apply
chezmoi-axi apply --preview   # dry run — shows what would change
```

### `chezmoi-axi verify`

Check that installed files match source state. Exits 0 if clean, 1 if drifted (Principle 5).

```
chezmoi-axi verify
```

### `chezmoi-axi sync`

Pull remote changes and apply. Combines `git pull` + `chezmoi apply`.

```
chezmoi-axi sync
chezmoi-axi sync --preview    # fetch + diff, no apply
```

### `chezmoi-axi commit [message]`

Stage all chezmoi changes, commit, push, and open a PR. Uses conventional commits.

```
chezmoi-axi commit                    # auto-generated message
chezmoi-axi commit "feat(app): add new config"
```

## Output Format

All output uses TOON (Token-Oriented Object Notation) per AXI Principle 1.

**Status example:**
```
chezmoi:
  bin: ~/.local/bin/chezmoi-axi
  description: Agent-ergonomic chezmoi wrapper
  managed: 47
  changed: 2
  encrypted: 8
  last_sync: 2h ago
help[2]:
  Run `chezmoi-axi list --changed` to see pending changes
  Run `chezmoi-axi diff` to review diffs
```

**List example:**
```
files[5]{path,type,encrypted}:
  ~/.bashrc,shell,no
  ~/.config/opencode/opencode.json,json,no
  ~/.config/opencode/.groq-key,key,yes
  ~/.ssh/config,ssh,no
  ~/.tmux.conf,config,no
count: 5 of 47 total
help[2]:
  Run `chezmoi-axi add <file>` to track a new file
  Run `chezmoi-axi diff` to review changes
```

**Empty state example (Principle 5):**
```
files: 0 changed files found
help[1]:
  Run `chezmoi-axi list` to see all managed files
```

## Error Format

Errors go to stdout in the same structured format (Principle 6):

```
error: file not managed by chezmoi: ~/.config/missing/file
help: Run `chezmoi-axi add ~/.config/missing/file` to start tracking it
```

## Contextual Disclosure

Every command includes 1-3 next-step suggestions (Principle 9) relevant to the current output.
Suggestions omit when the output is self-contained (detail views, confirmations).

## Token Budget

This skill is static — no per-session live state. For ambient context at session start,
use the dotfiles skill's health check procedures instead.
