# Global OpenCode Rules

## Git Commit Identity

Before any `git commit`, the agent **must** set the commit author identity dynamically from the deterministic session model:

```bash
# Chain: $OPENCODE_MODEL (user convention) → opencode.db session record → unknown
model="${OPENCODE_MODEL:-}"
if [ -z "$model" ] && command -v sqlite3 >/dev/null 2>&1 && [ -f "$HOME/.local/share/opencode/opencode.db" ]; then
  model="$(sqlite3 "$HOME/.local/share/opencode/opencode.db" "SELECT model FROM session ORDER BY time_updated DESC LIMIT 1;" 2>/dev/null | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')"
fi
export GIT_AUTHOR_NAME="${model:-unknown}@$(hostname -s)"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
```

`opencode.db` is SQLite at `~/.local/share/opencode/opencode.db`; the `session` table's `model` column stores JSON like `{"id":"big-pickle","providerID":"opencode"}`. `ORDER BY time_updated DESC LIMIT 1` selects the active session. If resolution yields `unknown`, prompt the user for the model name on first commit.

The format is always: **`<model>@<hostname>`** — e.g., `big-pickle@nasbox` or `gpt-oss-120b@phillias-dev`.

This applies to both `GIT_AUTHOR_NAME` and `GIT_COMMITTER_NAME`.

## Conventional Commits

All commit messages **must** follow the Conventional Commits format:

```
<type>(<scope>): <description>

<body> (optional)
<footer> (optional)
```

Types: `feat`, `fix`, `chore`, `docs`, `style`, `refactor`, `perf`, `test`, `ci`, `build`

## Path Portability (Parity Rule)

Never hardcode an absolute home path (`/home/<user>`, `/Users/<user>`) in configs, systemd units, skills, scripts, plugins, or docs. Every agent installation should reach parity using its own home directory.

- **Shell/scripts**: `$HOME`
- **Configs/docs**: `~`
- **Chezmoi templates** (`.tmpl`): `{{ .chezmoi.homeDir }}`
- **Systemd units**: `%h` (or a chezmoi `.tmpl` — never a literal path)
- **OpenCode configs**: `{env:HOME}`

A chezmoi source file containing a home path MUST be a `.tmpl`. Historical archives (`ARCHIVE.md`/`MIGRATION.md`) may retain pre-parity paths as documentation.

## PR Workflow

When pushing changes intended for a pull request:

1. **Before pushing**, check if a PR already exists from the current branch using `gh pr view --json title,body,state,baseRefName` or check the branch's upstream status.
2. **If a PR already exists**: push new commits, then update the PR body/description with `gh pr edit` to reflect the new changes.
3. **If no PR exists**: create a feature branch, push it, and open a pull request via `gh pr create --base master`.

To infer the base branch: compare `git merge-base` against `master` and `develop` and any other likely upstream branches, then pick the closest one (smallest divergence).

## Docker Service Discovery

When a live URL or container name is given, locate its compose/project dir via the running container before grep-ing the filesystem:

```bash
docker ps | grep <name-or-port-from-url>
docker inspect <container> | grep -iE 'WorkingDir|com.docker.compose.*Working.*Dir|com.docker.compose.project.config_files'
```

The runtime always knows where a running container came from; the filesystem does not.

## Compound Engineering Integration

When the compound-engineering skills are installed (`~/.agents/skills/ce-*`):
- Skill catalog and chaining guide: https://github.com/EveryInc/compound-engineering-plugin/blob/main/skills/guides/README.md (fetched locally with the plugin; the cache path is version-dependent, so reference the URL)
- `/lfg` is the default hands-off shipping gateway (plan → implement → review/fix → commit → push → PR → CI-to-green). Use `/ce-plan` when a plan gate is wanted first.
- Plan-first → `/ce-plan`; ambiguous scope → `/ce-brainstorm`; bugs → `/ce-debug`. Skill descriptions in `~/.agents/skills/` are the authoritative routing triggers.
- Sub-agents are pinned to budget-optimized models — do not override their assignments.

## Safety Guardrails

The agent **must not** perform the following without explicit user confirmation:

- `git push --force` or `git push --force-with-lease`
- `git reset --hard` on a branch with unpushed commits
- `git branch -D` (force delete)
- `git rebase --onto` against shared branches
- Deleting files outside the project scope
- Modifying files in `~/.config/opencode/` without being asked to

## Compound Engineering Skills

Short references; full trigger conditions and behavior live in each skill's `SKILL.md` (`~/.agents/skills/ce-*`):

- **`/lfg`** — full autonomous shipping pipeline to a green PR (plan → implement → review/fix → commit → push → PR → CI). Default gateway for clear ship requests.
- **`/ce-plan`** — structured planning with confidence gating; durable plans in `docs/plans/`.
- **`/ce-brainstorm`** — interactive requirements exploration; outputs a requirements doc for `/ce-plan`.
- **`/ce-work`** — execute a plan end-to-end (implementation → review → PR within Phases 3-4).
- **`/ce-code-review`** — parallel multi-agent review (`mode:autofix` for hands-off fixing, `mode:report-only` for read-only).
- **`/ce-debug`** — root-cause analysis with test-first fixes.
- **`/ce-compound`** — capture solved problems as durable learnings in `docs/solutions/`.
- **`/ce-optimize`** — metric-driven improvement loops.
- **`/ce-strategy`** — create or maintain `STRATEGY.md`.

**Invocation:** Use the `skill` tool with `name: ce-<skill>` (e.g. `name: lfg`). Sub-agents are pinned to budget-optimized models — do not override.

## Model Budget Awareness

All CE sub-agents are pinned to budget-optimized models. Do not override their model assignments. The session's current model is used for skill entry points only; sub-agents use their own pinned models.

## Token Budget Discipline

Token budget is a first-class design constraint. The authoritative source is the **AXI skill** (`~/.agents/skills/axi/SKILL.md`), which defines 10 principles for agent-ergonomic CLIs (TOON output, minimal schemas, content truncation, pre-computed aggregates, definitive empty states, structured errors, ambient context, content-first, contextual disclosure, consistent help).

**Directive:** Treat token count as a measurable cost when building or reviewing agent-facing tools, CLIs, or structured output. Prefer TOON over JSON; default to 3-4 fields, not 10; truncate large output with size hints; include aggregates; fail with structure, not noise. **Load the full AXI skill** for CLI design, output formatting, or AXI review — not for general coding, debugging, or code review.

## Dispatch Rules

Read `~/.config/opencode/dispatch-rules.json` at task intake to translate task shape into `task(...)` calls. Schema and examples live in the file itself. **Evaluation order:** (1) explicit user instruction this turn wins; (2) first matching rule in `rules[]`; (3) the `default` block. Rules are advisory — apply judgment. Skip the file for trivially obvious single-step tasks, mid-clarification conversations, or work already in flight. Edit the file directly; re-read it when its mtime is newer than the cached read.

## Fleet State Communications (Zero-Token Background-Task Status)

Background-task completion notifications ride the `chat.message` hook chain and can be disrupted by compaction, model fallback, or plugins intercepting mid-turn. A sidecar state tree at `~/.local/state/opencode-fleet/` survives those drops:

| File | Purpose |
|---|---|
| `wake.log` | TSV append-only event log (rotates >1MB to last 1000 lines). |
| `state.json` | Current state of every dispatched task (writer-owned; terminal states never overwritten). |
| `digest.txt` | TSV snapshot: `<key>\t<status>\t<type>\t<digest>\t<age>`. Regenerated on every state change. |
| `decisions.tsv` | Authored decisions (written only by `fleet-note.sh`, never by the plugin). |

**Writer:** `plugins/fleet-state-writer.ts` (auto-loaded) subscribes to `event` (session.* lifecycle), `chat.message` (mines `[BACKGROUND TASK *]` headers), and `tool.execute.after` (`background_output` calls). All handlers catch+log — zero LLM cost. On every non-terminal update whose digest differs, it appends a `fleet.replaced` wake so no transition is silently swallowed.

**Decision authoring:** `scripts/fleet-note.sh <key> --decision "<text>" [--type dispatch\|merge\|teardown]` — flock-guarded filesystem write that never touches `state.json`. Record at dispatch and at terminal outcome.

**Reader:** `scripts/fleet-digest.sh` (pure bash, zero LLM cost): default = snapshot + wakes from last 30m; `--since N` = last N minutes; `--wakes-only`; `--json` = raw state.json.

### When to consult fleet state

- **At session start:** `fleet-digest.sh` to ground in fleet state before responding.
- **After a background-task system-reminder:** verify against `state.json`, don't trust only the reminder.
- **Before dispatching:** glance at `digest.txt` to avoid duplicate dispatches.
- **"What's running?":** `fleet-digest.sh --since 240`.

### Failure modes

- `state.json` empty/missing → sidecar not loaded; fall back to `background_output` API.
- `wake.log` corrupted → truncate; the plugin repopulates.
- The state tree is a **terse index**, never the task transcript (that lives in `opencode.db`).

## Self-Learning & Memory

- **Golden paths → skills.** When a task only worked after several attempts, or you worked out a non-obvious recurring workflow (DB access, deploy, env-var locations, verification), harvest it as a reusable skill via the `self-learning` skill (`~/.agents/skills/self-learning/`). Promotion rule: promote only when verified (passing check) + a repeatable verification step + named failure pattern + ≥1 ruled-out dead-end; otherwise record a low-confidence `mem` note (`mem add --confidence 0.2`) instead.
- **Facts & one-liners → axi-memory.** Single facts/corrections go to axi-memory (`axi-memory-add` tool or `mem add --type <constraint|decision|failure|howto|preference>`), not a new skill.
- **Seeding → axi-memory, cheap.** Short research items are the catalog-building flow: `mem add` them directly (decision/howto, `--priority 50`) — no skill promotion, no filtering. They are expected to be many and shallow.
- **Struggle sessions → winning-path memories, guaranteed.** The infrequent, dense sessions are where the value is: a multi-step win → skill; a single-step win (one fix, one command that mattered) → `mem add --type howto|failure --priority 75+`. These are the "winning path" memories — never let them fall through the cracks.
- **Dedup is OS-side, not LLM.** After any batch of adds (seeding or harvest), run `mem dedup --dry-run` (normalized-title Jaccard, zero LLM cost); `mem dedup --apply` merges near-duplicates keeping the higher priority. Only escalate to an LLM judgment when the OS heuristic looks wrong.
- **Never write secret values** into skills or memory — record where they live (env var, vault, MCP tool), never the value.
- **Autocapture cues.** The `self-learning-autocapture` plugin writes harvest cues to `~/.local/state/opencode-selflearning/cues.tsv` when it detects hard-won wins or explicit skill requests. At session start, if that file is non-empty: triage by kind — `hard-win` cues always harvest (winning path → skill or howto/failure memory); `explicit` cues always; `session` (high-activity) cues harvest only if the session actually contains a verified win. Then append processed lines to `processed.tsv` and truncate `cues.tsv`. After harvesting, run `mem dedup --apply` to merge winning paths that repeat prior lessons.
- **Skill review digest.** The same plugin maintains `skills_review.tsv` (pre-aggregated, ≤8 lines, **empty when nothing needs review**) plus raw evidence (`skill_applications.tsv`, `skill_feedback.tsv`) and counters (`skill_stats.tsv`) under `~/.local/state/opencode-selflearning/`. At session start, if `skills_review.tsv` is non-empty: read each line (`<skill>\t<loads>\t<fails>\t<idle>\t<reason>`), report flagged skills to the user one line each, and propose **keep / update / demote-to-mem / retire**. **Never demote or delete a skill without explicit user approval** — retire = move to a `_review/` folder or convert to a low-confidence `mem` note, never delete. Record decisions in `review-decisions.tsv`; when retiring, append `<skill>\t<retiredTs>` to `retired.tsv` so the plugin can surface re-promotion candidates (retired skills loaded ≥2× post-retirement). Re-promotion is manual + user-approved (flywheel reversibility).

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
