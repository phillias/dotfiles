import type { Plugin } from "@opencode-ai/plugin";
import { mkdirSync, appendFileSync, writeFileSync, readFileSync, existsSync, statSync } from "fs";
import { join } from "path";
import { homedir } from "os";

// ── State tree paths ──────────────────────────────────────────────────
const STATE_DIR = join(homedir(), ".local", "state", "opencode-fleet");
const WAKE_LOG = join(STATE_DIR, "wake.log");
const STATE_JSON = join(STATE_DIR, "state.json");
const DIGEST_TXT = join(STATE_DIR, "digest.txt");

// ── Init on plugin load ────────────────────────────────────────────────
mkdirSync(STATE_DIR, { recursive: true });
if (!existsSync(STATE_JSON)) {
  writeFileSync(STATE_JSON, JSON.stringify({ tasks: {}, updated_at: 0 }, null, 2));
}
if (!existsSync(WAKE_LOG)) writeFileSync(WAKE_LOG, "");
if (!existsSync(DIGEST_TXT)) writeFileSync(DIGEST_TXT, "");

// ── Types ──────────────────────────────────────────────────────────────
type Status = "pending" | "running" | "completed" | "failed" | "cancelled" | "interrupted" | "resulted";

interface TaskState {
  task_id?: string;
  session_id: string;
  status: Status;
  type: string;
  digest: string;
  updated_at: number;
  agent?: string;
}

interface StateFile {
  tasks: Record<string, TaskState>;
  updated_at: number;
}

// ── State I/O ─────────────────────────────────────────────────────────
function loadState(): StateFile {
  try {
    const raw = readFileSync(STATE_JSON, "utf-8");
    const parsed = JSON.parse(raw) as StateFile;
    if (!parsed.tasks) parsed.tasks = {};
    return parsed;
  } catch {
    return { tasks: {}, updated_at: 0 };
  }
}

function saveState(state: StateFile): void {
  state.updated_at = Date.now();
  writeFileSync(STATE_JSON, JSON.stringify(state, null, 2));

  // Regenerate digest.txt as TSV: key<TAB>status<TAB>type<TAB>digest<TAB>age
  const now = Date.now();
  const lines: string[] = [];
  for (const [key, t] of Object.entries(state.tasks)) {
    const ageSec = Math.floor((now - t.updated_at) / 1000);
    const ageStr = ageSec < 60 ? `${ageSec}s`
      : ageSec < 3600 ? `${Math.floor(ageSec / 60)}m`
      : `${Math.floor(ageSec / 3600)}h`;
    lines.push(`${key}\t${t.status}\t${t.type}\t${t.digest}\t${ageStr} ago`);
  }
  writeFileSync(DIGEST_TXT, lines.join("\n") + (lines.length ? "\n" : ""));
}

function appendWake(type: string, sessionID: string, digest: string): void {
  const ts = new Date().toISOString();
  const line = `${ts}\t${type}\t${sessionID}\t${digest}\n`;
  try {
    appendFileSync(WAKE_LOG, line);
    // Rotate wake.log if >1MB: keep last 1000 lines
    const stat = statSync(WAKE_LOG);
    if (stat.size > 1_000_000) {
      const content = readFileSync(WAKE_LOG, "utf-8").split("\n").slice(-1000).join("\n");
      writeFileSync(WAKE_LOG, content);
    }
  } catch (err) {
    console.error("[fleet-state-writer] appendWake error:", err);
  }
}

function updateTask(
  key: string,
  partial: { task_id?: string; session_id: string; status?: Status; type: string; digest: string; agent?: string },
): void {
  try {
    const state = loadState();
    const t: TaskState = {
      task_id: partial.task_id,
      session_id: partial.session_id,
      status: partial.status ?? "running",
      type: partial.type,
      digest: partial.digest,
      updated_at: Date.now(),
      agent: partial.agent,
    };
    state.tasks[key] = t;
    saveState(state);
    appendWake(t.type, t.session_id, t.digest);
  } catch (err) {
    console.error("[fleet-state-writer] updateTask error:", err);
  }
}

// ── Background-task header patterns mined from chat.message text ──────
const BG_HEADERS: Array<{ re: RegExp; status: Status }> = [
  { re: /\[BACKGROUND TASK RESULT READY\]/i, status: "resulted" },
  { re: /\[BACKGROUND TASK COMPLETED\]/i, status: "completed" },
  { re: /\[BACKGROUND TASK CANCELLED\]/i, status: "cancelled" },
  { re: /\[BACKGROUND TASK INTERRUPTED\]/i, status: "interrupted" },
  { re: /\[BACKGROUND TASK ERROR\]/i, status: "failed" },
];

// ── Plugin ────────────────────────────────────────────────────────────
export const FleetStateWriterPlugin: Plugin = async () => {
  return {
    // Catch all session.* lifecycle events. session.idle = a session went idle;
    // for subagent sessions, idle ≈ finished.
    event: async (input: { event: { type: string; properties?: any } }) => {
      try {
        const ev = input.event;
        const t = ev.type;
        if (!t.startsWith("session.")) return;
        const props = ev.properties ?? {};
        const sessionID: string = props.sessionID ?? props.id ?? "";
        if (!sessionID) return;

        const status: Status =
          t === "session.idle" ? "completed" :
          t === "session.error" ? "failed" :
          t === "session.deleted" ? "cancelled" :
          t === "session.compacted" ? "completed" :
          t === "session.created" ? "running" :
          "running";

        const digest = `[${t}] session=${sessionID}${props.error ? ` err=${String(props.error).slice(0, 80)}` : ""}`;
        updateTask(sessionID, {
          session_id: sessionID,
          status,
          type: t,
          digest,
          agent: props.agent as string | undefined,
        });
      } catch (err) {
        console.error("[fleet-state-writer] event handler error:", err);
      }
    },

    // Mine chat messages for [BACKGROUND TASK *] headers — survives compaction
    // because we record the event to disk before any compaction prompt runs.
    "chat.message": async (
      input: { sessionID: string },
      output: { parts: Array<{ text?: string }> },
    ) => {
      try {
        const text = output.parts.map((p) => p.text ?? "").join(" ");
        let hit: { re: RegExp; status: Status } | undefined;
        for (const h of BG_HEADERS) {
          if (h.re.test(text)) { hit = h; break; }
        }
        if (!hit) return;

        // Extract any bg_... or ses_... identifier from the text
        const idMatch = text.match(/\b(bg_[a-zA-Z0-9]+|ses_[a-zA-Z0-9]+)\b/);
        const id = idMatch?.[0] ?? input.sessionID;

        // Pull the matching line as the digest (first 120 chars)
        const lineMatch = text.split("\n").find((l) => hit!.re.test(l)) ?? "";
        const digest = lineMatch.slice(0, 120);

        updateTask(id, {
          task_id: id.startsWith("bg_") ? id : undefined,
          session_id: id,
          status: hit.status,
          type: "chat.message.bg",
          digest,
        });
      } catch (err) {
        console.error("[fleet-state-writer] chat.message handler error:", err);
      }
    },

    // When Sisyphus calls background_output(task_id=bg_...) to fetch results,
    // record that the task's results were retrieved. Useful for distinguishing
    // "completed but not yet inspected" from "completed and acted-on".
    "tool.execute.after": async (input: {
      tool: string;
      sessionID: string;
      callID: string;
      args: any;
    }) => {
      try {
        if (input.tool !== "background_output") return;
        const taskID: string | undefined = input.args?.task_id;
        if (!taskID) return;
        updateTask(taskID, {
          task_id: taskID,
          session_id: input.sessionID,
          status: "resulted",
          type: "tool.background_output",
          digest: `Sisyphus fetched results for ${taskID}`,
        });
      } catch (err) {
        console.error("[fleet-state-writer] tool.execute.after handler error:", err);
      }
    },
  };
};