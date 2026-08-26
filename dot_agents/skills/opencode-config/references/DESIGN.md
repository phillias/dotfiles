# OpenCode Runtime Systems — Design

Design authority for the four custom runtime systems that keep this agent fleet
operating headlessly:

1. **Self-learning flywheel** — the DETECT → GATE → HARVEST → COMPOUND loop that
   turns hard-won sessions into durable skills and memories.
2. **Model fallback + catalog drift** — reactive chain stepping on failure plus
   the proactive catalog-promotion gate that keeps chains healthy.
3. **axi-memory // self-learning routing** — the triage rules that decide whether
   a lesson becomes a skill, a memory, or nothing.
4. **Fleet state communications** — the zero-token sidecar that recovers
   dispatched-task status and authored decisions when the chat-message hook
   chain is disrupted.

This document lives in `opencode-config/references/` (house pattern from PR #176)
so it sits next to the config reference (`SKILL.md`) and the model snapshot
(`models.snapshot.json`) that the drift system already maintains. It is the
design companion to `~/.config/opencode/self-improvement-loop.md` (the flywheel's
operations doc) — this file is *why*, that file is *how to run it*.

**Provenance.** PR #167 built the self-improve loop (2026-08-05). PRs #171/#172/#173
wired and fixed the cue loop (2026-08-08) — the last of those carries the failure
lesson in §1.3. PR #174 promoted the runtime-fallback + catalog-drift system
(2026-08-08). PRs #175/#177 removed the OmO/TOON experiments and renamed this
skill. The fallback chain configuration was seeded 2026-08-08 from the recovered
`~/.omo/omo.jsonc` (captain decision). **Cross-machine note:** the flywheel's
design lineage may predate this machine's session history — research and earlier
iterations possibly ran on the `primary` / `kalione` hosts; treat any "first
built here" claim as local-evidence-only.

---

## 1. Self-Learning Flywheel

### 1.1 Pipeline overview

```mermaid
flowchart TD
    A[Session ends / skill loaded / explicit ask] --> D[DETECT<br/>self-learning-autocapture.ts]
    D -->|cues.tsv or skills_review.tsv non-empty| G[GATE<br/>fm-selfimprove-drain.sh<br/>systemd timer 6h]
    D -->|nothing to drain| Z[zero-token silence<br/>exit 0]
    G -->|opencode run --pure| H[HARVEST<br/>self-improve agent<br/>glm-5.1]
    H --> C[COMPOUND<br/>compound skill<br/>docs/solutions/]
    H --> S[skills / axi-memory stores]
    C --> R[ROUTING<br/>dispatch-rules.json]
    S --> L[LOOKUP<br/>solutions-research agent]
    R --> S
```

Key invariant: everything below the **GATE** is zero-token (regex + file state,
no LLM) until the gate decides a drain run is warranted. `--pure` is critical —
it disables plugins so the drain cannot re-trigger autocapture on its own
session (self-referential cue loop).

### 1.2 Components

| Stage | Component | Zero-token? | Role |
|---|---|---|---|
| DETECT | `plugins/self-learning-autocapture.ts` | ✅ | session.idle regex/TSV detection → `cues.tsv`, `skill_stats.tsv` → `skills_review.tsv`; evidence rows on session-error / model-fallback |
| GATE | `~/.local/bin/fm-selfimprove-drain.sh` | ✅ | silent exit 0 unless queues non-empty; then `opencode run --pure --agent self-improve "Run your full self-improvement drain procedure now." --format json`; log `~/.local/state/opencode-selflearning/selfimprove-drain.log` |
| HARVEST | `~/.config/opencode/agents/self-improve.md` (primary, opencode-zen/glm-5.1) | ❌ | carries the FULL drain procedure in its prompt (headless runs don't load global AGENTS.md): drain cues from opencode.db transcripts, apply promotion rule, route to stores, append `processed.tsv`, truncate `cues.tsv`; review flywheel digest → `review-pending.tsv`; compound solved problems |
| COMPOUND | `~/.agents/skills/compound/` | ❌ | capture (default) + refresh; `mode:headless`; schema validation via `scripts/validate-frontmatter.py` |
| LOOKUP | `~/.config/opencode/agents/solutions-research.md` (subagent, nemotron-3-ultra-free) | ❌ | searches `docs/solutions/` for applicable past learnings |
| ROUTING | `~/.config/opencode/dispatch-rules.json` | ✅ | 3 rules: compound headless / solutions-research / self-improve |

State files live in `~/.local/state/opencode-selflearning/`: `cues.tsv`
(`<ts>\t<kind>\t<sessionID>\t<detail>`, kinds `explicit|hard-win|session`),
`skill_applications.tsv`, `skill_feedback.tsv`, `skill_stats.tsv`,
`skills_review.tsv` (≤8 pre-aggregated lines, **empty when nothing needs
review**), `retired.tsv`, `review-decisions.tsv`, `evidence.tsv`.

Key thresholds: `SESSION_CUE_MIN_TOOL_CALLS=40`, `MIN_FAILS_TO_FLAG=2`,
`STALE_MS=60d` (cold), `COOLDOWN_MS=14d` (re-flag), `REPROMOTE_MIN_LOADS=2`
(retired skill loaded ≥2× → re-promotion candidate).

### 1.3 The design lesson that shaped it

**Failure `f-2026-08-08` — the unwired cue loop.** The autocapture plugin was
designed on the contract that "a global AGENTS.md instruction consumes
`cues.tsv` at session start." On Aug 8 the plugin was live and writing cues —
but no `AGENTS.md` existed anywhere (`~/.config/opencode/AGENTS.md`,
`~/AGENTS.md`, `~/.agents/AGENTS.md`, `~/.claude/CLAUDE.md` — all absent). The
consumption half of the loop was never wired, so cues accumulated unread.

**Fix:** PR #173 (commit `9f8636c`) created the 17-line AGENTS.md flywheel
section and the current consumption rule; the 14-cue backlog was processed into
`processed.tsv` with honest dispositions and `cues.tsv` truncated so the new
instruction started from a clean queue.

**Rule this teaches:** a system with two halves (produce + consume) is not
"done" until both halves are verified end-to-end — the producer can be
perfect and the system still dead. Verification must include the consumer.

### 1.4 Drill-down map

| Topic | Where |
|---|---|
| Drain procedure & session-synthesis methodology (1a) | `self-improve.md` agent prompt |
| Flywheel ops (run it, log, timer) | `~/.config/opencode/self-improvement-loop.md` |
| Harvest promotion rule (check + verify + failure + dead-end) | `self-learning` skill §"Promotion rule" |
| Skill authoring spec | `self-learning/references/skill-authoring.md` |
| Autocapture regexes & thresholds | `plugins/self-learning-autocapture.ts` header |
| Memory routing | this doc §3 |

---

## 2. Model Fallback + Catalog Drift

The fallback system is **two coupled subsystems**: a reactive runtime fallback
(step the chain when a call fails) and a proactive catalog-promotion pipeline
(drift detection → PR → captain merge) that keeps the chain configuration
current.

### 2.1 Architecture

```mermaid
flowchart TB
    CFG[opencode-fallback.jsonc<br/>single-root OmO shape] --> CORE[Chain engine<br/>lib/opencode-runtime-fallback-core.ts]
    EV[event hooks<br/>session.status / session.error] --> CORE
    CORE --> STEP[advance chain<br/>skip cooldown]
    STEP --> UPD[client.session.update<br/>+ title marker]
    STEP --> CHP[chat.params<br/>per-model settings]
    CORE --> CD[per-model cooldown]
    CORE --> AXS[AXI + agent-aware surfaces]
    AXS --> TOOL[fallback-status tool<br/>TOON]
    AXS --> PROMPT[system-transform<br/>one-line annotation]
    AXS --> STATE[durable state file<br/>fallback.json]
```

### 2.2 Failure sequence

```mermaid
sequenceDiagram
    participant M as Model call
    participant H as Plugin hooks
    participant E as Chain engine
    participant S as Session
    M->>H: retryable error (400/429/5xx/529)
    H->>E: classify + resolve chain
    E->>S: session.update fallback model
    E->>S: title marker [fallback: ...]
    E->>H: toast if notify_on_fallback
    H->>M: system annotation on next turn
    Note over E: cooldown primary, increment attempts
    E-->>H: chain empty → structured exhaustion
```

### 2.3 Chain state machine

```mermaid
stateDiagram-v2
    [*] --> healthy
    healthy --> degraded: retryable error
    degraded --> cooldown: model enters cooldown
    cooldown --> healthy: cooldown expires → auto-recover primary
    degraded --> exhausted: chain empty or max attempts
    exhausted --> [*]
```

### 2.4 Chain resolution & config

**Resolution order** (per `opencode-fallback.jsonc` header):
1. UI-selected session model
2. agent `fallback_models`
3. category `fallback_models`
4. global `fallback_models` ladder
5. opencode system default

**Keys:** `enabled`, `retry_on_errors`
`[400,401,402,403,429,500,502,503,504,529]`, `max_fallback_attempts: 15`,
`cooldown_seconds: 60`, `timeout_seconds: 120`, `notify_on_fallback: true`.
Classification is retryable on status code, `ProviderAuthError`, or the
RETRYABLE_PATTERN regex (`rate\s?limit|quota|insufficient_quota|server_error|overloaded|timed?\s?out|timeout|429|5\d\d|529|pool.*exhaust`).

**Global ladder:** **paid-first since 2026-08-12** — big-pickle → OpenCode Go
→ Command Code GOAT → **Z.AI Coding Plan Lite** (GLM-5.3/5.2/5-Turbo,
credits-based, 0.5× off-peak) → **Cloudflare AI Gateway** (BYOK, analytics,
$50/mo spend cap; kimi-k2.7-code, glm-4.7-flash; small-prompts only —
262K/131K context) → **OpenRouter** (cheapest GLM-5 per-token) → OpenCode Zen
free → together Ternary-Bonsai (single-shot only) → nvidia NIM (~40 RPM shared,
max 1-2 per chain) → openrouter free → baseten subsidized →
google/gemini-2.5-flash (paid last resort). Z.AI added 2026-08-25 (captain
decision): Lite plan provides exclusive GLM-5.3 and credits-based metering with
off-peak advantage during ET hours. OpenRouter added 2026-08-25 for cheapest
GLM-5 overflow. KTD6 constraints: GPT-class models only via `opencode/` prefix;
Ternary Bonsai never primary; 400 stays in `retry_on_errors`. Full policy and
rationale in §2.6.

**Per-entry settings** (`temperature`/`maxOutputTokens`/`options`) are promoted
**only when that entry is active** — from the agent or category fallback entry —
and cleared on `session.deleted`. The primary model auto-recovers when its
cooldown expires (`primaryAvailable` → reset, attempts=0). State persists in
`~/.local/state/opencode-fleet/fallback.json`.

**Agent-aware surfaces:** `fallback-status` tool (TOON; healthy chains → the
definitive empty state "chain: healthy"); one-line system-transform annotation
`[model: active on X; N left in fallback chain]`; `tui.prompt.append` is
unavailable in this API version so the annotation rides system-transform.

### 2.5 Catalog drift + promotion gate

- **`catalog-drift.mjs`** fetches models.dev + opencode-zen catalogs, builds a
  snapshot (config-referenced OR free models only) against
  `models.snapshot.json`, diffs on added/removed/price (≥25% blended
  tokens-per-dollar, two-sided) / context-window change, and writes
  `catalog-drift.{json,txt}`. Exit 1 on drift, 2 on failure; `--seed` (re)writes
  the snapshot. Runs via `catalog-drift.service/timer`
  (OnBootSec=10min + daily).
- **`fm-drift-pr.sh`** is the promotion gate's final step: chezmoi re-adds the
  drift-affected files (fallback config, snapshot, SKILL.md), branches
  `fm/catalog-drift-<ts>` from dotfiles master, pushes, and opens a PR with the
  gate criteria body. **Merge = captain approval** — the drift system NEVER
  writes master directly (captain decision 2026-08-08). Identity:
  `${OPENCODE_MODEL:-firstmate}@$(hostname -s)` (deliberate, not the opencode.db
  chain).

### 2.6 Paid-first fallback policy (GO → GOAT → Z.AI → Cloudflare → OpenRouter → Zen)

**2026-08-12 (captain decision):** fallback reverses from free-first to
**paid-first** — prepaid flat-rate pools are spent before throttled free tiers:
**Command Code GOAT** ($70 pool) → **OpenCode Go** ($60 pool) → **Cloudflare**
(free tier) → **OpenCode Zen** (free tier) → free providers
(NVIDIA/OpenRouter/Together/Baseten) → Google (pay last resort). Decision B:
GOAT leads so its exhaustion rate is observable; ordering may change after
experience.

**2026-08-16 (captain decision):** Cloudflare stage inserted between Go and Zen
free — the chain becomes **GOAT → Go → Cloudflare → Zen**. Rationale:
Cloudflare's free tier (kimi-k2.7-code 262K, glm-4.7-flash 131K) outclasses
Zen's free tier (deepseek-v4-flash-free, nemotron-3-ultra-free) in quality and
throttles at 300 RPM vs Zen free ~200/day, so it is spent first. The
small-prompts-only constraint carries over (CF context windows are 131-262K;
prompts must fit before CF is reached, and the 24K llama must still sit at the
END of chains).

**2026-08-25 (captain decision):** Two structural changes:
1. **Z.AI Coding Plan Lite ($18/mo)** inserted between GOAT and Cloudflare.
   Chain: **Go → GOAT → Z.AI → Cloudflare → OpenRouter → Zen**. Z.AI Lite
   provides exclusive GLM-5.3 access, plus GLM-5.2 and GLM-5-Turbo at
   credits-based metering with 0.5× off-peak during ET 7am-11pm operational
   hours. Base URL: `https://api.z.ai/api/coding/paas/v4`. The Coding Plan
   endpoint is restricted to supported coding tools (OpenCode is supported).
2. **Cloudflare Workers AI rerouted through AI Gateway (BYOK)** for analytics,
   edge caching, and a $50/mo universal spend cap. The gateway endpoint
   (`https://gateway.ai.cloudflare.com/v1/{account_id}/opencode/compat`) replaces
   the direct REST API endpoint. BYOK means provider keys are stored in the
   gateway dashboard; OpenCode authenticates with a CF AI Gateway token.
   Workers AI remains a native provider — no custom setup needed; the `@cf/`
   prefix routes automatically. Third-party providers (Z.AI, OpenCode, CommandCode)
   added as custom providers in the AI Gateway dashboard with base URLs.
3. **OpenRouter added** for cheapest GLM-5 per-token overflow ($0.60/$1.92 via
   DeepInfra/GMICloud, vs $1.40/$4.40 direct). Sits after Cloudflare in the
   chain.

**`go-pool-guard.ts` retired 2026-08-12.** The proactive guard (polled
`https://opencode.ai/zen/go/v1/usage`) was purged along with its
`go-pool-*.sh` helpers: the usage endpoint now returns 401 (no auth sent → the
guard silently no-opped) and its redirect-to-free behavior conflicts with
paid-first. Reactive chain stepping in the runtime-fallback plugin is the single
owner of exhaustion handling (`classifyError` treats 429/402/403 +
`pool.*exhaust` as retryable; a windowed pool error advances the chain).

**Fleet integration** (the `agents`/`categories`/global blocks map to the live
fleet, not the retired OmO taxonomy):

- **Firstmate session** — the main session has no agent name, so
  `resolveChain` falls straight to the **global `fallback_models` ladder**,
  which leads with `opencode-zen/big-pickle`, then GO → GOAT → Z.AI →
  Cloudflare → OpenRouter → Zen → free.
- **Crewmates** (`task(subagent_type=...)`) — `agents.<type>` chains. Utility
  types (`general`, `explore`, ...): big-pickle primary, fallback
  GO → GOAT → Z.AI → Cloudflare → OpenRouter → Zen → free. Specialized types
  (oracle, metis, momus, looker, science): models stay pinned, fallback
  Z.AI → GOAT → Go → Zen **only** — no free downgrade; chain end surfaces as
  a visible failure for the captain to fix.
- **Categories** (`task(category=...)`) — `categories.<name>` chains. Utility
  categories (`quick`, `unspecified-low`): big-pickle + GO → GOAT → Z.AI →
  Cloudflare → OpenRouter → Zen → free. High-intensity/specialized categories
  (`ultrabrain`, `deep`, `unspecified-high`, `visual-engineering`, `artistry`,
  `writing`): models stay pinned, fallback Z.AI → GOAT → Go → Zen only.
- **Secondmates** — same chezmoi-synced config; their main sessions resolve the
  global ladder (big-pickle → GO → GOAT → Z.AI → Cloudflare → OpenRouter →
  Zen → free).

The LLM determines a subagent's model by choosing the task shape at the intent
gate (dispatch-rules.json → `task(category=...)` / `task(subagent_type=...)`);
`chat.params.agent` → `resolveChain` → agent > category > global ladder. This is
the "know, not operate" contract — the LLM picks the class of work, never the
specific model (Layer D stays deferred).

### 2.7 Drill-down map

| Topic | Where |
|---|---|
| Full provider/limits reference (16 providers) | `SKILL.md` (Provider Rate Limits section) |
| Concurrency profiles (team + free) | `SKILL.md` |
| Fallback config (chains, agents, categories) | `opencode-fallback.jsonc` |
| Chain engine (pure functions, unit-tested) | `lib/opencode-runtime-fallback-core.ts` |
| Plugin wiring & state file | `plugins/opencode-runtime-fallback.ts` |
| Drift + promotion scripts | `scripts/catalog-drift.mjs`, `scripts/fm-drift-pr.sh` |
| Prior art consciously NOT adopted | `SKILL.md` (Layer D: Hermes `model_switch`, deepagents `switch_model`) |

---

## 3. axi-memory // Self-Learning Routing

### 3.1 Triage

```mermaid
flowchart TD
    A[Cue: hard-won path / explicit ask / recurring op] --> B{Triage}
    B -->|multi-step procedure| C[Harvest as skill]
    B -->|one-line fact| D[axi-memory note]
    B -->|one-off| E[Skip]
    C --> F{Promotion rule}
    F -->|passing check + verify step + failure pattern + dead-end| G[Dedupe: update existing or write new]
    F -->|any missing| H[Low-confidence memory note, unverified]
    G --> I[Distill golden path from THIS conversation]
    I --> J[Write SKILL.md + references + Verify section]
    J --> K[Relay path to user]
    K --> L[Flywheel review: keep/update/demote-to-mem/retire]
    L -->|retire| M[retired.tsv + review-decisions.tsv]
    M -->|loaded >= 2x after retire| N[Re-promotion candidate - user approved]
```

### 3.2 Store & sync

- **Skills:** `~/.agents/skills/<name>/SKILL.md` (+ `references/`, `assets/`).
  Keep SKILL.md < 500 lines; push detail to references.
- **Memory:** `mem` CLI (`~/.local/bin/mem`), store `~/memories/` (markdown +
  YAML frontmatter git repo, `objects/<type>/`); types
  `constraint|decision|failure|howto|preference`.
- **L0 abstracts:** optional `abstract: "<≤120 chars>"` frontmatter field on
  memory files. Used by `mem search --inject` for compact recall output
  (`id type title — abstract` per line, ≤120 chars each). When absent, falls
  back to first 120 chars of body. Agent-authored memories should always
  include an abstract via the `axi-memory-add` tool's `abstract` parameter;
  auto-captured memories extract it from the captured text.
- **`mem sync` anchor rule:** on primary/OCI-anchor the remote MUST be the local
  bare `/home/ubuntu/mem-bare.git` — never the tunnel
  `ssh://primary55522.phillias.cc/~/mem-bare.git` (hairpin timeout). Other
  machines use the tunnel URL + `primary55522` alias. Bare repo covered by
  restic.

### 3.3 Gotchas

- **Secrets never in skill files** — record *where* they live (env var, MCP
  tool, vault), never the value.
- **Chezmoi MM divergence:** dispatch-rules edits land in the live target;
  `chezmoi apply` reverts them unless the source is synced.
- **New skills invisible until a fresh session** (`available_skills` is built at
  session start).
- **Headless drains never demote/delete skills** without captain approval
  (reversibility: retire → `_review/` or low-confidence memory, never delete).
- **Identity:** `opencode debug config` returns the DEFAULT model, not the
  session model — use the opencode.db chain for commit authorship.

---

## 4. Fleet State Communications (Zero-Token Background-Task Status)

Background-task completion notifications delivered via
`<system-reminder>[BACKGROUND TASK COMPLETED]...</system-reminder>` are fragile:
they ride the `chat.message` hook chain, which can be disrupted by compaction
(`experimental.session.compacting`), model fallback, or other plugins
intercepting the chain mid-turn. To recover dispatched-task status regardless of
chat-message delivery, a **sidecar state tree** is maintained on disk — a terse
index, never the transcript source of truth (that lives in `opencode.db`).

### 4.1 Architecture

```mermaid
flowchart TD
    SESS["session.* lifecycle events"] --> W["Writer plugin<br/>fleet-state-writer.ts"]
    CHAT["chat.message<br/>(mined for [BACKGROUND TASK *] headers)"] --> W
    TOOL["tool.execute.after<br/>(background_output → resulted)"] --> W
    W -->|"append-only"| WL["wake.log (TSV)"]
    W -->|"rewrite in place"| SJ["state.json"]
    W -->|"regenerate"| DT["digest.txt (TSV)"]
    W -->|"tag displacement"| WL
    NOTE["fleet-note.sh<br/>(harness-agnostic CLI)"] -->|"append"| WL
    NOTE -->|"append-only sidecar"| DCT["decisions.tsv"]
    READ["fleet-digest.sh<br/>(pure bash, zero LLM)"] --> DT
    READ --> WL
    READ --> DCT
    READ --> SIS["Sisyphus / any agent<br/>(glanceable block)"]
    WL -.->|"recovery when<br/>chat chain broke"| SIS
```

Key invariant: every write path is **non-LLM** (TypeScript plugin handlers + a
bash CLI), and the readable summary is pure bash. A decision record is a direct
filesystem write — it rides no hook chain, so it survives exactly the fragility
the sidecar exists to defeat.

### 4.2 State tree

`~/.local/state/opencode-fleet/`

| File | Format | Owner | Purpose |
|---|---|---|---|
| `wake.log` | TSV append-only: `<ISO>\t<type>\t<session_id>\t<digest>` | writer plugin + `fleet-note.sh` | Raw event log. Rotates >1MB to last 1000 lines. Types: `session.*`, `chat.message.bg`, `tool.background_output`, `fleet.gc`, `fleet.decision`, `fleet.replaced`. |
| `state.json` | JSON snapshot, rewritten in place | **writer plugin only** | Current state of every dispatched task; `tasks` map keyed by session_id/task_id. Terminal states (`completed`/`failed`/`cancelled`) are never overwritten. |
| `digest.txt` | TSV: `<key>\t<status>\t<type>\t<digest>\t<age> ago` | writer plugin | Regenerated whenever `state.json` changes. |
| `decisions.tsv` | TSV append-only: `<key>\t<ISO>\t<type>\t<decision>\t<rationale>` | **`fleet-note.sh` only** | Sidecar of authored decisions. Never written by the plugin → cannot race `state.json` rewrites. Surfaced by `fleet-digest.sh`. |

Single-writer discipline: `state.json` is the plugin's whole-file rewrite;
`decisions.tsv` is `fleet-note.sh`'s append. Two writers, two files, no races.

### 4.3 Writer plugin (`plugins/fleet-state-writer.ts`)

Subscribes to `event` (all `session.*`), `chat.message` (mines
`[BACKGROUND TASK RESULT READY|COMPLETED|CANCELLED|INTERRUPTED|ERROR]` headers),
and `tool.execute.after` (marks `bg_...` tasks `resulted` when their output is
fetched). Never throws — every handler catches + logs.

Two transition protections in `updateTask`:

- **Terminal guard:** never overwrite `completed`/`failed`/`cancelled`.
- **`fleet.replaced` flag:** when a record's `digest` is overwritten with a
  different reason, append `fleet.replaced` (`prev=<old> -> <new>`) so no
  transition is silently swallowed — the displaced reason stays recoverable by
  name alongside the append-only `wake.log`.

### 4.4 Decision authoring (`scripts/fleet-note.sh`)

Fail-closed, harness-agnostic CLI:

```bash
scripts/fleet-note.sh <key> --decision "<text>" [--rationale "<text>"] [--type dispatch|merge|teardown|other]
```

Records a decision at two points (any orchestrating agent — Sisyphus, firstmate,
or another harness — calls the same CLI):

- **At dispatch:** `--type dispatch --decision "<why this task is running>"`
- **At terminal outcome:** `--type merge|teardown --decision "<merged / PR opened / discarded>"`

Survives chat-chain fragility by design (direct filesystem write, no hook
delivery). `fleet-digest.sh` surfaces the latest decision per key in its
`== decisions ==` section.

### 4.5 Reader (`scripts/fleet-digest.sh`)

Pure bash, zero LLM. Emits a single glanceable block:

```bash
scripts/fleet-digest.sh              # state + decisions + wakes from last 30m
scripts/fleet-digest.sh --since 60   # last 60m of wakes
scripts/fleet-digest.sh --wakes-only # just recent wake events
scripts/fleet-digest.sh --json       # raw state.json
```

### 4.6 When to consult

- **At session start** — `bash scripts/fleet-digest.sh` to ground yourself
- **After a background-task system-reminder** — verify against `state.json`
- **Before dispatching** — glance at `digest.txt` to avoid duplicate dispatches
- **When the user asks "what's running?"** — `fleet-digest.sh --since 240`

### 4.7 Failure modes

- `state.json` empty/missing → sidecar not loaded; fall back to
  `background_output` API.
- `wake.log` corrupted → truncate and let the plugin repopulate.
- The state tree is **never** the transcript source of truth (`opencode.db`
  `session`/`message`/`part` tables are). It is a **terse index** for fast
  reads.

### 4.8 Drill-down map

| Topic | Where |
|---|---|
| Writer plugin wiring & wake types | `plugins/fleet-state-writer.ts` |
| Reader output format & flags | `scripts/fleet-digest.sh` |
| Decision authoring contract | `scripts/fleet-note.sh`, `~/.config/opencode/AGENTS.md` §"Fleet State Communications" |
| Decision consumption in agent turns | global `AGENTS.md` fleet-state section |

---

## 5. Hook Collision Risk Assessment (firstmate on opencode)

Collision analysis performed 2026-08-15 for a firstmate deployment running
exclusively on the opencode harness. Verdict: runtime-fallback, the axi-memory
flywheel (bridge + autocapture), and fleet-state-writer each provide more value
than risk; net collision risk is low and was priced in at design time. The
sections below record the risk paths and their mitigations.

### 5.1 Hook surface map

| Plugin | Hooks | Overlap with firstmate |
|---|---|---|
| runtime-fallback | `event` (session.status retry / session.error / session.deleted), `chat.params`, `experimental.chat.system.transform`, `tool.fallback-status` | No `chat.message`; no shared `event` types; `chat.params` is fallback-only |
| axi-memory-bridge | `chat.message` (try/catch-wrapped), `experimental.chat.system.transform`, `tool.execute.after` | Pushes alongside on `system.transform` — additive, compatible |
| self-learning-autocapture | `chat.message`, `tool.execute.after`, `event` (session.idle) | Shares `event` session.idle with firstmate's turn-end guard and watch-arm; all three coexist |
| fleet-state-writer | `event` (all session.*), `chat.message` (mined), `tool.execute.after` | Firstmate consumes its sidecar output; handlers never throw |
| firstmate (project-local) | `event` (session.created/idle), `tool.execute.before` | Disjoint from fallback surfaces by construction |

### 5.2 Risk path 1 — `chat.params` auto-recovery overrides dispatched models

The fallback's `chat.params` handler reverts any session whose active model sits
at chain index > 0 back to the chain primary (`big-pickle`) as soon as the
primary is healthy — on the first turn if it is not cooling. It cannot
distinguish "fell back on a runtime error" from "explicitly dispatched to a
mid-chain model." Under an opencode-exclusive firstmate every crewmate is an
opencode-harness spawn, so this fires **per dispatch** whenever crew-dispatch
resolves a mid-chain model for opencode work. It is a behavioral override, not
a crash.

**Tuning rule:** resolve crew-dispatch profiles for opencode-harness spawns only
to the chain-top model (`big-pickle`) or a non-chain model, so auto-recovery
never fires and dispatched model choices stick. No `no-auto-recover` flag exists
in the fallback config today — one would require a plugin change.

### 5.3 Risk path 2 — mid-turn stepping vs the `chat.message` chain

Already documented in §4: mid-turn model fallback can disrupt the `chat.message`
hook chain, and fleet-state-writer's disk sidecar exists to survive exactly that.
Consequence for the flywheel: a mid-turn step could swallow a harvest cue or
memory-score event in autocapture / axi-memory-bridge. Recoverable — cues
re-derive from session transcripts — and the price of keeping the session alive.

### 5.4 Non-risks (additive or disjoint surfaces)

- `experimental.chat.system.transform` — the fallback annotation and memory
  injection both push to `output.system`; no overwrite.
- `event` types — fallback consumes session.status/error/deleted; firstmate
  consumes session.created/idle. Disjoint.
- `chat.message` consumers — fleet-state-writer, axi-memory-bridge, and
  autocapture are all catch-wrapped; axi-memory-bridge ships an explicit
  "never throw into the chain" contract plus a dedicated test
  (`axi-memory-bridge-chat-guard.test.ts`).
- `tool.execute.before` is firstmate-owned (pretool / cd checks) and shared with
  no runtime plugin.

### 5.5 Drill-down map

| Topic | Where |
|---|---|
| Fallback `chat.params` auto-recovery logic | `plugins/opencode-runtime-fallback.ts` (chat.params handler) |
| `chat.message` chain disruption (design rationale) | this doc §4 |
| Flywheel consumer contract | `plugins/axi-memory-bridge.ts`, `plugins/self-learning-autocapture.ts` |
| Crew-dispatch model resolution | firstmate `config/crew-dispatch.json` + `bin/fm-spawn.sh` |

### 5.6 Plugin Hook Catalog

Complete reference of every plugin and which hooks it subscribes to. Updated
when plugins are added or removed. Every `chat.message` handler MUST wrap in
try/catch and never rethrow — a throw disrupts the entire hook chain for all
subscribers.

#### `chat.message` — called for every user and assistant message

| # | Plugin | Failure Mode | Purpose |
|---|---|---|---|
| 1 | opencode-log-sanitizer | swallow | Redacts JWTs, bcrypt hashes, base64 blobs, long quoted strings |
| 2 | fleet-state-writer | swallow | Mines `[BACKGROUND TASK *]` headers; records task state transitions |
| 3 | axi-memory-bridge | swallow | Injection veto, stores last user message, scores for auto-capture, topic-shift auto-recall |

**Execution order:** opencode runs handlers in plugin registration order
(opencode.json `plugin[]` array). Log-sanitizer runs first so redacted content
never reaches downstream handlers. All three must be isolation-safe.

#### `experimental.chat.system.transform` — inject into system prompt per session

| # | Plugin | Failure Mode | Purpose |
|---|---|---|---|
| 1 | axi-memory-bridge | swallow | One-shot axi-memory search injection (first user message → `mem search --inject` → compact L0 abstracts) |
| 2 | axi-gh-axi.js | swallow | gh-axi ambient context (issues, PRs, help) |
| 3 | axi-chrome-devtools-axi.js | swallow | chrome-devtools-axi ambient context |
| 4 | axi-lavish-axi.js | swallow | lavish-axi ambient context (sessions, visual guidance, playbooks) |
| 5 | opencode-runtime-fallback.ts | swallow | Fallback chain state annotation |

#### `tool.execute.after` — after every tool call

| # | Plugin | Failure Mode | Purpose |
|---|---|---|---|
| 1 | axi-memory-bridge | swallow | Auto-search axi-memory; appends ambient context (throttled 5s/session, LRU cached 60s) |
| 2 | opencode-telemetry | swallow | Records tool call completion, output sizes, timing |

#### `tool.execute.before` — before every tool call

| # | Plugin | Failure Mode | Purpose |
|---|---|---|---|
| 1 | envsitter-guard | block | Blocks `read`/`edit`/`write` on `.env*` files; redirects to EnvSitter |
| 2 | opencode-telemetry | swallow | Records tool call start timestamps |

#### `event` — session lifecycle events

| # | Plugin | Failure Mode | Purpose |
|---|---|---|---|
| 1 | fleet-state-writer | swallow | Task state → `state.json` + `wake.log` |
| 2 | opencode-ntfy.sh | swallow | Push notifications via ntfy.sh |
| 3 | opencode-telemetry | swallow | SQLite telemetry |
| 4 | opencode-runtime-fallback.ts | swallow | Model fallback chain on retry/error |
| 5 | tps-status.tsx | swallow | TPS calculation for TUI status bar |

#### `tool` — register custom tools

| Plugin | Tools |
|---|---|
| envsitter-guard | `envsitter_*` (keys, match, set, add, delete, copy, format, validate, annotate, help) |
| axi-memory-bridge | `axi-memory-search`, `axi-memory-add`, `axi-memory-show` |
| opencode-runtime-fallback.ts | `fallback-status` |

#### Safety contract

1. Every `chat.message` handler wraps in try/catch. Errors logged to
   `console.error` with plugin prefix, swallowed. A throw disrupts all
   downstream subscribers.
2. Every `event` handler is similarly isolated.
3. `tool.execute.before` handlers that block return immediately after blocking.
4. `experimental.chat.system.transform` handlers are additive — each appends
   to `output.system[]`. No handler reads or modifies another's strings.
5. No plugin reads or writes another plugin's in-memory state. Each owns its
   own `Map`/`Set` keyed by `sessionID`.

---

## 6. Maintenance & Evolution

**systemd units (user):** `catalog-drift.{service,timer}` (drift detection),
`selfimprove-drain.{service,timer}` (cue drain, 6h). Neither currently writes a
design doc — if a future `opencode-design` unit is added, its contract is to
regenerate *this* file (or the skill's docs) from the live config, never to
invent structure.

**Design rules for changes:**
- Keep AXI discipline: TOON output, definitive empty states ("chain: healthy"),
  structured errors, no interactive prompts.
- Keep `%h` / `$HOME` portability — no hardcoded home paths (parity rule).
- Chain edits flow through the drift PR gate, never direct master writes.
- When the flywheel procedure changes, regenerate or prune the drill-down maps
  — a stale map is worse than none.

---

## 7. Architecture Overview — Single-Root Config System

The OpenCode config is a single-root layer with no profiles (`OPENCODE_CONFIG_DIR`
unset) and no environment switching. Machine diffs are handled via chezmoi `.tmpl`;
no symlinks. OmO-era material is archived in `ARCHIVE-OMO.md`.

### 7.1 `~/.config/opencode/` tree (live)

- `opencode.json` — root config: providers + MCPs + compaction (18 providers)
- `opencode-fallback.jsonc` — global default fallback (PAID-FIRST chain; project > global first-match-wins)
- `dispatch-rules.json` — 30 crew-dispatch rules
- `plugins/` — fleet-state-writer.ts, self-learning-autocapture.ts, axi-memory-bridge.ts, tps-status.tsx, opencode-runtime-fallback.ts (retired: better-compaction.ts, tmux-subagent-activator.ts, go-pool-guard.ts)
- `lib/` — opencode-runtime-fallback-core.ts
- `scripts/` — fleet-digest.sh, fleet-note.sh, catalog-drift.mjs, fm-drift-pr.sh
- `AGENTS.md`, `docs/plans/`, `skills/`, `.*-key` files

Runtime state: `~/.local/state/opencode-fleet/` (wake.log, state.json, digest.txt, decisions.tsv, fallback.json).

### 7.2 Critical rules

1. One config, no profiles, `OPENCODE_CONFIG_DIR` unset.
2. `opencode.json` defines the live providers + MCPs.
3. Routing is owned by `opencode-fallback.jsonc` (agents/categories/global); the legacy `oh-my-openagent.jsonc` orphan is never read.
4. `opencode-fallback.jsonc` is the global default fallback — project > global first-match-wins.
5. Plugins auto-load from `plugins/`; retired plugins are enforced-removed.
6. No symlinks, no env switching; machine diffs via chezmoi `.tmpl` with `%h` / `$HOME` portability.

### 7.3 Config defaults (live)

`small_model: opencode-zen/nemotron-3-ultra-free` · `compaction {auto:false, prune:true, reserved:50000, tail_turns:40}` · MCP baseline: context7, grep_app, websearch, mcp_everything. TUI theme: tokyonight (tui.json), solarized-dark alternative. Provider concurrency: Team Profile default 8 (PROVIDERS.md §concurrency).

### 7.4 Mermaid hygiene

Node labels containing `<br/>` MUST be quoted (`["text<br/>text"]`). Unquoted `<br/>` inside `[...]` breaks the chart — the root cause of the rendering error at "Layer D → Architecture".
