#!/usr/bin/env node
/**
 * Deterministic audit for the CF AI Gateway dynamic routes (cf-aig-dynamic).
 *
 * Rule-based only — no LLM. Documented by the provider-catalog skill
 * (~/.agents/skills/provider-catalog), which explains what each test means and
 * how owners act on the results; that skill also governs how the captain
 * triggers interactive LLM proposals from this log.
 *
 * Tests (per run):
 *   1. config-drift — cf-aig-dynamic routes declared in opencode.json, pi
 *      models.json, and pi fallback-chains.json match each other and the
 *      catalog's purpose list (TUI, high, pr-gate, vision).
 *   2. route-probe  — one fixed 4-token completion per route; records HTTP
 *      code, latency, upstream model id served, and retry-after/rate headers
 *      on 429/5xx. These are routing evidence for route rebuilds.
 *
 * Output: one JSON line per event appended to
 *   ~/.local/state/opencode-fleet/dynamic-audit.jsonl
 *
 * Exit codes: 0 healthy · 1 drift detected · 2 audit machinery failure.
 * Transient upstream conditions (429/5xx/timeout) are logged, never an exit
 * code, because the skill reads them as routing evidence rather than tool
 * failure.
 */
import { readFileSync, appendFileSync, mkdirSync, existsSync } from "fs";
import { homedir } from "os";
import { join } from "path";
import { EOL } from "os";

const HOME = homedir();
const STATE_DIR = join(HOME, ".local", "state", "opencode-fleet");
const LOG = join(STATE_DIR, "dynamic-audit.jsonl");
const OPENCODE_JSON = join(HOME, ".config/opencode/opencode.json");
const PI_CHAINS_JSON = join(HOME, ".pi/fallback-chains.json");
const PI_MODELS_JSON = join(HOME, ".pi/agent/models.json");
/** Route declarations each chain must include (catalog owner defaults). */
const CHAIN_EXPECT = { default: "dynamic/TUI", gate: "dynamic/pr-gate" };
const SKILL_PROVIDERS_MD = join(
  HOME,
  ".agents/skills/provider-catalog/references/PROVIDERS.md"
);
const GW_TOKEN_FILE = join(HOME, ".config/opencode/.cf-ai-gw-token");
const BASE_URL =
  "https://gateway.ai.cloudflare.com/v1/a7fa198dd5b359a187c671064fe6b36e/opencode/compat";
const EXPECTED_ROUTES = ["TUI", "high", "pr-gate", "vision"];
const TIMEOUT_MS = 60_000;
const PROBE_GAP_MS = 2_000;

mkdirSync(STATE_DIR, { recursive: true });

const logEvent = (test, fields) =>
  appendFileSync(LOG, JSON.stringify({ ts: new Date().toISOString(), test, ...fields }) + EOL);

const die = (detail) => {
  logEvent("audit_error", { detail });
  console.error(`dynamic-audit: ${detail}`);
  process.exit(2);
};

/** Minimal jsonc stripper: block+line comments, trailing commas. */
const stripJsonc = (src) =>
  src
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:"'\w\\])\/\/.*$/gm, "$1")
    .replace(/,\s*([}\]])/g, "$1");

/** Return the routes referenced by a provider block; null when unreadable. */
function routesFromProviderModels(src) {
  const doc = JSON.parse(stripJsonc(src));
  const block = doc?.providers?.["cf-aig-dynamic"] ?? doc?.provider?.["cf-aig-dynamic"];
  return block?.models ? Object.keys(block.models) : null;
}

const readJsoncRoutes = (path) => {
  if (!existsSync(path)) return { routes: null, error: "missing file" };
  try {
    return { routes: routesFromProviderModels(readFileSync(path, "utf8")), error: null };
  } catch (e) {
    return { routes: null, error: e.message };
  }
};

/** Pull an exact one-line JSON string out of a raw JSON file. */
const routeInFallbackChains = (src) => {
  const flat = JSON.stringify(JSON.parse(stripJsonc(src)));
  return EXPECTED_ROUTES.filter((r) => flat.includes(`cf-aig-dynamic/dynamic/${r}`));
};

function dynamicSection(md) {
  const m = md.match(/## Dynamic routes[\s\S]*?(?=\n## |$)/);
  return m ? m[0] : "";
}

/** Test 1 — configuration drift, purely by static comparison. */
function configDrift() {
  const details = [];
  const oc = readRoutesFromOpencode();
  const pi = readRoutesFromPi();
  if (!oc) details.push("opencode.json cf-aig-dynamic routes unreadable");
  if (!pi) details.push("pi agent/models.json cf-aig-dynamic routes unreadable");
  if (oc && pi && oc !== pi)
    details.push("opencode.json and pi agent/models.json list different routes");
  let catalog = "";
  try {
    catalog = dynamicSection(readFileSync(SKILL_PROVIDERS_MD, "utf8"));
  } catch {
    details.push("provider-catalog PROVIDERS.md unreadable");
  }
  for (const r of EXPECTED_ROUTES) {
    if (catalog && !new RegExp(`\\b${r}\\b`).test(catalog))
      details.push(`PROVIDERS.md has no purpose entry for route ${r}`);
  }
  try {
    const flat = JSON.stringify(JSON.parse(stripJsonc(readFileSyncSafe(PI_CHAINS_JSON))));
    for (const [chain, route] of Object.entries(CHAIN_EXPECT)) {
      if (!flat.includes(`"cf-aig-dynamic/${route}"`))
        details.push(`pi fallback chain "${chain}" missing ${route}`);
    }
  } catch (e) {
    details.push(`pi fallback-chains.json unreadable: ${String(e.message).slice(0, 60)}`);
  }
  logEvent("config_drift", {
    status: details.length === 0 ? "clean" : "drift",
    detail: details.length ? details.join("; ") : undefined,
  });
  if (details.length) console.error(`config drift: ${details.join("; ")}`);
  return details.length === 0 ? 0 : 1;
}

function readRoutesFromOpencode() {
  try {
    const doc = JSON.parse(readFileSync(OPENCODE_JSON, "utf8"));
    const models = doc?.provider?.["cf-aig-dynamic"]?.models;
    return models ? Object.keys(models).sort().join("|") : null;
  } catch {
    return null;
  }
}

function readRoutesFromPi() {
  try {
    const src = readFileSync(PI_MODELS_JSON, "utf8");
    const routes = routesFromProviderModels(src);
    return routes ? routes.sort().join("|") : null;
  } catch {
    return null;
  }
}

const readFileSyncSafe = (p) => (existsSync(p) ? readFileSync(p, "utf8") : "");

/** Test 2 — fixed 4-token probe per route. */
async function probeRoute(route, token) {
  const started = Date.now();
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  const fields = { route: `dynamic/${route}`, status: "unknown" };
  try {
    const res = await fetch(`${BASE_URL}/chat/completions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "cf-aig-gateway-id": "opencode",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: `dynamic/${route}`,
        messages: [{ role: "user", content: "Reply with the single word: ok" }],
        max_tokens: 4,
        temperature: 0,
      }),
      signal: ctrl.signal,
    });
    fields.http = res.status;
    fields.latency_ms = Date.now() - started;
    if (res.ok) {
      const body = await res.json();
      fields.status = "ok";
      fields.served_model = body?.model ?? "(unset)";
      fields.completion_prefix = (body?.choices?.[0]?.message?.content ?? "").slice(0, 16);
    } else if (res.status === 429) {
      fields.status = "limited";
      const ra = res.headers.get("retry-after");
      fields.retry_after_s = ra ? Number(ra) : undefined;
    } else {
      fields.status = "error";
      fields.err = `HTTP ${res.status}`;
    }
    const hop = res.headers.get("cf-aig-hop-by-hop-status") ?? res.headers.get("cf-aig-status");
    if (hop) fields.cf_aig_status = hop;
  } catch (e) {
    fields.status = e?.name === "AbortError" ? "timeout" : `exc:${e?.message}`;
  } finally {
    clearTimeout(timer);
  }
  logEvent("route_probe", fields);
  return fields;
}

function main() {
  if (!existsSync(GW_TOKEN_FILE)) {
    logEvent("audit_error", { detail: "gateway token file missing" });
    console.error("dynamic-audit: gateway token file missing");
    process.exit(2);
  }
  const token = readFileSync(GW_TOKEN_FILE, "utf8").trim();

  const driftExit = configDrift();

  process.on("unhandledRejection", (e) => {
    logEvent("audit_error", { detail: String(e) });
    process.exit(2);
  });

  (async () => {
    const probes = [];
    for (const route of EXPECTED_ROUTES) {
      probes.push(await probeRoute(route, token));
      await new Promise((r) => setTimeout(r, PROBE_GAP_MS));
    }
    const healthy = probes.filter((p) => p.status === "ok").length;
    const line = `drift=${driftExit === 0 ? "clean" : "DRIFT"} routes_healthy=${healthy}/${probes.length}`;
    console.log(`dynamic-audit: ${line} log=${LOG}`);
    if (driftExit !== 0) process.exit(1);
    process.exit(0);
  })();
}

main();
