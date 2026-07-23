#!/bin/sh
':' //; exec node -- "$0" "$@"
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { spawnSync } from "node:child_process";

const DESCRIPTION = "Operate Docker apps through safe build, run, debug, publish, and cleanup AXI workflows";
const VERSION = "0.1.0";
const PREVIEW_LIMIT = 1200;
const LOG_LIMIT = 1500;
const GLOBAL_VALUE_FLAGS = new Set(["--cwd"]);
const GLOBAL_BOOLEAN_FLAGS = new Set(["--help"]);

const COMMANDS = {
  home: { value: new Set(), boolean: new Set(["--help"]), help: helpHome },
  doctor: { value: new Set(), boolean: new Set(["--help"]), help: helpDoctor },
  services: { value: new Set(["--capability", "--fields"]), boolean: new Set(["--help"]), help: helpServices },
  discover: { value: new Set(["--fields"]), boolean: new Set(["--full", "--help"]), help: helpDiscover },
  recommend: { value: new Set(["--goal"]), boolean: new Set(["--help"]), help: helpRecommend },
  plan: { value: new Set(["--target", "--environment", "--tag"]), boolean: new Set(["--full", "--help"]), help: helpPlan },
  apply: { value: new Set(["--target", "--environment", "--tag"]), boolean: new Set(["--execute", "--full", "--help"]), help: helpApply },
  build: { value: new Set(["--target", "--tag"]), boolean: new Set(["--execute", "--help"]), help: helpBuild },
  run: { value: new Set(["--target", "--name", "--ports", "--env-file"]), boolean: new Set(["--execute", "--help"]), help: helpRun },
  "compose up": { value: new Set(["--file", "--service"]), boolean: new Set(["--execute", "--help"]), help: helpComposeUp },
  "compose down": { value: new Set(["--file"]), boolean: new Set(["--execute", "--help"]), help: helpComposeDown },
  ps: { value: new Set(["--fields"]), boolean: new Set(["--help"]), help: helpPs },
  images: { value: new Set(["--fields"]), boolean: new Set(["--help"]), help: helpImages },
  logs: { value: new Set(["--container", "--tail"]), boolean: new Set(["--full", "--help"]), help: helpLogs },
  inspect: { value: new Set(["--kind", "--id"]), boolean: new Set(["--full", "--help"]), help: helpInspect },
  exec: { value: new Set(["--container", "--cmd"]), rest: "--cmd", boolean: new Set(["--execute", "--help"]), help: helpExec },
  clean: { value: new Set(["--kind"]), boolean: new Set(["--execute", "--help"]), help: helpClean },
  "hooks install": { value: new Set(["--agent", "--scope"]), boolean: new Set(["--execute", "--help"]), help: helpHooksInstall },
  "skill generate": { value: new Set(["--output"]), boolean: new Set(["--check", "--help"]), help: helpSkillGenerate }
};

const SERVICE_DOMAINS = [
  { capability: "build", domain: "Dockerfile|BuildKit|multi-stage", use: "build images safely with redacted build args" },
  { capability: "runtime", domain: "containers|ports|env-files|healthchecks", use: "run app containers without leaking env values" },
  { capability: "compose", domain: "compose files|services|profiles|depends_on", use: "inspect and operate multi-service local stacks" },
  { capability: "registry", domain: "tags|login-status|push|pull", use: "plan Docker Hub GHCR and ECR-compatible publishing" },
  { capability: "debugging", domain: "logs|inspect|exec|events|stats", use: "debug containers with truncation and redaction" },
  { capability: "storage-networking", domain: "volumes|bind-mounts|networks", use: "inspect storage and networking blast radius" },
  { capability: "cleanup", domain: "container|image|volume|network|builder-cache prune", use: "preview destructive cleanup before execution" },
  { capability: "security", domain: "non-root|secrets|ports|image-size|sbom", use: "surface safety hints and optional scout hooks" },
  { capability: "local-dev", domain: "devcontainers|compose dev stacks", use: "orient local development environments" },
  { capability: "ci-cd", domain: "build|tag|publish planning", use: "prepare safe CI build and registry workflows" }
];

const RECOMMENDATIONS = {
  web: [
    ["dockerfile-web", "Dockerfile + EXPOSE", "best for a single web image", "docker-axi discover"],
    ["compose-web", "compose service + port", "best for local web plus dependencies", "docker-axi compose up --file docker-compose.yml"],
    ["registry-web", "tag + push plan", "best for deployment pipelines", "docker-axi plan --target <id> --environment ci"]
  ],
  api: [
    ["api-image", "Dockerfile + healthcheck", "best for long-running API containers", "docker-axi build --target <id> --tag api:local"],
    ["api-compose", "compose api + database", "best for integration testing", "docker-axi compose up --file docker-compose.yml --service api"],
    ["api-publish", "GHCR/ECR-compatible tag", "best for CI deployment", "docker-axi plan --target <id> --environment ci"]
  ],
  worker: [
    ["worker-image", "Dockerfile no public port", "best for queue workers", "docker-axi build --target <id>"],
    ["worker-compose", "compose worker + broker", "best for local job stacks", "docker-axi discover"],
    ["worker-logs", "logs + inspect", "best for debugging worker exits", "docker-axi logs --container <name>"]
  ],
  database: [
    ["compose-db", "compose managed database", "best for local databases", "docker-axi compose up --file docker-compose.yml --service db"],
    ["volume-review", "named volumes", "best before cleanup or reset", "docker-axi inspect --kind volume --id <name>"],
    ["network-review", "compose networks", "best for dependency debugging", "docker-axi services --capability storage-networking"]
  ],
  fullstack: [
    ["fullstack-compose", "web|api|db services", "best for local fullstack apps", "docker-axi discover"],
    ["fullstack-build", "multi-image build plan", "best for CI preflight", "docker-axi plan --target <id> --environment ci"],
    ["fullstack-debug", "ps|logs|inspect", "best after startup failures", "docker-axi ps"]
  ],
  "local-dev": [
    ["devcontainer", ".devcontainer config", "best for agent-ready dev environments", "docker-axi discover"],
    ["compose-dev", "compose profiles", "best for repeatable local stacks", "docker-axi compose up --file docker-compose.yml"],
    ["cleanup-preview", "dry-run cleanup", "best before reclaiming disk", "docker-axi clean --kind builder-cache"]
  ],
  ci: [
    ["ci-build", "docker build with tag", "best for image build jobs", "docker-axi build --target <id> --tag <registry>/<image>:<sha>"],
    ["ci-publish", "registry push plan", "best for release jobs", "docker-axi plan --target <id> --environment ci"],
    ["ci-compose", "compose config validation", "best for service test jobs", "docker-axi compose up --file docker-compose.yml"]
  ]
};

main();

function main() {
  const commandInfo = resolveCommand(process.argv.slice(2));
  const config = COMMANDS[commandInfo.command];
  if (!config) usageError(`unknown command ${toonScalar(commandInfo.command)}`, ["Run `docker-axi --help` for available commands"]);
  const parsed = parseArgs(commandInfo.command, commandInfo.args, config);
  if (parsed.flags.help) {
    print(config.help());
    return;
  }
  const context = buildContext(parsed.flags);
  const handlers = {
    home,
    doctor,
    services,
    discover,
    recommend,
    plan,
    apply,
    build,
    run: runContainer,
    "compose up": composeUp,
    "compose down": composeDown,
    ps,
    images,
    logs,
    inspect,
    exec: execContainer,
    clean,
    "hooks install": hooksInstall,
    "skill generate": skillGenerate
  };
  handlers[commandInfo.command](parsed, context);
}

function resolveCommand(args) {
  if (args.length === 0 || args[0].startsWith("--")) return { command: "home", args };
  if (["compose", "hooks", "skill"].includes(args[0]) && args[1] && !args[1].startsWith("--")) {
    return { command: `${args[0]} ${args[1]}`, args: args.slice(2) };
  }
  return { command: args[0], args: args.slice(1) };
}

function parseArgs(command, args, config) {
  const valueFlags = new Set([...GLOBAL_VALUE_FLAGS, ...config.value]);
  const booleanFlags = new Set([...GLOBAL_BOOLEAN_FLAGS, ...config.boolean]);
  const flags = {};
  const positional = [];

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith("--")) {
      positional.push(arg);
      continue;
    }
    const [rawName, inlineValue] = arg.split("=", 2);
    if (!valueFlags.has(rawName) && !booleanFlags.has(rawName)) {
      usageError(`unknown flag ${rawName} for \`${command}\``, [`valid flags for \`${command}\`: ${validFlags(valueFlags, booleanFlags)}`]);
    }
    if (booleanFlags.has(rawName)) {
      if (inlineValue !== undefined) usageError(`${rawName} does not take a value`, [`Run \`docker-axi ${command} --help\` for examples`]);
      flags[flagName(rawName)] = true;
      continue;
    }
    if (config.rest === rawName) {
      const restParts = inlineValue !== undefined ? [inlineValue] : [];
      if (inlineValue === undefined) {
        for (let restIndex = index + 1; restIndex < args.length; restIndex += 1) {
          const next = args[restIndex];
          if (next === "--execute" || next === "--help") {
            flags[flagName(next)] = true;
            continue;
          }
          if (next === "--cwd") {
            const cwdValue = args[restIndex + 1];
            if (!cwdValue || cwdValue.startsWith("--")) usageError("--cwd requires a value", [`Run \`docker-axi ${command} --help\` for examples`]);
            flags.cwd = cwdValue;
            restIndex += 1;
            continue;
          }
          if (next.startsWith("--cwd=")) {
            flags.cwd = next.slice("--cwd=".length);
            continue;
          }
          restParts.push(next);
        }
      }
      const restValue = restParts.join(" ");
      if (!restValue) usageError(`${rawName} requires a value`, [`Run \`docker-axi ${command} --help\` for examples`]);
      flags[flagName(rawName)] = restValue;
      index = args.length;
      continue;
    }
    const value = inlineValue ?? args[index + 1];
    if (value === undefined || value.startsWith("--")) usageError(`${rawName} requires a value`, [`Run \`docker-axi ${command} --help\` for examples`]);
    flags[flagName(rawName)] = value;
    if (inlineValue === undefined) index += 1;
  }
  if (positional.length > 0) usageError(`unexpected argument ${toonScalar(positional[0])} for \`${command}\``, [`Run \`docker-axi ${command} --help\` for examples`]);
  return { flags, positional };
}

function validFlags(valueFlags, booleanFlags) {
  return [...new Set([...valueFlags, ...booleanFlags])].sort().join(", ");
}

function flagName(rawName) {
  return rawName.slice(2).replaceAll("-", "_");
}

function buildContext(flags) {
  return { cwd: path.resolve(flags.cwd ?? process.cwd()) };
}

function home(_parsed, context) {
  const state = dockerState(context);
  const targets = discoverTargets(context);
  const rows = targets.slice(0, 8).map((target) => ({ id: target.id, type: target.type, source: displayPath(target.path, context.cwd), detail: target.detail ?? target.reason ?? "" }));
  const lines = [
    `bin: ${toonScalar(collapseHome(process.argv[1]))}`,
    `description: ${toonScalar(DESCRIPTION)}`,
    `version: ${VERSION}`,
    "docker:",
    `  cli: ${state.cli}`,
    `  daemon: ${state.daemon}`,
    `  context: ${toonScalar(state.context)}`,
    `  compose: ${state.compose}`,
    "counts:",
    `  running_containers: ${state.running}`,
    `  stopped_containers: ${state.stopped}`,
    `  images: ${state.images}`,
    `  volumes: ${state.volumes}`,
    `  networks: ${state.networks}`,
    `targets_count: ${targets.length}`
  ];
  if (rows.length === 0) lines.push("targets: 0 Docker targets detected in this workspace");
  else lines.push(formatTable("targets", rows, ["id", "type", "source", "detail"]));
  const help = ["Run `docker-axi doctor` to check Docker readiness", "Run `docker-axi discover --full` to inspect Docker targets"];
  if (targets.length > 0) help.push("Run `docker-axi plan --target <id> --environment <name>` before mutating");
  else help.push("Run `docker-axi recommend --goal fullstack` to choose a Docker path");
  lines.push(formatHelp(help));
  print(lines.join("\n"));
}

function doctor(_parsed, context) {
  const dockerPath = findExecutable("docker");
  const compose = composeInfo(context);
  const version = dockerPath ? runDocker(["version", "--format", "{{json .}}"], context) : { status: 127, stdout: "", stderr: "docker not found" };
  const disk = dockerPath ? runDocker(["system", "df"], context) : { status: 127, stdout: "", stderr: "" };
  const registry = registryStatus();
  const rows = [
    { check: "docker-cli", status: dockerPath ? "ok" : "missing", detail: dockerPath ? collapseHome(dockerPath) : "install Docker CLI" },
    { check: "daemon", status: version.status === 0 ? "ok" : "error", detail: version.status === 0 ? "reachable" : truncate(sanitize(version.stderr || version.stdout || "daemon unavailable"), 160).text },
    { check: "context", status: dockerPath ? "ok" : "missing", detail: dockerPath ? dockerContext(context) : "unavailable" },
    { check: "compose", status: compose.available ? "ok" : "missing", detail: compose.detail },
    { check: "buildkit", status: buildkitStatus(context).status, detail: buildkitStatus(context).detail },
    { check: "registry-auth", status: registry.status, detail: registry.detail },
    { check: "disk-usage", status: disk.status === 0 ? "ok" : "unknown", detail: disk.status === 0 ? truncate(sanitize(disk.stdout), 120).text : "run docker system df" }
  ];
  print([
    `summary: ${dockerPath && version.status === 0 ? "ready" : "attention-required"}`,
    formatTable("checks", rows, ["check", "status", "detail"]),
    formatHelp(["Run `docker-axi discover` to list Docker targets", "Run `docker-axi services` to inspect supported Docker domains"])
  ].join("\n"));
}

function services(parsed) {
  const fields = parseFields(parsed.flags.fields, ["capability", "domain", "use"], ["capability", "domain", "use"]);
  const rows = SERVICE_DOMAINS.filter((row) => !parsed.flags.capability || row.capability === parsed.flags.capability).map((row) => pick(row, fields));
  const lines = [`count: ${rows.length} of ${SERVICE_DOMAINS.length} Docker domains`];
  if (rows.length === 0) lines.push(`services: 0 Docker domains found for ${toonScalar(parsed.flags.capability)}`);
  else lines.push(formatTable("services", rows, fields));
  lines.push(formatHelp(["Run `docker-axi recommend --goal <web|api|worker|database|fullstack|local-dev|ci>` for workflow paths"]));
  print(lines.join("\n"));
}

function discover(parsed, context) {
  const fields = parseFields(parsed.flags.fields, ["id", "type", "source", "detail"], ["id", "type", "source", "detail", "ports", "healthcheck", "services", "reason"]);
  const targets = discoverTargets(context);
  const rows = targets.map((target) => {
    const row = { ...target, source: displayPath(target.path, context.cwd) };
    if (!parsed.flags.full) {
      row.reason = truncate(row.reason ?? "", 120).text;
      row.detail = truncate(row.detail ?? "", 120).text;
    }
    return pick(row, fields);
  });
  const lines = [`count: ${rows.length} Docker targets detected`];
  if (rows.length === 0) lines.push("targets: 0 Docker targets detected in this workspace");
  else lines.push(formatTable("targets", rows, fields));
  lines.push(formatHelp(["Run `docker-axi plan --target <id> --environment <name>` before mutating", "Run `docker-axi recommend --goal fullstack` if no target matches the app"]));
  print(lines.join("\n"));
}

function recommend(parsed) {
  const goal = parsed.flags.goal;
  if (!goal) usageError("--goal is required", ["Run `docker-axi recommend --goal <web|api|worker|database|fullstack|local-dev|ci>`"]);
  const rows = RECOMMENDATIONS[goal];
  if (!rows) usageError(`unknown goal ${toonScalar(goal)}`, ["valid goals: web, api, worker, database, fullstack, local-dev, ci"]);
  print([
    `goal: ${goal}`,
    formatTable("paths", rows.map(([id, pattern, fit, command]) => ({ id, pattern, fit, command })), ["id", "pattern", "fit", "command"]),
    formatHelp(["Run the suggested command for the path that best matches the app"])
  ].join("\n"));
}

function plan(parsed, context) {
  const target = requireTarget(parsed, context);
  const environment = parsed.flags.environment ?? "local";
  print(buildPlan(target, environment, parsed.flags, context));
}

function apply(parsed, context) {
  const target = requireTarget(parsed, context);
  const environment = parsed.flags.environment ?? "local";
  if (!parsed.flags.execute) {
    print([
      "apply:",
      "  dry_run: true",
      `  target: ${toonScalar(target.id)}`,
      `  environment: ${toonScalar(environment)}`,
      buildPlan(target, environment, parsed.flags, context),
      formatHelp([`Run \`docker-axi apply --target ${target.id} --environment ${environment} --execute\` to execute after review`])
    ].join("\n"));
    return;
  }
  const command = applyCommand(target, environment, parsed.flags);
  if (!command) runtimeError(`target ${toonScalar(target.id)} does not have an executable apply command`, ["Use `docker-axi build`, `docker-axi run`, or `docker-axi compose up` for this target"]);
  ensureDocker();
  const result = runCommand(command.cmd, command.args, commandContext(command, context));
  if (result.status !== 0) runtimeError("docker apply command failed", [sanitize(result.stderr || result.stdout || "Run `docker-axi doctor` and retry")]);
  print(["apply:", "  dry_run: false", `  target: ${toonScalar(target.id)}`, `  environment: ${toonScalar(environment)}`, `  command: ${toonScalar(formatCommand(command))}`, `  output: ${toonScalar(truncate(sanitize(result.stdout), PREVIEW_LIMIT).text)}`].join("\n"));
}

function build(parsed, context) {
  const target = requireTarget(parsed, context);
  if (target.type !== "dockerfile" && !target.commands?.build) usageError(`target ${toonScalar(target.id)} is not buildable`, ["Run `docker-axi discover` to find Dockerfile targets"]);
  const command = buildCommand(target, parsed.flags);
  if (!parsed.flags.execute) {
    print(["build:", "  dry_run: true", `  target: ${toonScalar(target.id)}`, `  command: ${toonScalar(formatCommand(command))}`, formatHelp([`Run \`docker-axi build --target ${target.id} --tag ${command.tag} --execute\` to build`])].join("\n"));
    return;
  }
  ensureDocker();
  const result = runCommand(command.cmd, command.args, commandContext(command, context));
  if (result.status !== 0) runtimeError("docker build failed", [sanitize(result.stderr || result.stdout || "Run `docker-axi doctor` and retry")]);
  print(["build:", "  dry_run: false", `  target: ${toonScalar(target.id)}`, `  tag: ${toonScalar(command.tag)}`, `  output: ${toonScalar(truncate(sanitize(result.stdout || result.stderr), PREVIEW_LIMIT).text)}`].join("\n"));
}

function runContainer(parsed, context) {
  const target = requireTarget(parsed, context);
  if (target.type === "compose" || target.type === "compose-service") usageError("compose targets should use `docker-axi compose up`", ["Run `docker-axi compose up --file <path> [--service <name>]`"]);
  const command = runTargetCommand(target, parsed.flags);
  if (!parsed.flags.execute) {
    print(["run:", "  dry_run: true", `  target: ${toonScalar(target.id)}`, `  command: ${toonScalar(formatCommand(command))}`, formatHelp(["Review env-file contents locally; docker-axi never prints env values", "Add `--execute` to run the container after review"])].join("\n"));
    return;
  }
  ensureDocker();
  const result = runCommand(command.cmd, command.args, context);
  if (result.status !== 0) runtimeError("docker run failed", [sanitize(result.stderr || result.stdout || "Run `docker-axi doctor` and retry")]);
  print(["run:", "  dry_run: false", `  target: ${toonScalar(target.id)}`, `  output: ${toonScalar(truncate(sanitize(result.stdout), PREVIEW_LIMIT).text)}`].join("\n"));
}

function composeUp(parsed, context) {
  const file = requireFileFlag(parsed, context);
  const command = composeCommand(context, ["-f", file, "up", "-d", ...(parsed.flags.service ? [parsed.flags.service] : [])]);
  if (!parsed.flags.execute) {
    print(["compose_up:", "  dry_run: true", `  file: ${toonScalar(displayPath(file, context.cwd))}`, `  service: ${toonScalar(parsed.flags.service ?? "all")}`, `  command: ${toonScalar(formatCommand(command))}`, formatHelp(["Add `--execute` to start the compose stack after review"])].join("\n"));
    return;
  }
  const result = runCommand(command.cmd, command.args, context);
  if (result.status !== 0) runtimeError("docker compose up failed", [sanitize(result.stderr || result.stdout || "Run `docker-axi doctor` and retry")]);
  print(["compose_up:", "  dry_run: false", `  output: ${toonScalar(truncate(sanitize(result.stdout), PREVIEW_LIMIT).text)}`].join("\n"));
}

function composeDown(parsed, context) {
  const file = requireFileFlag(parsed, context);
  const command = composeCommand(context, ["-f", file, "down"]);
  if (!parsed.flags.execute) {
    print(["compose_down:", "  dry_run: true", `  file: ${toonScalar(displayPath(file, context.cwd))}`, `  command: ${toonScalar(formatCommand(command))}`, formatHelp(["Add `--execute` to stop and remove this compose stack"])].join("\n"));
    return;
  }
  const result = runCommand(command.cmd, command.args, context);
  if (result.status !== 0) runtimeError("docker compose down failed", [sanitize(result.stderr || result.stdout || "Run `docker-axi doctor` and retry")]);
  print(["compose_down:", "  dry_run: false", `  output: ${toonScalar(truncate(sanitize(result.stdout), PREVIEW_LIMIT).text)}`].join("\n"));
}

function ps(parsed, context) {
  ensureDocker();
  const fields = parseFields(parsed.flags.fields, ["id", "name", "image", "state"], ["id", "name", "image", "state", "ports", "status"]);
  const result = runDocker(["ps", "-a", "--format", "{{json .}}"], context);
  if (result.status !== 0) runtimeError("docker ps failed", [sanitize(result.stderr || result.stdout)]);
  const rows = parseJsonLines(result.stdout).map(containerRow).map((row) => pick(row, fields));
  print(rows.length === 0 ? "containers: 0 containers found" : [`count: ${rows.length} containers`, formatTable("containers", rows, fields)].join("\n"));
}

function images(parsed, context) {
  ensureDocker();
  const fields = parseFields(parsed.flags.fields, ["id", "repository", "tag", "size"], ["id", "repository", "tag", "size", "created"]);
  const result = runDocker(["images", "--format", "{{json .}}"], context);
  if (result.status !== 0) runtimeError("docker images failed", [sanitize(result.stderr || result.stdout)]);
  const rows = parseJsonLines(result.stdout).map(imageRow).map((row) => pick(row, fields));
  print(rows.length === 0 ? "images: 0 images found" : [`count: ${rows.length} images`, formatTable("images", rows, fields)].join("\n"));
}

function logs(parsed, context) {
  const container = parsed.flags.container;
  if (!container) usageError("--container is required", ["Run `docker-axi logs --container <id|name> [--tail 100]`"]);
  const tail = parsePositiveInteger(parsed.flags.tail ?? "100", "--tail");
  ensureDocker();
  const result = runDocker(["logs", "--tail", String(tail), container], context);
  if (result.status !== 0) runtimeError("docker logs failed", [sanitize(result.stderr || result.stdout)]);
  const sanitized = sanitize(result.stdout || result.stderr);
  const body = parsed.flags.full ? sanitized : truncate(sanitized, LOG_LIMIT).text;
  const lines = ["logs:", `  container: ${toonScalar(container)}`, `  tail: ${tail}`, `  output: ${toonScalar(body)}`];
  if (!parsed.flags.full && truncate(sanitized, LOG_LIMIT).truncated) lines.push(formatHelp([`Run \`docker-axi logs --container ${container} --tail ${tail} --full\` for complete output`]));
  print(lines.join("\n"));
}

function inspect(parsed, context) {
  const kind = parsed.flags.kind;
  const id = parsed.flags.id;
  const validKinds = new Set(["container", "image", "volume", "network"]);
  if (!kind) usageError("--kind is required", ["Run `docker-axi inspect --kind <container|image|volume|network> --id <id>`"]);
  if (!validKinds.has(kind)) usageError(`unknown kind ${toonScalar(kind)}`, ["valid kinds: container, image, volume, network"]);
  if (!id) usageError("--id is required", ["Run `docker-axi inspect --kind <kind> --id <id>`"]);
  ensureDocker();
  const args = kind === "volume" || kind === "network" ? [kind, "inspect", id] : ["inspect", id];
  const result = runDocker(args, context);
  if (result.status !== 0) runtimeError("docker inspect failed", [sanitize(result.stderr || result.stdout)]);
  const sanitized = sanitize(result.stdout);
  if (parsed.flags.full) {
    print(["inspect:", `  kind: ${kind}`, `  id: ${toonScalar(id)}`, `  output: ${toonScalar(sanitized)}`].join("\n"));
    return;
  }
  const summary = inspectSummary(kind, result.stdout);
  const preview = truncate(sanitized, PREVIEW_LIMIT);
  const lines = ["inspect:", `  kind: ${kind}`, `  id: ${toonScalar(id)}`, ...summary.map(([key, value]) => `  ${key}: ${toonScalar(value)}`), `  preview: ${toonScalar(preview.text)}`];
  if (preview.truncated) lines.push(formatHelp([`Run \`docker-axi inspect --kind ${kind} --id ${id} --full\` for complete sanitized inspect output`]));
  print(lines.join("\n"));
}

function execContainer(parsed, context) {
  const container = parsed.flags.container;
  const cmd = parsed.flags.cmd;
  if (!container) usageError("--container is required", ["Run `docker-axi exec --container <id|name> --cmd <argv...>`"]);
  if (!cmd) usageError("--cmd is required", ["Run `docker-axi exec --container <id|name> --cmd node --version`"]);
  const argv = splitCommand(cmd);
  if (argv.length === 0) usageError("--cmd is required", ["Run `docker-axi exec --container <id|name> --cmd node --version`"]);
  const command = { cmd: "docker", args: ["exec", container, ...argv] };
  if (!parsed.flags.execute) {
    print(["exec:", "  dry_run: true", `  container: ${toonScalar(container)}`, `  command: ${toonScalar(formatCommand(command))}`, formatHelp(["Add `--execute` to run this non-interactive command"])].join("\n"));
    return;
  }
  ensureDocker();
  const result = runCommand(command.cmd, command.args, context);
  if (result.status !== 0) runtimeError("docker exec failed", [sanitize(result.stderr || result.stdout)]);
  print(["exec:", "  dry_run: false", `  output: ${toonScalar(truncate(sanitize(result.stdout), PREVIEW_LIMIT).text)}`].join("\n"));
}

function clean(parsed, context) {
  const kind = parsed.flags.kind;
  const commands = {
    containers: ["container", "prune", "-f"],
    images: ["image", "prune", "-f"],
    volumes: ["volume", "prune", "-f"],
    networks: ["network", "prune", "-f"],
    "builder-cache": ["builder", "prune", "-f"]
  };
  if (!kind) usageError("--kind is required", ["Run `docker-axi clean --kind <containers|images|volumes|networks|builder-cache>`"]);
  if (!commands[kind]) usageError(`unknown cleanup kind ${toonScalar(kind)}`, ["valid kinds: containers, images, volumes, networks, builder-cache"]);
  const command = { cmd: "docker", args: commands[kind] };
  if (!parsed.flags.execute) {
    print(["clean:", "  dry_run: true", `  kind: ${kind}`, `  command: ${toonScalar(formatCommand(command))}`, formatHelp([`Run \`docker-axi clean --kind ${kind} --execute\` to prune after review`])].join("\n"));
    return;
  }
  ensureDocker();
  const result = runCommand(command.cmd, command.args, context);
  if (result.status !== 0) runtimeError("docker cleanup failed", [sanitize(result.stderr || result.stdout)]);
  print(["clean:", "  dry_run: false", `  kind: ${kind}`, `  output: ${toonScalar(truncate(sanitize(result.stdout), PREVIEW_LIMIT).text)}`].join("\n"));
}

function hooksInstall(parsed, context) {
  const agent = parsed.flags.agent ?? "all";
  const scope = parsed.flags.scope ?? "project";
  const validAgents = new Set(["codex", "claude", "opencode", "all"]);
  const validScopes = new Set(["user", "project"]);
  if (!validAgents.has(agent)) usageError(`unknown agent ${toonScalar(agent)}`, ["valid agents: codex, claude, opencode, all"]);
  if (!validScopes.has(scope)) usageError(`unknown scope ${toonScalar(scope)}`, ["valid scopes: user, project"]);
  const rows = hookTargets(agent, scope, context);
  if (!parsed.flags.execute) {
    print(["hooks:", "  dry_run: true", formatTable("files", rows, ["agent", "path", "status"]), formatHelp(["Run `docker-axi hooks install --agent all --scope project --execute` to write hook files"])].join("\n"));
    return;
  }
  for (const row of rows) {
    fs.mkdirSync(path.dirname(row.absolutePath), { recursive: true });
    fs.writeFileSync(row.absolutePath, hookContent(row.agent), "utf8");
  }
  print(formatTable("files", rows.map((row) => ({ agent: row.agent, path: row.path, status: "written" })), ["agent", "path", "status"]));
}

function skillGenerate(parsed, context) {
  const output = path.resolve(context.cwd, parsed.flags.output ?? "SKILL.md");
  const content = skillContent();
  if (parsed.flags.check) {
    const actual = fs.existsSync(output) ? fs.readFileSync(output, "utf8") : "";
    if (actual !== content) runtimeError("generated skill is stale or missing", [`Run \`docker-axi skill generate --output ${displayPath(output, context.cwd)}\``], 1);
    print("skill: up-to-date");
    return;
  }
  fs.writeFileSync(output, content, "utf8");
  print(["skill:", `  path: ${toonScalar(displayPath(output, context.cwd))}`, "  status: written"].join("\n"));
}

function requireTarget(parsed, context) {
  const id = parsed.flags.target;
  if (!id) usageError("--target is required", ["Run `docker-axi discover` to find target ids"]);
  const target = discoverTargets(context).find((item) => item.id === id);
  if (!target) usageError(`target ${toonScalar(id)} was not found`, ["Run `docker-axi discover` to find target ids"]);
  return target;
}

function requireFileFlag(parsed, context) {
  if (!parsed.flags.file) usageError("--file is required", ["Run `docker-axi compose up --file <path>`"]);
  return path.resolve(context.cwd, parsed.flags.file);
}

function buildPlan(target, environment, flags, context) {
  const command = planCommand(target, environment, flags, context);
  const rows = [
    { check: "target", status: "ok", detail: target.id },
    { check: "environment", status: "ok", detail: environment },
    { check: "docker-cli", status: findExecutable("docker") ? "ok" : "missing", detail: findExecutable("docker") ? collapseHome(findExecutable("docker")) : "install Docker" },
    { check: "compose", status: target.type.startsWith("compose") ? (composeInfo(context).available ? "ok" : "missing") : "not-needed", detail: target.type.startsWith("compose") ? composeInfo(context).detail : "" },
    { check: "secrets", status: "redacted", detail: "env values labels build args compose output logs inspect" }
  ];
  const lines = ["plan:", `  target: ${toonScalar(target.id)}`, `  type: ${toonScalar(target.type)}`, `  environment: ${toonScalar(environment)}`, `  command: ${toonScalar(command ? formatCommand(command) : "manual review required")}`, formatTable("checks", rows, ["check", "status", "detail"])];
  if (command?.preview) {
    const result = runCommand(command.cmd, command.args, commandContext(command, context));
    lines.push("preview:");
    lines.push(`  status: ${result.status === 0 ? "ok" : "error"}`);
    lines.push(`  output: ${toonScalar(flags.full ? sanitize(result.stdout || result.stderr) : truncate(sanitize(result.stdout || result.stderr), PREVIEW_LIMIT).text)}`);
  }
  lines.push(formatHelp([`Run \`docker-axi apply --target ${target.id} --environment ${environment}\` to see the guarded apply command`]));
  return lines.join("\n");
}

function planCommand(target, environment, flags, context) {
  if (target.commands?.plan) return expandCommand(target.commands.plan, environment, target.path);
  if (target.type === "compose" || target.type === "compose-service") {
    return { ...composeCommand(context, ["-f", target.path, "config", "--services"]), preview: true };
  }
  if (target.type === "dockerfile") return buildCommand(target, flags);
  if (target.type === "custom" && target.commands?.apply) return expandCommand(target.commands.apply, environment, target.path);
  return null;
}

function applyCommand(target, environment, flags) {
  if (target.commands?.apply) return expandCommand(target.commands.apply, environment, target.path);
  if (target.type === "dockerfile") return buildCommand(target, flags);
  if (target.type === "compose") return composeCommand({ cwd: path.dirname(target.path) }, ["-f", target.path, "up", "-d"]);
  if (target.type === "compose-service") return composeCommand({ cwd: path.dirname(target.path) }, ["-f", target.path, "up", "-d", target.service]);
  return null;
}

function buildCommand(target, flags) {
  if (target.commands?.build) return expandCommand(target.commands.build, "local", target.path);
  const tag = flags.tag ?? target.tag ?? localImageFor(target);
  return { cmd: "docker", args: ["build", "-f", target.path, "-t", tag, path.dirname(target.path)], tag };
}

function runTargetCommand(target, flags) {
  const image = target.tag ?? localImageFor(target);
  const args = ["run", "--rm"];
  if (flags.name) args.push("--name", flags.name);
  if (flags.ports) args.push("-p", flags.ports);
  if (flags.env_file) args.push("--env-file", flags.env_file);
  args.push(image);
  return { cmd: "docker", args };
}

function expandCommand(command, environment, cwd) {
  const [cmd, ...args] = command.map((part) => String(part).replaceAll("${environment}", environment));
  return { cmd, args, cwd: cwd && fs.statSync(cwd).isDirectory() ? cwd : path.dirname(cwd) };
}

function discoverTargets(context) {
  const targets = [];
  targets.push(...customTargets(context));
  for (const file of findFiles(context.cwd, isDockerfile, 3)) {
    const info = parseDockerfile(file);
    targets.push({
      id: dockerfileId(file, context.cwd),
      type: "dockerfile",
      path: file,
      detail: info.detail,
      ports: info.ports,
      healthcheck: info.healthcheck,
      reason: info.reason
    });
  }
  for (const file of findFiles(context.cwd, isComposeFile, 2)) {
    const services = parseComposeServices(file);
    targets.push({ id: `compose:${displayPath(file, context.cwd)}`, type: "compose", path: file, detail: services.length ? `${services.length} services` : "compose file", services: services.join("|"), reason: "compose file found" });
    for (const service of services) {
      targets.push({ id: `compose:${displayPath(file, context.cwd)}:${service}`, type: "compose-service", path: file, service, detail: `service ${service}`, services: service, reason: "compose service found" });
    }
  }
  const devcontainer = path.join(context.cwd, ".devcontainer", "devcontainer.json");
  if (fs.existsSync(devcontainer)) {
    const config = readJson(devcontainer) ?? {};
    targets.push({ id: "devcontainer:.devcontainer/devcontainer.json", type: "devcontainer", path: devcontainer, detail: config.image ? "image" : config.dockerFile ? "dockerfile" : config.dockerComposeFile ? "compose" : "devcontainer", reason: "devcontainer config found" });
  }
  const packageJson = readJson(path.join(context.cwd, "package.json"));
  if (packageJson) {
    const deps = Object.keys({ ...(packageJson.dependencies ?? {}), ...(packageJson.devDependencies ?? {}) }).join(" ");
    const scripts = Object.keys(packageJson.scripts ?? {}).join(" ");
    if (/start|server|api|worker|dev|build/i.test(scripts) || /express|fastify|hono|next|vite|react|vue|svelte/i.test(deps)) {
      targets.push({ id: "package:node-app", type: "package-app", path: path.join(context.cwd, "package.json"), detail: "package app candidate", reason: "package scripts or dependencies suggest a container target" });
    }
  }
  return dedupeTargets(targets);
}

function customTargets(context) {
  const file = path.join(context.cwd, "docker-axi.config.json");
  const config = readJson(file);
  if (!config?.targets || !Array.isArray(config.targets)) return [];
  return config.targets.map((target) => ({
    id: String(target.id),
    type: target.type ?? "custom",
    path: path.resolve(context.cwd, target.path ?? "."),
    tag: target.tag,
    detail: target.detail ?? target.type ?? "custom Docker workflow",
    reason: target.reason ?? "docker-axi.config.json target",
    commands: target.commands
  }));
}

function isDockerfile(file) {
  const base = path.basename(file);
  return base === "Dockerfile" || base.startsWith("Dockerfile.");
}

function isComposeFile(file) {
  return ["compose.yml", "compose.yaml", "docker-compose.yml", "docker-compose.yaml"].includes(path.basename(file));
}

function dockerfileId(file, cwd) {
  const relative = path.relative(cwd, file);
  if (relative === "Dockerfile") return "dockerfile:root";
  const dir = path.dirname(relative);
  if (path.basename(file) === "Dockerfile" && dir !== ".") return `dockerfile:${dir.replaceAll(path.sep, "-")}`;
  return `dockerfile:${relative.replaceAll(path.sep, "-")}`;
}

function parseDockerfile(file) {
  const content = safeRead(file);
  const ports = [...content.matchAll(/^\s*EXPOSE\s+(.+)$/gim)].flatMap((match) => match[1].split(/\s+/)).join("|");
  const healthcheck = /^\s*HEALTHCHECK\s+/im.test(content) ? "yes" : "no";
  const stages = [...content.matchAll(/^\s*FROM\s+/gim)].length;
  const user = [...content.matchAll(/^\s*USER\s+(.+)$/gim)].at(-1)?.[1]?.trim() ?? "";
  const nonRoot = user && user !== "0" && user.toLowerCase() !== "root" ? "non-root" : "root-or-unspecified";
  return { ports, healthcheck, detail: `${stages || 1} stage(s), ${nonRoot}`, reason: "Dockerfile found" };
}

function parseComposeServices(file) {
  const lines = safeRead(file).split(/\r?\n/);
  const services = [];
  let inServices = false;
  let serviceIndent = -1;
  for (const line of lines) {
    if (/^\s*#/.test(line) || !line.trim()) continue;
    const top = line.match(/^(\s*)services:\s*$/);
    if (top) {
      inServices = true;
      serviceIndent = -1;
      continue;
    }
    if (!inServices) continue;
    const match = line.match(/^(\s*)([A-Za-z0-9_.-]+):\s*(?:#.*)?$/);
    if (!match) continue;
    const indent = match[1].length;
    if (serviceIndent === -1 && indent > 0) serviceIndent = indent;
    if (indent === serviceIndent) services.push(match[2]);
    if (indent === 0 && match[2] !== "services") break;
  }
  return services;
}

function dockerState(context) {
  const dockerPath = findExecutable("docker");
  if (!dockerPath) return { cli: "missing", daemon: "missing", context: "", compose: "missing", running: 0, stopped: 0, images: 0, volumes: 0, networks: 0 };
  const version = runDocker(["version", "--format", "{{json .}}"], context);
  const containers = runDocker(["ps", "-a", "--format", "{{json .}}"], context);
  const rows = containers.status === 0 ? parseJsonLines(containers.stdout) : [];
  const running = rows.filter((row) => String(row.State ?? row.Status ?? "").toLowerCase().includes("running") || String(row.Status ?? "").toLowerCase().startsWith("up")).length;
  return {
    cli: "ok",
    daemon: version.status === 0 ? "ok" : "error",
    context: dockerContext(context),
    compose: composeInfo(context).available ? "ok" : "missing",
    running,
    stopped: Math.max(rows.length - running, 0),
    images: lineCount(runDocker(["images", "-q"], context).stdout),
    volumes: lineCount(runDocker(["volume", "ls", "-q"], context).stdout),
    networks: lineCount(runDocker(["network", "ls", "-q"], context).stdout)
  };
}

function dockerContext(context) {
  const result = runDocker(["context", "show"], context);
  return result.status === 0 ? sanitize(result.stdout).trim() : "unknown";
}

function composeInfo(context) {
  if (findExecutable("docker")) {
    const result = runDocker(["compose", "version", "--short"], context);
    if (result.status === 0) return { available: true, command: "docker compose", detail: sanitize(result.stdout).trim() || "docker compose" };
  }
  if (findExecutable("docker-compose")) {
    const result = runCommand("docker-compose", ["version", "--short"], context);
    return { available: result.status === 0, command: "docker-compose", detail: result.status === 0 ? sanitize(result.stdout).trim() : "docker-compose found but failed" };
  }
  return { available: false, command: "", detail: "install Docker Compose v2" };
}

function buildkitStatus(context) {
  if (process.env.DOCKER_BUILDKIT === "1") return { status: "ok", detail: "DOCKER_BUILDKIT=1" };
  if (!findExecutable("docker")) return { status: "unknown", detail: "docker missing" };
  const result = runDocker(["buildx", "version"], context);
  return result.status === 0 ? { status: "available", detail: "docker buildx available" } : { status: "unknown", detail: "set DOCKER_BUILDKIT=1 or install buildx" };
}

function registryStatus() {
  const file = path.join(os.homedir(), ".docker", "config.json");
  const config = readJson(file);
  if (!config) return { status: "unknown", detail: "no docker config auths detected" };
  const auths = Object.keys(config.auths ?? {});
  const helpers = Object.keys(config.credHelpers ?? {});
  if (auths.length === 0 && helpers.length === 0 && !config.credsStore) return { status: "unknown", detail: "no registry auth metadata" };
  return { status: "detectable", detail: `auths:${auths.length}|helpers:${helpers.length}|store:${config.credsStore ? "yes" : "no"}` };
}

function composeCommand(context, args) {
  if (findExecutable("docker")) return { cmd: "docker", args: ["compose", ...args], cwd: context.cwd };
  return { cmd: "docker-compose", args, cwd: context.cwd };
}

function commandContext(command, context) {
  return command.cwd ? { ...context, cwd: command.cwd } : context;
}

function runDocker(args, context) {
  return runCommand("docker", args, context);
}

function runCommand(cmd, args, context) {
  const result = spawnSync(cmd, args, { cwd: context.cwd, env: process.env, encoding: "utf8", maxBuffer: 1024 * 1024 * 8 });
  if (result.error) return { status: 127, stdout: "", stderr: result.error.message };
  return { status: result.status ?? 1, stdout: result.stdout ?? "", stderr: result.stderr ?? "" };
}

function ensureDocker() {
  if (!findExecutable("docker")) runtimeError("docker is required", ["Install Docker or ensure docker is on PATH"]);
}

function findExecutable(name) {
  if (name.includes(path.sep)) return fs.existsSync(name) ? name : "";
  for (const dir of (process.env.PATH ?? "").split(path.delimiter)) {
    const full = path.join(dir, name);
    if (fs.existsSync(full)) return full;
  }
  return "";
}

function findFiles(root, predicate, maxDepth, depth = 0) {
  if (depth > maxDepth) return [];
  let entries = [];
  try {
    entries = fs.readdirSync(root, { withFileTypes: true });
  } catch {
    return [];
  }
  const files = [];
  for (const entry of entries) {
    if (["node_modules", ".git", "coverage"].includes(entry.name)) continue;
    const full = path.join(root, entry.name);
    if (entry.isDirectory()) files.push(...findFiles(full, predicate, maxDepth, depth + 1));
    else if (predicate(full)) files.push(full);
  }
  return files;
}

function dedupeTargets(targets) {
  const seen = new Set();
  return targets.filter((target) => {
    if (seen.has(target.id)) return false;
    seen.add(target.id);
    return true;
  });
}

function localImageFor(target) {
  return `${target.id.replace(/[^a-zA-Z0-9_.-]+/g, "-").replace(/^-|-$/g, "") || "app"}:local`;
}

function containerRow(row) {
  return { id: row.ID ?? row.Id ?? "", name: row.Names ?? row.Name ?? "", image: row.Image ?? "", state: row.State ?? "", status: row.Status ?? "", ports: row.Ports ?? "" };
}

function imageRow(row) {
  return { id: row.ID ?? row.Id ?? "", repository: row.Repository ?? "", tag: row.Tag ?? "", size: row.Size ?? "", created: row.CreatedSince ?? row.CreatedAt ?? "" };
}

function inspectSummary(kind, value) {
  const parsed = parseJson(value);
  const item = Array.isArray(parsed) ? parsed[0] : parsed;
  if (!item || typeof item !== "object") return [];
  if (kind === "container") return [["name", item.Name ?? ""], ["image", item.Config?.Image ?? item.Image ?? ""], ["state", item.State?.Status ?? ""], ["ports", Object.keys(item.NetworkSettings?.Ports ?? {}).join("|")], ["labels", Object.keys(item.Config?.Labels ?? {}).join("|")]];
  if (kind === "image") return [["id", item.Id ?? ""], ["tags", (item.RepoTags ?? []).join("|")], ["size", item.Size ?? ""], ["created", item.Created ?? ""]];
  if (kind === "volume") return [["name", item.Name ?? ""], ["driver", item.Driver ?? ""], ["mountpoint", item.Mountpoint ?? ""]];
  if (kind === "network") return [["name", item.Name ?? ""], ["driver", item.Driver ?? ""], ["scope", item.Scope ?? ""]];
  return [];
}

function parseJsonLines(value) {
  return String(value ?? "").split(/\r?\n/).map((line) => line.trim()).filter(Boolean).map((line) => parseJson(line)).filter(Boolean);
}

function parseJson(value) {
  try {
    return JSON.parse(value);
  } catch {
    return null;
  }
}

function readJson(file) {
  if (!fs.existsSync(file)) return null;
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return null;
  }
}

function safeRead(file) {
  try {
    return fs.readFileSync(file, "utf8");
  } catch {
    return "";
  }
}

function lineCount(value) {
  return String(value ?? "").split(/\r?\n/).filter((line) => line.trim()).length;
}

function parseFields(value, defaults, allowed) {
  if (!value) return defaults;
  const fields = value.split(",").map((field) => field.trim()).filter(Boolean);
  const unknown = fields.find((field) => !allowed.includes(field));
  if (unknown) usageError(`unknown field ${toonScalar(unknown)}`, [`valid fields: ${allowed.join(", ")}`]);
  return fields.length > 0 ? fields : defaults;
}

function parsePositiveInteger(value, flag) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1) usageError(`${flag} must be a positive integer`, [`Run \`docker-axi logs ${flag} 100\``]);
  return parsed;
}

function splitCommand(value) {
  return String(value).match(/(?:[^\s"']+|"[^"]*"|'[^']*')+/g)?.map((part) => part.replace(/^["']|["']$/g, "")) ?? [];
}

function pick(row, fields) {
  return Object.fromEntries(fields.map((field) => [field, row[field] ?? ""]));
}

function truncate(value, limit) {
  const text = String(value ?? "");
  if (text.length <= limit) return { text, truncated: false, total: text.length };
  return { text: `${text.slice(0, limit)}... (truncated, ${text.length} chars total)`, truncated: true, total: text.length };
}

function sanitize(value) {
  let text = String(value ?? "");
  text = text.replace(/("?[A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|PASS|API_KEY|ACCESS_KEY|PRIVATE_KEY|AUTH)[A-Z0-9_]*"?\s*:\s*)("[^"]*"|'[^']*'|[^\s,}]+)/gi, "$1\"<redacted>\"");
  text = text.replace(/([A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|PASS|API_KEY|ACCESS_KEY|PRIVATE_KEY|AUTH)[A-Z0-9_]*)(\s*[:=]\s*)("[^"]*"|'[^']*'|[^\s,}]+)/gi, "$1$2<redacted>");
  text = text.replace(/((?:token|secret|password|passwd|api[_-]?key|access[_-]?key|private[_-]?key|auth)\s*[:=]\s*)("[^"]*"|'[^']*'|[^\s,}]+)/gi, "$1<redacted>");
  text = text.replace(/(https?:\/\/)([^:\s/@]+):([^@\s]+)@/gi, "$1<redacted>:<redacted>@");
  text = text.replace(/\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/g, "<redacted-jwt>");
  text = text.replace(/\b(?:ghp|gho|ghu|ghs|glpat|sk)-[A-Za-z0-9_=-]{16,}\b/g, "<redacted-token>");
  return text.trim();
}

function formatCommand(command) {
  return [command.cmd, ...command.args.map((arg) => String(arg).includes(" ") ? `"${String(arg).replaceAll("\"", "\\\"")}"` : String(arg))].join(" ");
}

function formatTable(name, rows, fields) {
  const header = `${name}[${rows.length}]{${fields.join(",")}}:`;
  return [header, ...rows.map((row) => `  ${fields.map((field) => toonScalar(row[field])).join(",")}`)].join("\n");
}

function formatHelp(items) {
  return [`help[${items.length}]:`, ...items.map((item) => `  ${item}`)].join("\n");
}

function toonScalar(value) {
  if (value === null || value === undefined) return "null";
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "number") return Number.isFinite(value) ? String(value) : "null";
  const text = String(value);
  if (text === "") return "\"\"";
  const mustQuote = /[,\[\]{}:"#\n\r\t|]|^\s|\s$/.test(text);
  if (!mustQuote) return text;
  return `"${text.replaceAll("\\", "\\\\").replaceAll("\"", "\\\"").replaceAll("\n", "\\n").replaceAll("\r", "\\r").replaceAll("\t", "\\t")}"`;
}

function collapseHome(filePath) {
  const home = os.homedir();
  return filePath.startsWith(home) ? `~${filePath.slice(home.length)}` : filePath;
}

function displayPath(filePath, cwd) {
  const relative = path.relative(cwd, filePath);
  if (relative && !relative.startsWith("..") && !path.isAbsolute(relative)) return relative;
  return collapseHome(filePath);
}

function hookTargets(agent, scope, context) {
  const selected = agent === "all" ? ["codex", "claude", "opencode"] : [agent];
  return selected.map((item) => {
    const absolutePath = hookPath(item, scope, context);
    return { agent: item, path: displayPath(absolutePath, context.cwd), absolutePath, status: fs.existsSync(absolutePath) ? "repair" : "create" };
  });
}

function hookPath(agent, scope, context) {
  if (agent === "codex") return scope === "project" ? path.join(context.cwd, ".codex", "hooks.json") : path.join(os.homedir(), ".codex", "hooks.json");
  if (agent === "claude") return scope === "project" ? path.join(context.cwd, ".claude", "settings.json") : path.join(os.homedir(), ".claude", "settings.json");
  return scope === "project" ? path.join(context.cwd, ".opencode", "docker-axi.json") : path.join(os.homedir(), ".config", "opencode", "plugins", "docker-axi.json");
}

function hookContent(agent) {
  const command = hookCommand();
  if (agent === "codex") return `${JSON.stringify({ SessionStart: [{ command }] }, null, 2)}\n`;
  if (agent === "claude") return `${JSON.stringify({ hooks: { SessionStart: [{ hooks: [{ type: "command", command }] }] } }, null, 2)}\n`;
  return `${JSON.stringify({ name: "docker-axi", command }, null, 2)}\n`;
}

function hookCommand() {
  const installed = findExecutable("docker-axi");
  if (installed && path.resolve(installed) === path.resolve(process.argv[1])) return "docker-axi";
  return `${process.execPath} ${process.argv[1]}`;
}

function skillContent() {
  return `---\nname: docker-axi\ndescription: Use docker-axi to discover, plan, build, run, debug, publish, inspect, and clean up Docker apps through safe TOON CLI workflows.\n---\n\n# docker-axi\n\nUse \`docker-axi\` when a task involves Dockerfiles, Docker Compose, containers, images, logs, inspect output, local dev stacks, registry publishing, cleanup, or Docker safety checks.\n\nRun \`npx -y docker-axi\` for live context. Use \`npx -y docker-axi doctor\` before Docker work. Discover targets with \`npx -y docker-axi discover\`. Plan before mutating: \`npx -y docker-axi plan --target <id> --environment <name>\`. Mutations require \`--execute\`.\n`;
}

function usageError(message, help, code = 2) {
  print([`error: ${message}`, formatHelp(help)].join("\n"));
  process.exit(code);
}

function runtimeError(message, help, code = 1) {
  print([`error: ${message}`, formatHelp(help)].join("\n"));
  process.exit(code);
}

function print(value) {
  process.stdout.write(value);
}

function helpHome() {
  return [
    `bin: ${toonScalar(collapseHome(process.argv[1]))}`,
    `description: ${toonScalar(DESCRIPTION)}`,
    "commands[18]{name,description}:",
    "  doctor,Check Docker CLI daemon Compose BuildKit registry and disk readiness",
    "  services,List Docker capability domains",
    "  discover,Detect Dockerfiles compose files package apps and devcontainers",
    "  recommend,Suggest Docker workflows for a goal",
    "  plan,Run non-mutating preflight for a target",
    "  apply,Apply a target with explicit execution guards",
    "  build,Build an image only with --execute",
    "  run,Run a container only with --execute",
    "  compose up,Start a compose stack only with --execute",
    "  compose down,Stop and remove a compose stack only with --execute",
    "  ps,List containers",
    "  images,List images",
    "  logs,Read truncated redacted container logs",
    "  inspect,Summarize redacted Docker inspect output",
    "  exec,Run non-interactive container command only with --execute",
    "  clean,Preview or run safe prune workflows",
    "  hooks install,Install session context hooks",
    "  skill generate,Generate installable Agent Skill guidance",
    "examples[3]:",
    "  docker-axi",
    "  docker-axi discover",
    "  docker-axi plan --target <id> --environment local"
  ].join("\n");
}

function helpDoctor() {
  return helpUsage("docker-axi doctor", "Check Docker CLI daemon Compose BuildKit registry and disk readiness");
}

function helpServices() {
  return helpUsage("docker-axi services [--capability <name>] [--fields <csv>]", "List Docker capability domains");
}

function helpDiscover() {
  return helpUsage("docker-axi discover [--fields <csv>] [--full]", "Detect Docker targets in the current repo");
}

function helpRecommend() {
  return helpUsage("docker-axi recommend --goal <web|api|worker|database|fullstack|local-dev|ci>", "Suggest Docker workflow paths");
}

function helpPlan() {
  return helpUsage("docker-axi plan --target <id> [--environment <name>] [--tag <tag>] [--full]", "Run non-mutating preflight and command planning");
}

function helpApply() {
  return helpUsage("docker-axi apply --target <id> [--environment <name>] [--tag <tag>] [--execute]", "Apply target command only when execution guard is explicit");
}

function helpBuild() {
  return helpUsage("docker-axi build --target <id> [--tag <tag>] [--execute]", "Build an image from a Dockerfile target");
}

function helpRun() {
  return helpUsage("docker-axi run --target <id> [--name <name>] [--ports <mapping>] [--env-file <path>] [--execute]", "Run a container without printing env values");
}

function helpComposeUp() {
  return helpUsage("docker-axi compose up --file <path> [--service <name>] [--execute]", "Start a compose stack or service");
}

function helpComposeDown() {
  return helpUsage("docker-axi compose down --file <path> [--execute]", "Stop and remove a compose stack");
}

function helpPs() {
  return helpUsage("docker-axi ps [--fields <csv>]", "List containers in compact TOON");
}

function helpImages() {
  return helpUsage("docker-axi images [--fields <csv>]", "List images in compact TOON");
}

function helpLogs() {
  return helpUsage("docker-axi logs --container <id|name> [--tail <n>] [--full]", "Read redacted truncated container logs");
}

function helpInspect() {
  return helpUsage("docker-axi inspect --kind <container|image|volume|network> --id <id> [--full]", "Summarize redacted Docker inspect output");
}

function helpExec() {
  return helpUsage("docker-axi exec --container <id|name> --cmd <argv...> [--execute]", "Run a non-interactive command in a container");
}

function helpClean() {
  return helpUsage("docker-axi clean --kind <containers|images|volumes|networks|builder-cache> [--execute]", "Preview or run safe Docker prune workflows");
}

function helpHooksInstall() {
  return helpUsage("docker-axi hooks install [--agent codex|claude|opencode|all] [--scope user|project] [--execute]", "Install or preview session hooks");
}

function helpSkillGenerate() {
  return helpUsage("docker-axi skill generate [--output SKILL.md] [--check]", "Generate or verify installable Agent Skill guidance");
}

function helpUsage(usage, description) {
  return [
    `usage: ${usage}`,
    `description: ${description}`,
    "global_flags[2]{name,default,description}:",
    "  --cwd,\".\",Workspace root",
    "  --help,false,Show this help",
    "examples[2]:",
    `  ${usage.replace(/\s?\[.*?\]/g, "").replace(/<[^>]+>/g, "example")}`,
    "  docker-axi doctor"
  ].join("\n");
}
