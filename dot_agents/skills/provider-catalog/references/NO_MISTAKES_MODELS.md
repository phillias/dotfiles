# no-mistakes model reliability (step-role requirements)

Hand-curated from live pipeline forensics, 2026-10-04. Complements
`ROUTING_TOPOLOGY.md` (which maps the ladders structurally): this file records
WHICH models the no-mistakes pipeline steps can actually run on, and why.
Ladder truth is the gateway; this file is the observed-behavior layer on top.

Deep log: axi-memory `f-2026-10-04-no-mistakes-test-step-json-failures-stal`.

## Why no-mistakes is stricter than chat

Pipeline steps must emit **machine-parseable structured JSON** — findings
arrays, verdict objects, test summaries. A model that interleaves prose with
JSON, or drops template literals into findings text, breaks the step even when
its actual review/test work was correct. Symptom classes observed:

1. `invalid character '$' after array element` — description text contained a
   `${...}` template literal OUTSIDE a string.
2. `invalid character 'T' after top-level value` — valid JSON object followed
   by trailing prose.
3. Silent stalls — agent goes quiet (no tool/log activity) until the step
   budget kill (exit 143).

Parse failures do NOT trigger agent fallback (only invocation failures do), so
a bad rung poisons the whole step.

## Step-role map (which chain serves which step)

- `review_agents` (global config) covers reviewer/fixer roles ONLY — it does
  NOT select the agents for test, document, lint, or CI repair.
- **Test steps ride the global `agent` on `agent_config.<harness>.model` —
  the fallback/gate chain.** There is no `test_agents` role (verified against
  no-mistakes v1.84.0 global-config reference).
- Reviewer/fixer ride `fallback/review`.
- Generic steps (document, lint, rebase-repair, PR drafting) ride the global
  agent with the generic `agent_timeout` (default 30m).

## Verdict table (2026-10-04 forensics)

| Model | Role tested | Result |
|---|---|---|
| `opencode-go-gw/deepseek-v4-flash` | review chain head (reviewer/fixer) | CLEAN — strict JSON all day, no stalls; reviews 36s–434s. Later stalled twice as TEST agent (51m silent at 60m; quiet 6m at 12m budget) — reliable JSON, can go quiet on long test drives. Now rung-2 on both chains. |
| `opencode-go-gw/longcat-2.5-preview-free` | gate chain head (test steps) | BROKEN — both JSON failure modes + 51m silent stalls ×3 in one day; removed from the gate chain (dotfiles PR #392). **Light work / scout-class ONLY** (captain 2026-10-04) — never a JSON-bearing pipeline role again. |
| `openrouter-direct/z-ai/glm-5.2:free` | gate + review chain HEAD (captain directive 2026-10-04) | UNPROVEN on this pipeline — the free OpenRouter glm variant positioned so every JSON-bearing stage (reviewer, test, document, lint, rebase-repair, PR-drafting, CI-fix) tries it first; deepseek rung-2 is the safety net (429/403 invocations fall through; silent stalls do NOT). Discipline under observation — report first JSON failure or stall pattern. Caveats: OpenRouter :free lanes historically rate-limit aggressively (2026-09-01 :free trio removed after run deaths; 2026-09-15 inkling 403 funnel + TM training logging). |

## Budgets (dot_no-mistakes/config.yaml, PR #392)

`review_agent_timeout` + `test_agent_timeout`: **12m** (was 60m; the 60m era
was for nemotron NIM gate reviews, a chain since retired). Observed legitimate
durations: review 36s–434s; test 2.5m–7.7m clean, worst ~19.8m with two fix
rounds. `step_quiet_warning: 10m` is observability only — it never cancels;
the budget kill is the stop.

## Operational gotchas

- Test rounds that drive real Docker leave `nmt-*` containers on the daemon
  (net=none, no ports). Harmless but should be removed after the run:
  `docker ps -a --format '{{.Names}}' | grep nmt`.
- A run's intent text lives in `~/.no-mistakes/state.sqlite` (`runs` table) —
  recoverable verbatim if a retry needs it.
- Changing `~/.pi/fallback-chains.json` (chezmoi: `private_dot_pi/`) or
  `dot_no-mistakes/config.yaml` takes effect at the NEXT run's setup — the
  shipping run itself is the validation run.
