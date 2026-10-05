# CLM self-managed context (opencode plugin)

An opencode plugin that implements **CLM — Context Language Models** style
self-managed context: the model's context is exposed as a live, editable file
that the model itself reads and rewrites, with the harness providing the
mechanics.

- Plugin entry: `../clm-context.ts` (registered in `opencode.json`)
- Pure core + tests: `../../lib/clm-context-core.ts`, `../../lib/clm-context-core.test.ts`
- **Inert by default.** With the gate off it registers no hooks and no tools, so
  a session behaves exactly as if the plugin were not installed.

## What it does

1. **Live-context file (per session).** Every message turn is mirrored into
   `~/.local/state/opencode-clm/LIVE_CTX_<session>.txt` as one block. User turns
   arrive via `chat.message`; assistant turns are accumulated from settled
   `message.part.updated` text parts and appended once per completed
   `message.updated`, so each assistant message becomes one block:

   ```
   @@TURN user 1
   <verbatim turn text>
   @@END

   @@TURN assistant 2
   ...
   @@END
   ```

   Blank lines and `#` comments are allowed outside blocks. A content line that
   would otherwise be read as a terminator (or that starts with `\`) is escaped
   with a leading backslash on write and unescaped on read, so any turn text
   round-trips verbatim.

2. **`context_edit` tool (model-facing).** `action: read` returns the file;
   `action: replace` supplies the full new file content. On replace the harness
   parses the edit back into a well-formed message structure and applies the
   **edit gate**:

   - accepted if the edit **fits** the token budget, or
   - accepted if it **strictly shrinks** the file, otherwise
   - **rejected** with a one-line reason.

   Every call returns a one-line receipt, e.g.
   `context_edit: accepted (fits) blocks 3->3 tokens 120->118 budget 8000`.

3. **Injection.** Once per session the current file, trimmed to the token
   budget via the same enforcement, is appended to the system prompt
   (additive) so the model sees its own authored context; an over-budget file
   that cannot be trimmed is never injected. Budget-trim nudges are delivered
   to the model here and in `context_edit` responses.

4. **Compaction.** When opencode compacts, the plugin replaces the built-in
   summarizer prompt. If the mirror is within budget, the prompt embeds the
   file verbatim (bounded mode). If the mirror is unbounded, the prompt
   instructs the summarizer to condense the conversation into a fresh
   bounded CLM context (re-seed mode). On `session.compacted`, the plugin
   fetches the compaction summary message and writes it back to the mirror
   file, re-seeding it for the next session segment.

## How to enable

Config file `~/.config/opencode/clm.jsonc`:

```jsonc
{
  // master gate; false/absent = inert
  "enabled": true,
  // token budget for the edit gate (default 8000)
  "budget_tokens": 8000
}
```

Environment override (wins over config): `OPENCODE_CLM=1` / `OPENCODE_CLM=0`.

## Token budget

`estimateTokens(text) = ceil(chars / 4)` — a deliberately simple, deterministic
order-of-magnitude estimate so the gate is reproducible without a tokenizer.
`budget_tokens` bounds the file; edits over budget are only accepted when they
strictly reduce it.

## Coexistence contract

This plugin is designed to run **alongside** the existing context stack, not to
replace it:

- **dcp** (`@tarquinen/opencode-dcp`) uses
  `experimental.chat.messages.transform`, `experimental.chat.system.transform`,
  `experimental.text.complete`, and `command.execute.before`. It does **not**
  use `experimental.session.compacting`, so this plugin's compaction hook is
  purely additive. This plugin does **not** touch
  `experimental.chat.messages.transform`, so it cannot interfere with dcp's
  message rewriting.
- **Built-in compaction.** opencode's compaction still runs its hidden
  `compaction` summarizer agent; there is no hook to supply a summary directly.
  This plugin sets the hook's `prompt` field, which *replaces the default
  summarizer prompt*. opencode still appends the rendered conversation history
  after that prompt, which is why the directive explicitly tells the summarizer
  to replay the authored file verbatim and ignore the history. When
  `compaction.auto` is `false`, automatic overflow-triggered compaction is
  skipped, so the plugin has no effect on it; manual (or API-triggered)
  compaction still fires the hook and this plugin still replaces the
  summarizer prompt.
- **Inert default.** Disabled ⇒ `{}` returned from the plugin factory ⇒ no
  hooks, no tool, zero behavioral change.

## Safety

All hook handlers and the tool wrap in `try/catch`, log to `console.error` with
a `[clm-context]` prefix, and never rethrow (a throw would disrupt the shared
hook chain for every other plugin).

## References

- facebookresearch/context-language-models — <https://github.com/facebookresearch/context-language-models>
- "Context Language Models" — arXiv:2609.37725 — <https://arxiv.org/abs/2609.37725>

## License

MIT — see `LICENSE`. The CLM protocol concept originates with the authors of
the papers above; this is an independent opencode implementation of the
protocol, not affiliated with or endorsed by them.
