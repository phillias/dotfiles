/**
 * Pure, side-effect-free logic for the CLM (Context Language Models)
 * self-managed context plugin.
 *
 * CLM treats the model's context as a live, model-editable file: the harness
 * supplies the mechanics (a per-session file, an edit tool with a fit/shrink
 * gate, and a compaction hook that replays the authored file verbatim). This
 * module holds the deterministic core — parsing, serialization, token-budget
 * accounting, the edit gate, and the compaction-prompt builder — so it can be
 * unit-tested without opencode.
 *
 * References:
 *   - facebookresearch/context-language-models
 *   - "Context Language Models" arXiv:2609.37725
 *
 * See ../plugins/clm-context/README.md for the protocol and coexistence contract.
 */

import { stripJsonc } from "./opencode-runtime-fallback-core";

export type ClmRole = "user" | "assistant" | "system";

export interface ClmMessage {
  role: ClmRole;
  content: string;
}

export interface ClmBudget {
  /** Estimated token count (chars / 4). */
  tokens: number;
  /** Number of message blocks. */
  blocks: number;
  /** Raw character count across all block contents. */
  chars: number;
}

export interface ClmParseOk {
  ok: true;
  messages: ClmMessage[];
}

export interface ClmParseErr {
  ok: false;
  error: string;
  /** 1-based line number the error was detected on. */
  line: number;
}

export type ClmParseResult = ClmParseOk | ClmParseErr;

export interface ClmEditDecision {
  accepted: boolean;
  /** One-line reason; empty string when accepted. */
  reason: string;
  /** One-line receipt, always present. */
  receipt: string;
  before: ClmBudget;
  after: ClmBudget;
  budget: number;
}

export interface ClmConfig {
  enabled?: boolean;
  budget_tokens?: number;
}

/** Opening marker of a context block: `@@TURN <role> <n>`. */
export const TURN_OPEN = "@@TURN";
/** Closing marker of a context block. */
export const TURN_CLOSE = "@@END";
/** Default token budget for a live-context file. */
export const DEFAULT_BUDGET_TOKENS = 8000;

const ROLES: ReadonlySet<string> = new Set(["user", "assistant", "system"]);

/**
 * Rough token estimate: ~4 characters per token. Deliberately simple and
 * deterministic so the gate is reproducible; CLM budgets are order-of-magnitude,
 * not exact tokenizer counts.
 */
export function estimateTokens(text: string): number {
  if (!text) return 0;
  return Math.ceil([...text].length / 4);
}

export function computeBudget(messages: ClmMessage[]): ClmBudget {
  let chars = 0;
  for (const m of messages) chars += [...m.content].length;
  const joined = messages.map((m) => m.content).join("\n");
  return { tokens: estimateTokens(joined), blocks: messages.length, chars };
}

/** Render messages into the live-context file format. */
export function serializeLiveContext(messages: ClmMessage[]): string {
  const parts: string[] = [];
  for (let i = 0; i < messages.length; i++) {
    const m = messages[i];
    parts.push(`${TURN_OPEN} ${m.role} ${i + 1}`);
    parts.push(m.content);
    parts.push(TURN_CLOSE);
    parts.push("");
  }
  return parts.join("\n");
}

/**
 * Parse the live-context file back into a well-formed message structure.
 *
 * Format: one `@@TURN <role> <n>` header, arbitrary content lines, then
 * `@@END`. Blank lines and `#` comments are allowed outside blocks. Content is
 * taken verbatim; a `@@END` line inside content terminates the block, so content
 * must not contain a line equal to `@@END`.
 */
export function parseLiveContext(text: string): ClmParseResult {
  const lines = text.split("\n");
  const messages: ClmMessage[] = [];
  let i = 0;
  while (i < lines.length) {
    const trimmed = lines[i].trim();
    if (trimmed === "" || trimmed.startsWith("#")) {
      i++;
      continue;
    }
    if (!trimmed.startsWith(TURN_OPEN)) {
      return {
        ok: false,
        error: `unexpected content outside a ${TURN_OPEN} block`,
        line: i + 1,
      };
    }
    const header = trimmed.slice(TURN_OPEN.length).trim();
    const role = header.split(/\s+/)[0] ?? "";
    if (!ROLES.has(role)) {
      return {
        ok: false,
        error: `invalid or missing role (expected user|assistant|system)`,
        line: i + 1,
      };
    }
    i++;
    const content: string[] = [];
    let closed = false;
    while (i < lines.length) {
      if (lines[i].trim() === TURN_CLOSE) {
        closed = true;
        i++;
        break;
      }
      content.push(lines[i]);
      i++;
    }
    if (!closed) {
      return {
        ok: false,
        error: `missing ${TURN_CLOSE} for ${TURN_OPEN} ${role}`,
        line: i,
      };
    }
    while (content.length && content[0].trim() === "") content.shift();
    while (content.length && content[content.length - 1].trim() === "") content.pop();
    messages.push({ role: role as ClmRole, content: content.join("\n") });
  }
  return { ok: true, messages };
}

function safeParse(text: string): ClmMessage[] {
  const parsed = parseLiveContext(text);
  return parsed.ok ? parsed.messages : [];
}

/** Append one turn and re-serialize. Invalid prior content is treated as empty. */
export function appendTurn(text: string, role: ClmRole, content: string): string {
  const messages = safeParse(text);
  messages.push({ role, content });
  return serializeLiveContext(messages);
}

/**
 * The edit gate. An edit is accepted when it parses AND either fits the token
 * budget or strictly shrinks the file. Everything else is rejected with a
 * one-line reason. A one-line receipt is always produced.
 */
export function evaluateEdit(
  previous: string,
  edited: string,
  budget: number = DEFAULT_BUDGET_TOKENS,
): ClmEditDecision {
  const before = computeBudget(safeParse(previous));
  const parsed = parseLiveContext(edited);
  if (!parsed.ok) {
    const reason = `parse error (line ${parsed.line}): ${parsed.error}`;
    return {
      accepted: false,
      reason,
      receipt: `context_edit: rejected — ${reason}`,
      before,
      after: before,
      budget,
    };
  }
  const after = computeBudget(parsed.messages);
  const delta = `blocks ${before.blocks}->${after.blocks} tokens ${before.tokens}->${after.tokens} budget ${budget}`;
  if (after.tokens <= budget) {
    return {
      accepted: true,
      reason: "",
      receipt: `context_edit: accepted (fits) ${delta}`,
      before,
      after,
      budget,
    };
  }
  if (after.tokens < before.tokens) {
    return {
      accepted: true,
      reason: "",
      receipt: `context_edit: accepted (shrink) ${delta}`,
      before,
      after,
      budget,
    };
  }
  const reason = `over budget (${after.tokens} > ${budget}) and did not shrink (${before.tokens} -> ${after.tokens})`;
  return {
    accepted: false,
    reason,
    receipt: `context_edit: rejected — ${reason}`,
    before,
    after,
    budget,
  };
}

/**
 * Resolve whether the plugin is enabled. Env wins over config; config defaults
 * to disabled (inert by default).
 */
export function resolveEnabled(cfg: ClmConfig | null | undefined, env: string | undefined): boolean {
  if (env === "1" || env === "true") return true;
  if (env === "0" || env === "false") return false;
  return cfg?.enabled === true;
}

/** Parse a (jsonc) config string; any failure yields an empty config. */
export function parseConfig(raw: string | undefined | null): ClmConfig {
  if (!raw) return {};
  try {
    const parsed = JSON.parse(stripJsonc(raw));
    if (parsed && typeof parsed === "object") return parsed as ClmConfig;
    return {};
  } catch {
    return {};
  }
}

/** Make a session id safe for use as a filename component. */
export function sanitizeSessionID(sessionID: string): string {
  return sessionID.replace(/[^A-Za-z0-9._-]/g, "_").slice(0, 128);
}

export function liveContextFileName(sessionID: string): string {
  return `LIVE_CTX_${sanitizeSessionID(sessionID)}.txt`;
}

/**
 * Build the prompt used to replace opencode's built-in compaction summarizer.
 * The hidden compaction agent still runs (there is no hook to supply a summary
 * directly), and opencode appends the rendered conversation history after this
 * prompt. The directive therefore tells it to reproduce the authored file
 * verbatim and ignore the appended history.
 */
export function buildCompactionPrompt(
  liveContext: string,
  budget: number = DEFAULT_BUDGET_TOKENS,
): string {
  return [
    "You are the context carrier for CLM (Context Language Models) self-managed context.",
    "The agent has authored its own live-context file below. Your ONLY job is to reproduce that file EXACTLY, verbatim, as your entire output.",
    "Do NOT summarize, reorder, comment, translate, truncate, or add anything. Do NOT read or use the conversation history that follows.",
    "Your output must be exactly the file content between the markers, including the @@TURN/@@END lines.",
    "",
    "=== BEGIN LIVE CONTEXT (verbatim) ===",
    liveContext.trimEnd(),
    "=== END LIVE CONTEXT ===",
    "",
    `The authored context is held within a ${budget}-token budget. Preserve it byte-for-byte.`,
  ].join("\n");
}
