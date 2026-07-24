import type { Plugin } from "@opencode-ai/plugin";
import { tool } from "@opencode-ai/plugin";
import { z } from "zod";

/**
 * axi-memory-bridge — Hybrid injection plugin for axi-memory
 *
 * Three injection strategies:
 * 1. Turn-level system context: injects relevant memories into system prompt every turn
 * 2. Agent-callable tools: axi-memory-search and axi-memory-add
 * 3. Auto-search on tool execution: appends ambient context to tool output
 *
 * Plus: user boost detection + lightweight memory scoring
 *
 * This plugin runs alongside codemem for A/B comparison during Phase 1-2.
 *
 * Design principle: ZERO console output. All communication to the agent happens
 * via tool output injection and system prompt context. No TUI disruption.
 */

// --- Lightweight scoring (adapted from better-compaction) -------------------

interface ScoreResult {
  score: number;
  reasoning: string;
  shouldRemember: boolean;
}

/**
 * Score a message for memory-worthiness using observable signals only.
 * Max score: 45. Threshold: >=12.
 *
 * Adapted from better-compaction's evaluateSkillWorthiness.
 * We lose: tool diversity, time investment, priority (todo-level signals).
 * We gain: real-time capture, lower cost, per-turn operation.
 */
function scoreMessage(content: string, userBoosted: boolean): ScoreResult {
  const c = content.toLowerCase();
  let score = 0;
  const reasons: string[] = [];

  // User boost is the strongest signal (+15)
  if (userBoosted) {
    score += 15;
    reasons.push("user_boost:15");
  }

  // Novelty keywords (+7)
  const noveltyKw = ["implement", "create", "build", "design", "architect", "setup", "configure", "migrate", "new", "added", "created"];
  if (noveltyKw.some(k => c.includes(k))) {
    score += 7;
    reasons.push("novelty:7");
  }

  // Depth keywords (+7)
  const depthKw = ["debug", "investigate", "research", "refactor", "optimize", "root cause", "analyze", "trace", "found that"];
  if (depthKw.some(k => c.includes(k))) {
    score += 7;
    reasons.push("depth:7");
  }

  // Risk keywords (+6)
  const riskKw = ["config", "setup", "integration", "deploy", "infra", "auth", "permission", "secret", "vault", "token"];
  if (riskKw.some(k => c.includes(k))) {
    score += 6;
    reasons.push("risk:6");
  }

  // Error/failure signal (+5)
  const errorKw = ["error", "failed", "broke", "crash", "panic", "exception", "bug", "regression"];
  if (errorKw.some(k => c.includes(k))) {
    score += 5;
    reasons.push("error:5");
  }

  // Decision signal (+5)
  const decisionKw = ["decided", "chose", "selected", "going with", "switched to", "adopted", "using instead"];
  if (decisionKw.some(k => c.includes(k))) {
    score += 5;
    reasons.push("decision:5");
  }

  return {
    score,
    reasoning: reasons.join(", "),
    shouldRemember: score >= 12,
  };
}

// --- Keyword detection for memory type --------------------------------------

function inferMemType(content: string): "constraint" | "decision" | "failure" | "howto" | "preference" {
  const c = content.toLowerCase();
  if (c.includes("debug") || c.includes("investigate") || c.includes("root cause") || c.includes("analyze") || c.includes("trace") || c.includes("found that")) return "failure";
  if (c.includes("fix") || c.includes("bug") || c.includes("patch") || c.includes("hotfix") || c.includes("error") || c.includes("broke")) return "failure";
  if (c.includes("must") || c.includes("never") || c.includes("always") || c.includes("don't") || c.includes("required")) return "constraint";
  if (c.includes("decided") || c.includes("chose") || c.includes("switched") || c.includes("adopted") || c.includes("going with")) return "decision";
  if (c.includes("to deploy") || c.includes("run ") || c.includes("execute") || c.includes("steps:") || c.includes("how to")) return "howto";
  if (c.includes("prefer") || c.includes("like ") || c.includes("favorite") || c.includes("best ")) return "preference";
  return "decision"; // default
}

function inferTags(content: string): string[] {
  const tags: string[] = [];
  const c = content.toLowerCase();
  if (c.includes("docker") || c.includes("compose") || c.includes("container")) tags.push("docker");
  if (c.includes("auth") || c.includes("jwt") || c.includes("token") || c.includes("oauth")) tags.push("auth");
  if (c.includes("db") || c.includes("database") || c.includes("postgres") || c.includes("sqlite")) tags.push("database");
  if (c.includes("deploy") || c.includes("ci") || c.includes("cd") || c.includes("github")) tags.push("ci");
  if (c.includes("proxy") || c.includes("reverse") || c.includes("gateway")) tags.push("proxy");
  if (c.includes("backup") || c.includes("restic") || c.includes("restore")) tags.push("backup");
  if (c.includes("mem") || c.includes("codemem") || c.includes("memory") || c.includes("sync")) tags.push("memory");
  if (c.includes("config") || c.includes("setup") || c.includes("install")) tags.push("config");
  return tags.length > 0 ? tags : ["general"];
}

// --- User boost detection (from better-compaction) ---------------------------

const BOOST_PHRASES = [
  "remember that", "keep that one", "save that", "remember this", "keep this",
  "worth remembering", "note that", "remember", "that's it", "fixed",
  "perfect", "worked", "got it", "nailed it",
];

function hasUserBoost(text: string): boolean {
  const lower = text.toLowerCase();
  return BOOST_PHRASES.some(p => lower.includes(p));
}

// --- Helpers ----------------------------------------------------------------

/** Check if mem search output has actual results (not empty state) */
function hasResults(output: string): boolean {
  return output.trim().length > 0 && !output.includes("count: 0 of 0");
}

/** Extract keywords from text, skipping stop words */
function extractKeywords(text: string, maxWords = 5): string {
  const stopWords = new Set(["the", "a", "an", "is", "are", "was", "were", "be", "been",
    "being", "have", "has", "had", "do", "does", "did", "will", "would", "could",
    "should", "may", "might", "can", "shall", "to", "of", "in", "for", "on", "with",
    "at", "by", "from", "as", "into", "through", "during", "before", "after",
    "and", "but", "or", "nor", "not", "so", "if", "then", "that", "this",
    "these", "those", "it", "its", "i", "me", "my", "we", "our", "you", "your",
    "he", "she", "they", "them", "what", "which", "who", "how", "when", "where", "why"]);

  return text.toLowerCase()
    .replace(/[^a-z0-9\s-]/g, " ")
    .split(/\s+/)
    .filter(w => w.length > 2 && !stopWords.has(w))
    .slice(0, maxWords)
    .join(" ");
}

// --- Plugin -----------------------------------------------------------------

export const AxiMemoryBridgePlugin: Plugin = async (input) => {
  const shell = input.$;

  const lastUserMessages = new Map<string, string>();
  const capturedThisSession = new Map<string, Set<string>>();

  return {
    // ── Strategy 1: Turn-level system context ─────────────────────────────
    // Runs on EVERY turn (no injectedSessions guard).
    // Extracts keywords from the last user message and searches axi-memory.
    "experimental.chat.system.transform": async (
      input: { sessionID?: string; model: any },
      output: { system: string[] },
    ) => {
      if (!input.sessionID) return;

      const lastMsg = lastUserMessages.get(input.sessionID);
      if (!lastMsg) return;

      const query = extractKeywords(lastMsg, 5);
      if (!query) return;

      try {
        const result = await shell`mem search "${query}" --limit 3`.quiet().nothrow().text();
        if (hasResults(result)) {
          output.system.push(`\n## axi-memory (live)\n${result}`);
        }
      } catch {
        // Silent fail — axi-memory is best-effort
      }
    },

    // ── Strategy 2: Agent-callable tools ──────────────────────────────────
    tool: {
      "axi-memory-search": tool({
        description: "Search durable memories (axi-memory). Use at the start of new tasks, when encountering familiar patterns, or when the user references past decisions. Returns markdown memories with YAML frontmatter.",
        args: {
          query: z.string().describe("Search query (keywords or phrase)"),
          type: z.enum(["constraint", "decision", "failure", "howto", "preference"]).optional()
            .describe("Filter by memory type"),
        },
        execute: async (args) => {
          try {
            const cmd = args.type
              ? `mem search "${args.query}" --type ${args.type} --limit 5`
              : `mem search "${args.query}" --limit 5`;
            const result = await shell`${cmd}`.quiet().nothrow().text();
            if (!hasResults(result)) {
              return { output: `No memories found for "${args.query}".` };
            }
            return { output: `axi-memory results for "${args.query}":\n${result}` };
          } catch (err) {
            return { output: `axi-memory search error: ${err}` };
          }
        },
      }),

      "axi-memory-add": tool({
        description: "Persist a memory (axi-memory). Use when you discover something worth remembering across sessions: a decision with rationale, a failure root cause, a constraint, a procedure, or a user preference.",
        args: {
          type: z.enum(["constraint", "decision", "failure", "howto", "preference"])
            .describe("Memory type"),
          title: z.string().describe("Short title (used to generate slug)"),
          body: z.string().optional().describe("Long-form markdown body"),
          tags: z.string().optional().describe("Comma-separated tags"),
        },
        execute: async (args) => {
          try {
            let cmd = `mem add --type ${args.type} --title "${args.title}"`;
            if (args.body) cmd += ` --body "${args.body}"`;
            if (args.tags) cmd += ` --tags "${args.tags}"`;
            const result = await shell`${cmd}`.quiet().nothrow().text();
            return { output: result };
          } catch (err) {
            return { output: `axi-memory add error: ${err}` };
          }
        },
      }),
    },

    // ── Capture last user message + user boost detection ──────────────────
    "chat.message": async (
      input: { sessionID: string; agent?: string; model?: any; messageID?: string; variant?: string },
      output: { message: any; parts: any[] },
    ) => {
      const text = output.parts.map(p => p.text ?? "").join(" ");
      if (!text) return;

      // Store last user message for system context injection
      lastUserMessages.set(input.sessionID, text);

      // Score ALL messages — auto-save high-scoring ones (threshold ≥12/45).
      // User boost adds +15, making "remember that" nearly always cross the line.
      // But novelty(7)+depth(7)=14 or novelty(7)+risk(6)+error(5)=18 also trigger.
      const boosted = hasUserBoost(text);
      const score = scoreMessage(text, boosted);
      if (score.shouldRemember) {
        const title = text.slice(0, 80).replace(/"/g, '\\"');
        const sessionCaptures = capturedThisSession.get(input.sessionID) ?? new Set<string>();
        if (!capturedThisSession.has(input.sessionID)) capturedThisSession.set(input.sessionID, sessionCaptures);
        sessionCaptures.add(title);
      }
    },

    // ── Strategy 3: Auto-search on tool execution ─────────────────────────
    // After non-trivial tool calls, search axi-memory and append results
    // to the tool output so the agent sees ambient context.
    "tool.execute.after": async (input: {
      tool: string;
      sessionID: string;
      callID: string;
      args: any;
    }, output: {
      title: string;
      output: string;
      metadata: any;
    }) => {
      // Skip tools where memory context is not useful
      const skipTools = new Set([
        // File ops — context is in the file itself
        "read", "glob", "lsp_diagnostics", "lsp_symbols", "lsp_find_references",
        // Meta tools — no useful memory context
        "todowrite", "session_info", "session_list", "session_read",
        // Fleet tools — different concern
        "background_output", "background_cancel",
        // Memory tools themselves — avoid recursion
        "axi-memory-search", "axi-memory-add", "codemem-search",
        // Edit/write — we just changed the file, memory about it is stale
        "edit", "write",
      ]);
      if (skipTools.has(input.tool)) return;

      // Build a search query from the tool name + relevant args
      let query = input.tool;
      if (input.args?.query) query += " " + input.args.query;
      if (input.args?.command) query += " " + input.args.command;
      if (input.args?.pattern) query += " " + input.args.pattern;
      if (input.args?.filePath) {
        const parts = input.args.filePath.split("/");
        query += " " + parts[parts.length - 1].replace(/\.[^.]+$/, "");
      }

      try {
        const result = await shell`mem search "${query}" --limit 2`.quiet().nothrow().text();
        if (hasResults(result)) {
          // Append to tool output — agent sees this as ambient context
          output.output += `\n\n[axi-memory: ${result.trim()}]`;
        }
      } catch {
        // Silent fail
      }
    },

    // ── Strategy 4: Session-end auto-capture ────────────────────────────
    // On session.idle, check if any captured messages had high scores
    // but weren't saved yet (dedup via capturedThisSession set).
    event: async (input: { event: { type: string; properties?: any } }) => {
      if (input.event.type !== "session.idle") return;
      const sessionID = input.event.properties?.sessionID ?? "";
      if (!sessionID) return;

      const captured = capturedThisSession.get(sessionID);
      if (!captured || captured.size === 0) {
        lastUserMessages.delete(sessionID);
        capturedThisSession.delete(sessionID);
        return;
      }

      for (const title of captured) {
        const memType = inferMemType(title);
        const tags = inferTags(title).join(",");
        try {
          await shell`mem add --type ${memType} --title "${title.replace(/"/g, '\\"')}" --tags "${tags}" --body "Auto-captured at session end"`.quiet().nothrow();
        } catch {
          // Silent fail
        }
      }

      lastUserMessages.delete(sessionID);
      capturedThisSession.delete(sessionID);
    },
  };
};
