import type { Plugin } from "@opencode-ai/plugin";
import { tool } from "@opencode-ai/plugin";
import { z } from "zod";

/**
 * axi-memory-bridge — Hybrid injection plugin for axi-memory
 *
 * Three injection strategies:
 * 1. Turn-level system context: injects relevant memories into system prompt (once per session)
 * 2. Agent-callable tools: axi-memory-search and axi-memory-add
 * 3. Auto-search on tool execution: appends ambient context to tool output (throttled + cached)
 *
 * Plus: user boost detection + lightweight memory scoring
 *
 * Performance guards:
 * - System context: injected once per session (injectedSessions guard), not every turn
 * - Tool output: throttled to max 1 mem search per 5 seconds per session, with LRU cache
 * - Both use ripgrep which is fast (~0.1s) but process spawn overhead adds up at scale
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

// --- Throttle + Cache for tool.execute.after --------------------------------

const TOOL_SEARCH_INTERVAL_MS = 5_000; // Max 1 mem search per 5 seconds per session
const TOOL_CACHE_TTL_MS = 60_000;      // Cache results for 60 seconds
const TOOL_CACHE_MAX = 200;            // Max cached entries before eviction

interface CacheEntry {
  result: string;
  ts: number;
}

function makeToolCacheKey(sessionID: string, query: string): string {
  return `${sessionID}::${query}`;
}

/** Sanitize a string for safe use in a shell double-quoted argument.
 *  Strips control chars (newlines, tabs, etc.), truncates to 200 chars
 *  for search queries to prevent massive commands from flooding mem search. */
function sanitizeShellArg(s: string, maxLen = 200): string {
  return s
    .replace(/"/g, '\\"')
    .replace(/\n/g, ' ')
    .replace(/\r/g, ' ')
    .replace(/\t/g, ' ')
    .slice(0, maxLen)
    .trim();
}

/** Sanitize a string for use as a memory title (shorter, no newlines). */
function sanitizeTitle(s: string): string {
  return s
    .replace(/"/g, '\\"')
    .replace(/\n/g, ' ')
    .replace(/\r/g, '')
    .slice(0, 80)
    .trim();
}

// --- Plugin -----------------------------------------------------------------

export const AxiMemoryBridgePlugin: Plugin = async (input) => {
  const shell = input.$;

  const lastUserMessages = new Map<string, string>();
  const capturedThisSession = new Map<string, Set<string>>();

  // Strategy 1: session-scoped guard (run once per session)
  const injectedSessions = new Set<string>();

  // Strategy 3: throttle + LRU cache for tool.execute.after
  const lastToolSearch = new Map<string, number>(); // sessionID → timestamp
  const toolSearchCache = new Map<string, CacheEntry>(); // key → cached result

  function evictToolCache() {
    if (toolSearchCache.size <= TOOL_CACHE_MAX) return;
    // Evict oldest entries
    const entries = [...toolSearchCache.entries()]
      .sort((a, b) => a[1].ts - b[1].ts);
    const toRemove = entries.slice(0, entries.length - TOOL_CACHE_MAX);
    for (const [k] of toRemove) toolSearchCache.delete(k);
  }

  async function runMemSearch(query: string, limit: number): Promise<string> {
    return await shell`mem search "${query}" --limit ${limit}`.quiet().nothrow().text();
  }

  return {
    // ── Strategy 1: Turn-level system context ─────────────────────────────
    // Runs ONCE per session — extracts keywords from the first user message
    // and searches axi-memory. Subsequent turns reuse the injected context.
    "experimental.chat.system.transform": async (
      input: { sessionID?: string; model: any },
      output: { system: string[] },
    ) => {
      if (!input.sessionID) return;
      if (injectedSessions.has(input.sessionID)) return;

      const lastMsg = lastUserMessages.get(input.sessionID);
      if (!lastMsg) return;

      const query = extractKeywords(lastMsg, 5);
      if (!query) return;

      injectedSessions.add(input.sessionID);

      try {
        const result = await runMemSearch(query, 3);
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
          if (!args.query?.trim()) return { output: "Query is required." };
          const q = sanitizeShellArg(args.query);
          const cmd = args.type
            ? `mem search "${q}" --type ${args.type} --limit 5`
            : `mem search "${q}" --limit 5`;
          const result = await shell`${cmd}`.quiet().nothrow().text();
          if (!hasResults(result)) {
            return { output: `No memories found for "${q}".` };
          }
          return { output: `axi-memory results for "${q}":\n${result}` };
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
          const title = sanitizeTitle(args.title);
          if (!title) return { output: "Title is required." };
          let cmd = `mem add --type ${args.type} --title "${title}"`;
          if (args.body) {
            const body = sanitizeShellArg(args.body, 500);
            if (body) cmd += ` --body "${body}"`;
          }
          if (args.tags) {
            const tags = sanitizeShellArg(args.tags, 100);
            if (tags) cmd += ` --tags "${tags}"`;
          }
          const result = await shell`${cmd}`.quiet().nothrow().text();
          return { output: result };
        },
      }),
    },

    // ── Capture last user message + user boost detection + auto-save ──────
    "chat.message": async (
      input: { sessionID: string; agent?: string; model?: any; messageID?: string; variant?: string },
      output: { message: any; parts: any[] },
    ) => {
      const text = output.parts.map(p => p.text ?? "").join(" ");
      if (!text) return;

      // Store last user message for system context injection
      lastUserMessages.set(input.sessionID, text);

      // Score ALL messages — auto-save high-scoring ones immediately (threshold ≥12/45).
      // User boost adds +15, making "remember that" nearly always cross the line.
      // But novelty(7)+depth(7)=14 or novelty(7)+risk(6)+error(5)=18 also trigger.
      const boosted = hasUserBoost(text);
      const score = scoreMessage(text, boosted);
      if (score.shouldRemember) {
        // Dedup: don't save the same title twice in this session
        const sessionCaptures = capturedThisSession.get(input.sessionID) ?? new Set<string>();
        if (!capturedThisSession.has(input.sessionID)) capturedThisSession.set(input.sessionID, sessionCaptures);
        
        const title = sanitizeTitle(text);
        if (sessionCaptures.has(title)) return; // Already captured this turn
        sessionCaptures.add(title);

        // Save immediately — don't wait for session.idle (which may never fire)
        const memType = inferMemType(title);
        const tags = inferTags(title).join(",");
        try {
          await shell`mem add --type ${memType} --title "${title}" --tags "${tags}" --body "Auto-captured (${score.reasoning})"`.quiet().nothrow();
        } catch {
          // Silent fail — axi-memory is best-effort
        }
      }
    },

    // ── Strategy 3: Auto-search on tool execution ─────────────────────────
    // After non-trivial tool calls, search axi-memory and append results
    // to the tool output so the agent sees ambient context.
    //
    // THROTTLE: Max 1 mem search per 5 seconds per session. During rapid
    // tool execution (20-50 calls/turn), only the first search actually
    // runs; the rest are skipped. This prevents process spawn storms.
    //
    // CACHE: Search results are cached for 60 seconds by query hash.
    // Repeated similar queries (e.g., "bash" tool with similar commands)
    // hit the cache instead of spawning new processes.
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
        // Long-running tools — don't delay their output
        "task",
      ]);
      if (skipTools.has(input.tool)) return;

      // Build a search query from the tool name + relevant args
      // All args must be sanitized — especially `command` which is raw bash
      let query = input.tool;
      if (input.args?.query) query += " " + sanitizeShellArg(input.args.query);
      if (input.args?.command) query += " " + sanitizeShellArg(input.args.command);
      if (input.args?.pattern) query += " " + sanitizeShellArg(input.args.pattern);
      if (input.args?.filePath) {
        const parts = input.args.filePath.split("/");
        query += " " + sanitizeShellArg(parts[parts.length - 1].replace(/\.[^.]+$/, ""));
      }

      // Throttle: skip if we searched too recently for this session
      const now = Date.now();
      const lastSearch = lastToolSearch.get(input.sessionID) ?? 0;
      if (now - lastSearch < TOOL_SEARCH_INTERVAL_MS) {
        return; // Throttled — skip this search
      }

      // Check cache first
      const cacheKey = makeToolCacheKey(input.sessionID, query);
      const cached = toolSearchCache.get(cacheKey);
      if (cached && (now - cached.ts) < TOOL_CACHE_TTL_MS) {
        // Cache hit — still count as a search for throttling purposes
        // (prevents rapid-fire queries even on cache hits)
        lastToolSearch.set(input.sessionID, now);
        if (hasResults(cached.result)) {
          output.output += `\n\n[axi-memory: ${cached.result.trim()}]`;
        }
        return;
      }

      // Cache miss — run the search
      lastToolSearch.set(input.sessionID, now);

      try {
        const result = await runMemSearch(query, 2);

        // Store in cache
        toolSearchCache.set(cacheKey, { result, ts: now });
        evictToolCache();

        if (hasResults(result)) {
          // Append to tool output — agent sees this as ambient context
          output.output += `\n\n[axi-memory: ${result.trim()}]`;
        }
      } catch {
        // Silent fail
      }
    },

  };
};
