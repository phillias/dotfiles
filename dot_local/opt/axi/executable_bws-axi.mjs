#!/usr/bin/env node
// bws-axi — Bitwarden Secrets Manager for agents. TOON output, values redacted by default.
import { readFileSync, existsSync } from 'node:fs';
import { list, kv, help, fail, usageError, parseFlags, run, collapseHome, truncate } from './common.mjs';

const BWS = process.env.BWS_BIN || 'bws';

function token() {
  const env = process.env.BWS_ACCESS_TOKEN;
  if (env) return env;
  const tf = process.env.BWS_TOKEN_FILE || `${process.env.HOME}/.config/bwsh/token`;
  if (existsSync(tf)) return readFileSync(tf, 'utf8').trim();
  return null;
}

function bws(args, opts = {}) {
  const tok = token();
  if (!tok) fail('no Bitwarden SM access token found', 'AUTH_REQUIRED', [
    'Set BWS_ACCESS_TOKEN (or BWS_TOKEN_FILE pointing at a token file, e.g. ~/.config/bwsh/token)',
    'Run `bws-axi doctor` to diagnose',
  ]);
  const r = run(BWS, args, { env: { BWS_ACCESS_TOKEN: tok, ...(opts.env || {}) }, timeout: opts.timeout || 15000 });
  return r;
}

function json(cmd, args) {
  const r = bws(args, { env: { BWS_DEFAULT_PROJECT_ID: cmd.projectId || '' } });
  if (r.code !== 0) {
    const msg = r.stderr.split('\n').find((l) => l.trim() && !l.startsWith('Error')) || r.stderr.trim() || r.stdout.trim();
    fail(`bws: ${msg || 'command failed'}`, 'BWS_ERROR');
  }
  try {
    return JSON.parse(r.stdout);
  } catch {
    fail('bws returned invalid JSON', 'PARSE_ERROR');
  }
}

function resolveProject(arg) {
  const projects = json('projects', ['project', 'list']);
  const found = projects.find((p) => p.id === arg) || projects.find((p) => p.name === arg);
  if (!found) {
    fail(`project not found: ${arg}`, 'NOT_FOUND', [`Run \`bws-axi projects\` to list projects`]);
  }
  return found;
}

// ---- commands ----
const CMD_HELP = `usage: bws-axi [command] [args] [flags]
commands:
  (none)=dashboard, doctor, projects, items, secret, setup
flags: --help (after command)

examples:
  bws-axi
  bws-axi projects
  bws-axi items <project> --limit 50
  bws-axi secret <project> <key> --full`;

function cmdHelp(c) {
  return `usage: bws-axi ${c}
${COMMANDS[c]}`;
}

const COMMANDS = {
  'projects': `List Bitwarden SM projects (names + ids)
flags: --help
examples:
  bws-axi projects`,
  'items': `List secrets in a project (keys only, values never shown)
args: <project> (name or id)
flags: --limit <n> (default 100), --help
examples:
  bws-axi items sandbox
  bws-axi items sandbox --limit 20`,
  'secret': `Show one secret's value (redacted unless --full)
args: <project> <key>
flags: --full (show the actual value), --help
examples:
  bws-axi secret sandbox API_KEY
  bws-axi secret sandbox API_KEY --full`,
  'doctor': `Check bws binary and auth token
flags: --help`,
  'setup': `Print ambient-context setup instructions for agents
flags: --help`,
};

async function main() {
  const [cmd0, ...rest] = process.argv.slice(2);
  if (cmd0 === '--help' || cmd0 === '-h') { process.stdout.write(CMD_HELP + '\n'); process.exit(0); }
  const cmd = cmd0 || 'dashboard';

  if (!(cmd in COMMANDS) && cmd !== 'dashboard') {
    usageError(`unknown command: ${cmd}`, [`valid commands: dashboard, doctor, projects, items, secret, setup`, `Run \`bws-axi --help\` for usage`]);
  }

  if (cmd === 'dashboard') {
    const f = parseFlags(rest, { bools: [], values: ['limit'] });
    if (f.help) { process.stdout.write(CMD_HELP + '\n'); process.exit(0); }
    const limit = Math.min(parseInt(f.limit || '50', 10) || 50, 500);
    const projects = json('projects', ['project', 'list']);
    const rows = projects.slice(0, limit).map((p) => ({ id: p.id.slice(0, 12), name: p.name }));
    const out = [
      `bin: ${collapseHome(process.argv[1])}`,
      'description: Bitwarden Secrets Manager — list projects and secrets with values redacted by default',
    ];
    if (projects.length === 0) {
      out.push('projects: 0 projects found');
    } else {
      out.push(list('projects', ['name', 'id'], rows, { total: projects.length }));
      out.push(help([
        `Run \`bws-axi items <name>\` to list secrets in a project`,
        `Run \`bws-axi secret <name> <key> --full\` to read one value`,
      ]));
    }
    process.stdout.write(out.join('\n') + '\n');
    process.exit(0);
  }

  if (cmd === 'doctor') {
    const f = parseFlags(rest, {});
    if (f.help) { process.stdout.write(cmdHelp('doctor') + '\n'); process.exit(0); }
    const bin = run('sh', ['-c', `command -v ${BWS}`]);
    const tok = token();
    const out = [
      `binary: ${bin.code === 0 ? bin.stdout.trim() : 'MISSING'}`,
      `token: ${tok ? 'present' : 'MISSING'}`,
    ];
    if (bin.code !== 0) {
      out.push(help([`Install the bws CLI (https://bitwarden.com/help/cli/) or set BWS_BIN`]));
    } else if (!tok) {
      out.push(help([`Set BWS_ACCESS_TOKEN or BWS_TOKEN_FILE (e.g. ~/.config/bwsh/token)`]));
    } else {
      const r = bws(['project', 'list']);
      out.push(`auth: ${r.code === 0 ? 'ok' : 'failed'}`);
      if (r.code !== 0) out.push(help([`Check that the token is valid and has access (bws login / refresh token)`]));
    }
    process.stdout.write(out.join('\n') + '\n');
    process.exit(0);
  }

  if (cmd === 'projects') {
    const f = parseFlags(rest, { values: ['limit'] });
    if (f.help) { process.stdout.write(cmdHelp('projects') + '\n'); process.exit(0); }
    const limit = Math.min(parseInt(f.limit || '100', 10) || 100, 1000);
    const projects = json('projects', ['project', 'list']);
    const rows = projects.slice(0, limit).map((p) => ({ id: p.id.slice(0, 12), name: p.name }));
    const out = [];
    if (projects.length === 0) {
      out.push('projects: 0 projects found');
    } else {
      out.push(list('projects', ['name', 'id'], rows, { total: projects.length }));
      out.push(help([`Run \`bws-axi items <name>\` to list secrets in a project`]));
    }
    process.stdout.write(out.join('\n') + '\n');
    process.exit(0);
  }

  if (cmd === 'items') {
    const f = parseFlags(rest, { values: ['limit'] });
    if (f.help) { process.stdout.write(cmdHelp('items') + '\n'); process.exit(0); }
    if (f._.length !== 1) usageError('items requires exactly one argument: <project>', ['Run `bws-axi items --help`']);
    const project = resolveProject(f._[0]);
    const limit = Math.min(parseInt(f.limit || '100', 10) || 100, 1000);
    const secrets = json('secrets', ['secret', 'list', project.id]);
    const rows = secrets.slice(0, limit).map((s) => ({ key: s.key, type: s.type || 'login' }));
    const out = [`project: ${project.name}`];
    if (secrets.length === 0) {
      out.push(`secrets: 0 secrets found in project "${project.name}"`);
      out.push(help([`Run \`bws-axi projects\` to check other projects`]));
    } else {
      out.push(list('secrets', ['key', 'type'], rows, { total: secrets.length }));
      out.push(help([`Run \`bws-axi secret ${project.name} <key> --full\` to read one value`]));
    }
    process.stdout.write(out.join('\n') + '\n');
    process.exit(0);
  }

  if (cmd === 'secret') {
    const f = parseFlags(rest, { bools: ['full'] });
    if (f.help) { process.stdout.write(cmdHelp('secret') + '\n'); process.exit(0); }
    if (f._.length !== 2) usageError('secret requires two arguments: <project> <key>', ['Run `bws-axi secret --help`']);
    const [projArg, key] = f._;
    const project = resolveProject(projArg);
    const secrets = json('secrets', ['secret', 'list', project.id]);
    const match = secrets.find((s) => s.key === key);
    if (!match) {
      fail(`secret not found: ${key} in project ${project.name}`, 'NOT_FOUND', [
        `Run \`bws-axi items ${project.name}\` to list keys`,
      ]);
    }
    const val = f.full ? match.value : truncate(match.value, 120, `bws-axi secret ${project.name} ${key} --full`);
    process.stdout.write(
      kv({
        key: match.key,
        project: project.name,
        value: f.full ? val : (match.value ? `*** (${match.value.length} chars, use --full to read)` : '(empty)'),
      }) + '\n'
    );
    process.exit(0);
  }

  if (cmd === 'setup') {
    const f = parseFlags(rest, {});
    if (f.help) { process.stdout.write(cmdHelp('setup') + '\n'); process.exit(0); }
    process.stdout.write(
      [
        'bws-axi: ambient-context setup for agents',
        '',
        'Primary integration: set BWS_ACCESS_TOKEN in your agent session environment',
        '(or BWS_TOKEN_FILE pointing at ~/.config/bwsh/token, matching the bws-init pattern).',
        '',
        'Secondary: install this skill (~/.agents/skills/bws-axi/) so agents load it on demand.',
        '',
        'Session hooks are intentionally not auto-installed: secrets access should stay explicit.',
      ].join('\n') + '\n'
    );
    process.exit(0);
  }
}

main().catch((e) => fail(e.message, 'INTERNAL'));
