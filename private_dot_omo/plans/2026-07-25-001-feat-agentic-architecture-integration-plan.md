---
title: "Integrate Fareed Khan's Agentic Architecture Patterns into OmO"
type: feat
created: 2026-07-25
status: active
origin: Research synthesis from all-agentic-architectures analysis
---

# Integrate Agentic Architecture Patterns into OmO

## Problem Frame

OpenCode + OhMyOpenCode (OmO) is a sophisticated multi-agent orchestration system with 12+ specialized agents, 8 task categories, 55+ CE skills, and multi-layer memory management. While it already implements many agentic patterns informally, Fareed Khan's **all-agentic-architectures** project provides a formal taxonomy of 35 production-grade patterns that could harden and extend OmO's capabilities.

**Key Gap**: OmO's routing and scoring decisions are heuristic-based (dispatch-rules.json pattern matching) rather than principled. The deterministic-picker pattern from Fareed Khan's work could make these decisions auditable and scoreable.

## Scope Boundaries

### In Scope
- Deterministic-picker pattern for route selection and review scoring
- Episodic memory patterns for code review and session history
- Debate pattern for architecture decisions (formalizing hyperplan)
- Reflexion pattern for iterative code improvement
- Safety pattern enhancements (Dry-Run, Reflexive Metacognitive)

### Out of Scope
- Python/LangGraph rewrite (OmO is TypeScript)
- New model provider integrations
- UI/TUI changes
- MCP server modifications

### Deferred to Follow-Up Work
- Vector database integration for semantic memory
- Self-improvement loops (RLHF patterns)
- Cellular automata for emergent behavior

## Key Technical Decisions

### D1: Pattern Portability Over Implementation Reuse
**Decision**: Port patterns as TypeScript primitives, not Python ports. Fareed Khan's patterns are conceptual; OmO's TypeScript stack requires native implementations.

**Rationale**: Direct Python imports would introduce cross-language complexity. The deterministic-picker pattern (Pydantic → Zod) translates cleanly to TypeScript.

### D2: Dispatch Rules as Deterministic Picker
**Decision**: Replace current dispatch-rules.json heuristic matching with categorical feature extraction + scoring function.

**Rationale**: Current system uses pattern matching (first-match-wins). Deterministic picker extracts boolean/enum features from task description and composes a routing score.

### D3: Memory Layer Formalization
**Decision**: Formalize OmO's three memory layers (session, fleet state, ce-sessions) using Fareed Khan's memory taxonomy.

**Rationale**: OmO already has memory systems but they're ad-hoc. Formalizing as episodic/semantic/graph memory enables principled retrieval strategies.

## Implementation Units

### U1: Deterministic Picker Core Library
**Goal**: Create a TypeScript library implementing the deterministic-picker pattern for categorical scoring.

**Requirements**: Enables auditable, scoreable routing decisions across OmO.

**Dependencies**: None (foundation layer).

**Files**:
- `~/.config/opencode/plugins/deterministic-picker.ts` (new)
- `~/.config/opencode/plugins/deterministic-picker.test.ts` (new, test file)

**Approach**:
1. Define Zod schemas for task features (boolean/enum categorical fields)
2. Implement composite scoring functions that compose features into scores
3. Create picker functions that select categories based on scores
4. Add logging for audit trail (which features contributed to which score)

**Technical Design**:
```typescript
// Directional sketch — not implementation specification
interface TaskFeatures {
  is_single_file: boolean
  requires_ui_work: boolean
  needs_deep_research: boolean
  touches_auth_or_payments: boolean
  is_config_or_typo: boolean
  is_ambiguous: boolean
}

function pickCategory(features: TaskFeatures): string {
  // Categorical composition, not LLM flat-band
  if (features.is_config_or_typo) return "quick"
  if (features.requires_ui_work) return "visual-engineering"
  if (features.needs_deep_research) return "deep"
  if (features.touches_auth_or_payments) return "ultrabrain"
  return "unspecified-high"
}
```

**Test Scenarios**:
- **Happy path**: Config task → "quick" category
- **Edge case**: Ambiguous task with multiple true features → highest-priority category wins
- **Error path**: All features false → fallback to "unspecified-high"
- **Integration**: Picker output feeds into existing `task()` calls

**Verification**: Picker returns correct category for 10+ representative task descriptions.

---

### U2: Task Feature Extractor
**Goal**: Build a feature extractor that parses task descriptions into categorical features for the deterministic picker.

**Requirements**: Extract boolean/enum features from natural language task descriptions.

**Dependencies**: U1 (deterministic picker core).

**Files**:
- `~/.config/opencode/plugins/task-feature-extractor.ts` (new)
- `~/.config/opencode/plugins/task-feature-extractor.test.ts` (new)

**Approach**:
1. Define feature extraction rules (keyword matching, pattern detection)
2. Implement extractor that outputs TaskFeatures from task string
3. Add confidence scores for ambiguous extractions
4. Integrate with dispatch-rules.json evaluation

**Test Scenarios**:
- **Happy path**: "fix typo in README" → is_config_or_typo=true, is_single_file=true
- **Edge case**: "refactor auth module" → touches_auth_or_payments=true, is_ambiguous=true
- **Error path**: Empty string → all features false, confidence=0
- **Integration**: Extractor feeds into U1 picker

**Verification**: Extractor correctly identifies features for 15+ task descriptions.

---

### U3: Reflexion Memory for Code Review
**Goal**: Add episodic memory to ce-code-review so past review findings inform future reviews.

**Requirements**: Store review outcomes, retrieve relevant past findings for new reviews.

**Dependencies**: U1 (deterministic picker for scoring review quality).

**Files**:
- `~/.config/opencode/skills/ce-code-review/references/reflexion-memory.md` (new)
- `~/.config/opencode/skills/ce-code-review/scripts/store-review-outcome.py` (new)
- `~/.config/opencode/skills/ce-code-review/scripts/retrieve-past-findings.py` (new)

**Approach**:
1. Define review outcome schema (what was found, what was missed, quality score)
2. Store outcomes in `~/.local/state/ce-code-review/episodic/` as JSONL
3. Before new review, query past outcomes for same file/area/pattern
4. Inject past findings into reviewer prompts as "lessons learned"

**Technical Design**:
```python
# Directional sketch
outcome = {
  "run_id": "abc123",
  "timestamp": "2026-07-25T10:00:00Z",
  "files_reviewed": ["src/auth.ts", "src/auth.test.ts"],
  "findings": [...],
  "missed_patterns": ["off-by-one in token expiry"],
  "quality_score": 78  # From deterministic picker
}
```

**Test Scenarios**:
- **Happy path**: Review of auth.ts retrieves past auth findings
- **Edge case**: First review of new file → no past findings, clean slate
- **Error path**: Corrupted episodic store → graceful fallback to no memory
- **Integration**: Past findings appear in reviewer prompts

**Verification**: Reviewer prompts contain relevant past findings for returning files.

---

### U4: Debate Pattern for Architecture Decisions
**Goal**: Formalize the hyperplan command using Fareed Khan's Debate pattern for architecture decisions.

**Requirements**: Spawn 3+ agents with opposing viewpoints, synthesize consensus.

**Dependencies**: U1 (deterministic picker for scoring debate outcomes).

**Files**:
- `~/.config/opencode/skills/debate-architecture/SKILL.md` (new)
- `~/.config/opencode/agents/ce-debate-architect-1.md` (new)
- `~/.config/opencode/agents/ce-debate-architect-2.md` (new)
- `~/.config/opencode/agents/ce-debate-architect-3.md` (new)

**Approach**:
1. Define 3 architect personas with opposing viewpoints (conservative, aggressive, pragmatic)
2. Each agent critiques the proposal from their perspective
3. Synthesis agent aggregates critiques and produces consensus recommendation
4. Use deterministic picker to score debate quality (coverage, evidence, novelty)

**Test Scenarios**:
- **Happy path**: Architecture proposal → 3 critiques → synthesis with recommendation
- **Edge case**: All 3 agents agree → note consensus, still produce synthesis
- **Error path**: One agent fails → continue with 2, note partial coverage
- **Integration**: Debate output feeds into ce-plan for implementation

**Verification**: Debate produces 3+ critiques and a synthesis that addresses all viewpoints.

---

### U5: Safety Pattern Enhancements
**Goal**: Add Dry-Run and Reflexive Metacognitive patterns to OmO's safety layer.

**Requirements**: Simulate tool calls before executing, self-assess capability before attempting.

**Dependencies**: None (independent of other units).

**Files**:
- `~/.config/opencode/plugins/dry-run-simulator.ts` (new)
- `~/.config/opencode/skills/capability-assessment/SKILL.md` (new)

**Approach**:
1. Implement dry-run mode that simulates tool calls without execution
2. Add capability assessment skill that evaluates whether agent can complete task
3. Integrate with mcp-runtime-guard for shadow mode simulation
4. Add Reflexive Metacognitive checks before tool execution

**Test Scenarios**:
- **Happy path**: Dry-run mode simulates `git push` without executing
- **Edge case**: Dry-run detects policy violation → block before execution
- **Error path**: Simulation fails → fall through to normal execution with warning
- **Integration**: Capability assessment informs routing decisions

**Verification**: Dry-run mode correctly simulates tool outcomes without side effects.

---

### U6: Deterministic Review Scoring
**Goal**: Replace LLM-based review scoring with deterministic picker scoring.

**Requirements**: Score review findings using categorical features, not numeric LLM output.

**Dependencies**: U1 (deterministic picker core), U3 (reflexion memory).

**Files**:
- `~/.config/opencode/skills/ce-code-review/references/deterministic-scoring.md` (new)
- `~/.config/opencode/skills/ce-code-review/scripts/score-finding.py` (new)

**Approach**:
1. Define categorical features for review findings (severity, confidence, evidence quality)
2. Implement composite scoring that produces 0-100 scores with real spread
3. Replace LLM-based scoring in ce-code-review subagent template
4. Store scores in episodic memory for trend analysis

**Test Scenarios**:
- **Happy path**: Critical finding with strong evidence → high score
- **Edge case**: Ambiguous finding with weak evidence → medium score with low confidence
- **Error path**: Missing features → default conservative score
- **Integration**: Scores feed into finding prioritization

**Verification**: Scores show meaningful spread (not flat-band 4/5 behavior).

---

## System-Wide Impact

### Affected Parties
- **Sisyphus**: Dispatch rules evaluation changes (Phase 0 Intent Gate)
- **ce-code-review**: Scoring and memory integration
- **ce-plan**: Debate pattern integration for architecture decisions
- **mcp-runtime-guard**: Dry-run simulation mode
- **fleet-state-writer**: Extended to track episodic memory state

### Dependencies
- Existing OmO agent system (no changes required)
- Existing dispatch-rules.json (extended, not replaced)
- Existing ce-code-review personas (enhanced with memory)

### Risks
- **Risk**: Deterministic picker may miss nuanced tasks that current heuristics handle
  - **Mitigation**: Keep current dispatch-rules.json as fallback, picker as primary
- **Risk**: Episodic memory may grow unbounded
  - **Mitigation**: TTL-based pruning (keep last 30 days), summary compression
- **Risk**: Debate pattern adds latency to architecture decisions
  - **Mitigation**: Optional mode, not default; use only for high-stakes decisions

## Success Metrics

1. **Route Selection Accuracy**: Deterministic picker matches or exceeds current heuristic routing for 90%+ of tasks
2. **Review Score Spread**: Deterministic scoring produces scores with standard deviation > 1.5 (vs flat-band)
3. **Episodic Memory Retrieval**: Past findings relevant to 70%+ of returning file reviews
4. **Debate Consensus Quality**: Synthesis addresses all 3 viewpoints in 90%+ of debates
5. **Dry-Run Accuracy**: Simulation matches actual outcome for 85%+ of tool calls

## Alternatives Considered

### A1: Python/LangGraph Port
**Considered**: Port Fareed Khan's Python implementations directly.
**Rejected**: Cross-language complexity outweighs benefits. Patterns translate cleanly to TypeScript.

### A2: LLM-as-Judge for Scoring
**Considered**: Keep LLM scoring but add evaluation rubrics.
**Rejected**: LLM flat-band pathology is fundamental; deterministic picker solves root cause.

### A3: External Vector DB for Memory
**Considered**: Add Qdrant/Pinecone for semantic memory.
**Deferred**: Current session search + fleet state is sufficient. Vector DB adds operational complexity.

## Deferred to Follow-Up Work

- Vector database integration for semantic memory (duckdb/turso/qdrant survey needed)
- Self-improvement loops (RLHF patterns from Fareed Khan's training-ai-agents repo)
- Cellular automata for emergent behavior
- Production-grade MCP server architecture (from production-grade-mcp-agentic-system repo)
- Agentic parallelism patterns (from agentic-parallelism repo)

## References

- **Origin**: Fareed Khan's all-agentic-architectures (github.com/FareedKhan-dev/all-agentic-architectures)
- **Related repos**: production-grade-agentic-system, agentic-parallelism, claude-code-from-scratch
- **OmO architecture**: ~/.config/opencode/AGENTS.md, oh-my-openagent.jsonc, dispatch-rules.json
- **CE skills**: ce-code-review, ce-plan, ce-work, mcp-runtime-guard, mcp-policy-enforce
