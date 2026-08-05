# Self-Improvement Loop

The captain-private, machine-wide system that closes the learning loop for this
OpenCode agent environment: detect hard-won knowledge, gate deterministically,
harvest it into durable stores, and compound solved problems — with near-zero
LLM cost for everything except the actual writing.

This is **not** firstmate shared material. It is global agent infrastructure
living in `~/.config/opencode/`, `~/.agents/skills/`, `~/.local/bin/`, and
`~/.config/systemd/user/`. Every file below is chezmoi-managed except the
runtime state dir.

## The pipeline

```
DETECT ──▶ GATE ──▶ HARVEST ──▶ COMPOUND
 (free)    (free)    (LLM)       (LLM)
```

| Stage | Zero-token? | Mechanism | Artifacts |
|---|---|---|---|
| DETECT | yes | `self-learning-autocapture.ts` plugin: regex/TSV detection at `session.idle` | `cues.tsv`, `skill_stats.tsv` → `skills_review.tsv` |
| GATE | yes | `fm-selfimprove-drain.sh`: exits silently unless a queue is non-empty | log entry only when running |
| HARVEST | no | headless `opencode run --pure --agent self-improve` | skills, axi-memory entries, `processed.tsv` |
| COMPOUND | no | `compound` skill writes/refreshes `docs/solutions/` | solution docs |

The LLM is spent exactly once per drain: the harvesting run. Everything upstream
is file-state checks and regex — zero tokens when there is nothing to do.

## Components

### 1. DETECT — self-learning-autocapture plugin

`~/.config/opencode/plugins/self-learning-autocapture.ts` (pre-existing,
untouched by this system).

- Watches sessions for hard-won wins and explicit "make this a skill" requests.
- Writes TSV harvest cues to `~/.local/state/opencode-selflearning/cues.tsv`:
  `<ISO-ts>\t<kind>\t<sessionID>\t<detail>` where kind is `explicit`, `hard-win`,
  or `session`.
- Tracks every `skill` tool load → `skill_applications.tsv`, aggregated into
  `skill_stats.tsv`.
- Negative signals (skill wrong/outdated/stale) matched by regex → `skill_feedback.tsv`.
- At `session.idle`, pre-aggregates into `skills_review.tsv` (≤8 lines, EMPTY
  when nothing needs review). The digest only SUGGESTS review — demotion is
  always user-approved, never plugin-deleted.
- Retired skills loaded again → re-promotion candidates in `retired.tsv`
  (manual + user-approved, flywheel reversibility).

### 2. GATE — fm-selfimprove-drain.sh

`~/.local/bin/fm-selfimprove-drain.sh`

```
if cues.tsv empty AND skills_review.tsv empty  →  exit 0 silently (no log)
else  →  opencode run --pure --agent self-improve "Run your full procedure now."
```

- Runs via systemd user units:
  - `~/.config/systemd/user/selfimprove-drain.service` (`Type=oneshot`,
    `ExecStart=%h/.local/bin/fm-selfimprove-drain.sh`)
  - `~/.config/systemd/user/selfimprove-drain.timer` (every 6h, `OnBootSec=15min`)
- `%h` not a hardcoded home path — the repo's portability convention.
- **`--pure` is critical**: it disables plugins so the drain run cannot
  re-trigger the autocapture plugin and create a self-referential cue loop.
- Log: `~/.local/state/opencode-selflearning/selfimprove-drain.log`.

### 3. HARVEST — the self-improve agent

`~/.config/opencode/agents/self-improve.md` (mode: primary, model
`opencode-zen/glm-5.1`).

Carries the **full drain procedure in its prompt** — headless `opencode run`
does NOT load the global `AGENTS.md`, so the agent must be self-contained.

Three parts:

1. **Drain the cue queue.** Reads `cues.tsv`, queries session transcripts from
   `~/.local/share/opencode/opencode.db` (SQLite) when needed, applies the
   `self-learning` skill's harvest procedure (promotion rule: passing check +
   named failure pattern + ≥1 ruled-out dead-end), then routes each cue to its
   store. Appends to `processed.tsv`; truncates `cues.tsv` when done.
2. **Review the flywheel digest.** Reads `skills_review.tsv`; writes review
   recommendations to `review-pending.tsv` (`keep/update/demote-to-mem/retire`).
   Headless: NEVER demotes, deletes, or retires a skill without the captain's
   explicit approval.
3. **Compound solved problems.** If a session shows a solved, verified,
   non-trivial problem, invokes the `compound` skill's headless mode.

**Section 1a — session-synthesis methodology** (ported from the retired
`ce-session-historian`): extract investigation journey (with *why* dead-ends
failed), user corrections (higher signal than self-corrections), decisions +
rationale, error patterns across sessions, evolution across sessions,
cross-session blind spots. Discipline: never reproduce tool dumps verbatim,
never surface thinking-block content, never harvest the drain's own session,
technical-not-personal, caveat staleness, anchor to evidence.

### 4. COMPOUND — the compound skill

`~/.agents/skills/compound/` — the consolidated, self-contained replacement for
`ce-compound` + `ce-compound-refresh` (zero `ce-*` dependencies).

- **capture** (default): document a solved problem into `docs/solutions/`
  (YAML frontmatter, bug track vs knowledge track, overlap check before write —
  update beats duplicate).
- **refresh**: review existing docs against the current codebase; update,
  consolidate, or mark stale.
- Headless-capable (`mode:headless`) for automations; interactive for a human.
- Support files: `references/schema.yaml`, `references/yaml-schema.md`,
  `assets/resolution-template.md`, `scripts/validate-frontmatter.py` (YAML
  parser-safety validation, Python stdlib only).

### 5. LOOKUP — the solutions-research agent

`~/.config/opencode/agents/solutions-research.md` (subagent, model
`opencode-zen/nemotron-3-ultra-free`). Fork of `ce-learnings-researcher`.
Searches `docs/solutions/` for applicable past learnings (grep-first filtering,
frontmatter scoring) before new work in a documented area. Dispatch via the
`task` tool or dispatch rules.

### 6. ROUTING — dispatch-rules.json

`~/.config/opencode/dispatch-rules.json` — three rules added:

- "document a solved problem / refresh stale learnings" → `compound` (headless)
- "before implementing in a documented area / search past learnings" → `solutions-research`
- "harvest golden path / drain self-learning cues / self-improvement pass" → `self-improve`

### 7. The axi-memory system (the facts sink)

`~/.agents/skills/axi-memory/SKILL.md` + `~/.local/bin/mem` (the `mem` CLI).

Part of the same loop: cues that are single facts/corrections/decisions/
preferences route to axi-memory, not to a skill. The `axi-memory-bridge.ts`
plugin injects relevant memories into the system prompt and exposes
`axi-memory-search` / `axi-memory-add` tools.

- Store: `~/memories/` (markdown + YAML frontmatter in a git repo), objects in
  `~/memories/objects/<type>/`.
- Memory types: `constraint`, `decision`, `failure`, `howto`, `preference`.
- CLI: TOON output, `mem add`, `mem search`, `mem show <id>`, `mem sync`.
- Cross-machine sync: `mem sync` → local git remote. **Anchor-remote rule**: on
  this machine (`primary`, the OCI anchor) the remote MUST be the local bare
  repo `origin = /home/ubuntu/mem-bare.git`, never the tunnel hostname
  `ssh://primary55522.phillias.cc/~/mem-bare.git` — the anchor hairpinning
  through its own Cloudflare tunnel times out. Other machines use the tunnel
  URL + `primary55522` ssh alias. The bare repo is covered by the restic backup
  schedule on OCI.

## Data flow

```
session idle
  └─▶ self-learning-autocapture writes cues.tsv (+ skills_review.tsv digest)
timer (6h)
  └─▶ fm-selfimprove-drain.sh gate: both empty? → exit 0
        └─▶ opencode run --pure --agent self-improve
              ├─ read cues.tsv → opencode.db transcripts → self-learning triage
              │     ├─ golden path  → write skill in ~/.agents/skills/
              │     ├─ fact/decision→ axi-memory (mem add / axi-memory-add)
              │     └─ one-off      → skip
              ├─ skills_review.tsv → review-pending.tsv (no demotion)
              ├─ solved problem    → compound skill → docs/solutions/
              └─ processed.tsv += cues; cues.tsv → empty
```

## Operation

- **Check status**: `systemctl --user status selfimprove-drain.timer`;
  `cat ~/.local/state/opencode-selflearning/selfimprove-drain.log`.
- **Force a drain now**: `opencode run --pure --agent self-improve "Run your full self-improvement drain procedure now."`
- **Manual compound**: `compound` skill (`mode:headless` for no questions).
- **Review pending recommendations**: `cat ~/.local/state/opencode-selflearning/review-pending.tsv`.
- **Skill review digest**: `cat ~/.local/state/opencode-selflearning/skills_review.tsv` (empty = nothing needs review).
- **Pause/resume**: `systemctl --user stop/start selfimprove-drain.timer`.

## Design decisions (why it's built this way)

1. **Deterministic gate before LLM.** File-state checks decide whether to run;
   the LLM is spent only on actual harvesting. Token economy is the point.
2. **`--pure` headless run.** Prevents the autocapture plugin from cueing the
   drain's own session (self-referential cue loop).
3. **Agent carries the full procedure.** Headless `opencode run` does not load
   global `AGENTS.md`; `self-improve.md` is self-contained.
4. **`%h` in systemd units.** Matches the dotfiles repo portability convention;
   no hardcoded home paths.
5. **`ce-session-historian` was NOT forked.** Hard dependency on `ce-sessions`,
   which mines Claude/Codex/Cursor session dirs — not opencode's SQLite DB.
   Its synthesis methodology was ported into `self-improve` section 1a instead.
6. **Net-new only, no resurrection.** The dotfiles PR added exactly the new
   rules/files; the upstream MCP-purge (removed Aug 3) was not re-added.
7. **Skills never demoted headless.** Review is suggested, deletion is
   captain-approved.

## Gotchas

- **chezoi MM divergence**: dispatch-rules edits live in the target; `chezmoi
  apply` reverts them unless the source (`~/.local/share/chezmoi/...`) is synced.
- **Identity**: `opencode debug config` returns the *default* model, not the
  session model. Commit identity (`<model>@<hostname>`) should use the session
  model (e.g. `big-pickle@primary`).
- **New skills mid-session**: created skills are not in `available_skills`
  until a fresh session.
- **`mem sync` on the anchor**: remote must be the local bare repo (see
  anchor-remote rule above).

## History

- 2026-08-03: anchor-remote rule for mem sync documented (dotfiles PR #160).
- 2026-08-05: built this loop in this session; dotfiles PR #167
  (`feat/self-improve-loop`) ships it; `compound` forked from `ce-compound` +
  `ce-compound-refresh`, `solutions-research` forked from
  `ce-learnings-researcher`, `self-improve` agent created with ported
  ce-session-historian methodology, systemd timer armed, dispatch rules added,
  `/btw` command installed.
