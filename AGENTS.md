# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- Add durable project-specific notes here as they are discovered through real work.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.

## Sharp edges

This repo's apply target is the ENTIRE home directory of every fleet host that runs chezmoi against it, so a bad source change lands everywhere.
Never run `chezmoi apply` from any worktree.
`~/.local/share/chezmoi` is out of bounds for agents outside the guarded workflow: disable the chezmoi sync crontab, edit the source, ship a PR, then re-enable the crontab.

Secrets must never be committed plaintext; chef-encrypted keys live under
`dot_agents/private_keys/` as ASCII-armored `age` files (header
`-----BEGIN AGE ENCRYPTED FILE-----`), with the identity configured in
`~/.config/chezmoi/chezmoi.toml`. Compose-project env files (e.g.
`docker/private_bench-studio/private_dot_env` → `~/docker/bench-studio/.env`)
are tracked unencrypted with `${VAR}` interpolation placeholders only.
Provider loaders in `dot_zshrc` and `dot_bashrc` must stay in parity — update
both when adding a key.

## Keeping this repo aligned with AGENTS.md

Verify with `bash -n dot_bashrc && zsh -n dot_zshrc` and
`chezmoi managed --source .` when touching chezmoi sources.
