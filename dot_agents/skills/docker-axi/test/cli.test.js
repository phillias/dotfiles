import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

const root = path.resolve(import.meta.dirname, "..");
const cli = path.join(root, "bin", "docker-axi.js");

function tempWorkspace() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "docker-axi-"));
}

function makeFakeBin(workspace, handlers = {}) {
  const bin = path.join(workspace, "bin");
  fs.mkdirSync(bin, { recursive: true });
  for (const name of ["docker", "docker-compose"]) {
    const script = handlers[name] ?? defaultFake(name);
    const file = path.join(bin, name);
    fs.writeFileSync(file, script);
    fs.chmodSync(file, 0o755);
  }
  return bin;
}

function defaultFake(name) {
  if (name === "docker-compose") {
    return `#!/bin/sh
case "$1" in
  version) echo '2.39.2-legacy' ;;
  *) echo 'docker-compose ok' ;;
esac
`;
  }
  return `#!/bin/sh
if [ "$1" = "compose" ] && [ "$2" = "-f" ] && [ "$4" = "config" ]; then
  echo 'web'
  echo 'db'
  exit 0
fi
case "$1 $2" in
  "version --format") echo '{"Client":{"Version":"28.3.3","Context":"desktop-linux"},"Server":{"Version":"28.3.3"}}' ;;
  "context show") echo 'desktop-linux' ;;
  "compose version") echo '2.39.2' ;;
  "compose config") echo 'web'; echo 'db' ;;
  "system df") echo 'TYPE TOTAL ACTIVE SIZE RECLAIMABLE'; echo 'Images 2 1 100MB 20MB' ;;
  "buildx version") echo 'github.com/docker/buildx v0.20.0' ;;
  "ps -a") echo '{"ID":"abc123","Names":"web","Image":"app:local","State":"running","Status":"Up 2 minutes","Ports":"0.0.0.0:8080->8080/tcp"}'; echo '{"ID":"def456","Names":"db","Image":"postgres:16","State":"exited","Status":"Exited (0)"}' ;;
  "images -q") echo 'img1'; echo 'img2' ;;
  "images --format") echo '{"ID":"img1","Repository":"app","Tag":"local","Size":"100MB","CreatedSince":"1 hour ago"}' ;;
  "volume ls") echo 'vol1' ;;
  "network ls") echo 'net1'; echo 'net2' ;;
  "logs --tail") echo 'TOKEN=supersecret'; printf 'x%.0s' $(seq 1 1800); echo ;;
  "inspect web") echo '[{"Name":"/web","Config":{"Image":"app:local","Labels":{"PASSWORD":"secret","com.example":"ok"}},"State":{"Status":"running"},"NetworkSettings":{"Ports":{"8080/tcp":[{"HostPort":"8080"}]}}}]' ;;
  "volume inspect") echo '[{"Name":"vol1","Driver":"local","Mountpoint":"/var/lib/docker/volumes/vol1/_data"}]' ;;
  "network inspect") echo '[{"Name":"net1","Driver":"bridge","Scope":"local"}]' ;;
  "build -f") echo 'built image' ;;
  "run --rm") echo 'container started' ;;
  "exec web") echo 'exec output' ;;
  "container prune") echo 'Deleted Containers: abc123' ;;
  "image prune") echo 'Deleted Images: img1' ;;
  "builder prune") echo 'Deleted build cache' ;;
  *) echo "docker ok $*" ;;
esac
`;
}

function run(args, options = {}) {
  const cwd = options.cwd ?? tempWorkspace();
  const env = { ...process.env, ...(options.env ?? {}) };
  return spawnSync(cli, args, { cwd, env, encoding: "utf8" });
}

test("home view shows live Docker context and no help-first output", () => {
  const cwd = tempWorkspace();
  const fakeBin = makeFakeBin(cwd);
  fs.writeFileSync(path.join(cwd, "Dockerfile"), "FROM node:24\nEXPOSE 8080\nHEALTHCHECK CMD node health.js\nUSER node\n");
  const result = run([], { cwd, env: { PATH: `${fakeBin}${path.delimiter}${process.env.PATH}` } });

  assert.equal(result.status, 0);
  assert.match(result.stdout, /^bin: /);
  assert.match(result.stdout, /description: "Operate Docker apps/);
  assert.match(result.stdout, /daemon: ok/);
  assert.match(result.stdout, /context: desktop-linux/);
  assert.match(result.stdout, /running_containers: 1/);
  assert.match(result.stdout, /targets\[1\]{id,type,source,detail}:/);
  assert.doesNotMatch(result.stdout, /^usage:/);
  assert.equal(result.stderr, "");
});

test("services include Docker capability domains", () => {
  const result = run(["services"]);
  assert.equal(result.status, 0);
  assert.match(result.stdout, /build/);
  assert.match(result.stdout, /compose/);
  assert.match(result.stdout, /registry/);
  assert.match(result.stdout, /cleanup/);
});

test("discover detects Dockerfile, compose, package app, and devcontainer fixtures", () => {
  const cwd = tempWorkspace();
  fs.mkdirSync(path.join(cwd, "api"));
  fs.mkdirSync(path.join(cwd, ".devcontainer"));
  fs.writeFileSync(path.join(cwd, "api", "Dockerfile"), "FROM node:24\nEXPOSE 3000\n");
  fs.writeFileSync(path.join(cwd, "docker-compose.yml"), "services:\n  web:\n    build: .\n  db:\n    image: postgres:16\n");
  fs.writeFileSync(path.join(cwd, ".devcontainer", "devcontainer.json"), JSON.stringify({ dockerComposeFile: "../docker-compose.yml", service: "web" }));
  fs.writeFileSync(path.join(cwd, "package.json"), JSON.stringify({ scripts: { start: "node server.js" }, dependencies: { express: "latest" } }));
  const result = run(["discover", "--full"], { cwd });

  assert.equal(result.status, 0);
  assert.match(result.stdout, /dockerfile:api/);
  assert.match(result.stdout, /compose:docker-compose.yml/);
  assert.match(result.stdout, /compose:docker-compose.yml:web/);
  assert.match(result.stdout, /devcontainer:\.devcontainer\/devcontainer\.json/);
  assert.match(result.stdout, /package:node-app/);
});

test("unknown flags fail before calling Docker", () => {
  const cwd = tempWorkspace();
  const fakeBin = makeFakeBin(cwd, {
    docker: "#!/bin/sh\necho called >> docker-called\nexit 0\n"
  });
  const result = run(["discover", "--stat"], { cwd, env: { PATH: `${fakeBin}${path.delimiter}${process.env.PATH}` } });

  assert.equal(result.status, 2);
  assert.match(result.stdout, /error: unknown flag --stat for `discover`/);
  assert.equal(fs.existsSync(path.join(cwd, "docker-called")), false);
});

test("missing required flags return structured usage errors", () => {
  const result = run(["logs"]);
  assert.equal(result.status, 2);
  assert.match(result.stdout, /error: --container is required/);
  assert.match(result.stdout, /help\[1\]:/);
});

test("recommend returns compact paths for CI", () => {
  const result = run(["recommend", "--goal", "ci"]);
  assert.equal(result.status, 0);
  assert.match(result.stdout, /paths\[3\]{id,pattern,fit,command}:/);
  assert.match(result.stdout, /ci-build/);
  assert.match(result.stdout, /ci-publish/);
});

test("plan previews compose targets without mutation", () => {
  const cwd = tempWorkspace();
  const fakeBin = makeFakeBin(cwd);
  fs.writeFileSync(path.join(cwd, "docker-compose.yml"), "services:\n  web:\n    image: app\n");
  const result = run(["plan", "--target", "compose:docker-compose.yml", "--environment", "local"], { cwd, env: { PATH: `${fakeBin}${path.delimiter}${process.env.PATH}` } });

  assert.equal(result.status, 0);
  assert.match(result.stdout, /command: docker compose -f .*docker-compose.yml config --services/);
  assert.match(result.stdout, /preview:/);
  assert.match(result.stdout, /web/);
});

test("build is dry-run by default and executes only with --execute", () => {
  const cwd = tempWorkspace();
  const fakeBin = makeFakeBin(cwd, {
    docker: `${defaultFake("docker")}\n`
  });
  fs.writeFileSync(path.join(cwd, "Dockerfile"), "FROM alpine\n");

  const dryRun = run(["build", "--target", "dockerfile:root", "--tag", "app:test"], { cwd, env: { PATH: `${fakeBin}${path.delimiter}${process.env.PATH}` } });
  assert.equal(dryRun.status, 0);
  assert.match(dryRun.stdout, /dry_run: true/);
  assert.match(dryRun.stdout, /docker build/);

  const executed = run(["build", "--target", "dockerfile:root", "--tag", "app:test", "--execute"], { cwd, env: { PATH: `${fakeBin}${path.delimiter}${process.env.PATH}` } });
  assert.equal(executed.status, 0);
  assert.match(executed.stdout, /dry_run: false/);
  assert.match(executed.stdout, /built image/);
});

test("run and compose commands are dry-run by default", () => {
  const cwd = tempWorkspace();
  const fakeBin = makeFakeBin(cwd);
  fs.writeFileSync(path.join(cwd, "Dockerfile"), "FROM alpine\n");
  fs.writeFileSync(path.join(cwd, "docker-compose.yml"), "services:\n  web:\n    image: app\n");

  const runResult = run(["run", "--target", "dockerfile:root", "--name", "app", "--ports", "8080:8080", "--env-file", ".env"], { cwd, env: { PATH: `${fakeBin}${path.delimiter}${process.env.PATH}` } });
  assert.equal(runResult.status, 0);
  assert.match(runResult.stdout, /dry_run: true/);
  assert.match(runResult.stdout, /--env-file/);
  assert.doesNotMatch(runResult.stdout, /supersecret/);

  const composeResult = run(["compose", "up", "--file", "docker-compose.yml", "--service", "web"], { cwd, env: { PATH: `${fakeBin}${path.delimiter}${process.env.PATH}` } });
  assert.equal(composeResult.status, 0);
  assert.match(composeResult.stdout, /compose_up:/);
  assert.match(composeResult.stdout, /dry_run: true/);
});

test("cleanup requires explicit execution guard", () => {
  const cwd = tempWorkspace();
  const fakeBin = makeFakeBin(cwd);
  const dryRun = run(["clean", "--kind", "containers"], { cwd, env: { PATH: `${fakeBin}${path.delimiter}${process.env.PATH}` } });
  assert.equal(dryRun.status, 0);
  assert.match(dryRun.stdout, /dry_run: true/);
  assert.match(dryRun.stdout, /docker container prune -f/);

  const executed = run(["clean", "--kind", "containers", "--execute"], { cwd, env: { PATH: `${fakeBin}${path.delimiter}${process.env.PATH}` } });
  assert.equal(executed.status, 0);
  assert.match(executed.stdout, /dry_run: false/);
  assert.match(executed.stdout, /Deleted Containers/);
});

test("ps and images render compact TOON tables", () => {
  const cwd = tempWorkspace();
  const fakeBin = makeFakeBin(cwd);
  const env = { PATH: `${fakeBin}${path.delimiter}${process.env.PATH}` };

  const psResult = run(["ps"], { cwd, env });
  assert.equal(psResult.status, 0);
  assert.match(psResult.stdout, /containers\[2\]{id,name,image,state}:/);

  const imageResult = run(["images"], { cwd, env });
  assert.equal(imageResult.status, 0);
  assert.match(imageResult.stdout, /images\[1\]{id,repository,tag,size}:/);
});

test("logs truncate and redact secret-looking content by default", () => {
  const cwd = tempWorkspace();
  const fakeBin = makeFakeBin(cwd);
  const result = run(["logs", "--container", "web"], { cwd, env: { PATH: `${fakeBin}${path.delimiter}${process.env.PATH}` } });

  assert.equal(result.status, 0);
  assert.match(result.stdout, /TOKEN=<redacted>/);
  assert.doesNotMatch(result.stdout, /supersecret/);
  assert.match(result.stdout, /truncated/);
  assert.match(result.stdout, /--full/);
});

test("inspect summarizes and redacts labels", () => {
  const cwd = tempWorkspace();
  const fakeBin = makeFakeBin(cwd);
  const result = run(["inspect", "--kind", "container", "--id", "web"], { cwd, env: { PATH: `${fakeBin}${path.delimiter}${process.env.PATH}` } });

  assert.equal(result.status, 0);
  assert.match(result.stdout, /state: running/);
  assert.match(result.stdout, /PASSWORD/);
  assert.doesNotMatch(result.stdout, /secret/);
});

test("exec is dry-run by default and non-interactive", () => {
  const cwd = tempWorkspace();
  const fakeBin = makeFakeBin(cwd);
  const dryRun = run(["exec", "--container", "web", "--cmd", "node", "--version"], { cwd, env: { PATH: `${fakeBin}${path.delimiter}${process.env.PATH}` } });
  assert.equal(dryRun.status, 0);
  assert.match(dryRun.stdout, /dry_run: true/);
  assert.match(dryRun.stdout, /docker exec web node --version/);

  const executed = run(["exec", "--container", "web", "--cmd", "echo ok", "--execute"], { cwd, env: { PATH: `${fakeBin}${path.delimiter}${process.env.PATH}` } });
  assert.equal(executed.status, 0);
  assert.match(executed.stdout, /exec output/);
});

test("doctor reports missing Docker CLI without crashing", () => {
  const cwd = tempWorkspace();
  const result = run(["doctor"], { cwd, env: { PATH: path.dirname(process.execPath) } });
  assert.equal(result.status, 0);
  assert.match(result.stdout, /docker-cli,missing/);
  assert.match(result.stdout, /summary: attention-required/);
});

test("skill generate check fails when stale and passes after generation", () => {
  const cwd = tempWorkspace();
  const stale = run(["skill", "generate", "--check"], { cwd });
  assert.equal(stale.status, 1);
  assert.match(stale.stdout, /generated skill is stale or missing/);

  const generated = run(["skill", "generate"], { cwd });
  assert.equal(generated.status, 0);
  assert.equal(fs.existsSync(path.join(cwd, "SKILL.md")), true);

  const checked = run(["skill", "generate", "--check"], { cwd });
  assert.equal(checked.status, 0);
  assert.equal(checked.stdout, "skill: up-to-date");
});

test("optional live Docker doctor is gated behind DOCKER_AXI_LIVE_TESTS", { skip: process.env.DOCKER_AXI_LIVE_TESTS !== "1" }, () => {
  const result = run(["doctor"], { env: process.env });
  assert.equal(result.status, 0);
  assert.match(result.stdout, /checks\[/);
});
