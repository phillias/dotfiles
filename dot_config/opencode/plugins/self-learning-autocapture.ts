import type { Plugin } from "@opencode-ai/plugin";
import { mkdirSync, appendFileSync, readFileSync, writeFileSync, statSync, existsSync } from "fs";
import { join } from "path";
import { homedir } from "os";

/**
 * self-learning-autocapture — automatic golden-path instrumentation + skill feedback loop.
 *
 * Watches sessions for hard-won wins and explicit "make this a skill" requests,
 * then writes TSV harvest cues to ~/.local/state/opencode-selflearning/cues.tsv.
 * The agent consumes the cues at session start per the global AGENTS.md
 * instruction: process each cue (harvest a skill or route to axi-memory), then
 * append to processed.tsv and truncate cues.tsv. Deterministic detection only —
 * zero LLM cost; the LLM does the actual harvesting.
 *
 * Flywheel feedback loop (graph-free adaptation of the flywheel's
 * apply→track→detect→adjust cycle):
 * - Apply: every `skill` tool load is recorded (skill_applications.tsv) and
 *   aggregated into skill_stats.tsv.
 * - Track/Detect: negative signals (skill wrong/outdated/stale) are matched by
 *   regex in chat messages and recorded (skill_feedback.tsv), fidelity-gated
 *   on a known skill name appearing in the message.
 * - Adjust: at session.idle the plugin pre-aggregates counters into a digest
 *   (skills_review.tsv, ≤8 lines, EMPTY when nothing needs review) the agent
 *   reads at next session start. The digest only SUGGESTS review — demotion is
 *   always user-approved, never plugin-deleted.
 * - Re-promotion: retired skills (agent appends <skill>\t<retiredTs> to
 *   retired.tsv) loaded again after retirement surface as re-promotion
 *   candidates — manual, reversible (flywheel reversibility rule).
 *
 * All state paths derive from homedir() — portable across machines; never
 * hardcode /home/<user>. All fields are sanitized (control chars stripped,
 * truncated) before any TSV write — raw newlines in detail fields have broken
 * mem parsing historically.
 *
 * State files (all under ~/.local/state/opencode-selflearning/):
 *   cues.tsv                 <ts>\t<kind>\t<sessionID>\t<detail>   kinds: explicit | hard-win | session
 *   skill_applications.tsv   <ts>\t<skill>\t<sessionID>
 *   skill_feedback.tsv       <ts>\t<skill>\t<sessionID>\t<detail>
 *   skill_stats.tsv          <skill>\t<loads>\t<fails>\t<lastLoadTs>\t<lastFlagTs>\t<failsAtFlag>
 *   skills_review.tsv        <skill>\t<loads>\t<fails>\t<idleAgo>\t<reason>  reasons: fail-signals | cold | re-promotion-candidate
 *   retired.tsv              <skill>\t<retiredTs>  (agent-written; plugin reads for re-promotion)
 *   review-decisions.tsv     (agent-written audit trail; plugin never writes)
 */

const STATE_DIR = join(homedir(), ".local", "state", "opencode-selflearning");
const CUES_FILE = join(STATE_DIR, "cues.tsv");
const APPLICATIONS_FILE = join(STATE_DIR, "skill_applications.tsv");
const FEEDBACK_FILE = join(STATE_DIR, "skill_feedback.tsv");
const STATS_FILE = join(STATE_DIR, "skill_stats.tsv");
const REVIEW_FILE = join(STATE_DIR, "skills_review.tsv");
const RETIRED_FILE = join(STATE_DIR, "retired.tsv");
const ROTATE_BYTES = 900_000;
const ROTATE_KEEP = 1000;
const SESSION_CUE_MIN_TOOL_CALLS = 40;

// ── Flywheel thresholds (flag ≠ act — digest only suggests review) ───────────
const MIN_FAILS_TO_FLAG = 2; // ≥2 fail signals → surface for review
const STALE_MS = 60 * 24 * 3600 * 1000; // 60d without a load after ≥1 load → cold
const COOLDOWN_MS = 14 * 24 * 3600 * 1000; // don't re-flag for 14d unless new evidence
const DIGEST_MAX_LINES = 8; // hard token bound on the session-start read
const REPROMOTE_MIN_LOADS = 2; // retired skill loaded ≥2× post-retirement → candidate

type CueKind = "explicit" | "hard-win" | "session";

interface SessionState {
  cues: Set<CueKind>;
  toolCalls: number;
}

interface SkillStat {
  loads: number;
  fails: number;
  lastLoadTs: number;
  lastFlagTs: number;
  failsAtFlag: number;
}

const EXPLICIT_RE =
  /\b(save this as a skill|make a skill for this|create a skill for this|add this as a skill|don'?t make me re-explain|never make me re-explain|remember this|remember that|save this|keep this|harvest this)\b/i;

const HARD_WIN_RE =
  /\b(after \d+ (attempts|tries)|finally (worked|fixed|passed|succeeded|got it)|what finally worked|root cause was|the fix was|the trick was|eventually (worked|passed|succeeded|fixed))\b/i;

// Conservative negative-signal regexes. False negatives are free; false
// positives cost review tokens — so this stays narrow.
const SKILL_FAIL_RE =
  /\b(skill .*(was|is|turned out|proved) (wrong|incorrect|outdated|stale)|the skill (says|said|claims|claimed) .* but (actually|really|in reality)|skill (didn'?t|doesn'?t|failed to) (work|apply|fit|match))\b/i;

// ── Sanitization (all TSV fields — newlines/tabs have broken mem parsing) ────
function sanitize(v: unknown, maxLen: number): string {
  return String(v ?? "")
    .replace(/[\u0000-\u001F\u007F]+/g, " ") // control chars → space
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maxLen);
}

function appendRotated(file: string, line: string): void {
  try {
    mkdirSync(STATE_DIR, { recursive: true });
    appendFileSync(file, line);
    try {
      if (statSync(file).size > ROTATE_BYTES) {
        const tail = readFileSync(file, "utf-8").split("\n").slice(-ROTATE_KEEP).join("\n");
        writeFileSync(file, tail);
      }
    } catch {
      // rotation best-effort
    }
  } catch {
    // never throw — instrumentation must not break sessions
  }
}

// ── Skill stats (in-memory aggregate; persisted at session.idle) ─────────────
const skillStats = new Map<string, SkillStat>();

function loadStats(): void {
  try {
    if (!existsSync(STATS_FILE)) return;
    for (const line of readFileSync(STATS_FILE, "utf-8").split("\n")) {
      if (!line) continue;
      const [skill, loads, fails, lastLoadTs, lastFlagTs, failsAtFlag] = line.split("\t");
      if (!skill) continue;
      skillStats.set(skill, {
        loads: Number(loads) || 0,
        fails: Number(fails) || 0,
        lastLoadTs: Number(lastLoadTs) || 0,
        lastFlagTs: Number(lastFlagTs) || 0,
        failsAtFlag: Number(failsAtFlag) || 0,
      });
    }
  } catch {
    // best-effort
  }
}

function flushStats(): void {
  try {
    mkdirSync(STATE_DIR, { recursive: true });
    const lines = [...skillStats.entries()]
      .map(([skill, st]) => `${skill}\t${st.loads}\t${st.fails}\t${st.lastLoadTs}\t${st.lastFlagTs}\t${st.failsAtFlag}`)
      .join("\n");
    writeFileSync(STATS_FILE, lines + (lines ? "\n" : ""));
  } catch {
    // never throw
  }
}

function bumpSkillLoad(skill: string, sessionID: string): void {
  const name = sanitize(skill, 100);
  if (!name) return;
  const st = skillStats.get(name) ?? { loads: 0, fails: 0, lastLoadTs: 0, lastFlagTs: 0, failsAtFlag: 0 };
  st.loads += 1;
  st.lastLoadTs = Date.now();
  skillStats.set(name, st);
  appendRotated(APPLICATIONS_FILE, `${new Date().toISOString()}\t${name}\t${sanitize(sessionID, 100)}\n`);
}

function bumpSkillFail(skill: string, sessionID: string, detail: string): void {
  const name = sanitize(skill, 100);
  if (!name || name === "<unknown>") return; // unattributed evidence only, no stats bump
  const st = skillStats.get(name);
  if (!st) return; // fidelity gate: only count fails for skills we've seen loaded
  st.fails += 1;
  appendRotated(FEEDBACK_FILE, `${new Date().toISOString()}\t${name}\t${sanitize(sessionID, 100)}\t${sanitize(detail, 200)}\n`);
}

/** Return a known skill name mentioned in the text, or "<unknown>" if the word "skill" appears without attribution. */
function knownSkillIn(text: string): string | null {
  const lower = text.toLowerCase();
  for (const name of skillStats.keys()) {
    if (name.length >= 3 && lower.includes(name.toLowerCase())) return name;
  }
  return /\bskill\b/i.test(text) ? "<unknown>" : null;
}

// ── Review digest (pre-aggregated; agent reads at next session start) ────────
function ageAgo(ts: number): string {
  const s = Math.floor((Date.now() - ts) / 1000);
  if (s < 60) return `${s}s`;
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  if (s < 86400) return `${Math.floor(s / 3600)}h`;
  return `${Math.floor(s / 86400)}d`;
}

function readRetired(): Map<string, number> {
  const retired = new Map<string, number>();
  try {
    if (!existsSync(RETIRED_FILE)) return retired;
    for (const line of readFileSync(RETIRED_FILE, "utf-8").split("\n")) {
      if (!line) continue;
      const [skill, ts] = line.split("\t");
      if (skill) retired.set(skill.trim(), Number(ts) || 0);
    }
  } catch {
    // best-effort
  }
  return retired;
}

function countLoadsAfter(skill: string, afterTs: number): number {
  try {
    if (!existsSync(APPLICATIONS_FILE)) return 0;
    let n = 0;
    for (const line of readFileSync(APPLICATIONS_FILE, "utf-8").split("\n")) {
      if (!line) continue;
      const [ts, name] = line.split("\t");
      if (name === skill && Date.parse(ts) > afterTs) n++;
    }
    return n;
  } catch {
    return 0;
  }
}

function regenerateReviewDigest(): void {
  try {
    const now = Date.now();
    const lines: string[] = [];
    const retired = readRetired();

    for (const [skill, st] of skillStats) {
      if (retired.has(skill)) continue; // retired skills handled by re-promotion path below
      const cooldownPassed = now - st.lastFlagTs > COOLDOWN_MS;
      const newEvidence = st.fails > st.failsAtFlag;
      if (st.fails >= MIN_FAILS_TO_FLAG && (cooldownPassed || newEvidence)) {
        lines.push(`${skill}\t${st.loads}\t${st.fails}\t${ageAgo(st.lastLoadTs)}\tfail-signals`);
        st.lastFlagTs = now;
        st.failsAtFlag = st.fails;
      } else if (st.loads >= 1 && st.lastLoadTs > 0 && now - st.lastLoadTs > STALE_MS && cooldownPassed) {
        lines.push(`${skill}\t${st.loads}\t${st.fails}\t${ageAgo(st.lastLoadTs)}\tcold`);
        st.lastFlagTs = now;
        st.failsAtFlag = st.fails;
      }
    }

    // Re-promotion candidates: retired skills loaded again after retirement
    for (const [skill, retiredTs] of retired) {
      const n = countLoadsAfter(skill, retiredTs);
      if (n >= REPROMOTE_MIN_LOADS) {
        lines.push(`${skill}\t${n}\t-\t${ageAgo(retiredTs)}\tre-promotion-candidate`);
      }
    }

    mkdirSync(STATE_DIR, { recursive: true });
    writeFileSync(REVIEW_FILE, lines.slice(0, DIGEST_MAX_LINES).join("\n") + (lines.length ? "\n" : ""));
    flushStats();
  } catch {
    // never throw
  }
}

function writeCue(kind: CueKind, sessionID: string, detail: string): void {
  appendRotated(CUES_FILE, `${new Date().toISOString()}\t${kind}\t${sanitize(sessionID, 100)}\t${sanitize(detail, 200)}\n`);
}

export const SelfLearningAutocapturePlugin: Plugin = async () => {
  loadStats();
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

        // Negative-signal detection (flywheel "detect" step), fidelity-gated:
        // only count fails against skills we've actually seen loaded.
        if (SKILL_FAIL_RE.test(text)) {
          const known = knownSkillIn(text);
          if (known && known !== "<unknown>") {
            bumpSkillFail(known, input.sessionID, text);
          } else {
            // Unattributed — preserve evidence only, never bump stats.
            appendRotated(FEEDBACK_FILE, `${new Date().toISOString()}\t<unknown>\t${sanitize(input.sessionID, 100)}\t${sanitize(text, 200)}\n`);
          }
        }
      } catch {
        // never throw
      }
    },

    "tool.execute.after": async (input: {
      tool: string;
      sessionID: string;
      callID: string;
      args: any;
    }) => {
      try {
        const state = sessionCue(input.sessionID) ?? { cues: new Set<CueKind>(), toolCalls: 0 };
        state.toolCalls += 1;
        sessions.set(input.sessionID, state);

        // Flywheel "apply" step: record every skill tool load.
        if (input.tool === "skill" && typeof input.args?.name === "string") {
          bumpSkillLoad(input.args.name, input.sessionID);
        }
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
        if (state) {
          if (state.toolCalls >= SESSION_CUE_MIN_TOOL_CALLS) {
            cueOnce(state, "session", sessionID, `high-activity session (${state.toolCalls} tool calls) — review for harvest candidates`);
          }
          sessions.delete(sessionID);
        }
        // Flywheel "adjust" step: pre-aggregate stats + rewrite digest for
        // the next session start. Runs regardless of per-session state.
        regenerateReviewDigest();
      } catch {
        // never throw
      }
    },
  };
};
