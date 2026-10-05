/**
 * CLM (Context Language Models) self-managed context plugin.
 *
 * The model's context is exposed as a live, per-session file it can read and
 * rewrite through the `context_edit` tool. The harness mirrors user turns
 * (via chat.message) and assistant turns (via settled message.part.updated
 * events) into the file, injects it into the system prompt once per session,
 * and enforces a token budget by rolling back newest turns when the mirror
 * grows too large. At compaction, the mirror is re-seeded from the compacted
 * summary instead of embedding the unbounded file.
 *
 * Inert by default: unless `clm.jsonc` sets `enabled: true` (or
 * `OPENCODE_CLM=1`), this plugin registers no hooks and no tools, so session
 * behavior is byte-for-byte identical to running without it.
 *
 * References: facebookresearch/context-language-models, arXiv:2609.37725.
 * Docs: ./clm-context/README.md (coexistence contract with dcp + built-in compaction).
 */

import type { Plugin } from "@opencode-ai/plugin";
import { tool } from "@opencode-ai/plugin";
import { mkdirSync, readFileSync, writeFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";
import {
  DEFAULT_BUDGET_TOKENS,
  type ClmConfig,
  type ClmRole,
  appendTurn,
  buildCompactionPrompt,
  enforceBudget,
  evaluateEdit,
  liveContextFileName,
  parseConfig,
  resolveEnabled,
} from "../lib/clm-context-core";

const CONFIG_PATH = join(homedir(), ".config", "opencode", "clm.jsonc");
const STATE_DIR = join(homedir(), ".local", "state", "opencode-clm");

function loadConfig(): ClmConfig {
  try {
    return parseConfig(readFileSync(CONFIG_PATH, "utf-8"));
  } catch {
    return {};
  }
}

function textFromParts(parts: unknown): string {
  if (!Array.isArray(parts)) return "";
  return parts
    .filter(
      (p): p is { type: string; text: string } =>
        !!p &&
        typeof p === "object" &&
        (p as { type?: unknown }).type === "text" &&
        typeof (p as { text?: unknown }).text === "string",
    )
    .map((p) => p.text)
    .join("\n");
}

export const ClmContextPlugin: Plugin = async ({ client }) => {
  const cfg = loadConfig();
  const enabled = resolveEnabled(cfg, process.env.OPENCODE_CLM);
  if (!enabled) return {};

  const budget =
    typeof cfg.budget_tokens === "number" && cfg.budget_tokens > 0
      ? cfg.budget_tokens
      : DEFAULT_BUDGET_TOKENS;

  const injected = new Set<string>();
  const mirrored = new Set<string>();

  const fileFor = (sessionID: string) => join(STATE_DIR, liveContextFileName(sessionID));

  const read = (sessionID: string): string => {
    try {
      return readFileSync(fileFor(sessionID), "utf-8");
    } catch {
      return "";
    }
  };

  const write = (sessionID: string, text: string): void => {
    try {
      mkdirSync(STATE_DIR, { recursive: true });
      writeFileSync(fileFor(sessionID), text);
    } catch (err) {
      console.error("[clm-context] write failed", err);
    }
  };

  return {
    // Mirror user turns via chat.message (fires for user messages only).
    // Dedup by message id so re-delivery does not double-append.
    "chat.message": async (input, output) => {
      try {
        const sessionID = input.sessionID;
        if (!sessionID) return;
        const role = (output.message as { role?: string } | undefined)?.role;
        if (role !== "user") return;
        const messageID = input.messageID ?? (output.message as { id?: string })?.id ?? "";
        const key = `${sessionID}:${messageID}`;
        if (messageID && mirrored.has(key)) return;
        const text = textFromParts(output.parts);
        if (!text.trim()) return;
        if (messageID) mirrored.add(key);
        const appended = appendTurn(read(sessionID), role as ClmRole, text);
        const enforced = enforceBudget(appended, budget);
        write(sessionID, enforced.content);
        if (enforced.nudge) console.info(`[clm-context] ${enforced.nudge}`);
      } catch (err) {
        console.error("[clm-context] chat.message mirror failed", err);
      }
    },

    // One-shot: surface the authored context to the model at session start.
    "experimental.chat.system.transform": async (input, output) => {
      try {
        const sessionID = input.sessionID;
        if (!sessionID || injected.has(sessionID)) return;
        const current = read(sessionID);
        if (!current.trim()) return;
        injected.add(sessionID);
        output.system.push(
          [
            "# CLM live context (self-managed)",
            "You own the context file below. Read it with `context_edit` (action: read) and rewrite it with `context_edit` (action: replace).",
            "The edit gate accepts a rewrite only if it fits the token budget or strictly shrinks the file; otherwise it is rejected with a one-line reason.",
            "",
            current.trimEnd(),
          ].join("\n"),
        );
      } catch (err) {
        console.error("[clm-context] system.transform inject failed", err);
      }
    },

    // Replace the built-in summarizer prompt. When the mirror is within budget,
    // embed it verbatim (bounded mode). When unbounded, instruct the summarizer
    // to condense into a fresh bounded context (re-seed mode) — the summary is
    // then fetched on session.compacted and written back to the mirror file.
    // dcp does not use this hook, and built-in compaction still runs its hidden
    // summarizer agent — see the README coexistence contract.
    "experimental.session.compacting": async (input, output) => {
      try {
        const sessionID = input.sessionID;
        if (!sessionID) return;
        const current = read(sessionID);
        if (!current.trim()) return;
        const enforced = enforceBudget(current, budget);
        if (enforced.tokens <= budget) {
          output.prompt = buildCompactionPrompt(enforced.content, budget);
        } else {
          output.prompt = buildCompactionPrompt(undefined, budget);
        }
      } catch (err) {
        console.error("[clm-context] compacting hook failed", err);
      }
    },

    event: async ({ event }) => {
      try {
        const e = event as {
          type?: string;
          properties?: { sessionID?: string; part?: { id?: string; type?: string; text?: string; time?: { end?: number } } };
        };
        const sid = e.properties?.sessionID;
        if (e?.type === "session.deleted") {
          if (sid) {
            injected.delete(sid);
            const prefix = `${sid}:`;
            for (const key of mirrored) {
              if (key.startsWith(prefix)) mirrored.delete(key);
            }
          }
          return;
        }
        if (e?.type === "session.compacted") {
          if (!sid) return;
          const result = await client.session.messages({ path: { id: sid } });
          const messages = result.data ?? [];
          for (let i = messages.length - 1; i >= 0; i--) {
            const entry = messages[i];
            if ((entry.info as { summary?: boolean } | undefined)?.summary !== true) continue;
            const text = textFromParts(entry.parts);
            if (text.trim()) write(sid, text);
            return;
          }
          return;
        }
        if (e?.type === "message.part.updated") {
          if (!sid) return;
          const part = e.properties?.part;
          if (!part || part.type !== "text" || part.time?.end === undefined) return;
          if (!part.text?.trim()) return;
          const key = `${sid}:part:${part.id}`;
          if (mirrored.has(key)) return;
          mirrored.add(key);
          const appended = appendTurn(read(sid), "assistant", part.text);
          const enforced = enforceBudget(appended, budget);
          write(sid, enforced.content);
          if (enforced.nudge) console.info(`[clm-context] ${enforced.nudge}`);
        }
      } catch (err) {
        console.error("[clm-context] event handler failed", err);
      }
    },

    tool: {
      context_edit: tool({
        description:
          "Read or rewrite this session's CLM live-context file. action=read returns the current file. " +
          "action=replace validates the full new content and, if accepted, overwrites the file. " +
          "An edit is accepted only if it fits the token budget or strictly shrinks the file; otherwise it is rejected with a one-line reason.",
        args: {
          action: tool.schema.enum(["read", "replace"]),
          content: tool.schema
            .string()
            .optional()
            .describe("Full new file content (required when action=replace)"),
        },
        execute: async (args, ctx) => {
          try {
            const sessionID = ctx.sessionID;
            const current = read(sessionID);
            if (args.action === "read") {
              return current.trim() ? current : "(live context is empty)";
            }
            if (typeof args.content !== "string") {
              return "context_edit: rejected — action=replace requires content";
            }
            const decision = evaluateEdit(current, args.content, budget);
            if (decision.accepted) write(sessionID, args.content);
            return decision.receipt;
          } catch (err) {
            console.error("[clm-context] context_edit failed", err);
            return "context_edit: rejected — internal error (see logs)";
          }
        },
      }),
    },
  };
};
