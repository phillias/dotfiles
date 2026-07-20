---
name: axi-memory
description: >
  Filesystem + git agent memory with TOON output. Use when the user says "remember",
  "recall", "memory", "what did I decide about", "have I seen", "previously", "how did
  we", "save this as a memory", "add to notes", or otherwise wants durable cross-session
  knowledge capture or retrieval. Backed by the `mem` CLI at ~/.local/bin/mem.
---

# axi-memory

Durable memory that survives across sessions and across machines, stored as
markdown + YAML frontmatter in a git repo, queried via `mem` CLI with TOON output.

## Why use this skill

The `mem` CLI follows the AXI protocol: TOON output (~40% smaller than JSON), 3-4
default fields per list, content-first home view, truncation with `--full` escape
hatch, definitive empty states, structured errors on stdout, exit 0/1/2. Total
token cost of typical round-trips (search + show) is under 200 tokens at small
memory counts.

## When to load

Load this skill when the user says any of:
- "remember", "recall", "memory", "-notes"
- "what did I do/decide about X"
- "have I seen/been here before", "previously"
- "save this", "make a memory", "add to my notes"
- "what was that thing about X"
- explicit invocation `/axi-memory`

## Available commands

The binary is at `~/.local/bin/mem`. If missing, run `mem init` (idempotent) first.

| Command | Purpose | Token cost |
|---|---|---|
| `mem` | content-first home view (recent + counts) | ~50 tokens @ 5 memories |
| `mem search "<query>"` | ripgrep keyword search | ~30 tokens/match |
| `mem show <id>` | detail (body truncated to 500B by default) | ~100-200 tokens |
| `mem show <id> --full` | full body | variable |
| `mem add --type <t> --title "<Title>" [--body ...]` | create memory | ~20 tokens ack |
| `mem list [--type t] [--tag t] [--limit n]` | filtered list | ~30 tokens/match |
| `mem sync` | pull + push to bare remote | ~30 tokens |

## Memory types and ids

Five first-class types. Id prefix encodes the type so ids stay unique.

| Type | Prefix | When to use |
|---|---|---|
| `constraint` | `c-` | "must do X / must not do Y" — enforced rules |
| `decision` | `d-` | "we chose X over Y because Z" — rationale |
| `failure` | `f-` | "this broke; root cause was W; fix was X" — postmortem |
| `howto` | `h-` | "to deploy Y, run A, B, C" — procedural recipes |
| `preference` | `p-` | "the user prefers X" — durable taste |

**Id shape:** `<prefix>-<datestamp>-<slug>`
- `c-2026-07-19-use-pnpm`
- `f-2026-07-19-jwt-decode-panic`

## Typical cognitive loop

When the user asks "remember X" or "what did we decide about Y":

1. **Search first** — cheap, fast, gets the agent oriented:
   ```
   mem search "<likely keywords>"
   ```
   If 0 matches, that's a definitive empty state — see `count: 0 of 0 total`.

2. **Show the relevant match** if any:
   ```
   mem show <id-from-search>
   ```
   If body is truncated, output includes `help[1]` suggesting `mem show <id> --full`.

3. **Add a new memory** if the search came up empty and the user wants durable capture:
   ```
   mem add --type decision --title "Use pnpm not npm" --body "Reason: lockfile ..." --tags "tooling,frontend" --scope phillias-api
   ```

4. **Push to remote** only if cross-machine sync was requested or implicitly assumed:
   ```
   mem sync
   ```

## Output reading guide

All list outputs are TOON — `[count]{fields}:` header, then one row per line.
The agent can parse count + first field (id) without parsing the rest if it just
needs orientation. Use `--limit` to keep lists short. `--type` and `--tag`
filters narrow further.

Use `mem show <id>` when you need the body. If it's truncated, the output
explicitly tells you with `truncated: 500 bytes shown of <N> total` and a
`help[1]` hint pointing to `--full`.

## Cross-machine sync model

This skill stores memories in `~/memories/` (working dir) and treats a bare
git repo on the OCI anchor (`~/mem-bare.git`) as the source of truth. Other
machines (cabinkali, kalione) clone the same bare repo over their existing
Cloudflare tunnel SSH route (`primary55522.phillias.cc`), no new tunnels
required.

`mem sync` runs `git pull --rebase && git push`. Conflicts are git conflicts —
user resolves by opening the file, merging by hand, `git add` + `git commit`.

If a remote is offline, the local memories still work — `mem search`/`show`/`list`/`add`
all operate on the local working directory. Sync happens lazily when the remote is back.

## What NOT to do

- **Don't store trivial or context-dependent things** — memories persist across sessions. If it's only useful for the next 3 turns, don't `mem add` it.
- **Don't store secrets** — the memory repo goes into restic backup → OCI Object Storage. No secrets, no tokens, no passwords.
- **Don't run `mem sync` after every add** — local commits accumulate; sync once at session end or when explicitly asked. Adding memories is fast (one git commit each); syncing is the only operation that touches the network.
- **Don't ignore the `--tags` flag** — well-tagged memories are `mem list --tag X` power. Always tag with at least one of: the project, the topic, the system involved.

## v2 semantic search (deferred, not implemented)

v1 uses ripgrep for literal + regex search. At memory counts under ~5000, this is
strictly better than vector search for agent use — the agent sees literal match
context (with `rg --context`-style evidence), cheap run cost, zero external
dependencies.

When `mem search` returns >50 matches and the right one isn't in the top 5,
semantic search is the next layer. Plan: sqlite-vec as a build artifact in
`$MEM_DIR/.cache/index.sqlite` (NOT source of truth), in-process ONNX
embedding (Xenova/bge-small-en-v1.5, 80MB). Activate with `--features=vector`,
not on by default. NEVER use a hosted vector DB.

If you find yourself wanting semantic search, that's the signal — but ship v1
first, prove the literal-search ceiling before paying the embedding tax.

## Backup

`~/mem-bare.git` is included in the existing restic backup schedule on OCI
(daily 03:00 UTC, retention 7d/4w/12m, offsite to OCI Object Storage). No
additional cron, no additional configuration. Loss of OCI = recoverable from
last restic snapshot. Loss of one client = recoverable from OCI bare repo.

## Sample memory file

Located at `~/memories/objects/decisions/d-2026-07-19-adopt-mem-as-memory-system.md`:

```markdown
---
id: d-2026-07-19-adopt-mem-as-memory-system
type: decision
title: Adopt mem as memory system
scope: opencode
status: active
confidence: 0.9
created: 2026-07-19
tags: ["memory","axi","toon","bash"]
---

After codemem proved expensive to operate across three boxes, switching to a bash+git+TOON CLI. Decided on 2026-07-19.
```

## Quick reference

```bash
# Get oriented (no arguments)
mem

# Capture a decision
mem add --type decision --title "Use Cloudflare tunnel X for Y" --body "Reason..." --tags "infra,proxy"

# Find memories about auth
mem search "auth"
mem search "jwt" --type failure --limit 5

# Get the full body of one
mem show d-2026-07-19-adopt-mem-as-memory-system --full

# Sync after a session
mem sync
```