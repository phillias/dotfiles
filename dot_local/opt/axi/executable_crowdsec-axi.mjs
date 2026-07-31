#!/usr/bin/env node
// crowdsec-axi — CrowdSec decisions/alerts/bouncers for agents. Read-only by default.
import { list, kv, help, fail, usageError, parseFlags, run, collapseHome, truncate } from './common.mjs';

const CONTAINER = process.env.CROWDSEC_CONTAINER || 'crowdsec';

// cscli is reachable via the crowdsec container (host cscli points at a stale LAPI).
function cscli(args, opts = {}) {
  if (process.env.CROWDSEC_EXEC) {
    return run(process.env.CROWDSEC_EXEC, args, { timeout: opts.timeout || 20000 });
  }
  const viaDocker = run('docker', ['exec', CONTAINER, 'cscli', ...args], { timeout: opts.timeout || 20000 });
  if (viaDocker.code === 0) return viaDocker;
  const direct = run('cscli', args, { timeout: opts.timeout || 20000 });
  return direct;
}

function json(args, opts) {
  const r = cscli([...args, '-o', 'json'], opts);
  if (r.code !== 0) {
    const msg = r.stderr.split('\n').find((l) => l.trim()) || r.stderr.trim();
    fail(`cscli: ${msg || 'command failed'}`, 'CSCLI_ERROR', [
      `Is the ${CONTAINER} container running? (docker ps | grep crowdsec)`,
    ]);
  }
  if (!r.stdout.trim()) return [];
  try {
    return JSON.parse(r.stdout);
  } catch {
    fail('cscli returned invalid JSON', 'PARSE_ERROR');
  }
}

const CMD_HELP = `usage: crowdsec-axi [command] [args] [flags]
commands:
  (none)=overview, decisions, alerts, bouncers, ban, unban, status
flags: --help (after command)

examples:
  crowdsec-axi
  crowdsec-axi decisions
  crowdsec-axi ban 1.2.3.4 --duration 4h --reason "bruteforce" --execute
  crowdsec-axi unban 1.2.3.4 --execute`;

const COMMANDS = {
  'decisions': `List CrowdSec decisions (bans)
flags: --active (default), --limit <n> (default 50), --help
examples:
  crowdsec-axi decisions
  crowdsec-axi decisions --limit 10`,
  'alerts': `List recent alerts
flags: --since <duration> (default 24h), --limit <n> (default 20), --help
examples:
  crowdsec-axi alerts
  crowdsec-axi alerts --since 7d`,
  'bouncers': `List registered bouncers
flags: --help
examples:
  crowdsec-axi bouncers`,
  'ban': `Ban an IP (dry-run unless --execute)
args: <ip>
flags: --duration <d> (default 4h), --reason <text>, --execute, --help
examples:
  crowdsec-axi ban 1.2.3.4 --execute`,
  'unban': `Remove all decisions for an IP (dry-run unless --execute)
args: <ip>
flags: --execute, --help
examples:
  crowdsec-axi unban 1.2.3.4 --execute`,
  'status': `LAPI connectivity and version
flags: --help`,
};

function cmdHelp(c) {
  return `usage: crowdsec-axi ${c}\n${COMMANDS[c]}`;
}

async function main() {
  const [cmd0, ...rest] = process.argv.slice(2);
  if (cmd0 === '--help' || cmd0 === '-h') { process.stdout.write(CMD_HELP + '\n'); process.exit(0); }
  const cmd = cmd0 || 'overview';

  if (!(cmd in COMMANDS) && cmd !== 'overview') {
    usageError(`unknown command: ${cmd}`, [`valid commands: overview, decisions, alerts, bouncers, ban, unban, status`, `Run \`crowdsec-axi --help\` for usage`]);
  }

  if (cmd === 'overview') {
    const f = parseFlags(rest, {});
    if (f.help) { process.stdout.write(CMD_HELP + '\n'); process.exit(0); }
    const decisions = json(['decisions', 'list']);
    const alerts = json(['alerts', 'list', '--limit', '100']);
    const bouncers = json(['bouncers', 'list']);
    const active = decisions.filter((d) => d.active);
    const out = [
      `bin: ${collapseHome(process.argv[1])}`,
      'description: CrowdSec — decisions, alerts, and bouncers for the selfhost WAF',
      `decisions: ${active.length} active of ${decisions.length} total`,
      `alerts_24h: ${alerts.length}`,
      `bouncers: ${bouncers.length}`,
    ];
    if (active.length > 0) {
      const rows = active.slice(0, 5).map((d) => ({
        ip: d.source?.ip || d.value || '?',
        scenario: (d.scenario || '?').slice(0, 40),
        expires: (d.expires_at || '').slice(0, 16),
      }));
      out.push(list('recent', ['ip', 'scenario', 'expires'], rows));
    }
    out.push(help([
      `Run \`crowdsec-axi decisions\` for all decisions`,
      `Run \`crowdsec-axi alerts --since 24h\` for recent alerts`,
      `Run \`crowdsec-axi ban <ip> --execute\` to ban an IP`,
    ]));
    process.stdout.write(out.join('\n') + '\n');
    process.exit(0);
  }

  if (cmd === 'decisions') {
    const f = parseFlags(rest, { values: ['limit'] });
    if (f.help) { process.stdout.write(cmdHelp('decisions') + '\n'); process.exit(0); }
    const limit = Math.min(parseInt(f.limit || '50', 10) || 50, 500);
    const decisions = json(['decisions', 'list']);
    const rows = decisions.slice(0, limit).map((d) => ({
      id: d.id,
      ip: d.source?.ip || d.value || '?',
      scenario: (d.scenario || '?').slice(0, 45),
      action: d.action || 'ban',
      expires: (d.expires_at || '').slice(0, 16),
    }));
    const out = [];
    if (decisions.length === 0) {
      out.push('decisions: 0 decisions found');
      out.push(help([`Run \`crowdsec-axi alerts\` to see what triggered`]));
    } else {
      out.push(list('decisions', ['id', 'ip', 'scenario', 'action', 'expires'], rows, { total: decisions.length }));
      out.push(help([
        `Run \`crowdsec-axi unban <ip> --execute\` to remove a ban`,
        `Run \`crowdsec-axi decisions --limit 200\` for more`,
      ]));
    }
    process.stdout.write(out.join('\n') + '\n');
    process.exit(0);
  }

  if (cmd === 'alerts') {
    const f = parseFlags(rest, { values: ['since', 'limit'] });
    if (f.help) { process.stdout.write(cmdHelp('alerts') + '\n'); process.exit(0); }
    const since = f.since || '24h';
    const limit = Math.min(parseInt(f.limit || '20', 10) || 20, 200);
    const alerts = json(['alerts', 'list', '--since', since]);
    const rows = alerts.slice(0, limit).map((a) => ({
      id: a.id,
      scenario: (a.scenario || '?').slice(0, 45),
      source: a.source?.ip || a.source?.value || '?',
      created: (a.created_at || '').slice(0, 16),
      events: a.events?.length ?? 0,
    }));
    const out = [];
    if (alerts.length === 0) {
      out.push(`alerts: 0 alerts found since ${since}`);
    } else {
      out.push(list('alerts', ['id', 'scenario', 'source', 'created', 'events'], rows, { total: alerts.length }));
      out.push(help([`Run \`crowdsec-axi decisions\` to see resulting bans`]));
    }
    process.stdout.write(out.join('\n') + '\n');
    process.exit(0);
  }

  if (cmd === 'bouncers') {
    const f = parseFlags(rest, {});
    if (f.help) { process.stdout.write(cmdHelp('bouncers') + '\n'); process.exit(0); }
    const bouncers = json(['bouncers', 'list']);
    const rows = bouncers.map((b) => ({
      name: b.name,
      type: b.type,
      last_pull: (b.last_pull || '').slice(0, 16),
    }));
    const out = [];
    if (bouncers.length === 0) {
      out.push('bouncers: 0 bouncers registered');
    } else {
      out.push(list('bouncers', ['name', 'type', 'last_pull'], rows));
    }
    process.stdout.write(out.join('\n') + '\n');
    process.exit(0);
  }

  if (cmd === 'ban' || cmd === 'unban') {
    const f = parseFlags(rest, { bools: ['execute'], values: ['duration', 'reason'] });
    if (f.help) { process.stdout.write(cmdHelp(cmd) + '\n'); process.exit(0); }
    if (f._.length !== 1) usageError(`${cmd} requires exactly one argument: <ip>`, [`Run \`crowdsec-axi ${cmd} --help\``]);
    const ip = f._[0];
    // idempotency pre-flight: already banned?
    const existing = json(['decisions', 'list']).filter((d) => d.source?.ip === ip && d.active);
    if (cmd === 'ban' && existing.length > 0) {
      process.stdout.write(
        kv({ result: 'no-op', ip, reason: `already has ${existing.length} active decision(s)` }) + '\n'
      );
      process.exit(0);
    }
    if (cmd === 'unban' && existing.length === 0) {
      process.stdout.write(kv({ result: 'no-op', ip, reason: 'no active decisions' }) + '\n');
      process.exit(0);
    }
    if (!f.execute) {
      const op = cmd === 'ban' ? 'add' : 'delete';
      process.stdout.write(
        kv({
          result: 'dry-run',
          ip,
          action: `${op} ${ip}${cmd === 'ban' ? ` (${f.duration || '4h'})` : ''}`,
          note: 're-run with --execute to apply',
        }) + '\n'
      );
      process.exit(0);
    }
    const args = cmd === 'ban'
      ? ['decisions', 'add', '--ip', ip, '--duration', f.duration || '4h', '--type', 'ban', ...(f.reason ? ['--reason', f.reason] : [])]
      : ['decisions', 'delete', '--ip', ip];
    const r = cscli(args, { timeout: 30000 });
    if (r.code !== 0) {
      fail(`cscli ${cmd}: ${r.stderr.trim() || 'command failed'}`, 'CSCLI_ERROR');
    }
    process.stdout.write(kv({ result: 'ok', ip, action: cmd }) + '\n');
    process.exit(0);
  }

  if (cmd === 'status') {
    const f = parseFlags(rest, {});
    if (f.help) { process.stdout.write(cmdHelp('status') + '\n'); process.exit(0); }
    const v = cscli(['version']);
    const lapi = json(['lapi', 'status']);
    const out = [
      `version: ${(v.stdout.split('\n')[0] || '').trim()}`,
      `lapi: ${lapi.url || 'unknown'}`,
    ];
    process.stdout.write(out.join('\n') + '\n');
    process.exit(0);
  }
}

main().catch((e) => fail(e.message, 'INTERNAL'));
