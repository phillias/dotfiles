#!/usr/bin/env node
// d1-registry-refresh.mjs — once-daily structural refresh of the provider-catalog D1 registry.
//
// Pulls live route state from Cloudflare AI Gateway (REST) and Vercel AI Gateway
// (REST; falls back to D1-seeded slugs when the list endpoint returns empty),
// then upserts routes/route_models into D1 database `provider-catalog`
// (id 9979fd5f-4b7a-483f-96cf-976f846000c6) through one wrangler invocation.
// Appends one registry_refresh observation incl. ladder-drift detection.
//
// Scheduling: systemd user timer d1-registry-refresh.timer (05:00 America/New_York, Persistent).
// Env: CF_AI_GATEWAY_TOKEN (required, AI Gateway route scope), VERCEL_TOKEN (required for Vercel),
//      PROVIDER_CATALOG_D1=off disables the whole run (exit 0).
// Auth for D1: local wrangler OAuth login (d1 write scope) — no API token; see provider-catalog skill.
//
// Exit codes: 0 = refreshed, no drift; 1 = refreshed, drift detected (informational);
//             2 = error (missing env, upstream failure, or D1 write failure).

import { writeFileSync, unlinkSync, copyFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { spawnSync } from "node:child_process";

const D1_DATABASE = "provider-catalog";
const CF_BASE = "https://api.cloudflare.com/client/v4";
const CF_GATEWAY = "opencode";
const VERCEL_SCOPE = "phils-projects-336d7fca";
const VERCEL_API = "https://api.vercel.com";
const GW_CF = "cloudflare-ai-gateway";
const GW_VC = "vercel-ai-gateway";

const now = new Date();
const ts = now.toISOString();

function fail(msg) {
  console.error(`d1-registry-refresh: ${msg}`);
  process.exit(2);
}

if (process.env.PROVIDER_CATALOG_D1 === "off") {
  console.log("d1-registry-refresh: PROVIDER_CATALOG_D1=off — skipped");
  process.exit(0);
}

const cfToken = process.env.CF_AI_GATEWAY_TOKEN;
const vercelToken = process.env.VERCEL_TOKEN;
if (!cfToken) fail("CF_AI_GATEWAY_TOKEN not set");
const acct = process.env.CLOUDFLARE_ACCOUNT_ID || "a7fa198dd5b359a187c671064fe6b36e";

function cfGet(path) {
  const res = spawnSync("curl", [
    "-sS", "--max-time", "30",
    `${CF_BASE}/accounts/${acct}/ai-gateway/gateways/${CF_GATEWAY}/${path}`,
    "-H", `Authorization: Bearer ${cfToken}`,
    "-H", "cf-aig-skip-cache: true",
  ]);
  if (res.status !== 0) throw new Error(`cf curl ${path} exit ${res.status}`);
  const body = JSON.parse(String(res.stdout));
  if (body.success !== true) throw new Error(`cf api ${path}: ${JSON.stringify(body.errors ?? body).slice(0, 200)}`);
  return body;
}

/** Walk a CF route elements graph into an ordered [provider, model] ladder. */
function ladderFromElements(elements) {
  const byId = new Map(elements.map((e) => [e.id, e]));
  const start = elements.find((e) => e.type === "start");
  const ladder = [];
  let cur = start?.outputs?.next?.elementId;
  const seen = new Set();
  while (cur && cur !== "END" && !seen.has(cur)) {
    seen.add(cur);
    const node = byId.get(cur);
    if (!node || node.type !== "model") break;
    const p = node.properties ?? {};
    if (p.provider && p.model) ladder.push([p.provider, p.model]);
    cur = node.outputs?.fallback?.elementId;
  }
  return ladder;
}

function fetchCloudflare() {
  const list = cfGet("routes");
  const routes = list.data?.routes ?? [];
  const out = [];
  for (const r of routes) {
    const detail = cfGet(`routes/${r.id}`);
    const v = detail.result?.version ?? {};
    out.push({
      route: `dynamic/${detail.result?.name ?? r.name}`,
      active_version: v.version_id ?? null,
      deployed_at: v.active ? (detail.result?.deployment?.created_at ?? v.created_at ?? null) : null,
      ladder: ladderFromElements(v.data ?? []),
    });
  }
  return { routes: out, healthy: true };
}

function vcGet(path) {
  const res = spawnSync("curl", [
    "-sS", "--max-time", "30", `${VERCEL_API}${path}`,
    "-H", `Authorization: Bearer ${process.env.VERCEL_TOKEN}`,
  ]);
  if (res.status !== 0) throw new Error(`vercel curl ${path} exit ${res.status}`);
  return JSON.parse(String(res.stdout));
}

function vcRouteFromConfig(vm) {
  const models = Array.isArray(vm.models) ? vm.models : [];
  const ladder = models
    .map((m) => (typeof m === "string" ? m : m.model ?? ""))
    .filter(Boolean)
    .map((s) => { const i = s.indexOf("/"); return i === -1 ? ["vercel", s] : [s.slice(0, i), s.slice(i + 1)]; });
  return {
    route: `vmc/${vm.virtualModelSlug ?? vm.slug}`,
    active_version: null,
    deployed_at: vm.updatedAt ? new Date(vm.updatedAt).toISOString() : null,
    ladder,
  };
}

/**
 * Vercel discovery. The list endpoint can return an empty array even when
 * per-slug GETs resolve (observed 2026-09-27), so fall back to the slugs
 * already recorded in D1 routes and inspect each. New Vercel virtual models
 * need one manual seed (INSERT INTO routes) before auto-refresh picks them up.
 */
function fetchVercel() {
  const teams = vcGet("/v1/teams?limit=100").teams ?? [];
  const team = teams.find((t) => t.slug === VERCEL_SCOPE);
  if (!team) throw new Error(`vercel team slug ${VERCEL_SCOPE} not found in ${teams.length} teams`);
  const tid = team.id;
  const listConfigs = vcGet(`/ai-gateway/virtual-model-configs?teamId=${tid}&limit=100`).virtualModelConfigs ?? [];
  let configs = listConfigs;
  let healthy = listConfigs.length > 0;
  if (configs.length === 0) {
    const res = spawnSync("wrangler", ["d1", "execute", D1_DATABASE, "--remote", "--command",
      "SELECT route FROM routes WHERE gateway='vercel-ai-gateway';", "--json"], { timeout: 120000 });
    if (res.status !== 0 || res.error) throw new Error(`wrangler vercel-slug read failed: ${res.error?.message ?? ""} exit ${res.status}: ${String(res.stderr ?? "").slice(0, 200)}`);
    const parsed = JSON.parse(String(res.stdout));
    const rows = parsed?.result?.[0]?.results ?? parsed?.[0]?.results ?? [];
    configs = [];
    for (const row of rows) {
      const slug = String(row.route).replace(/^vmc\//, "");
      try {
        const vm = vcGet(`/ai-gateway/virtual-model-configs/${slug}?teamId=${tid}`);
        if (vm && !vm.deleted && (vm.virtualModelSlug || vm.slug)) configs.push(vm);
      } catch { /* retired or renamed slug: skip */ }
    }
    if (configs.length > 0) console.error("d1-registry-refresh: vercel list empty, refreshed from D1-seeded slugs");
  }
  return {
    routes: configs.filter((vm) => !vm.deleted).map(vcRouteFromConfig).filter((r) => r.route && r.ladder.length > 0),
    healthy,
  };
}

function q(v) { return `'${String(v).replace(/'/g, "''")}'`; }

/** Compare computed route set against D1 snapshot; returns drift description or null. */
function describeDrift(computed, snapshotRoutes, snapshotLadders) {
  const drift = [];
  const computedKeys = new Set(computed.map((r) => `${r.gateway}|${r.route}`));
  for (const key of snapshotRoutes) if (!computedKeys.has(key)) drift.push(`route-removed:${key}`);
  for (const r of computed) {
    const key = `${r.gateway}|${r.route}`;
    if (!snapshotRoutes.has(key)) { drift.push(`route-added:${key}`); continue; }
    const old = snapshotLadders.get(key) ?? [];
    const nowLadder = r.ladder.map(([p, m]) => `${p}/${m}`).join("|");
    if (old.join("|") !== nowLadder) drift.push(`ladder:${key}`);
  }
  return drift.length ? drift.join(",") : null;
}

function readSnapshot() {
  const sql = "SELECT gateway, route, active_version FROM routes; SELECT gateway, route, position, provider, model FROM route_models ORDER BY gateway, route, position;";
  const res = spawnSync("wrangler", ["d1", "execute", D1_DATABASE, "--remote", "--command", sql, "--json"], { timeout: 60000 });
  if (res.status !== 0) throw new Error(`wrangler snapshot read failed: ${String(res.stderr ?? "").slice(0, 200)}`);
  const out = JSON.parse(String(res.stdout));
  const results = Array.isArray(out) ? out : out.result ?? [];
  const routesRows = (Array.isArray(out) ? out[0]?.results : results[0]?.results) ?? (out?.result?.[0]?.results ?? []);
  const ladderRows = (Array.isArray(out) ? out[1]?.results : results[1]?.results) ?? (out?.result?.[1]?.results ?? []);
  const routesSet = new Set(routesRows.map((r) => `${r.gateway}|${r.route}`));
  const ladders = new Map();
  for (const row of ladderRows) {
    const key = `${row.gateway}|${row.route}`;
    if (!ladders.has(key)) ladders.set(key, []);
    ladders.get(key).push(`${row.provider}/${row.model}`);
  }
  return { routesSet, ladders };
}

function buildSql(cfRoutes, vcRoutes, drift, removedKeys) {
  const lines = ["PRAGMA foreign_keys=ON;"];
  const all = [
    ...cfRoutes.map((r) => ({ ...r, gateway: GW_CF })),
    ...vcRoutes.map((r) => ({ ...r, gateway: GW_VC })),
  ];
  for (const r of all) {
    lines.push(
      `INSERT INTO routes (gateway, route, active_version, deployed_at, updated_at, notes) VALUES (${q(r.gateway)}, ${q(r.route)}, ${r.active_version ? q(r.active_version) : "NULL"}, ${r.deployed_at ? q(r.deployed_at) : "NULL"}, ${q(ts)}, NULL) ` +
      `ON CONFLICT(gateway, route) DO UPDATE SET active_version=excluded.active_version, deployed_at=excluded.deployed_at, updated_at=excluded.updated_at;`
    );
  }
  for (const key of removedKeys ?? []) {
    const [gw, route] = key.split("|");
    lines.push(`DELETE FROM routes WHERE gateway=${q(gw)} AND route=${q(route)};`);
  }
  for (const gw of [GW_CF, GW_VC]) {
    lines.push(`DELETE FROM route_models WHERE gateway=${q(gw)};`);
    for (const r of all.filter((x) => x.gateway === gw)) {
      r.ladder.forEach(([p, m], i) => {
        lines.push(
          `INSERT INTO route_models (gateway, route, position, provider, model, notes) VALUES (${q(gw)}, ${q(r.route)}, ${i + 1}, ${q(p)}, ${q(m)}, NULL);`
        );
        lines.push(
          `INSERT INTO models (provider, model, display_name, context_tokens, price_input_per_m, price_output_per_m, free_tier, status, status_source, status_updated_at, notes) ` +
          `VALUES (${q(p)}, ${q(m)}, NULL, NULL, NULL, NULL, 0, 'unknown', 'registry-refresh', ${q(ts)}, NULL) ` +
          `ON CONFLICT(provider, model) DO NOTHING;`
        );
      });
    }
  }
  lines.push(
    `INSERT INTO observations (ts, kind, subject, metric, value_num, value_text, source, details) VALUES ` +
    `(${q(ts)}, 'registry_refresh', 'catalog:provider-catalog', 'routes_refreshed', ${all.length}, '${all.length} routes', 'd1-registry-refresh', ${q(`cf=${cfRoutes.length} vercel=${vcRoutes.length}`)});`
  );
  lines.push(
    `INSERT INTO observations (ts, kind, subject, metric, value_num, value_text, source, details) VALUES ` +
    `(${q(ts)}, 'registry_refresh', 'catalog:provider-catalog', 'ladder_drift', ${drift ? 1 : 0}, ${drift ? "'drift'" : "'clean'"}, 'd1-registry-refresh', ${q(drift ?? "no change")});`
  );
  return lines.join("\n");
}

function main() {
  let cfFetch, vcFetch;
  try { cfFetch = fetchCloudflare(); } catch (e) { fail(`cloudflare fetch: ${e.message}`); }
  try { vcFetch = fetchVercel(); } catch (e) { fail(`vercel fetch: ${e.message}`); }
  const cfRoutes = cfFetch.routes;
  const vcRoutes = vcFetch.routes;
  const gwOk = { [GW_CF]: cfFetch.healthy, [GW_VC]: vcFetch.healthy };

  let drift = null;
  let removedKeys = [];
  try {
    const snap = readSnapshot();
    const computed = [...cfRoutes.map((r) => ({ ...r, gateway: GW_CF })), ...vcRoutes.map((r) => ({ ...r, gateway: GW_VC }))];
    drift = describeDrift(computed, snap.routesSet, snap.ladders);
    const currentKeys = new Set(computed.map((r) => `${r.gateway}|${r.route}`));
    removedKeys = [...snap.routesSet].filter((k) => {
      const gw = k.split("|")[0];
      return !currentKeys.has(k) && gwOk[gw];
    });
  } catch (e) {
    console.error(`d1-registry-refresh: snapshot read failed, drift unknown (${e.message})`);
  }

  const statements = buildSql(cfRoutes, vcRoutes, drift, removedKeys).split("\n").filter((l) => l.trim() && !l.startsWith("PRAGMA"));
  const CHUNK = 40; // remote D1 file batches fail above ~this size (D1_RESET_DO, observed 2026-09-27)
  const RETRIES = 3; // consecutive remote batches also fail transiently; retry with backoff
  const failed = `${process.env.HOME}/.local/state/opencode-fleet/d1-registry-refresh-failed.sql`;
  const sleep = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
  for (let i = 0; i < statements.length; i += CHUNK) {
    const chunk = statements.slice(i, i + CHUNK);
    const tmp = `${tmpdir()}/d1-registry-refresh-${now.getTime()}-${i}.sql`;
    writeFileSync(tmp, chunk.join("\n"));
    let ok = false;
    let lastErr = "";
    for (let attempt = 1; attempt <= RETRIES && !ok; attempt++) {
      const res = spawnSync("wrangler", ["d1", "execute", D1_DATABASE, "--remote", "--file", tmp], { timeout: 120000 });
      if (res.status === 0 && !res.error) { ok = true; break; }
      lastErr = `${res.error?.message ?? ""} ${String(res.stderr ?? "").replace(/\x1b\[[0-9;]*m/g, "").slice(0, 200)}`;
      if (attempt < RETRIES) sleep(attempt * 5000);
    }
    if (!ok) {
      try { copyFileSync(tmp, failed); } catch {}
      try { unlinkSync(tmp); } catch {}
      fail(`wrangler execute chunk ${i / CHUNK + 1} failed after ${RETRIES} attempts (sql preserved at ${failed}): ${lastErr}`);
    }
    unlinkSync(tmp);
    if (i + CHUNK < statements.length) sleep(2000); // spacing between consecutive remote batches
  }
  console.log(`d1-registry-refresh: cf=${cfRoutes.length} vercel=${vcRoutes.length} statements=${statements.length} drift=${drift ? "DRIFT" : "clean"}${drift ? ` (${drift})` : ""}`);
  process.exit(drift ? 1 : 0);
}

main();
