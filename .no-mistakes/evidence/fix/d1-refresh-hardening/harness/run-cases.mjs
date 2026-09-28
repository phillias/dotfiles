#!/usr/bin/env node
// Runs the stub-harness scenarios against the real d1-registry-refresh.mjs and
// asserts observable outcomes (exit codes, stdout/stderr, persisted DB state,
// curl argv hygiene, tmp cleanup).
import fs from "node:fs";
import path from "node:path";
import { runCase, query, vcVm } from "./harness.mjs";

const results = [];
function check(cond, label, detail = "") {
  results.push({ pass: !!cond, label, detail });
  console.log(`${cond ? "PASS" : "FAIL"}: ${label}${detail ? ` — ${detail}` : ""}`);
}
function have(hay, needle) { return hay.includes(needle); }

const CF_DEFAULT_LADDER = ["openai/gpt-4o", "anthropic/claude-3-5-sonnet"];
const cfSeed = (ids, opts = {}) => {
  const stmts = [];
  for (const id of ids) {
    stmts.push(`INSERT INTO routes (gateway, route, active_version, deployed_at, updated_at, notes) VALUES ('cloudflare-ai-gateway', 'dynamic/${id}', 'v-${id}', '2026-09-26T00:00:00Z', '2026-09-27T00:00:00Z', NULL);`);
    (opts.ladder ?? CF_DEFAULT_LADDER).forEach((pm, i) => {
      const [p, m] = pm.split("/");
      stmts.push(`INSERT INTO route_models (gateway, route, position, provider, model, notes) VALUES ('cloudflare-ai-gateway', 'dynamic/${id}', ${i + 1}, '${p}', '${m}', NULL);`);
    });
  }
  return stmts;
};
const vcSeed = (slugs, modelsBySlug = {}) => slugs.map((slug) => { const models = modelsBySlug[slug];
  return `INSERT INTO routes (gateway, route, active_version, deployed_at, updated_at, notes) VALUES ('vercel-ai-gateway', 'vmc/${slug}', NULL, '2026-09-27T00:00:00Z', '2026-09-27T00:00:00Z', NULL);`; });
const vcList = (slugs, modelsBySlug = {}) => ({ virtualModelConfigs: slugs.map((s) => vcVm(s, modelsBySlug[s] ?? ["anthropic/claude-3.5-sonnet", "openai/gpt-4o"])) });
const VC_MODELS_1 = ["anthropic/claude-3.5-sonnet", "openai/gpt-4o"];
const VC_MODELS_2 = ["anthropic/claude-3.5-sonnet", "openai/gpt-4o"];
const vcModelsSeed = (slug, models) => models.map((pm, i) => { const [p, m] = pm.split("/");
  return `INSERT INTO route_models (gateway, route, position, provider, model, notes) VALUES ('vercel-ai-gateway','vmc/${slug}',${i + 1},'${p}','${m}',NULL);`; });
const VC_SEED_MODELS = [...vcModelsSeed("vm1", VC_MODELS_1), ...vcModelsSeed("vm2", VC_MODELS_2)];

// ============ 1. happy path: multi-page pagination, healthy, no drift ============
let happyDir;
{
  const page1 = Array.from({ length: 25 }, (_, i) => `r${i + 1}`);
  const page2 = Array.from({ length: 5 }, (_, i) => `r${i + 26}`);
  const all = [...page1, ...page2];
  const details = {};
  for (const id of all) details[id] = { ladder: CF_DEFAULT_LADDER };
  const r = runCase("case-1-happy", {
    pages: { 1: page1, 2: page2 }, perPage: 25, details,
    vcList: vcList(["vm1", "vm2"]),
    seed: [...cfSeed(all), ...vcSeed(["vm1", "vm2"]), ...VC_SEED_MODELS],
  });
  happyDir = r.dir;
  check(r.status === 0, "exit 0 on clean healthy run", `status=${r.status}`);
  check(have(r.stdout, "cf=30 vercel=2"), "summary reports cf=30 vercel=2", r.stdout.trim());
  const argv = fs.readFileSync(r.curlLog, "utf8");
  check(have(argv, "routes?page=1&per_page=25") && have(argv, "routes?page=2&per_page=25"), "pagination: pages 1 and 2 fetched");
  check(!have(argv, "DUMMY_CF_TOKEN_VALUE") && !have(argv, "DUMMY_VERCEL_TOKEN_VALUE"), "tokens never appear in curl argv");
  check(have(argv, "-H @") && argv.includes("cf-auth.txt"), "auth via -H @file (cf)");
  check(argv.includes("vc-auth.txt"), "auth via -H @file (vercel)");
  const routes = query(r.dbPath, "SELECT count(*) c FROM routes");
  check(routes[0].c === 32, "route table holds 32 routes", `got ${routes[0].c}`);
  const obs = query(r.dbPath, "SELECT details FROM observations WHERE metric='routes_refreshed'");
  check(obs.length === 1 && have(obs[0].details, "skipped=none"), "observation records skipped=none", obs[0]?.details);
  const driftObs = query(r.dbPath, "SELECT value_num FROM observations WHERE metric='ladder_drift'");
  check(driftObs.length === 1 && driftObs[0].value_num === 0, "ladder_drift observation = 0 (clean)");
  const leftover = fs.readdirSync(path.join(r.dir, "tmp")).filter((f) => f.startsWith("d1-registry-refresh-"));
  check(leftover.length === 0, "tmp scratch dir removed after run", `left=${JSON.stringify(leftover)}`);

  // ============ 1b. mkdtemp randomness: two runs use different scratch dirs ============
  const r2 = runCase("case-1b-random", {
    pages: { 1: page1, 2: page2 }, perPage: 25, details,
    vcList: vcList(["vm1", "vm2"]),
    seed: [...cfSeed(all), ...vcSeed(["vm1", "vm2"]), ...VC_SEED_MODELS],
  });
  const argv1 = fs.readFileSync(r.curlLog, "utf8");
  const argv2 = fs.readFileSync(r2.curlLog, "utf8");
  const dir1 = (argv1.match(/-H @([^ ]*cf-auth\.txt)/) ?? [])[1];
  const dir2 = (argv2.match(/-H @([^ ]*cf-auth\.txt)/) ?? [])[1];
  check(!!dir1 && !!dir2 && dir1 !== dir2, "no predictable tmp path (mkdtemp random per run)", `${dir1} vs ${dir2}`);
}

// ============ 2. malformed-schema page -> unhealthy -> CF writes skipped ============
{
  const page1 = Array.from({ length: 25 }, (_, i) => `r${i + 1}`);
  const r = runCase("case-2-unhealthy-page", {
    pages: { 1: page1, 2: '{"success":true,"data":{}}' }, perPage: 25,
    vcList: vcList(["vm1", "vm2"]),
    seed: [...vcSeed(["vm1", "vm2"]), ...VC_SEED_MODELS],
  });
  check(r.status === 0, "exit 0 with one unhealthy gateway", `status=${r.status}`);
  check(have(r.stdout, "cf=0 vercel=2"), "summary cf=0 vercel=2 (cf skipped)", r.stdout.trim());
  const cfRows = query(r.dbPath, "SELECT count(*) c FROM routes WHERE gateway='cloudflare-ai-gateway'");
  check(cfRows[0].c === 0, "no cloudflare rows written when discovery unhealthy", `cf rows=${cfRows[0].c}`);
  const obs = query(r.dbPath, "SELECT details FROM observations WHERE metric='routes_refreshed'");
  check(obs.length === 1 && have(obs[0].details, "skipped=cf"), "observation records skipped=cf", obs[0]?.details);
}

// ============ 2b. unhealthy CF discovery must NOT delete stored CF rows (clobber guard) ============
{
  const r = runCase("case-2b-clobber-guard", {
    pages: { 1: '{"success":true,"data":{}}' },
    vcList: vcList(["vm1", "vm2"]),
    seed: [...cfSeed(["stale"]), ...vcSeed(["vm1", "vm2"]), ...VC_SEED_MODELS],
  });
  const cfRows = query(r.dbPath, "SELECT route FROM routes WHERE gateway='cloudflare-ai-gateway'");
  check(r.status === 0, "exit 0 (cf unhealthy, vercel written)", `status=${r.status}`);
  check(cfRows.length === 1 && cfRows[0].route === "dynamic/stale", "stored CF rows survive unhealthy discovery (no clobber, no delete)", JSON.stringify(cfRows));
}

// ============ 3. malformed JSON page -> structured error, exit 2, no writes ============
{
  const r = runCase("case-3-malformed-json", {
    pages: { 1: ">>>> not json <<<<" },
    vcList: vcList(["vm1"]),
    seed: [],
  });
  check(r.status === 2, "exit 2 on malformed API JSON", `status=${r.status}`);
  check(have(r.stderr, "malformed JSON"), "stderr names malformed JSON", r.stderr.trim().slice(0, 200));
  check(have(r.stderr, "cf api routes?page=1&per_page=25"), "stderr identifies failing endpoint");
  const obs = query(r.dbPath, "SELECT count(*) c FROM observations");
  check(obs[0].c === 0, "no writes persisted (D1 untouched)");
  const leftover = fs.readdirSync(path.join(r.dir, "tmp")).filter((f) => f.startsWith("d1-registry-refresh-"));
  check(leftover.length === 0, "tmp scratch dir removed on fail() path");

  // vercel-side malformed JSON (CORR-002 parity): garbage from the teams endpoint
  const { buildCase, finalizeLogs, SCRIPT } = await import("./harness.mjs");
  const { spawnSync } = await import("node:child_process");
  const built = buildCase("case-3b-vercel-malformed-json", { pages: { 1: [] }, vcList: {}, seed: [] });
  fs.writeFileSync(path.join(built.dir, "vc-teams.json"), ">>>> vercel garbage <<<<");
  const resV = spawnSync("node", [SCRIPT], { env: built.env, encoding: "utf8", timeout: 120000 });
  finalizeLogs(built.dir);
  check(resV.status === 2, "exit 2 on malformed vercel JSON", `status=${resV.status}`);
  check((resV.stderr ?? "").includes("vercel api /v1/teams?limit=100: malformed JSON"), "vercel endpoint named in structured error", (resV.stderr ?? "").trim().slice(0, 200));
}

// ============ 4. per_page=0 empty page terminates (round-2 fix) ============
{
  const t0 = Date.now();
  const r = runCase("case-4-perpage0", {
    pages: { 1: '{"success":true,"data":{"routes":[],"per_page":0}}' },
    vcList: vcList(["vm1", "vm2"]),
    seed: [...vcSeed(["vm1", "vm2"]), ...VC_SEED_MODELS],
  });
  const wall = Date.now() - t0;
  check(r.status === 0, "exit 0 with per_page=0 empty list", `status=${r.status}`);
  check(wall < 15000, "terminates quickly (no page loop hang)", `${wall}ms`);
  check(have(r.stdout, "cf=0 vercel=2"), "summary cf=0 vercel=2", r.stdout.trim());
  const obs = query(r.dbPath, "SELECT details FROM observations WHERE metric='routes_refreshed'");
  check(obs.length === 1 && have(obs[0].details, "skipped=none"), "valid empty list stays healthy (not marked unhealthy)", obs[0]?.details);
}

// ============ 5. 100 full pages -> page cap marks unhealthy ============
{
  const pages = {};
  for (let i = 1; i <= 105; i++) pages[String(i)] = Array.from({ length: 25 }, (_, j) => `r${(i - 1) * 25 + j + 1}`);
  const r = runCase("case-5-pagecap", {
    pages, perPage: 25,
    vcList: vcList(["vm1", "vm2"]),
    seed: [...vcSeed(["vm1", "vm2"]), ...VC_SEED_MODELS],
  });
  check(r.status === 0, "exit 0 (cap -> unhealthy cf, vercel still written)", `status=${r.status}`);
  check(have(r.stdout, "cf=0 vercel=2"), "summary cf=0 vercel=2", r.stdout.trim());
  const argv = fs.readFileSync(r.curlLog, "utf8");
  check(have(argv, "routes?page=100&per_page=25"), "loop reached page 100");
  check(!argv.includes("routes?page=101"), "loop stopped at cap (no page 101)");
  const obsC5 = query(r.dbPath, "SELECT details FROM observations WHERE metric='routes_refreshed'");
  check(obsC5.length === 1 && have(obsC5[0].details, "skipped=cf"), "cap marks cf unhealthy in observation", obsC5[0]?.details);
}

// ============ 6. cycle-log false positive on non-model sink (round-2 fix) ============
{
  const r = runCase("case-6-cycle-sink", {
    pages: { 1: ["foo"] }, perPage: 25, details: { foo: { ladder: CF_DEFAULT_LADDER, opts: { sink: true } } },
    vcList: vcList(["vm1"]),
    seed: [...vcSeed(["vm1"]), VC_SEED_MODELS[0], VC_SEED_MODELS[1]],
  });
  check(!have(r.stderr, "ladder cycle detected"), "no spurious cycle log when walk breaks on non-model sink", r.stderr.trim().slice(0, 300));
  const ladder = query(r.dbPath, "SELECT provider, model FROM route_models WHERE gateway='cloudflare-ai-gateway' AND route='dynamic/foo' ORDER BY position");
  check(ladder.length === 2 && ladder[0].provider === "openai" && ladder[1].model === "claude-3-5-sonnet", "route ladder still captured through model nodes", JSON.stringify(ladder));
}

// ============ 7. cycle-log true positive on real cycle + dangling id (round-2 fix) ============
{
  const r = runCase("case-7-cycle-real", {
    pages: { 1: ["foo"] }, perPage: 25, details: { foo: { ladder: CF_DEFAULT_LADDER, opts: { cycle: true } } },
    vcList: vcList(["vm1"]),
    seed: [...vcSeed(["vm1"]), VC_SEED_MODELS[0], VC_SEED_MODELS[1]],
  });
  check(have(r.stderr, "ladder cycle detected at element m0"), "real cycle IS logged", r.stderr.trim().slice(0, 300));
  const ladder = query(r.dbPath, "SELECT provider, model FROM route_models WHERE gateway='cloudflare-ai-gateway' AND route='dynamic/foo' ORDER BY position");
  check(ladder.length === 2, "walk terminated (ladder trimmed, no hang)", JSON.stringify(ladder));
  const r2 = runCase("case-7b-dangling", {
    pages: { 1: ["foo2"] }, perPage: 25, details: { foo2: { ladder: CF_DEFAULT_LADDER, opts: { dangling: true } } },
    vcList: vcList(["vm1"]),
    seed: [...vcSeed(["vm1"]), VC_SEED_MODELS[0], VC_SEED_MODELS[1]],
  });
  check(!have(r2.stderr, "ladder cycle detected"), "no false positive on dangling elementId", r2.stderr.trim().slice(0, 300));
}

// ============ 8. vercel slug fetch failure -> unhealthy -> vercel writes skipped ============
{
  const r = runCase("case-8-slug-fail", {
    pages: { 1: ["alpha"] }, perPage: 25, details: { alpha: { ladder: CF_DEFAULT_LADDER } },
    vcList: {}, vcSlugs: { good: vcVm("good", ["anthropic/claude-3.5-sonnet"]) },
    failUrls: "bad",
    seed: [...cfSeed(["alpha"]),
      ...vcSeed(["good", "bad"])],
  });
  check(have(r.stderr, "vercel slug fetch failed: bad"), "slug failure counted and logged", r.stderr.trim().slice(0, 300));
  check(have(r.stdout, "cf=1 vercel=0"), "summary cf=1 vercel=0", r.stdout.trim());
  const vcRows = query(r.dbPath, "SELECT route FROM routes WHERE gateway='vercel-ai-gateway' ORDER BY route");
  check(vcRows.length === 2, "stored vercel routes untouched (no clobber)", JSON.stringify(vcRows));
  const obs = query(r.dbPath, "SELECT details FROM observations WHERE metric='routes_refreshed'");
  check(obs.length === 1 && have(obs[0].details, "skipped=vercel"), "observation records skipped=vercel", obs[0]?.details);
}

// ============ 9. both gateways unhealthy -> refuse all writes, exit 2 ============
{
  const r = runCase("case-9-both-unhealthy", {
    pages: { 1: '{"success":true,"data":{}}' },
    vcList: {}, vcSlugs: {}, failUrls: "",
    seed: [...vcSeed(["good", "bad"])],
  });
  check(r.status === 2, "exit 2 when both gateways unhealthy", `status=${r.status}`);
  check(have(r.stderr, "both gateways reported unhealthy discovery; refusing all writes"), "stderr refuses writes");
  const obs = query(r.dbPath, "SELECT count(*) c FROM observations");
  check(obs[0].c === 0, "D1 untouched when both unhealthy");
}

const failed = results.filter((x) => !x.pass);
console.log(`\n==== ${results.length - failed.length}/${results.length} harness assertions passed ====`);
if (failed.length) {
  console.log("FAILED:");
  for (const f of failed) console.log(` - ${f.label} ${f.detail}`);
}
process.exit(failed.length ? 1 : 0);