# OpenRouter Key to Dotfiles

## TL;DR

> **Quick Summary**: Copy the OpenRouter API key from opencode's auth store to a managed dotfiles location, export it in shell environments, and age-encrypt it via chezmoi for cross-machine sync.
>
> **Deliverables**:
> - `~/.config/opencode/.openrouter-key` (plaintext, gitignored)
> - Shell exports in `~/.bashrc` and `~/.zshrc`
> - Chezmoi-managed `dot_config/opencode/dot_openrouter-key.age` (age-encrypted)
> - Dotfiles PR on master branch
>
> **Estimated Effort**: Quick (<10 min)
> **Parallel Execution**: NO - sequential chain
> **Critical Path**: Task 1 → Task 2 → Task 3 → Task 4

---

## Context

### Original Request
Copy the OpenRouter key from opencode's auth store into `~/.config/opencode/.openrouter-key`, set up bashrc/zshrc to export it, chezmoi-add the file age-encrypted, and create a dotfiles PR.

### Research Findings
- Key source: `~/.local/share/opencode/auth.json` → `openrouter.key` (sk-or-v1-7a557bd7a42...)
- Target: `~/.config/opencode/.openrouter-key` (does not exist yet)
- Chezmoi source: `~/.local/share/chezmoi/` (age encryption configured)
- Existing shell exports: `ANTHROPIC_BASE_URL="https://openrouter.ai"` in both bashrc and zshrc
- No existing OPENROUTER_API_KEY export

---

## Work Objectives

### Core Objective
Persist the OpenRouter API key in a chezmoi-managed, age-encrypted dotfiles setup for cross-machine availability.

### Must Have
- Plaintext key file at `~/.config/opencode/.openrouter-key`
- `export OPENROUTER_API_KEY` in both `~/.bashrc` and `~/.zshrc`
- Chezmoi age-encrypted copy in dotfiles repo
- Dotfiles PR created

### Must NOT Have
- Do NOT commit plaintext key to git (must be age-encrypted)
- Do NOT modify `~/.local/share/opencode/auth.json`
- Do NOT echo the key to terminal output
- Do NOT add the key to any file that isn't gitignored or encrypted

---

## Verification Strategy

### QA Policy
Agent-executed verification via Bash commands. Evidence saved to `.omo/evidence/`.

---

## Execution Strategy

### Sequential Chain (trivial scope)

```
Task 1: Write key file + shell exports
  → Task 2: Chezmoi add (age-encrypt)
    → Task 3: Verify encryption + shell sourcing
      → Task 4: Create dotfiles PR
```

---

## TODOs

- [ ] 1. Write key file and shell exports

  **What to do**:
  - Extract key from `~/.local/share/opencode/auth.json`
  - Write to `~/.config/opencode/.openrouter-key` (chmod 600)
  - Append to `~/.bashrc`: `export OPENROUTER_API_KEY="$(cat ~/.config/opencode/.openrouter-key 2>/dev/null)"`
  - Append to `~/.zshrc`: same export line
  - Ensure both files end with newline

  **Must NOT do**:
  - Do NOT echo the key value to terminal
  - Do NOT create the file with world-readable permissions

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Blocks**: Task 2
  - **Blocked By**: None

  **References**:
  - `~/.local/share/opencode/auth.json` - Key source (field: openrouter.key)
  - `~/.bashrc` - Append export to end
  - `~/.zshrc` - Append export to end

  **Acceptance Criteria**:
  - [ ] `~/.config/opencode/.openrouter-key` exists with 600 permissions
  - [ ] File content matches key from auth.json
  - [ ] `grep OPENROUTER_API_KEY ~/.bashrc` returns the export line
  - [ ] `grep OPENROUTER_API_KEY ~/.zshrc` returns the export line

  **QA Scenarios**:

  ```
  Scenario: Key file created correctly
    Tool: Bash
    Steps:
      1. stat -c "%a" ~/.config/opencode/.openrouter-key
      2. wc -c < ~/.config/opencode/.openrouter-key
    Expected: permissions=600, size=73 (72 chars + newline)
    Evidence: .omo/evidence/task-1-key-file.txt

  Scenario: Shell exports present
    Tool: Bash
    Steps:
      1. grep -c "OPENROUTER_API_KEY" ~/.bashrc
      2. grep -c "OPENROUTER_API_KEY" ~/.zshrc
    Expected: both return 1
    Evidence: .omo/evidence/task-1-shell-exports.txt
  ```

  **Commit**: NO (done in Task 3 via chezmoi)

- [ ] 2. Chezmoi add the key file (age-encrypt)

  **What to do**:
  - Run `chezmoi add ~/.config/opencode/.openrouter-key`
  - This will age-encrypt the file and place it in `~/.local/share/chezmoi/dot_config/opencode/dot_openrouter-key.age`
  - Verify the .age file exists and is not plaintext
  - Also chezmoi-add the updated bashrc and zshrc: `chezmoi add ~/.bashrc ~/.zshrc`

  **Must NOT do**:
  - Do NOT use `chezmoi add --encrypt=false`
  - Do NOT commit before verifying encryption

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: [`dotfiles-chezmoi`]

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Blocks**: Task 3
  - **Blocked By**: Task 1

  **References**:
  - `~/.local/share/chezmoi/` - Chezmoi source directory
  - `~/.config/chezmoi/chezmoi.json` or `~/.config/chezmoi/chezmoi.toml` - Age encryption config

  **Acceptance Criteria**:
  - [ ] `ls ~/.local/share/chezmoi/dot_config/opencode/dot_openrouter-key.age` succeeds
  - [ ] `file ~/.local/share/chezmoi/dot_config/opencode/dot_openrouter-key.age` shows "data" or "age" (not text)
  - [ ] `chezmoi diff` shows no unexpected changes

  **QA Scenarios**:

  ```
  Scenario: Age-encrypted file exists
    Tool: Bash
    Steps:
      1. ls -la ~/.local/share/chezmoi/dot_config/opencode/dot_openrouter-key.age
      2. head -c 20 ~/.local/share/chezmoi/dot_config/opencode/dot_openrouter-key.age | xxd | head -1
    Expected: File exists, starts with age magic bytes (not plaintext)
    Evidence: .omo/evidence/task-2-age-encrypted.txt

  Scenario: Chezmoi clean
    Tool: Bash
    Steps:
      1. chezmoi diff 2>&1 | head -20
    Expected: No diff (all changes committed)
    Evidence: .omo/evidence/task-2-chezmoi-clean.txt
  ```

  **Commit**: NO (committed in Task 4)

- [ ] 3. Verify encryption and shell sourcing

  **What to do**:
  - Verify the .age file cannot be read as plaintext
  - Source both shell configs and verify the env var is set
  - Test that `source ~/.bashrc && echo $OPENROUTER_API_KEY | head -c 10` shows the key prefix

  **Must NOT do**:
  - Do NOT print the full key

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Blocks**: Task 4
  - **Blocked By**: Task 2

  **References**:
  - `~/.local/share/chezmoi/dot_config/opencode/dot_openrouter-key.age` - Encrypted file

  **Acceptance Criteria**:
  - [ ] `cat ~/.local/share/chezmoi/dot_config/opencode/dot_openrouter-key.age | grep -c "sk-or"` returns 0 (not plaintext)
  - [ ] `bash -c 'source ~/.bashrc && echo $OPENROUTER_API_KEY | head -c 10'` returns `sk-or-v1-7`
  - [ ] `zsh -c 'source ~/.zshrc && echo $OPENROUTER_API_KEY | head -c 10'` returns `sk-or-v1-7`

  **QA Scenarios**:

  ```
  Scenario: File is encrypted
    Tool: Bash
    Steps:
      1. grep -c "sk-or" ~/.local/share/chezmoi/dot_config/opencode/dot_openrouter-key.age
    Expected: 0 (no plaintext in .age file)
    Evidence: .omo/evidence/task-3-encrypted.txt

  Scenario: Shell export works
    Tool: Bash
    Steps:
      1. bash -c 'source ~/.bashrc && echo $OPENROUTER_API_KEY | head -c 10'
      2. zsh -c 'source ~/.zshrc && echo $OPENROUTER_API_KEY | head -c 10'
    Expected: both return "sk-or-v1-7"
    Evidence: .omo/evidence/task-3-shell-test.txt
  ```

  **Commit**: NO

- [ ] 4. Create dotfiles PR

  **What to do**:
  - `cd ~/.local/share/chezmoi` (or wherever the dotfiles repo is)
  - Create feature branch: `git checkout -b feat/openrouter-key`
  - `git add dot_config/opencode/dot_openrouter-key.age dot_bashrc dot_zshrc`
  - `git commit -m "feat(opencode): add OpenRouter API key (age-encrypted)"`
  - Push branch: `git push -u origin feat/openrouter-key`
  - Create PR: `gh pr create --base master --title "feat(opencode): add OpenRouter API key" --body "Adds OpenRouter API key as age-encrypted chezmoi-managed file. Exports OPENROUTER_API_KEY in bashrc and zshrc."`
  - Return PR URL

  **Must NOT do**:
  - Do NOT commit any plaintext key files
  - Do NOT push to master directly
  - Do NOT merge the PR (user reviews first)

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: [`dotfiles`, `ce-commit-push-pr`]

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Blocks**: None (final task)
  - **Blocked By**: Task 3

  **References**:
  - `~/.local/share/chezmoi/` - Dotfiles repo root
  - `~/.config/opencode/skills/dotfiles/SKILL.md` - Dotfiles conventions

  **Acceptance Criteria**:
  - [ ] Branch `feat/openrouter-key` created and pushed
  - [ ] PR created with title and description
  - [ ] No plaintext key in git diff: `git diff master..feat/openrouter-key | grep -c "sk-or"` returns 0
  - [ ] PR URL returned

  **QA Scenarios**:

  ```
  Scenario: PR created successfully
    Tool: Bash
    Steps:
      1. gh pr view --json title,url,state
    Expected: PR exists with title containing "OpenRouter"
    Evidence: .omo/evidence/task-4-pr-created.txt

  Scenario: No plaintext in diff
    Tool: Bash
    Steps:
      1. cd ~/.local/share/chezmoi && git diff master..HEAD | grep -c "sk-or-v1"
    Expected: 0
    Evidence: .omo/evidence/task-4-no-plaintext.txt
  ```

  **Commit**: YES (the PR IS the commit)
  - Message: `feat(opencode): add OpenRouter API key (age-encrypted)`
  - Files: `dot_config/opencode/dot_openrouter-key.age`, `dot_bashrc`, `dot_zshrc`

---

## Success Criteria

### Verification Commands
```bash
# Key file exists and is encrypted
file ~/.config/opencode/.openrouter-key  # ASCII text (plaintext, gitignored)
file ~/.local/share/chezmoi/dot_config/opencode/dot_openrouter-key.age  # Data (encrypted)

# Shell exports work
source ~/.bashrc && echo ${OPENROUTER_API_KEY:0:10}  # sk-or-v1-7
source ~/.zshrc && echo ${OPENROUTER_API_KEY:0:10}   # sk-or-v1-7

# PR exists
gh pr list | grep -i openrouter
```

### Final Checklist
- [ ] Plaintext key at `~/.config/opencode/.openrouter-key` (600 perms)
- [ ] Age-encrypted at `dot_config/opencode/dot_openrouter-key.age`
- [ ] `OPENROUTER_API_KEY` exported in bashrc and zshrc
- [ ] PR created on master
