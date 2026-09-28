#!/usr/bin/env node
// Harness driver for d1-registry-refresh.mjs scenarios.
// Builds an isolated case dir (fixture responses + seeded sqlite "D1"), runs the
// REAL script from the worktree with shimmed curl/wrangler on PATH, captures
// exit/stdout/stderr, then asserts expected outcomes against DB + logs.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { DatabaseSync } from "node:sqlite";

const WORKTREE = process.env.WORKTREE;
const SCRIPT = path.join(WORKTREE, "dot_config/opencode/scripts/executable_d1-registry-refresh.mjs");
const HARNESS = path.join(process.env.EVIDENCE_DIR, "harness");
const RUNS = path.join(HARNESS, "runs");

const BIN_ROOTS = [path.join(HARNESS, "bin"), "/usr/bin", "/bin"];

// ---------- response builders ----------
function elems(ladder, opts = {}) {
  // ladder: ["provider/model", ...]; opts: {cycle:bool, sink:bool, dangling:bool}
  const out = [{ id: "start", type: "start", outputs: { next: { elementId: "m0" } } }];
  ladder.forEach((pm, i) => {
    const [provider, model] = pm.split("/");
    let fb = i + 1 < ladder.length ? { elementId: `m${i + 1}` } : { elementId: "END" };
    if (opts.cycle && i === ladder.length - 1) fb = { elementId: "m0" };
    if (opts.sink && i === ladder.length - 1) fb = { elementId: "sink" };
    out.push({ id: `m${i}`, type: "model", properties: { provider, model }, outputs: { fallback: fb } });
  });
  if (opts.sink) out.push({ id: "sink", type: "sink", outputs: {} });
  if (opts.dangling && ladder.length) {
    out[out.length - 1].outputs.fallback.elementId = "missing-el";
  }
  return out;
}
function detail(name, ladder, opts = {}) {
  const v = opts.noVersion ? {} : {
    version_id: `v-${name}`,
    active: true,
    data: elems(ladder, opts),
    created_at: "2026-09-27T00:00:00Z",
  };
  return JSON.stringify({
    success: true,
    result: { name, version: v, deployment: { created_at: "2026-09-26T00:00:00Z" } },
  });
}
function page(routeIds, perPage = 25, extra = {}) {
  const routes = routeIds.map((id) => ({ id, name: id }));
  if (extra.malformedSchema) return JSON.stringify({ success: true, data: {} });
  if (extra.badJson) return ">>>> not json <<<<";
  return JSON.stringify({ success: true, data: { routes, per_page: perPage } });
}
function vcVm(slug, models, opts = {}) {
  return { virtualModelSlug: slug, models, updatedAt: "2026-09-27T00:00:00Z", ...(opts.deleted ? { deleted: true } : {}) };
}

const SEED_SCHEMA = `
CREATE TABLE IF NOT EXISTS routes (gateway TEXT, route TEXT, active_version TEXT, deployed_at TEXT, updated_at TEXT, notes TEXT, PRIMARY KEY (gateway, route));
CREATE TABLE IF NOT EXISTS route_models (gateway TEXT, route TEXT, position INTEGER, provider TEXT, model TEXT, notes TEXT, PRIMARY KEY (gateway, route, position));
CREATE TABLE IF NOT EXISTS models (provider TEXT, model TEXT, display_name TEXT, context_tokens INTEGER, price_input_per_m REAL, price_output_per_m REAL, free_tier INTEGER, status TEXT, status_source TEXT, status_updated_at TEXT, notes TEXT, PRIMARY KEY (provider, model));
CREATE TABLE IF NOT EXISTS observations (ts TEXT, kind TEXT, subject TEXT, metric TEXT, value_num INTEGER, value_text TEXT, source TEXT, details TEXT);
`;

function seedDb(dbPath, stmts) {
  const db = new DatabaseSync(dbPath);
  db.exec(SEED_SCHEMA);
  for (const s of stmts) db.exec(s);
  db.close();
}
function query(dbPath, sql) {
  const db = new DatabaseSync(dbPath, { readOnly: true });
  const rows = db.prepare(sql).all();
  db.close();
  return rows;
}

// ---------- case runner ----------
function makeCaseDir(name) {
  const dir = path.join(RUNS, name);
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(path.join(dir, "pages"), { recursive: true });
  fs.mkdirSync(path.join(dir, "details"), { recursive: true });
  return dir;
}

function buildCase(name, spec) {
  const dir = makeCaseDir(name);
  // fixtures
  for (const [p, routes] of Object.entries(spec.pages ?? {})) {
    const content = typeof routes === "string" ? routes : page(routes, spec.perPage ?? 25);
    fs.writeFileSync(path.join(dir, "pages", `page-${p}.json`), content);
  }
  for (const [id, d] of Object.entries(spec.details ?? {})) {
    fs.writeFileSync(path.join(dir, "details", `${id}.json`), detail(id, d.ladder, d.opts ?? {}));
  }
  fs.writeFileSync(path.join(dir, "vc-teams.json"), JSON.stringify({ teams: [{ slug: "phils-projects-336d7fca", id: "tid-1" }] }));
  fs.writeFileSync(path.join(dir, "vc-list.json"), JSON.stringify(spec.vcList ?? { virtualModelConfigs: [] }));
  for (const [slug, vm] of Object.entries(spec.vcSlugs ?? {})) {
    fs.writeFileSync(path.join(dir, `vc-slug-${slug}.json`), JSON.stringify(vm));
  }
  const dbPath = path.join(dir, "db.sqlite");
  seedDb(dbPath, spec.seed ?? []);

  const tmpRoot = path.join(dir, "tmp");
  fs.mkdirSync(tmpRoot, { recursive: true });
  const curlLog = path.join(dir, "curl-argv.log");
  const wranglerLog = path.join(dir, "wrangler.log");
  const outPath = path.join(dir, "stdout.txt");
  const errPath = path.join(dir, "stderr.txt");
  fs.writeFileSync(curlLog, "");
  fs.writeFileSync(wranglerLog, "");

  const env = {
    ...process.env,
    PATH: BIN_ROOTS.join(":"),
    CASE_DIR: dir,
    CURL_LOG: curlLog,
    WRANGLER_DB: dbPath,
    WRANGLER_LOG: wranglerLog,
    FAIL_URLS: spec.failUrls ?? "",
    PROVIDER_CATALOG_D1: "",
    CF_AI_GATEWAY_TOKEN: spec.cfToken ?? "DUMMY_CF_TOKEN_VALUE",
    VERCEL_TOKEN: spec.vercelToken ?? "DUMMY_VERCEL_TOKEN_VALUE",
    TMPDIR: tmpRoot,
    HOME: dir,
  };
  return { dir, env, outPath, errPath, curlLog, wranglerLog, dbPath };
}

function finalizeLogs(dir) {
  // concatenate per-call curl argv slot files into curl-argv.log
  const parts = fs.readdirSync(dir).filter((f) => f.startsWith("curl-argv.log.part.")).sort();
  if (!parts.length) return;
  fs.appendFileSync(path.join(dir, "curl-argv.log"), parts.map((p) => fs.readFileSync(path.join(dir, p), "utf8")).join("\n") + "\n");
  for (const p of parts) fs.rmSync(path.join(dir, p));
}

function runCase(name, spec) {
  const { dir, env, outPath, errPath, curlLog, wranglerLog, dbPath } = buildCase(name, spec);
  const res = spawnSync("node", [SCRIPT], { env, encoding: "utf8", timeout: 300000 });
  fs.writeFileSync(outPath, res.stdout ?? "");
  fs.writeFileSync(errPath, res.stderr ?? "");
  finalizeLogs(dir);
  return { dir, status: res.status, stdout: res.stdout ?? "", stderr: res.stderr ?? "", outPath, errPath, curlLog, wranglerLog, dbPath };
}

export { runCase, buildCase, finalizeLogs, query, seedDb, detail, page, vcVm, elems, RUNS };
export { SCRIPT, BIN_ROOTS };