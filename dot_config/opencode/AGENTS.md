# Global Rules

## Self-learning flywheel — consume harvest cues at session start

State dir: `~/.local/state/opencode-selflearning/`

If `cues.tsv` is non-empty:

1. Read each line: `<ts>\t<kind>\t<sessionID>\t<detail>` (kinds: `explicit` | `hard-win` | `session`)
2. For each cue, follow the `self-learning` skill: harvest the golden path into a skill, or route one-off facts to axi-memory. Skip noise and false positives (e.g. `<auto-slash-command>` expansions).
3. Append each processed cue to `processed.tsv` (same columns + disposition) and truncate `cues.tsv`.

Rules:

- Never demote, move, or delete a skill without explicit user approval
- Secrets never go in skill files — record only where to find them
- Keep `SKILL.md` < 500 lines; push detail into `references/`
