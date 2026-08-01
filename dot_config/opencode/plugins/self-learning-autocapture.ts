import type { Plugin } from "@opencode-ai/plugin";
import { mkdirSync, appendFileSync, readFileSync, writeFileSync, statSync } from "fs";
import { join } from "path";
import { homedir } from "os";

/**
 * self-learning-autocapture — automatic golden-path instrumentation.
 *
 * Watches sessions for hard-won wins and explicit "make this a skill" requests,
 * then writes TSV harvest cues to ~/.local/state/opencode-selflearning/cues.tsv.
 * The agent consumes the cues at session start per the global AGENTS.md
 * instruction: process each cue (harvest a skill or route to axi-memory), then
 * append to processed.tsv and truncate cues.tsv. Deterministic detection only —
 * zero LLM cost; the LLM does the actual harvesting.
 *
 * Cue line: <ISO-ts>\t<kind>\t<sessionID>\t<detail>
 * kinds: explicit | hard-win | session
 */

const STATE_DIR = join(homedir(), ".local", "state", "opencode-selflearning");
const CUES_FILE = join(STATE_DIR, "cues.tsv");
const ROTATE_BYTES = 900_000;
const ROTATE_KEEP = 1000;
const SESSION_CUE_MIN_TOOL_CALLS = 40;

type CueKind = "explicit" | "hard-win" | "session";

interface SessionState {
  cues: Set<CueKind>;
  toolCalls: number;
}

const EXPLICIT_RE =
  /\b(save this as a skill|make a skill for this|create a skill for this|add this as a skill|don'?t make me re-explain|never make me re-explain|remember this|remember that|save this|keep this|harvest this)\b/i;

const HARD_WIN_RE =
  /\b(after \d+ (attempts|tries)|finally (worked|fixed|passed|succeeded|got it)|what finally worked|root cause was|the fix was|the trick was|eventually (worked|passed|succeeded|fixed))\b/i;

function writeCue(kind: CueKind, sessionID: string, detail: string): void {
  try {
    mkdirSync(STATE_DIR, { recursive: true });
    const clean = detail.replace(/[\t\n\r]+/g, " ").slice(0, 200);
    appendFileSync(CUES_FILE, `${new Date().toISOString()}\t${kind}\t${sessionID}\t${clean}\n`);
    try {
      if (statSync(CUES_FILE).size > ROTATE_BYTES) {
        const tail = readFileSync(CUES_FILE, "utf-8").split("\n").slice(-ROTATE_KEEP).join("\n");
        writeFileSync(CUES_FILE, tail);
      }
    } catch {
      // rotation best-effort
    }
  } catch {
    // never throw — instrumentation must not break sessions
  }
}

export const SelfLearningAutocapturePlugin: Plugin = async () => {
  const sessions = new Map<string, SessionState>();

  function sessionCue(sessionID: string): SessionState | undefined {
    return sessions.get(sessionID);
  }

  function cueOnce(state: SessionState, kind: CueKind, sessionID: string, detail: string): void {
    if (state.cues.has(kind)) return;
    state.cues.add(kind);
    writeCue(kind, sessionID, detail);
  }

  return {
    "chat.message": async (
      input: { sessionID: string },
      output: { message?: { role?: string }; parts: Array<{ type?: string; text?: string }> },
    ) => {
      try {
        const text = output.parts.map((p) => p.text ?? "").join(" ");
        if (!text) return;
        const role = output.message?.role ?? "";
        const state = sessionCue(input.sessionID) ?? { cues: new Set<CueKind>(), toolCalls: 0 };
        if (!sessions.has(input.sessionID)) sessions.set(input.sessionID, state);

        if ((role === "user" || role === "") && EXPLICIT_RE.test(text)) {
          cueOnce(state, "explicit", input.sessionID, text);
        }
        if (role === "assistant" && HARD_WIN_RE.test(text)) {
          cueOnce(state, "hard-win", input.sessionID, text);
        }
      } catch {
        // never throw
      }
    },

    "tool.execute.after": async (input: { sessionID: string }) => {
      try {
        const state = sessionCue(input.sessionID) ?? { cues: new Set<CueKind>(), toolCalls: 0 };
        state.toolCalls += 1;
        sessions.set(input.sessionID, state);
      } catch {
        // never throw
      }
    },

    event: async (input: { event: { type: string; properties?: any } }) => {
      try {
        const ev = input.event;
        if (ev.type !== "session.idle") return;
        const sessionID: string = ev.properties?.sessionID ?? ev.properties?.id ?? "";
        if (!sessionID) return;
        const state = sessions.get(sessionID);
        if (!state) return;
        if (state.toolCalls >= SESSION_CUE_MIN_TOOL_CALLS) {
          cueOnce(state, "session", sessionID, `high-activity session (${state.toolCalls} tool calls) — review for harvest candidates`);
        }
        sessions.delete(sessionID);
      } catch {
        // never throw
      }
    },
  };
};
