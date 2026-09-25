#!/usr/bin/env node
/**
 * Deterministic audit for the CF AI Gateway dynamic routes (CfAiGw).
 *
 * Rule-based only — no LLM. Documented by the provider-catalog skill
 * (~/.agents/skills/provider-catalog), which explains what each test means and
 * how owners act on the results; that skill also governs how the captain
 * triggers interactive LLM proposals from this log.
 *
 * Tests (per run):
 *   1. config-drift — CfAiGw routes declared in opencode.json, pi
 *      models.json, and pi fallback-chains.json include the catalog's
 *      purpose routes (TUI, high, pr-gate, vision); harness-specific
 *      extras are allowed.
 *   2. route-probe  — one fixed 4-token completion per route; records HTTP
 *      code, latency, upstream model id served, and retry-after/rate headers
 *      on 429/5xx. These are routing evidence for route rebuilds.
 *
 * Output: one JSON line per event appended to
 *   ~/.local/state/opencode-fleet/dynamic-audit.jsonl
 * Route probes, provider windows, config drift, and audit errors are also
 * mirrored as rows in the shared provider-catalog D1 database (default
 * `provider-catalog`; set PROVIDER_CATALOG_D1=off to disable). A D1 mirror
 * failure is an audit machinery failure (exit 2) because the shared catalog
 * is the durable sink for these observations.
 *
 * Exit codes: 0 healthy · 1 drift detected · 2 audit machinery failure.
 * Transient upstream conditions (429/5xx/timeout) are logged, never an exit
 * code, because the skill reads them as routing evidence rather than tool
 * failure.
 */
import { readFileSync, appendFileSync, mkdirSync, existsSync, writeFileSync, unlinkSync, copyFileSync } from "fs";
import { homedir, tmpdir } from "os";
import { join } from "path";
import { EOL } from "os";
import { spawnSync } from "child_process";

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
const BASE_URL =
  "https://gateway.ai.cloudflare.com/v1/a7fa198dd5b359a187c671064fe6b36e/opencode/compat";
const EXPECTED_ROUTES = ["TUI", "high", "pr-gate", "vision"];
const TIMEOUT_MS = 60_000;
const PROBE_GAP_MS = 2_000;
/** Availability CSV authored by the big-pickle-watch.sh probe, documented in
 *  provider-catalog; the audit folds its 24h aggregate into the same log. */
const AVAILABILITY_CSV = "/tmp/big-pickle-availability.csv";
const AVAILABILITY_WINDOW_H = 24;
const D1_DATABASE = (process.env.PROVIDER_CATALOG_D1 ?? "provider-catalog").trim();
const D1_ENABLED = D1_DATABASE !== "" && D1_DATABASE.toLowerCase() !== "off";

mkdirSync(STATE_DIR, { recursive: true });

/** D1 observation rows queued during this run; flushed once at the end. */
const d1Rows = [];

const logEvent = (test, fields) => {
  const ts = new Date().toISOString();
  appendFileSync(LOG, JSON.stringify({ ts, test, ...fields }) + EOL);
  queueD1(ts, test, fields);
};

const sqlStr = (v) => `'${String(v ?? "").replace(/'/g, "''")}'`;
const sqlNum = (v) => (Number.isFinite(v) ? String(v) : "NULL");

/** Map one audit event onto the provider-catalog D1 observations table. */
function queueD1(ts, test, fields) {
  if (!D1_ENABLED) return;
  const push = (subject, metric, valueNum, valueText, details) =>
    d1Rows.push({ ts, subject, metric, valueNum, valueText, details });
  if (test === "route_probe") {
    const subject = `route:cloudflare-ai-gateway/${fields.route}`;
    const ok = fields.status === "ok" ? 1 : 0;
    const detail = [
      fields.http ? `http=${fields.http}` : null,
      fields.served_model ? `served=${fields.served_model}` : null,
      fields.retry_after_s ? `retry_after_s=${fields.retry_after_s}` : null,
      fields.cf_aig_status ? `cf_aig_status=${fields.cf_aig_status}` : null,
    ]
      .filter(Boolean)
      .join(" ");
    push(subject, "availability", ok, fields.status, detail);
    if (Number.isFinite(fields.latency_ms))
      push(subject, "latency_ms", fields.latency_ms, null, fields.served_model ?? null);
  } else if (test === "provider_window" && fields.status === "summary") {
    const total =
      Number(fields.ok ?? 0) + Number(fields.limited ?? 0) + Number(fields.error ?? 0) + Number(fields.timeout ?? 0);
    const subject = ["direct", "gateway"].includes(fields.route)
      ? `provider:big-pickle/${fields.route}`
      : `route:cloudflare-ai-gateway/${fields.route}`;
    push(
      subject,
      `availability_window_${fields.window_hours}h`,
      total > 0 ? Number(fields.ok ?? 0) / total : null,
      `ok=${fields.ok ?? 0} limited=${fields.limited ?? 0} error=${fields.error ?? 0} timeout=${fields.timeout ?? 0}`,
      "big-pickle-watch.sh CSV aggregate"
    );
  } else if (test === "config_drift") {
    push(
      "catalog:provider-catalog",
      "config_drift",
      fields.status === "clean" ? 0 : 1,
      fields.status,
      fields.detail ?? null
    );
  } else if (test === "audit_error") {
    push("audit:dynamic-audit", "audit_error", null, "error", String(fields.detail ?? "").slice(0, 300));
  }
}

/** Write queued observations to D1 with one wrangler invocation. */
function flushD1() {
  if (!D1_ENABLED || d1Rows.length === 0) return { ok: true, skipped: true };
  const file = join(tmpdir(), `dynamic-audit-d1-${process.pid}.sql`);
  const values = d1Rows
    .map(
      (r) =>
        `(${sqlStr(r.ts)},'${r.metric === "latency_ms" ? "latency" : r.metric.startsWith("availability") ? "availability" : r.metric === "config_drift" ? "drift" : "error"}',${sqlStr(r.subject)},${sqlStr(r.metric)},${sqlNum(r.valueNum)},${sqlStr(r.valueText)},'dynamic-audit',${sqlStr(r.details)})`
    )
    .join(",\n");
  try {
    writeFileSync(file, `INSERT INTO observations(ts, kind, subject, metric, value_num, value_text, source, details) VALUES\n${values};\n`);
    const res = spawnSync("wrangler", ["d1", "execute", D1_DATABASE, "--remote", "--file", file], {
      encoding: "utf8",
    });
    if (res.error) throw res.error;
    if (res.status !== 0) throw new Error(`wrangler exit ${res.status}: ${String(res.stderr ?? "").slice(0, 200)}`);
    return { ok: true, rows: d1Rows.length };
  } catch (e) {
    try {
      copyFileSync(file, join(HOME, ".local", "state", "opencode-fleet", "dynamic-audit-d1-failed.sql"));
    } catch {}
    return { ok: false, error: String(e?.message ?? e).slice(0, 300) };
  } finally {
    try {
      unlinkSync(file);
    } catch {}
  }
}

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
  const block = doc?.providers?.["CfAiGw"] ?? doc?.provider?.["CfAiGw"];
  if (Array.isArray(block?.models))
    return block.models.map((m) => m?.id).filter((id) => typeof id === "string");
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
  return EXPECTED_ROUTES.filter((r) => flat.includes(`CfAiGw/dynamic/${r}`));
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
  if (!oc) details.push("opencode.json CfAiGw routes unreadable");
  if (!pi) details.push("pi agent/models.json CfAiGw routes unreadable");
  for (const r of EXPECTED_ROUTES) {
    const id = `dynamic/${r}`;
    if (oc && !oc.includes(id)) details.push(`opencode.json missing CfAiGw route ${id}`);
    if (pi && !pi.includes(id)) details.push(`pi agent/models.json missing CfAiGw route ${id}`);
  }
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
      if (!flat.includes(`"CfAiGw/${route}"`))
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
    const models = doc?.provider?.["CfAiGw"]?.models;
    return models ? Object.keys(models).sort() : null;
  } catch {
    return null;
  }
}

function readRoutesFromPi() {
  try {
    const src = readFileSync(PI_MODELS_JSON, "utf8");
    const routes = routesFromProviderModels(src);
    return routes ? routes.sort() : null;
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

/** Test 3 — availability window: fold big-pickle-watch.sh CSV evidence into
 *  the audit log as a per-route 24h aggregate. pure file read, no network. */
function providerWindow() {
  try {
    if (!existsSync(AVAILABILITY_CSV)) {
      logEvent("provider_window", { status: "no-log", detail: `${AVAILABILITY_CSV} not yet created` });
      return;
    }
    const rows = readFileSync(AVAILABILITY_CSV, "utf8").trim().split("\n").slice(1);
    const now = Date.now();
    const cutoff = now - AVAILABILITY_WINDOW_H * 3_600_000;
    const byRoute = {};
    for (const line of rows) {
      const [ts, route, , result] = line.split(",");
      const t = Date.parse(ts);
      if (Number.isNaN(t) || t < cutoff) continue;
      const r = (byRoute[route] ||= { ok: 0, limited: 0, error: 0, timeout: 0 });
      if (result in r) r[result] += 1;
    }
    for (const [route, counts] of Object.entries(byRoute)) {
      logEvent("provider_window", {
        status: "summary",
        route,
        window_hours: AVAILABILITY_WINDOW_H,
        ok: counts.ok,
        limited: counts.limited,
        error: counts.error,
        timeout: counts.timeout,
      });
    }
  } catch (e) {
    logEvent("provider_window", { status: "unreadable", detail: String(e.message).slice(0, 80) });
  }
}

function main() {
  const token = (process.env.CF_AI_GATEWAY_TOKEN || "").trim();
  if (!token) {
    logEvent("audit_error", { detail: "CF_AI_GATEWAY_TOKEN missing" });
    console.error("dynamic-audit: CF_AI_GATEWAY_TOKEN missing");
    process.exit(2);
  }

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
    providerWindow();
    const mirror = flushD1();
    if (!mirror.ok) {
      appendFileSync(LOG, JSON.stringify({ ts: new Date().toISOString(), test: "d1_mirror", status: "error", detail: mirror.error }) + EOL);
      console.error(`dynamic-audit: D1 mirror failed: ${mirror.error}`);
      process.exit(2);
    }
    const line = `drift=${driftExit === 0 ? "clean" : "DRIFT"} routes_healthy=${healthy}/${probes.length}`;
    console.log(`dynamic-audit: ${line} log=${LOG}${mirror.skipped ? "" : ` d1_rows=${mirror.rows}`}`);
    if (driftExit !== 0) process.exit(1);
    process.exit(0);
  })();
}

main();
