# phillias/dotfiles

Chezmoi source repo. `chezmoi apply` renders everything here onto `$HOME`; edits go to this repo, never to rendered files.

## Tooling invariants

- Tools are mise-managed in `dot_config/mise/config.toml`; pin exact versions and note why each tool exists.
- pi model catalog lives in `private_dot_pi/private_agent/models.json.tmpl` and fallback chains in `private_dot_pi/fallback-chains.json`; a model referenced by a fallback chain must exist in the catalog or pi fails with `Model not found`.
- Vercel AI Gateway router-kind virtual models must be referenced as `router/<slug>`, not `vmc/<slug>`; the API rejects `vmc/` for routers with a 400 error. Do not "fix" `router/` ids back to `vmc/`.

## Never commit sandbox debris

- `.home-test/` and `.pi-test/` are pi test-suite sandboxes written inside this repo during validation runs; they hold conversation logs, binaries, extensions, and credentials (`auth.json`). They are gitignored; never stage, commit, or ship them.
- Any file under those directories appearing in a diff is test debris, not source code. Authors must remove it from the branch before review. Bot findings that scan `.home-test/.pi/agent/sessions/*.jsonl` (for example "SQL injection risk") are scanning logs, not code.

## Validation contracts

- A documentation or lint step must never revert or alter reviewed behavior changes (model ids, flags, config semantics); wording and comments only. If docs contradict reviewed code, the code wins and the doc gets fixed.
- `dot_no-mistakes/config.yaml` must not pass `--no-extensions` to pi: pi needs extensions to resolve `fallback/*` model chains.
