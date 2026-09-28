#!/usr/bin/env node
// case-10: uncaught write error (EFBIG via ulimit -f) -> token-bearing scratch dir
// must still be cleaned up by the process 'exit' handler (round-2 fix).
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { buildCase, finalizeLogs, query, vcVm, SCRIPT, BIN_ROOTS } from "./harness.mjs";

const ok = [];
const check = (cond, label, detail = "") => {
  ok.push(!!cond);
  console.log(`${cond ? "PASS" : "FAIL"}: ${label}${detail ? ` — ${detail}` : ""}`);
};

// small healthy case: 2 CF routes + 2 vercel vms
const { dir, env, errPath } = buildCase("case-10-uncaught-cleanup", {
  pages: { 1: ["alpha", "beta"] },
  details: {
    alpha: { ladder: ["openai/gpt-4o", "anthropic/claude-3-5-sonnet"] },
    beta: { ladder: ["anthropic/claude-3-5-sonnet"] },
  },
  vcList: { virtualModelConfigs: [vcVm("vm1", ["anthropic/claude-3.5-sonnet"])] },
  seed: [],
});

// ulimit -f 1 (1KB per file): header files (~52B) pass, first SQL chunk (~2KB) hits EFBIG -> uncaught
const res = spawnSync("bash", ["-c", `ulimit -f 1; exec node "$0"`, SCRIPT], { env, encoding: "utf8", timeout: 180000 });
fs.writeFileSync(errPath, res.stderr ?? "");
fs.writeFileSync(path.join(dir, "stdout.txt"), res.stdout ?? "");
finalizeLogs(dir);
console.log(`exit=${res.status}`);

check(res.status === 1, "uncaught exception exits non-zero (node exit 1)", `status=${res.status}`);
check((res.stderr ?? "").includes("File too large") || (res.stderr ?? "").includes("EFBIG") || (res.stderr ?? "").includes("size limit"), "stderr shows the write error", (res.stderr ?? "").trim().split("\n")[0].slice(0, 160));
const leftovers = fs.readdirSync(path.join(dir, "tmp")).filter((f) => f.startsWith("d1-registry-refresh-"));
check(leftovers.length === 0, "token-bearing scratch dir removed despite uncaught error", JSON.stringify(leftovers));
const failedSql = path.join(dir, ".local/state/opencode-fleet/d1-registry-refresh-failed.sql");
check(!fs.existsSync(failedSql), "no failed.sql planted (throw predates the copy path)");
const obsCount = query(path.join(dir, "db.sqlite"), "SELECT count(*) c FROM observations");
check(obsCount[0].c === 0, "no D1 writes happened before the crash");

console.log(`\n==== ${ok.filter(Boolean).length}/${ok.length} case-10 assertions passed ====`);
process.exit(ok.every(Boolean) ? 0 : 1);