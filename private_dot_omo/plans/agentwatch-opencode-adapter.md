# feat: Add OpenCode adapter to agentwatch

**Target repo:** [mishanefedov/agentwatch](https://github.com/mishanefedov/agentwatch)
**Created:** 2026-07-16
**Status:** Draft

---

## Problem Frame

agentwatch provides a unified timeline for multiple coding agents (Claude Code, Codex, Gemini, Hermes, OpenClaw, Cursor). OpenCode is missing from this list. Users running OpenCode alongside other agents cannot see their OpenCode sessions in the unified timeline.

**Goal:** Add an adapter that reads OpenCode session files and emits `AgentEvent` objects compatible with agentwatch's schema.

---

## Scope Boundaries

**In scope:**
- Adapter that watches `~/.opencode/sessions/` for JSONL session files
- Parse OpenCode's message format (role, timestamp, content, tool calls)
- Map to `AgentEvent` schema (session_start, session_end, prompt, response, tool_call)
- Register in adapter registry
- Unit tests for parser and event mapping
- Integration test with sample OpenCode session data

**Out of scope:**
- 3D visualization changes (mindmap/heatmap) — those are agentwatch-ui concerns
- OpenCode hooks integration (future enhancement)
- Cost calculation for OpenCode (model pricing data not yet available)
- Subagent drilldown (OpenCode subagent format TBD)

---

## Key Technical Decisions

### D1: Session file location

**Decision:** Watch `~/.opencode/sessions/` directory recursively for `*.jsonl` files.

**Rationale:** OpenCode stores sessions as JSONL files in this directory. The path is consistent across installations. Chokidar watching with depth limit matches the Claude Code adapter pattern.

### D2: Event mapping strategy

**Decision:** Map OpenCode message types to agentwatch event types as follows:

| OpenCode Message | agentwatch Event |
|------------------|------------------|
| First message in session | `session_start` |
| `role: "user"` | `prompt` |
| `role: "assistant"` | `response` |
| Tool call in assistant message | `tool_call` |
| Tool result | (paired with tool_call via `toolUseId`) |
| Last message + session end | `session_end` |

**Rationale:** Follows the same mapping used by Claude Code and Codex adapters. OpenCode's format is similar enough that the same event types apply.

### D3: Backfill strategy

**Decision:** Use `BACKFILL_BYTES = 512 * 1024` (512KB) on startup, matching Claude Code adapter.

**Rationale:** Covers gap between agentwatch restarts without re-reading full history. History comes from SQLite store.

---

## Implementation Units

### U1. Create adapter skeleton

**Goal:** Create `src/adapters/opencode.ts` with basic structure and chokidar watcher.

**Dependencies:** None

**Files:**
- `src/adapters/opencode.ts` (new)
- `src/adapters/opencode.test.ts` (new)

**Approach:**
1. Create adapter file following `claude-code.ts` structure
2. Implement `startOpenCodeAdapter(sink: Emit): () => void`
3. Set up chokidar watcher for `~/.opencode/sessions/`
4. Filter for `*.jsonl` files
5. Implement cursor tracking for incremental reads
6. Add basic file change detection

**Test scenarios:**
- Adapter starts without error when `~/.opencode/sessions/` exists
- Adapter returns cleanup function
- Adapter ignores non-JSONL files
- Adapter tracks file cursors correctly

**Verification:**
- Adapter compiles without errors
- Basic test passes

---

### U2. Implement JSONL parser

**Goal:** Parse OpenCode JSONL lines into structured message objects.

**Dependencies:** U1

**Files:**
- `src/adapters/opencode.ts` (modify)
- `src/adapters/opencode.test.ts` (modify)

**Approach:**
1. Define `OpenCodeMessage` interface based on OpenCode's schema
2. Implement `parseLine(line: string): OpenCodeMessage | null`
3. Handle malformed JSON gracefully (return null, emit parse_error)
4. Extract: role, timestamp, content, tool_calls, tool_results

**OpenCode message format (from session_read output):**
```json
{
  "role": "user" | "assistant" | "tool",
  "timestamp": "ISO-8601",
  "content": "string",
  "tool_calls": [...],  // optional, in assistant messages
  "tool_result": {...}  // optional, in tool messages
}
```

**Test scenarios:**
- Parse valid user message → returns OpenCodeMessage with role="user"
- Parse valid assistant message with tool calls → returns tool_calls array
- Parse malformed JSON → returns null
- Parse empty line → returns null
- Parse message with missing fields → returns null
- Timestamp parsing handles ISO-8601 correctly

**Verification:**
- Parser handles all OpenCode message variants
- Parse error tracking works

---

### U3. Implement event mapping

**Goal:** Convert parsed OpenCode messages to `AgentEvent` objects.

**Dependencies:** U2

**Files:**
- `src/adapters/opencode.ts` (modify)
- `src/adapters/opencode.test.ts` (modify)

**Approach:**
1. Implement `mapToAgentEvent(msg: OpenCodeMessage, sessionId: string): AgentEvent`
2. Map roles to event types:
   - First message → `session_start`
   - `user` → `prompt`
   - `assistant` → `response`
   - `tool_call` in assistant → `tool_call` event
   - `tool_result` → pair with pending tool_call via `toolUseId`
   - Session end → `session_end`
3. Extract metadata: timestamp, content, tool input/result
4. Handle token usage if available in OpenCode format

**Test scenarios:**
- User message maps to `prompt` event with correct content
- Assistant message maps to `response` event
- Tool call in assistant message creates `tool_call` event with `toolUseId`
- Tool result pairs with pending tool_call
- First message creates `session_start` event
- Session end creates `session_end` event
- Event includes correct `agentName: "opencode"`

**Verification:**
- All event types map correctly
- Tool call pairing works
- Session lifecycle events fire at correct times

---

### U4. Register adapter in registry

**Goal:** Add OpenCode to the adapter registry so it starts automatically.

**Dependencies:** U3

**Files:**
- `src/adapters/registry.ts` (modify)
- `src/schema.ts` (modify - add "opencode" to AgentName)

**Approach:**
1. Import `startOpenCodeAdapter` in registry.ts
2. Add to `startAllAdapters()` function
3. Add `"opencode"` to `AgentName` union type in schema.ts

**Test scenarios:**
- Registry includes opencode adapter
- `AgentName` type accepts "opencode"

**Verification:**
- TypeScript compiles without errors
- Agentwatch starts with OpenCode adapter active

---

### U5. Add integration tests

**Goal:** Test adapter with realistic OpenCode session data.

**Dependencies:** U4

**Files:**
- `src/adapters/opencode.integration.test.ts` (new)
- `src/adapters/fixtures/opencode-sample.jsonl` (new - test fixture)

**Approach:**
1. Create sample OpenCode session JSONL fixture
2. Test full flow: file watch → parse → emit events
3. Test backfill behavior on restart
4. Test multiple concurrent sessions

**Test scenarios:**
- Adapter emits correct event sequence for sample session
- Backfill reads recent history on startup
- Multiple session files processed independently
- Cleanup function stops watcher

**Verification:**
- Integration tests pass
- No memory leaks (cursors cleaned up)

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| OpenCode session format changes | Adapter breaks | Pin to known schema version, add format detection |
| Large session files | Memory pressure | Backfill limit + cursor tracking |
| Concurrent writes | Partial reads | Chokidar handles file system events safely |

---

## Deferred to Follow-Up Work

- **OpenCode hooks integration:** Emit events in real-time via OpenCode's hook system (like Claude Code hooks adapter)
- **Cost calculation:** Add model pricing for OpenCode models when available
- **Subagent drilldown:** Support OpenCode's subagent/session hierarchy
- **3D visualization:** If mindmap/heatmap features are added to agentwatch-ui, they'll automatically work with OpenCode events

---

## Success Criteria

1. `agentwatch` starts and detects OpenCode sessions in `~/.opencode/sessions/`
2. OpenCode sessions appear in unified timeline alongside other agents
3. Tool calls and results are properly paired
4. Session lifecycle (start/end) is correctly detected
5. No performance degradation with multiple agents running
6. All tests pass

---

## References

- [agentwatch adapter pattern](https://github.com/mishanefedov/agentwatch/tree/main/src/adapters)
- [AgentEvent schema](https://github.com/mishanefedov/agentwatch/blob/main/src/schema.ts)
- [Claude Code adapter (reference implementation)](https://github.com/mishanefedov/agentwatch/blob/main/src/adapters/claude-code.ts)
- [Hermes adapter (SQLite reference)](https://github.com/mishanefedov/agentwatch/blob/main/src/adapters/hermes.ts)
