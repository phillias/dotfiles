---
name: self-learning
description: >
  Capture a hard-won "golden path" from the current session as a reusable Agent
  Skill, so future sessions start already knowing it. Use it (1) right after
  non-trivial debugging, after working out a multi-step operational workflow, or
  after rediscovering project facts you didn't know up front — e.g. how to reach
  the dev/prod database, where credentials and env vars live, how to deploy, run
  migrations, or verify a change live; and (2) whenever the user says "remember
  this", "save this as a skill", "make a skill for this", "don't make me
  re-explain this next time", or otherwise wants a workflow preserved across
  sessions. Proactively recognize the moment even when unprompted: if a task took
  several attempts before it worked, used non-obvious tooling, or is likely to
  recur, harvest it without asking first. Delegates to a subagent when your tool
  supports one, or works inline, to extract the proven procedure into a new
  project-local or global skill.
license: MIT
metadata:
  author: kulaxyz
  version: "1.0"
# OpenCode adaptation: curated tool surface — enough to distill, dedupe,
# verify (bash), write skills, delegate (task), and route facts to axi-memory.
allowed-tools: read, write, edit, bash, glob, grep, task, axi-memory-add, axi-memory-search
---

# Self-learning: harvest golden paths into skills

This skill turns something you just figured out the hard way into a reusable
Agent Skill, so the next session — yours or a teammate's — starts already
knowing the proven route instead of rediscovering it from scratch.

It is a *meta-skill*: it doesn't do the work, it captures **how** work got done.
It's tool-neutral — it works with any agent that reads the Agent Skills format
(e.g. Claude Code and Codex, which both load `SKILL.md` skills natively). Where a
step differs by tool, the generic version comes first and any tool-specific
detail is only an example.

## Recognize the moment

Watch for these signals during normal work. Any one of them is a cue to harvest:

- A task only worked **after several attempts**, wrong turns, or a correction
  from the user. The successful path is worth more than the failures around it.
- You discovered **project-specific facts the agent didn't know up front**:
  where creds/env vars live, which selector or backend talks to a service, a
  non-obvious command, a required sequence, a gotcha that defies the obvious
  assumption.
- It's an **operational workflow likely to recur**: reach the dev/prod DB,
  deploy, run migrations, seed data, verify a change live, run one specific
  test path, rotate a key, tail the right logs.
- The user **signals it explicitly**: "remember this", "save this as a skill",
  "don't make me re-explain this next time".

**Act on the cue immediately — don't ask for permission first**, whether the
user requested it or you noticed it yourself. Harvest the skill, then tell the
user what you captured and where (step 5). They can always edit or delete it.

### Skill, memory, or skip?

Not every lesson deserves a whole skill — triage first, so you don't bloat the
skills list with one-liners:

- **A multi-step, reusable procedure or workflow** (how to deploy, reach the DB,
  run the migration dance, verify live) → harvest it as a **skill** using the
  procedure below.
- **A single standalone fact or one-line correction** (an env var name, a path,
  one gotcha) → record it in **axi-memory** (the `axi-memory-add` tool, or
  `mem add --type <constraint|decision|failure|howto|preference>`) instead; a
  whole skill is overkill for a one-liner. With no memory facility, make a small
  skill.
- **A genuinely one-off thing** unlikely to recur → skip it.

When you do harvest, capture the **failures too**, not just the win: the
approaches you ruled out and *why* often save more time next session than the
golden path itself.

### Promotion rule: don't enshrine guesses

A skill is authoritative — the next session trusts it without re-deriving it —
so hold promotion to a high bar. Only write a skill when **all three** hold:

1. **A passing check.** The path was actually verified — a test passed, the
   command exited clean, the repro reproduced, the build went green. Record what
   the check was. "Seemed to work" is not a passing check.
2. **A repeatable verification step.** The skill must carry a "Verify" section:
   the exact command or step the next session can run to re-prove the path still
   works. A skill without a verification step is a guess wearing authority — the
   promotion bar is "another session can trust it without re-deriving it", which
   requires that they *can* re-derive it cheaply.
3. **A named failure pattern.** You can name the failure this path avoids or
   diagnoses (e.g. "stale build cache → phantom type errors"), not a vague
   "sometimes it breaks".
4. **At least one ruled-out dead-end.** A concrete approach you tried and
   eliminated, with the reason.

If any is missing, it isn't a skill yet — leave a low-confidence axi-memory
note (`mem add --confidence 0.2`, marked unverified) or skip it. This keeps
confident guesses out of the skill set.

## Harvest procedure

- [ ] 1. **Apply the promotion rule** (above). Passing check + repeatable
      verification step + named failure pattern + one ruled-out dead-end — or it
      isn't a skill: note it in memory or skip. Don't proceed on a confident guess.
- [ ] 2. **Choose scope and name yourself** using the heuristics below — don't
      stop to ask. Default to project scope; pick a clear, specific `name`.
- [ ] 3. **Dedupe.** Look for an existing skill to UPDATE rather than duplicate.
      List your agent's skills directories — the project one and the user-level
      one (e.g. Claude Code `.claude/skills` + `~/.claude/skills`, Codex
      `.codex/skills` + `~/.codex/skills`, OpenCode `.agents/skills` +
      `~/.config/opencode/skills`, or your tool's equivalent). Also
      glance at any memory/notes index — a fact already there may just need a
      pointer.
- [ ] 4. **Distill the golden path from THIS conversation** before delegating —
      while it's fresh in your head: the exact working commands, file paths, env
      var names, the required order, and (just as important) the dead-ends to
      avoid. This is the raw material for the write.
- [ ] 5. **Delegate the write** to a subagent that inherits this conversation if
      your tool supports one, or do it inline otherwise — see below. The
      conversation is the only place the golden path lives, so whoever writes it
      must have that context.
- [ ] 6. When the write is done, **relay the new skill's path** to the user
      and, in one line, what it captured.

### Scope: project vs global

- **Project** (the repo's skills directory — e.g. `.claude/skills/`,
  `.codex/skills/`, `.agents/skills/` for OpenCode): the path is specific to
  THIS codebase — its env vars, its build/release steps, its schema, its quirks.
  Most harvested operational skills are project-scoped, and they ship to the
  team via git.
- **Global** (your user-level skills directory — e.g. `~/.claude/skills/`,
  `~/.codex/skills/`, `~/.config/opencode/skills/` for OpenCode): the path
  generalizes across projects — a personal tool, a cross-repo habit, or a
  workflow tied to your machine rather than to one repo.

When unsure, prefer **project** — an over-shared global skill triggers in repos
where its commands don't apply.

## Delegate the write (subagent, or inline)

Whoever writes the skill needs THIS conversation's context — it's the only place
the golden path lives. Two equally valid ways to run it:

- **Inline** — do the steps yourself in the main loop. Always works.
- **Subagent** — if your tool can delegate to a subagent that **inherits this
  conversation**, use it to keep the harvesting work out of your main context.
  (Claude Code: a skill with `context: fork`. Codex and others spawn subagents
  their own way.) Don't hand it to a *fresh* agent with no context — it would
  start blank with nothing to extract.
- **OpenCode:** `context: fork` is Claude Code-only — harvest inline, or
  delegate to a `task()` subagent by passing the distilled golden path (the
  brief below) in the prompt; the subagent will not inherit this conversation.

Either way it over-reaches by default, so box it in tightly. Follow this brief
(fill in the bracketed parts) — hand it to the subagent, or work through it
yourself inline:

> You are harvesting a skill. Your ONLY job is to write a new Agent Skill
> capturing the golden path we just worked out in this conversation:
> **[one-line description of the workflow]**.
>
> Hard rules:
> - Write ONLY under `[skills dir]/[skill-name]/`. Do NOT modify project
>   source, run builds, install anything, or resume the original task.
> - First read `[this-skill-dir]/references/skill-authoring.md` and
>   `[this-skill-dir]/assets/SKILL.template.md`, then author `SKILL.md` to that
>   spec, plus any `references/` or `assets/` files the procedure warrants.
> - Capture the PROCEDURE — commands, paths, the required order, gotchas — not a
>   one-off answer. Generalize so it works next time.
> - Capture the FAILURES too: the approaches we ruled out and why, so the next
>   session skips the dead-ends. Put them in a "What didn't work" section.
> - Include a `Verify` section: the exact command/step that re-proves the path
>   still works (the repeatable verification step from the promotion rule).
> - Enforce the promotion rule: the skill must record the passing check that
>   verified this path, name the failure pattern it addresses, and list at least
>   one ruled-out dead-end. If any is missing (e.g. nothing was actually
>   verified), STOP and report it isn't promotable — leave a tentative memory
>   note instead of writing the skill.
> - NEVER write secret VALUES (passwords, tokens, connection strings, API keys).
>   Record only WHERE to find them: the env var name, the selector function, the
>   MCP tool, the secret manager. Reproducing a secret into a skill file leaks it.
> - Self-validate before finishing (see the checklist in skill-authoring.md).
> - Report back: the absolute path you wrote and a one-line summary. Then STOP —
>   do not pick the original task back up.

## Review for demotion (closing the loop)

The `self-learning-autocapture` plugin pre-aggregates skill usage into
`~/.local/state/opencode-selflearning/skills_review.tsv` (empty when nothing
needs review; raw evidence in `skill_applications.tsv` / `skill_feedback.tsv`).
At session start, if that file is non-empty:

- Read each line (`<skill>\t<loads>\t<fails>\t<idle>\t<reason>`) and report it
  to the user in one line each — this is the flywheel's feedback loop: skills
  earn their keep or get surfaced for correction.
- **Never demote, move, or delete a skill without explicit user approval.** The
  digest only *suggests* review; the plugin never deletes anything.
- Offer the user: **keep / update / demote-to-mem / retire**.
  - *Retire* = move the skill to a `_review/` subfolder, or convert it to a
    low-confidence axi-memory note (`mem add --confidence 0.2`) — **never
    delete**.
  - Record the decision in `review-decisions.tsv` (audit trail).
  - When retiring, append `<skill>\t<retiredTs>` to `retired.tsv` so the
    plugin can watch for re-promotion signals.

### Re-promotion (reversibility)

A retired skill can come back — the flywheel's reversibility rule. The plugin
surfaces a `re-promotion-candidate` digest line when a retired skill is loaded
≥2× after its retirement timestamp (people keep reaching for it). Re-promotion
is manual and user-approved: re-apply the promotion rule (passing check +
repeatable verification step + named failure pattern + ruled-out dead-end), then
remove the skill from `retired.tsv`. Suppression is never permanent.

## Improvements (2026-08): mermaid as a derived index

Findings from studying TencentDB-Agent-Memory's memory layering, adopted as a
trial:

- **The transferable idea is the layering, not the graph syntax.** Keep a
  token-cheap structural index on top and lossless detail below, with
  deterministic drill-down. Their 3-tier stack (raw `refs/*.md` → jsonl step
  summaries → mermaid canvas of state transitions) attends only to the top
  layer in context; every node carries an id that drills to evidence. Summaries
  stay reversible because the layers below are never discarded.
- **Golden-path decision maps.** Harvested skills with multi-branch procedures
  may carry a small mermaid flowchart in `references/` encoding the branch
  structure (happy path, dead-ends to avoid, verify points) so the next session
  reads the map first, then pulls exact commands from the detail sections.
  `SKILL.md` stays under budget — the map lives in references.
- **Flywheel-review graph (proposed).** Back the review aggregates with a Turso
  (libSQL) query layer instead of parsing TSVs by hand. Scope decision: plain
  SQL for the keep/update/demote decision; add BM25 (FTS5) now and embeddings +
  reciprocal rank fusion later for harvest-time dedupe ("have we already
  captured this?"). RRF is a retrieval mode for recall, not an aggregation tool
  for the review graph.
- Trial flowchart: see `references/harvest-flow.md`.

## Gotchas

- **Secrets never go in a skill file.** Skills get committed and open-sourced.
  Point to *where* the secret lives; never reproduce the value. This is the
  single most important rule in this skill.
- **`name` must equal the directory name**, and be lowercase `a-z`/`0-9`/hyphens
  only — no leading, trailing, or doubled hyphens. A mismatch means the skill
  won't load.
- **Whoever writes the skill over-reaches by default** (a subagent especially).
  That's why the brief above forbids touching project source or resuming the
  task — keep it boxed to the skills directory.
- **Don't duplicate.** If a near-identical skill (or memory) already exists,
  update it instead of spawning a second one that competes to trigger.
- **Capture procedures, not answers.** "Join orders to customers for EMEA" is
  useless next time; "how to find the right tables and build the query" is the
  skill. See `references/skill-authoring.md`.
- **Keep `SKILL.md` tight** (< 500 lines, < ~5000 tokens). Push detail into
  `references/` and tell the reader *when* to load each file.

For the full authoring spec, see
[references/skill-authoring.md](references/skill-authoring.md). The fill-in
template is [assets/SKILL.template.md](assets/SKILL.template.md).
