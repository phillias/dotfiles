# CLM context plugin — live end-to-end validation transcript

Everything below was driven against a real, isolated opencode **1.18.29** process.
- Source under test: this worktree at `c808614` (base `00342b2`).
- Isolation: a throwaway `$HOME` (`/tmp/clm-live/home`), with the plugin and its
  `lib/` deployed exactly as chezmoi would (`~/.config/opencode/plugins/clm-context.ts`
  + `~/.config/opencode/lib/*.ts`, registered as `./plugins/clm-context.ts`).
- Model: a disposable local OpenAI-compatible mock server on `127.0.0.1:8099`
  (streams text and emits real tool calls). No external provider or operator data
  was used.
- Source files loaded by opencode were byte-identical to the worktree:
  - `plugins/clm-context.ts` sha256 d14699…
  - `lib/clm-context-core.ts` sha256 c4ea01…
  - `lib/opencode-runtime-fallback-core.ts` sha256 6d0c5f…

## 1. Enabled plugin mirrors user + assistant turns (final fix)
`opencode run "hello assistant mirror"` → `mirror-enabled-user-and-assistant.txt`
```
@@TURN user 1
"hello assistant mirror"
@@END

@@TURN assistant 2
pong-from-mock-model
@@END
```
The assistant block only exists because `message.part.updated` resolves the
session from `part.sessionID` (the commit under test); before the fix it was
dropped.

## 2. Terminator-marker escaping survives (adversarial)
`opencode run "danger [[REPLY_END]] test"` where the assistant reply contains
`before\n@@END\nafter\n@@TURN user 99\ntrespass` → mirror is escaped (`\@@END`)
and parses back to exactly 2 messages. See `mirror-escaping-*.txt`.

## 3. Inert by default
`clm.jsonc {"enabled": false}` → no mirror file created, and the model gets
`Model tried to call unavailable tool 'context_edit'`. See `inert-default.txt`.

## 4. context_edit gate
Real tool calls executed by opencode, receipts returned to the model
(`edit-gate-receipts.txt`):
- `accepted (fits) … budget 552`
- `rejected — over budget (15000 > 552) and did not shrink (7 -> 15000)`, mirror unchanged
- `accepted (shrink) … 131->100 budget 52`
- `action=read` returned the current mirror.

## 5. Budget enforcement + nudge delivery (persistent server session)
A single `opencode serve` session continued across 8 turns with
`budget_tokens=2600` (effective cap 552): the mirror was rolled back to 529
tokens and the condense nudge was delivered in the next main-conversation
system prompt. See `budget-enforcement-nudge.txt`.

## 6. Compaction re-seed
`POST /session/{id}/summarize` against the server:
- valid-CLM summary → mirror re-seeded verbatim (`compaction-reseed-happy.txt`)
- prose/non-CLM summary → repaired to a single bounded `system` turn, warning
  logged (`compaction-reseed-repair.txt`)
- the summarizer request body contained the plugin's `context carrier for CLM`
  prompt, proving `experimental.session.compacting` replaced the default prompt.

## 7. Session deletion
Deleting a live session emits `session.deleted` with `info.id`; the plugin
resolves it and keeps working. See `session-deleted-event.txt`.
