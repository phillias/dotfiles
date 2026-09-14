import type { Plugin } from "@opencode-ai/plugin";
import { mkdirSync, readFileSync, writeFileSync, readdirSync, statSync, unlinkSync } from "fs";
import { join } from "path";
import { homedir } from "os";

// shunt-digest — AXI shunt pilot (bash tool, tool-call-granularity delegation)
//
// When a bash tool result exceeds the pass-through gate, the full text is
// stashed durably and the result the session sees is replaced with a cheap
// worker-model digest (primary opencode-zen/claude-haiku-4-5, fallback
// nemotron-3-ultra-free, mechanical head/tail digest if no key or both fail).
// Every handler is fully try/catch-wrapped: a failing hook must NEVER abort
// the tool call or the remaining hook chain (opencode core does not isolate
// hook errors; a throw becomes a defect that kills the call).
//
// Env knobs (all optional):
//   SHUNT_MAX_LINES            pass-through gate lines   (default 350)
//   SHUNT_MAX_BYTES            pass-through gate bytes   (default 50000)
//   SHUNT_MAX_STASH_BYTES       max bytes fed to digest    (default 262144)
//   SHUNT_MAX_OUTPUT_TOKENS     chat.params maxOutputTokens (unset = no cap)
//   SHUNT_TERSE=1               prepend terse-output directive to system prompt
//   SHUNT_DIGEST_BASE_URL       chat-completions base URL (default: zen gateway)
//   SHUNT_DIGEST_API_KEY        Bearer key (default: resolved from local opencode config)
//   SHUNT_DIGEST_MODEL          primary digest model      (default claude-haiku-4-5)
//   SHUNT_DIGEST_MODEL_FALLBACK fallback digest model    (default nemotron-3-ultra-free)
//   SHUNT_STASH_DIR             stash dir (default ~/.local/state/opencode-shunt)
//
// Health/validity: a load-time self-test result and running counters
// (shunted, llm_ok, llm_fail, mech_fallback, rejected_env, last_error) are
// written to ~/.local/state/opencode-shunt/health.json after each shunt and
// at plugin load. Per-call post-conditions (digest size, pointer presence,
// stash existence) roll back to the original output on any failure — a call
// is never half-shunted.

const STASH_DIR = process.env.SHUNT_STASH_DIR ?? join(homedir(), ".local", "state", "opencode-shunt");
const SHUNT_MARKER = "shunted.";

// ── Health snapshot (validity counters, load self-test) ──────────────
type Health = {
  loaded_at: string;
  self_test: "pass" | "fail" | "skipped";
  shunted: number;
  llm_ok: number;
  llm_fail: number;
  mech_fallback: number;
  rolled_back: number;
  rejected_env: string[];
  last_error: string | null;
};
const HEALTH_FILE = join(STASH_DIR, "health.json");
let healthState: Health | null = null;

function health(): Health {
  if (healthState) return healthState;
  healthState = {
    loaded_at: new Date().toISOString(),
    self_test: "skipped",
    shunted: 0,
    llm_ok: 0,
    llm_fail: 0,
    mech_fallback: 0,
    rolled_back: 0,
    rejected_env: [],
    last_error: null,
  } as Health;
  try {
    const prev = JSON.parse(readFileSync(HEALTH_FILE, "utf-8")) as Partial<Health>;
    if (prev && typeof prev === "object") {
      // Carry counters across reloads; refresh load-time fields.
      healthState.shunted = Number(prev.shunted) || 0;
      healthState.llm_ok = Number(prev.llm_ok) || 0;
      healthState.llm_fail = Number(prev.llm_fail) || 0;
      healthState.mech_fallback = Number(prev.mech_fallback) || 0;
      healthState.rolled_back = Number(prev.rolled_back) || 0;
    }
  } catch {}
  return healthState;
}

function saveHealth(): void {
  try {
    mkdirSync(STASH_DIR, { recursive: true });
    writeFileSync(HEALTH_FILE, JSON.stringify(health(), null, 2));
  } catch {}
}

function noteError(e: unknown): void {
  try {
    const h = health();
    h.last_error = String((e as Error)?.message ?? e).slice(0, 300);
    saveHealth();
  } catch {}
}


function envNum(name: string, def: number): number {
  const raw = process.env[name];
  if (raw === undefined || raw === "") return def;
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) {
    health().rejected_env.push(`${name}=${JSON.stringify(raw)} -> ${def}`);
    return def;
  }
  return n;
}

// Env parsing hardening: an invalid numeric env would yield NaN, and every
// NaN comparison is false, silently inverting the pass-through gate (shunting
// everything). Invalid values fall back to defaults and are recorded in the
// health snapshot.
const MAX_LINES = envNum("SHUNT_MAX_LINES", 350);
const MAX_BYTES = envNum("SHUNT_MAX_BYTES", 50000);
const MAX_STASH_BYTES = envNum("SHUNT_MAX_STASH_BYTES", 262144);
const DIGEST_CAP_BYTES = 4096;
const TERSE = process.env.SHUNT_TERSE === "1";

const MAX_OUTPUT_TOKENS = (() => {
  const n = Number(process.env.SHUNT_MAX_OUTPUT_TOKENS);
  return Number.isFinite(n) && n > 0 ? n : undefined;
})();

// Provider auth is resolved at runtime from opencode's own config (provider
// "opencode-zen"): baseURL, apiKey ({file:...} template resolved locally), and
// headers come from the machine-local install, never from this repo. Env
// overrides: SHUNT_DIGEST_BASE_URL / SHUNT_DIGEST_API_KEY / SHUNT_DIGEST_API_KEY_FILE.
const DIGEST_MODEL = process.env.SHUNT_DIGEST_MODEL ?? "claude-haiku-4-5";
const DIGEST_MODEL_FALLBACK = process.env.SHUNT_DIGEST_MODEL_FALLBACK ?? "nemotron-3-ultra-free";
const DIGEST_TIMEOUT_MS = 20000;

function readOpencodeConfigText(): string | null {
  const env = process.env.OPENCODE_CONFIG;
  const cands = [
    ...(env ? [env] : []),
    join(homedir(), ".config", "opencode", "opencode.json"),
    join(homedir(), ".config", "opencode", "opencode.jsonc"),
  ];
  for (const c of cands) {
    try {
      const t = readFileSync(c, "utf-8");
      if (t) return t;
    } catch {}
  }
  return null;
}

function stripJsonComments(s: string): string {
  // comment stripper good enough for configOC style files; tolerates // and /* */
  return s
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/[^\n"]*(?=\n|$)/g, "$1");
}

function parseConfigJson(t: string | null): any {
  if (!t) return null;
  try {
    return JSON.parse(t);
  } catch {}
  try {
    return JSON.parse(stripJsonComments(t));
  } catch {}
  return null;
}

function resolveFileTemplate(v: string): string | null {
  // apiKey value may be "{file:~/path}" per opencode config
  const m = /^\{file:(.+)\}$/.exec(v);
  if (!m) return v || null;
  const p = m[1].startsWith("~/") ? join(homedir(), m[1].slice(2)) : m[1];
  try {
    const k = readFileSync(p, "utf-8");
    const t = k.trim();
    return t || null;
  } catch {
    return null;
  }
}

type ZenAuth = { baseUrl: string; apiKey: string | null; headers: Record<string, string> };

let zenAuthCache: ZenAuth | null | undefined;
function zenAuth(): ZenAuth | null {
  if (zenAuthCache !== undefined) return zenAuthCache;
  const finish = (z: ZenAuth | null) => {
    zenAuthCache = z;
    return z;
  };
  const envKey = process.env.SHUNT_DIGEST_API_KEY?.trim() || null;
  const envUrl = process.env.SHUNT_DIGEST_BASE_URL?.trim() || null;
  if (envUrl && envKey) return finish({ baseUrl: envUrl, apiKey: envKey, headers: {} });

  try {
    const cfg = parseConfigJson(readOpencodeConfigText());
    const block = cfg?.provider?.["opencode-zen"];
    const opts = block?.options ?? {};
    const url = envUrl ?? (typeof opts.baseURL === "string" ? opts.baseURL : null);
    let key: string | null = envKey;
    if (!key && typeof opts.apiKey === "string") key = resolveFileTemplate(opts.apiKey);
    if (!url || !key) return finish(null);
    const headers: Record<string, string> = {};
    const raw = opts.headers ?? {};
    if (raw && typeof raw === "object") {
      for (const [k, v] of Object.entries(raw)) {
        if (typeof v === "string") headers[k] = v;
      }
    }
    return finish({ baseUrl: url, apiKey: key, headers });
  } catch {
    return finish(null);
  }
}

// ── Lazy stash dir + backup pruning (best-effort) ────────────────────
let stashReady = false;
function ensureStash(): string {
  mkdirSync(STASH_DIR, { recursive: true });
  if (!stashReady) {
    stashReady = true;
    try {
      const TTL = 7 * 24 * 3600 * 1000;
      for (const f of readdirSync(STASH_DIR)) {
        try {
          if (!f.startsWith("stash-")) continue;
          if (Date.now() - statSync(join(STASH_DIR, f)).mtimeMs > TTL) unlinkSync(join(STASH_DIR, f));
        } catch {}
      }
    } catch {}
  }
  return STASH_DIR;
}

function stashName(callID: string) {
  return join(ensureStash(), `stash-${Date.now()}-${String(callID).replace(/[^a-zA-Z0-9._-]/g, "_")}.txt`);
}

type DigestResult = { digest: string; stash: string; bytes: number; lines: number };

function mechanicalDigest(full: string, stash: string): string {
  const ls = full.split("\n");
  const lines = ls.length;
  const cap = 2000;
  const take = (s: string) => (s.length <= cap ? s : s.slice(0, cap) + `...(+${s.length - cap}B truncated)`);
  const oversizedLines = lines > MAX_LINES;
  const head = take(ls.slice(0, 30).join("\n"));
  const tail = oversizedLines ? take(ls.slice(-15).join("\n")) : undefined;
  return (
    `${full.length}B ${lines}L shunted. full: ${stash}\n` +
    (head || "(empty output)") +
    (tail ? `\n...(middle omitted)\n${tail}` : "")
  );
}

// Primary cheap-lane digest with bounded mechanical fallback.
async function shunt(full: string, callID: string): Promise<DigestResult> {
  const stash = stashName(callID);
  writeFileSync(stash, full, "utf-8");
  const lines = full.split("\n").length;
  const mech = mechanicalDigest(full, stash);
  const done = (digest: string, lane: "llm" | "mech"): DigestResult => {
    const h = health();
    if (lane === "llm") h.llm_ok += 1;
    else h.mech_fallback += 1;
    h.shunted += 1;
    saveHealth();
    return { digest, stash, bytes: full.length, lines };
  };
  let sawLlmAttempt = false;

  const auth = zenAuth();
  if (!auth) return done(mech, "mech");

  const headers: Record<string, string> = {
    "content-type": "application/json",
    authorization: `Bearer ${auth.apiKey}`,
    ...auth.headers,
  };
  const sys =
    "You condense large terminal tool output for an agent's context window. Return ONLY a terse plain-text digest: main result or exit signal, key values, errors, counts. No preamble, under 120 words.";

  for (const model of [DIGEST_MODEL, DIGEST_MODEL_FALLBACK]) {
    sawLlmAttempt = true;
    try {
      const res = await fetch(`${auth.baseUrl}/chat/completions`, {
        method: "POST",
        headers,
        body: JSON.stringify({
          model,
          max_tokens: 600,
          messages: [
            { role: "system", content: sys },
            { role: "user", content: full.slice(0, MAX_STASH_BYTES) },
          ],
        }),
        signal: AbortSignal.timeout(DIGEST_TIMEOUT_MS),
      });
      if (!res.ok) continue;
      const j: any = await res.json();
      const out: string | undefined = j?.choices?.[0]?.message?.content;
      if (typeof out === "string" && out.trim().length > 0) {
        return done(`${full.length}B ${lines}L shunted. full: ${stash}\n${out.trim()}`, "llm");
      }
    } catch {
      /* try next lane, then mechanical */
    }
  }
  if (sawLlmAttempt) {
    health().llm_fail += 1;
    saveHealth();
  }
  return done(mech, "mech");
}

// Post-conditions for a valid shunt: bounded digest with a stash pointer,
// stash file present and non-empty. Any violation is a rollback, never a
// half-shunted call.
function shuntValid(digest: string, stash: string, original: string): string | null {
  if (digest.length > DIGEST_CAP_BYTES) return `digest too large: ${digest.length}B`;
  if (!digest.includes(stash)) return "digest missing stash pointer";
  try {
    if (statSync(stash).size <= 0) return "stash empty";
  } catch {
    return "stash missing";
  }
  if (digest.length >= original.length) return "digest not smaller than original";
  return null;
}

const REGISTERED_HOOKS: Record<string, unknown> = {
  "tool.execute.after": async (input: any, output: any) => {
    // Error isolation is mandatory: core does NOT isolate hook throws.
    try {
      if (input?.tool !== "bash" || !output?.output) return;
      const text = String(output.output);
      // Anti-recursion: never re-digest an already-shunted result.
      if (text.includes(SHUNT_MARKER) && text.length < DIGEST_CAP_BYTES) return;
      const lines = text.split("\n").length;
      if (lines <= MAX_LINES && text.length <= MAX_BYTES) return;

      const meta = output.metadata ?? {};
      let full = text;
      if (meta.truncated === true && typeof meta.outputPath === "string") {
        try {
          const spilled = readFileSync(meta.outputPath, "utf-8");
          if (spilled) full = spilled;
        } catch {}
      }

      const r = await shunt(full, String(input.callID ?? "x"));
      const bad = shuntValid(r.digest, r.stash, full);
      if (bad) {
        health().rolled_back += 1;
        health().last_error = `post-condition failed (${bad}) — original output preserved`;
        saveHealth();
        return;
      }
      output.output = r.digest;
      output.metadata = {
        ...meta,
        shunted: true,
        shunt: { stash: r.stash, bytes: r.bytes, lines: r.lines },
      };
    } catch (e) {
      noteError(e);
      /* swallow — never abort the tool call */
    }
  },

  "chat.params": async (input: any, output: any) => {
    try {
      if (MAX_OUTPUT_TOKENS !== undefined) output.maxOutputTokens = MAX_OUTPUT_TOKENS;
    } catch {}
  },

  "experimental.chat.system.transform": async (input: any, output: any) => {
    try {
      if (!TERSE) return;
      const directive = "Brevity contract: answer concisely, no restating, no filler.";
      output.system = output.system && Array.isArray(output.system) ? [directive, ...output.system] : [directive];
    } catch {}
  },
};

export const ShuntPlugin: Plugin = (async () => REGISTERED_HOOKS) satisfies Plugin;

// ── Load-time self-test (validity gate; runs once per process) ────────
// Catches the upstream shunt's failure class at startup: a hook key typo
// registers nothing, and a broken gate or unwritable stash silently no-ops.
// Writes the verdict to health.json; a failing self-test never throws at load.
let selfTestRan = false;
function runSelfTest(): void {
  if (selfTestRan) return;
  selfTestRan = true;
  const h = health();
  const fail = (why: string) => {
    h.self_test = "fail";
    h.last_error = `self-test: ${why}`;
    saveHealth();
  };
  try {
    for (const k of ["tool.execute.after", "chat.params", "experimental.chat.system.transform"]) {
      if (!(k in REGISTERED_HOOKS)) return fail(`hook missing: ${k}`);
    }
    if (MAX_LINES <= 0 || MAX_BYTES <= 0) return fail("gate constants invalid");
    try {
      mkdirSync(STASH_DIR, { recursive: true });
      const probe = join(STASH_DIR, ".selftest");
      writeFileSync(probe, String(Date.now()));
      if (statSync(probe).size <= 0) return fail("stash not writable");
      unlinkSync(probe);
    } catch (e) {
      return fail(`stash write failed: ${String((e as Error)?.message ?? e)}`);
    }
    h.self_test = "pass";
    saveHealth();
  } catch (e) {
    fail(String((e as Error)?.message ?? e));
  }
}

// Fire the self-test off the load path so it never delays plugin startup.
setTimeout(runSelfTest, 0);
