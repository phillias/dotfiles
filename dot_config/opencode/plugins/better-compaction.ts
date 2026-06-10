import type { Plugin } from "@opencode-ai/plugin";

/**
 * Better Compaction Plugin
 *
 * Replaces the default compaction prompt with one that aggressively
 * preserves critical context: exact technical details, user-pasted
 * content, constraints, preferences, and debugging state.
 *
 * Based on: https://github.com/anomalyco/opencode/issues/16512
 *
 * Without this plugin, the default compaction prompt tells the LLM to
 * summarize "what was done, what we're doing, which files we're working
 * on, what we're going to do next" — which causes it to:
 *   - Generalize exact names, paths, values, error messages away
 *   - Summarize user-pasted content into nothing
 *   - Lose user-stated constraints and preferences
 *   - Forget which debugging hypotheses were tested and ruled out
 */
export const BetterCompactionPlugin: Plugin = async () => {
  return {
    "experimental.session.compacting": async (_input, output) => {
      output.prompt = `You are compacting a conversation so it can continue in a new context window. Your job is to produce a continuation prompt that preserves ALL information needed to seamlessly resume work without losing anything important.

## CRITICAL RULES

1. NEVER generalize or summarize away specific details. Keep exact names, paths, values, error messages, flag names, config keys, URLs, version numbers, and file locations.
2. If the user pasted external content (conversation logs, error output, code snippets, config files), reproduce the KEY PARTS verbatim — do not summarize them.
3. Preserve ALL user-stated constraints, preferences, behavioral instructions, and communication style preferences.
4. Preserve the full investigation/debugging state: what hypotheses were tested, what was ruled out and with what evidence, what remains unexplored.
5. Preserve the agent/category model configuration and any fallback chain details that are relevant to ongoing work.

## OUTPUT TEMPLATE

Use this exact structure for the continuation prompt:

---
## Goal
[The specific goal(s) of the current task]

## Active Constraints & Preferences
- [User instructions, behavioral constraints, communication preferences, rules the agent must follow]
- [Model/provider constraints if relevant]

## Discoveries & Technical Details
[Exact technical details discovered so far: config values, file paths, flag names, CLI commands used, error messages, version numbers, API endpoints. Include what was tried and what happened — never generalize these.]

## User-Pasted Content (Key Parts)
[Verbatim reproduction of critical user-pasted content — error logs, config snippets, conversation output. If the content was large, reproduce the most important sections exactly.]

## Progress
### ✅ Completed
[Specific completed work items with verification details]

### ❌ Not Solved / Blocked
[Unsolved items with the current investigation state — what was tried, what was ruled out, what evidence supports each conclusion]

### ⏭️ Next Steps
[Planned next actions in priority order]

## Relevant Files & Resources
[Files read, modified, or created during this session. Key external references, documentation links, or API endpoints used.]
---`,
    },
  };
};
