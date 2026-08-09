import type { Plugin } from "@opencode-ai/plugin";
import { tool } from "@opencode-ai/plugin";
import { readFileSync, writeFileSync, mkdirSync } from "fs";
import { homedir } from "os";
import { join } from "path";
import {
  type FallbackConfig,
  type ChainEntry,
  type ChainCfg,
  stripJsonc,
  entryModel,
  entrySettings,
  parseModel,
  classifyError,
  resolveChain,
  nextCandidate,
  remaining,
  primaryAvailable,
  annotationFor,
} from "../lib/opencode-runtime-fallback-core";

const CONFIG_PATH = join(homedir(), ".config", "opencode", "opencode-fallback.jsonc");
const STATE_DIR = join(homedir(), ".local", "state", "opencode-fleet");
const STATE_FILE = join(STATE_DIR, "fallback.json");

interface SessionState {
  agent?: string;
  activeModel?: string;
  chain: string[];
  index: number;
  attempts: number;
  history: Array<{ from: string; to: string; reason: string; at: number }>;
}

interface StateFile {
  sessions: Record<string, SessionState>;
  cooldowns: Record<string, number>;
  updated_at: number;
}

mkdirSync(STATE_DIR, { recursive: true });

let CONFIG: FallbackConfig | null = null;

function loadConfig(): FallbackConfig {
  if (CONFIG) return CONFIG;
  try {
    const raw = readFileSync(CONFIG_PATH, "utf-8");
    CONFIG = JSON.parse(stripJsonc(raw)) as FallbackConfig;
  } catch {
    CONFIG = {};
  }
  return CONFIG;
}

let STATE: StateFile = { sessions: {}, cooldowns: {}, updated_at: 0 };

function loadState(): void {
  try {
    const raw = readFileSync(STATE_FILE, "utf-8");
    STATE = JSON.parse(raw) as StateFile;
    if (!STATE.sessions) STATE.sessions = {};
    if (!STATE.cooldowns) STATE.cooldowns = {};
  } catch {
    STATE = { sessions: {}, cooldowns: {}, updated_at: 0 };
  }
}

function persist(): void {
  STATE.updated_at = Date.now();
  try { writeFileSync(STATE_FILE, JSON.stringify(STATE)); } catch { /* best-effort */ }
}

function now(): number {
  return Date.now();
}

function inCooldown(model: string): number {
  const until = STATE.cooldowns[model];
  if (!until) return 0;
  const left = Math.round((until - now()) / 1000);
  if (left <= 0) { delete STATE.cooldowns[model]; return 0; }
  return left;
}

function cool(model: string, seconds: number): void {
  STATE.cooldowns[model] = now() + seconds * 1000;
}

function ensureSession(sessionID: string, agent: string | undefined, model: string | undefined): SessionState {
  let s = STATE.sessions[sessionID];
  if (!s) {
    s = { chain: [], index: 0, attempts: 0, history: [] };
    STATE.sessions[sessionID] = s;
  }
  if (agent) s.agent = agent;
  if (model) s.activeModel = model;
  if (!s.chain.length) {
    s.chain = resolveChain(loadConfig(), agent).map(entryModel);
    s.index = Math.max(0, s.chain.indexOf(model ?? ""));
  }
  return s;
}

function sessionFor(sessionID: string): SessionState | undefined {
  return STATE.sessions[sessionID];
}

async function applyFallback(sessionID: string, reason: string): Promise<boolean> {
  const cfg = loadConfig();
  if (!cfg.enabled) return false;
  const s = sessionFor(sessionID);
  if (!s || !s.activeModel) return false;
  if (s.attempts >= (cfg.max_fallback_attempts ?? 15)) return true;

  cool(s.activeModel, cfg.cooldown_seconds ?? 60);
  const next = nextCandidate(s.chain, s.activeModel, inCooldown);
  const attempted = next === undefined;
  const from = s.activeModel;
  if (next) {
    s.activeModel = next;
    s.index = Math.max(0, s.chain.indexOf(next));
    s.attempts += 1;
  } else {
    s.attempts = cfg.max_fallback_attempts ?? 15;
  }
  s.history.push({ from, to: next ?? "exhausted", reason, at: now() });
  persist();
  return attempted;
}

function toonStatus(sessionID: string): string {
  const s = sessionFor(sessionID);
  const active = s?.activeModel ?? "unknown";
  const chain = s?.chain ?? [];
  const index = s?.index ?? 0;
  const cooldowns = Object.entries(STATE.cooldowns).map(([m, u]) => [m, Math.round((u - now()) / 1000)] as const)
    .filter(([, sec]) => sec > 0).sort((a, b) => a[1] - b[1]);
  const cd = cooldowns.length ? cooldowns.map(([m, sec]) => `${m}:${sec}s`).join(", ") : "none";
  if (!s || index === 0) {
    return `fallback:
  active: ${active}
  chain: healthy
  cooldown: ${cd}`;
  }
  return `fallback:
  active: ${active}
  remaining: ${remaining(chain, index)}
  cooldown: ${cd}`;
}

function entrySettingsFor(s: SessionState): { temperature?: number; maxOutputTokens?: number; options?: Record<string, unknown> } | undefined {
  const cfg = loadConfig();
  const ag: ChainCfg | undefined = s.agent ? cfg.agents?.[s.agent] : undefined;
  const cat: ChainCfg | undefined = s.agent ? cfg.categories?.[s.agent] : undefined;
  const entries: ChainEntry[] = [...(ag?.fallback_models ?? []), ...(cat?.fallback_models ?? [])];
  for (const e of entries) {
    if (typeof e === "object" && entryModel(e) === s.activeModel) return entrySettings(e);
  }
  return undefined;
}

export const RuntimeFallbackPlugin: Plugin = async ({ client }) => {
  loadState();
  loadConfig();

  const notify = async (sessionID: string, title: string, message: string) => {
    if (!loadConfig().notify_on_fallback) return;
    try { await (client as any).tui?.showToast?.({ sessionID, title, message, variant: "warning" }); } catch { /* noop */ }
  };

  const handleError = async (sessionID: string | undefined, err: unknown) => {
    if (!sessionID) return;
    const cfg = loadConfig();
    if (classifyError(err, cfg) !== "retryable") return;
    const exhausted = await applyFallback(sessionID, String((err as any)?.data?.message ?? "provider error").slice(0, 200));
    const s = sessionFor(sessionID);
    const m = s?.activeModel;
    if (m) {
      const parsed = parseModel(m);
      try {
        await (client as any).session.update(sessionID, {
          model: { id: parsed.modelID, providerID: parsed.providerID, variant: undefined },
        });
      } catch { /* model swap unsupported on this build; title marker still lands */ }
      try {
        await (client as any).session.update(sessionID, { title: `[fallback: ${m}]` });
      } catch { /* noop */ }
    }
    if (exhausted) {
      await notify(sessionID, "fallback: chain exhausted", `No fallback available; last error on ${m ?? "primary"}`);
    } else {
      await notify(sessionID, "fallback applied", `Moved to ${m}`);
    }
  };

  return {
    event: async ({ event }: any) => {
      const t = event?.type;
      if (t === "session.status") {
        const st = event.properties?.status;
        if (st?.type === "retry") {
          const sid = event.properties.sessionID;
          if (sid) await handleError(sid, { name: "RetrySignal", data: { message: st.message, statusCode: 429 } });
        }
      } else if (t === "session.error") {
        await handleError(event.properties?.sessionID, event.properties?.error);
      } else if (t === "session.deleted") {
        const sid = event.properties?.info?.id ?? event.properties?.sessionID;
        if (sid) delete STATE.sessions[sid];
        persist();
      }
    },

    "chat.params": async ({ sessionID, agent, model }: any, output: any) => {
      const s = ensureSession(sessionID, agent, model?.id ? `${model.providerID}/${model.id}` : undefined);
      if (s.index > 0 && primaryAvailable(s.chain, s.activeModel, inCooldown)) {
        const primary = s.chain[0];
        s.activeModel = primary;
        s.index = 0;
        s.attempts = 0;
        persist();
      }
      const settings = entrySettingsFor(s);
      if (settings) {
        if (typeof settings.temperature === "number") output.temperature = settings.temperature;
        if (typeof settings.maxOutputTokens === "number") output.maxOutputTokens = settings.maxOutputTokens;
        if (settings.options) Object.assign(output.options, settings.options);
      }
    },

    "experimental.chat.system.transform": async ({ sessionID }: any, output: any) => {
      const s = sessionFor(sessionID);
      if (!s) return;
      const note = annotationFor(s.activeModel, s.index, s.chain);
      if (note && Array.isArray(output.system)) output.system.push(note);
    },

    tool: {
      "fallback-status": tool({
        description: "Show the current model fallback chain state for this session: active model, chain remaining, and per-model cooldowns. Chain-healthy sessions print a one-line definitive empty state.",
        args: {},
        async execute(_args, context) {
          return toonStatus(context.sessionID);
        },
      }),
    },
  };
};
