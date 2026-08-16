# ARCHIVE: recursive-llm (RLM) opencode plugin experiment

Status: **RIPPED OUT — 2026-08-16.** Captain decision: firstmate's own context
management already captures the value at lower machinery cost. Archive exists so
the experiment never needs to be re-researched from scratch.

## 1. What it was

Evaluated [grishahq/recursive-llm](https://github.com/grishahq/recursive-llm) as
an opencode plugin tool that answers questions about single giant context files
(multi-hundred-thousand-token blobs) through a bounded recursive-llm Python
sidecar. RLM keeps full context in a restricted Python REPL variable and lets
the root model explore it via code before answering, with a hard budget
(calls/tokens/cost/elapsed).

Pin used: git SHA `64620536bd4b6b766627c68d453773b80b5955d2`, version 0.3.1,
CPython 3.12.13, LiteLLM backend. RLM is an independent implementation of the
Recursive Language Models paper (arXiv:2512.24601).

## 2. Decision chain

1. Captain asked whether RLM could be adapted to opencode+firstmate in an AXI
   method (and separately: explain the Relay/X integration, see AGENTS.md §14).
2. Verdict: adaptable only at the "giant single blob" content-analysis seam, not
   as a replacement for opencode's loop or firstmate's orchestration. RLM cannot
   run natively in opencode's Node/Bun plugin runtime (it is CPython-specific:
   RestrictedPython + subprocess + LiteLLM), so the only integration is a plugin
   tool shelling out to a Python sidecar.
3. Captain: no skill; only pursue if the integration is elegant and risk-free;
   the plugin sidecar wrapper is acceptable if AXI-compliant.
4. Captain gave go/no-go after the AXI design; **GO**, then reversed on review
   of the token economy (this archive), choosing firstmate's existing discipline
   over the machinery.

## 3. What was built and verified

Three files, all removed in the teardown:

- `~/.config/opencode/plugins/rlm-axi.ts` — opencode plugin registering a single
  custom tool `rlm_analyze` (query, context_file, optional model / recursive
  model / budget overrides). Lazy self-provisioned pinned venv under
  `~/.cache/opencode/rlm-axi/` via uv (CPython 3.12 + `uv pip install` of RLM at
  the pinned SHA, flock-guarded, marker file). Declined files under 10k bytes
  with a hint to use the Read tool. Type-checked clean (strict tsconfig) and
  bundled clean for `--target=node`.
- `~/.config/opencode/plugins/rlm-sidecar/rlm_sidecar.py` — AXI-shaped sidecar:
  TOON stdout, exit 0/1/2, unknown flags rejected by name with the valid-flag
  list, `--help` always passes, no prompts, translated provider errors (auth,
  rate-limit, timeout) instead of raw LiteLLM traces, definitive empty state
  ("no match in context"), pre-computed stats aggregates. Status resolved from
  RLM's typed `error_type` (BudgetExceededError/MaxIterationsError/
  MaxDepthError/ProviderResponseError), not message matching. `stats` is a plain
  dict (UsageTracker.snapshot: llm_calls, root_calls, recursive_calls,
  leaf_calls, retry_calls, total_iterations, max_depth_reached, prompt_tokens,
  completion_tokens, total_tokens, cached_tokens, usage_calls, priced_calls,
  estimated_cost_usd [None when unpriced], by_model). Cost line rendered
  `unpriced (n/m calls priced)` when pricing metadata is absent.
- `~/.config/opencode/plugins/rlm-sidecar/README.md` — contract table, flags,
  FM_RLM_* env knobs, security posture.

Verified: `--help` (exit 0), unknown flag (exit 2, names the flag), missing
required (exit 2), bad context path (exit 1), end-to-end failure path with all
provider keys stripped (clean translated auth error + full stats, exit 1). Venv
was pre-provisioned so first use was instant.

## 4. Projected token economy (why it was scrapped)

RLM's own benchmark (100k-char corpus, GPT-5-mini):

| Surface | Tokens | Cost |
|---|---|---|
| Direct full-load | 37,928 | $0.00888 |
| RLM recursive | 8,224 | $0.00481 |

That is a ~78% token cut / ~46% cost cut **against the naive baseline** — but
firstmate never loads the blob wholesale. Its model is disk-backed context: a
bounded startup digest (7,500-token budget) plus targeted on-demand reads. A
100k-char file never enters the window as a unit; the agent greps and reads
slices. Realistic in-window cost for the same "what is the total liability"
question: ~5-15k tokens of tool output plus the reasoning turns of an already
running session.

Projected comparison for one aggregation question on a ~30k-token blob:

| Approach | Window cost | Marginal cost | Latency |
|---|---|---|---|
| Naive full load | ~38k tokens | full blob, every time | 1 call |
| RLM sidecar | ~8k tokens | $0.005-0.10/question floor, new provider | sequential REPL round-trips |
| firstmate targeted | ~5-15k tokens | near-zero (session already running) | 2-4 tool calls |

So RLM's win is real but against the wrong baseline. Against firstmate's actual
discipline the advantage is roughly a wash on tokens, and RLM *loses* on:

- **Budget floor**: even a trivial question burns root + REPL steps (defaults:
  24 calls, $0.10, 120-300s).
- **Latency**: sequential REPL steps; only batched subcalls parallelize.
- **No prefix caching**: the same slice can be re-read across nodes.
- **Machinery/attack surface**: pinned venv + RestrictedPython sandbox that the
  project's own SECURITY.md states is defense-in-depth, NOT a hostile-input
  boundary; a second provider dependency.
- **Maintenance**: pinned to a git SHA, venv rebuilds, budget plumbing.

Where RLM would still beat firstmate: multi-MB blobs (>10k chars was already
below its own decline threshold), fully unattended batch analysis with no agent
loop, and exact-count/aggregate questions where the REPL's deterministic
computation is the answer. None of these are frequent enough in this fleet to
justify the machinery. If a future need arises, this archive plus the git SHA
recreates the sidecar in under an hour.

## 5. Teardown record

Removed:

- `~/.config/opencode/plugins/rlm-axi.ts`
- `~/.config/opencode/plugins/rlm-sidecar/` (rlm_sidecar.py, README.md)
- `~/.cache/opencode/rlm-axi/` (venv, pin)
- `/tmp/opencode/rlm-axi-bundle-check.js`, `/tmp/opencode/test-ctx.txt`

Nothing else touched. The opencode plugin loader now sees no rlm-axi plugin
(verified on next opencode start; plugins load at startup).
