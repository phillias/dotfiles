#!/usr/bin/env node
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "fs";
import { homedir } from "os";
import { join } from "path";

const HOME = homedir();
const STATE_DIR = join(HOME, ".local", "state", "opencode-fleet");
const CACHE_DIR = join(HOME, ".cache", "opencode-models");
const SNAP = join(HOME, ".agents", "skills", "opencode-config", "models.snapshot.json");
const OUT_JSON = join(STATE_DIR, "catalog-drift.json");
const OUT_TXT = join(STATE_DIR, "catalog-drift.txt");
const ZEN_KEY = join(HOME, ".config", "opencode", ".zen-key");
const CONFIG = join(HOME, ".config", "opencode", "opencode-fallback.jsonc");

const MODELS_DEV = "https://models.dev/api.json";
const ZEN_MODELS = "https://opencode.ai/zen/v1/models";
const FETCH_TIMEOUT_MS = 30000;

const TRACKED = new Set([
  "cloudflare-workers-ai", "nvidia", "openrouter", "together", "baseten",
  "google", "mistral", "sambanova", "agnes-ai", "internlm", "opencode-go", "opencode-zen",
]);

mkdirSync(STATE_DIR, { recursive: true });
mkdirSync(CACHE_DIR, { recursive: true });

function stripJsonc(src) {
  let out = "";
  let inString = false, inLine = false, inBlock = false;
  for (let i = 0; i < src.length; i++) {
    const c = src[i], n = src[i + 1];
    if (inLine) { if (c === "\n") { inLine = false; out += c; } continue; }
    if (inBlock) { if (c === "*" && n === "/") { inBlock = false; i++; } continue; }
    if (inString) { out += c; if (c === "\\" && n) { out += n; i++; } else if (c === '"') inString = false; continue; }
    if (c === '"') { inString = true; out += c; continue; }
    if (c === "/" && n === "/") { inLine = true; i++; continue; }
    if (c === "/" && n === "*") { inBlock = true; i++; continue; }
    out += c;
  }
  return out.replace(/,(\s*[}\]])/g, "$1");
}

async function fetchJson(url, headers = {}) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), FETCH_TIMEOUT_MS);
  try {
    const res = await fetch(url, { headers, signal: ctrl.signal });
    if (!res.ok) throw new Error(`HTTP ${res.status} from ${url}`);
    return await res.json();
  } finally {
    clearTimeout(t);
  }
}

async function loadModelsDev() {
  const cache = join(CACHE_DIR, "models.dev.json");
  try {
    const raw = await fetchJson(MODELS_DEV);
    writeFileSync(cache, JSON.stringify(raw));
    return raw;
  } catch (err) {
    if (existsSync(cache)) return JSON.parse(readFileSync(cache, "utf-8"));
    throw new Error(`models.dev unreachable and no cache: ${err.message}`);
  }
}

async function loadZen() {
  if (!existsSync(ZEN_KEY)) return {};
  const key = readFileSync(ZEN_KEY, "utf-8").trim();
  if (!key) return {};
  try {
    const data = await fetchJson(ZEN_MODELS, { Authorization: `Bearer ${key}` });
    const out = {};
    for (const m of (data?.data ?? [])) {
      const id = m?.id;
      if (id) out[`opencode-zen/${id}`] = { context: m?.context_length ?? null, in: 0, out: 0, free: String(id).endsWith("-free") };
    }
    return out;
  } catch {
    return {};
  }
}

function modelEntry(key, provider, data) {
  const models = provider?.models ?? {};
  const id = key.slice(key.indexOf("/") + 1);
  const m = models[id];
  if (!m) return undefined;
  const cost = m.cost ?? {};
  const limit = m.limit ?? {};
  return {
    context: typeof limit.context === "number" ? limit.context : null,
    in: typeof cost.input === "number" ? cost.input : null,
    out: typeof cost.output === "number" ? cost.output : null,
    free: (cost.input === 0 && cost.output === 0) || (m.free === true),
  };
}

function catalogFromDev(modelsDev) {
  const out = {};
  for (const [provider, prov] of Object.entries(modelsDev)) {
    if (!prov || typeof prov !== "object" || !prov.models) continue;
    for (const id of Object.keys(prov.models)) {
      out[`${provider}/${id}`] = modelEntry(`${provider}/${id}`, prov, modelsDev);
    }
  }
  return out;
}

function blendedValue(m) {
  if (!m || typeof m.in !== "number" || typeof m.out !== "number") return null;
  const cost = 0.75 * m.in + 0.25 * m.out;
  if (cost <= 0) return null;
  return 1 / cost;
}

function configModels() {
  try {
    const cfg = JSON.parse(stripJsonc(readFileSync(CONFIG, "utf-8")));
    const set = new Set();
    const add = (e) => {
      if (typeof e === "string") set.add(e);
      else if (e && typeof e.model === "string") set.add(e.model);
    };
    for (const e of cfg.fallback_models ?? []) add(e);
    for (const a of Object.values(cfg.agents ?? {})) { add(a?.model); for (const e of a?.fallback_models ?? []) add(e); }
    for (const c of Object.values(cfg.categories ?? {})) { add(c?.model); for (const e of c?.fallback_models ?? []) add(e); }
    return [...set];
  } catch {
    return [];
  }
}

function consideredModels(catalog, zen) {
  const out = { ...zen };
  for (const [key, m] of Object.entries(catalog)) {
    if (TRACKED.has(key.split("/")[0])) out[key] = m;
  }
  return out;
}

function isFree(m) {
  return !!m?.free || (typeof m?.in === "number" && typeof m?.out === "number" && m.in === 0 && m.out === 0);
}

function buildSnapshot(catalog, zen, configRefs) {
  const refs = new Set(configRefs);
  const considered = consideredModels(catalog, zen);
  const models = {};
  for (const [key, m] of Object.entries(considered)) {
    const free = isFree(m);
    if (!(refs.has(key) || free)) continue;
    models[key] = { context: m.context, in: m.in, out: m.out, free: !!free };
  }
  return { models, updated_at: new Date().toISOString() };
}

function computeDiff(catalog, zen, snapshot) {
  const cur = consideredModels(catalog, zen);
  const removed = [];
  const added = [];
  const price = [];
  const context = [];
  for (const key of Object.keys(snapshot.models)) {
    const m = cur[key];
    if (!m) { removed.push(key); continue; }
    const old = snapshot.models[key];
    const nv = blendedValue(m);
    const ov = blendedValue(old);
    if (nv !== null && ov !== null && ov > 0) {
      const delta = Math.abs(nv - ov) / ov;
      if (delta >= 0.25) price.push({ model: key, from: old.in, to: m.in, delta_pct: Math.round(delta * 100) });
    }
    if (typeof m.context === "number" && typeof old.context === "number" && m.context !== old.context) {
      context.push({ model: key, from: old.context, to: m.context });
    }
  }
  for (const key of Object.keys(cur)) {
    if (!snapshot.models[key] && isFree(cur[key])) added.push(key);
  }
  return { removed, added, price, context };
}

function writeReport(diff, checkedAt) {
  const drift = { checked_at: checkedAt, ok: true, drift: diff };
  writeFileSync(OUT_JSON, JSON.stringify(drift));
  const n = diff.removed.length + diff.added.length + diff.price.length;
  if (n === 0) {
    writeFileSync(OUT_TXT, `catalog: no drift — checked ${checkedAt}`);
  } else {
    writeFileSync(OUT_TXT, `catalog: drift — ${diff.added.length} added, ${diff.removed.length} removed, ${diff.price.length} price>=25%, ${diff.context.length} context changed — run fallback-status / view catalog-drift.json`);
  }
  return n;
}

async function main() {
  const seed = process.argv.includes("--seed");
  let modelsDev, zen;
  try {
    modelsDev = await loadModelsDev();
    zen = await loadZen();
  } catch (err) {
    writeFileSync(OUT_JSON, JSON.stringify({ checked_at: new Date().toISOString(), ok: false, error: err.message }));
    writeFileSync(OUT_TXT, `catalog: check failed — ${err.message}`);
    process.exit(2);
  }
  const catalog = catalogFromDev(modelsDev);
  if (seed) {
    const snapshot = buildSnapshot(catalog, zen, configModels());
    writeFileSync(SNAP, JSON.stringify(snapshot, null, 2));
    console.log(`seeded snapshot: ${Object.keys(snapshot.models).length} models -> ${SNAP}`);
    return;
  }
  if (!existsSync(SNAP)) {
    writeFileSync(OUT_TXT, "catalog: snapshot missing — run `catalog-drift --seed` first");
    process.exit(2);
  }
  const snapshot = JSON.parse(readFileSync(SNAP, "utf-8"));
  const diff = computeDiff(catalog, zen, snapshot);
  const n = writeReport(diff, new Date().toISOString());
  process.exit(n > 0 ? 1 : 0);
}

main().catch((err) => {
  writeFileSync(OUT_JSON, JSON.stringify({ checked_at: new Date().toISOString(), ok: false, error: err.message }));
  writeFileSync(OUT_TXT, `catalog: check failed — ${err.message}`);
  process.exit(2);
});
