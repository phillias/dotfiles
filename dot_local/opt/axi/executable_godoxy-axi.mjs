#!/usr/bin/env node
// godoxy-axi — reverse proxy routes for the selfhost stack (config-view).
// Reads hostapps.yml + config.yml + live docker labels. Read-only.
import { existsSync, readFileSync } from 'node:fs';
import { list, kv, help, fail, usageError, parseFlags, run, collapseHome } from './common.mjs';

const GODOXY_DIR = process.env.GODOXY_DIR || `${process.env.HOME}/docker/selfhost/godoxy`;
const CONFIG_YML = `${GODOXY_DIR}/config/config.yml`;
const HOSTAPPS_YML = `${GODOXY_DIR}/config/hostapps.yml`;

function readYml(path) {
  if (!existsSync(path)) return null;
  return readFileSync(path, 'utf8');
}

// --- hostapps.yml: flat blocks `name:` + indented key: value pairs (with nesting) ---
function parseHostapps(text) {
  const routes = {};
  const blocks = text.split(/^(?=\S)/m);
  for (const block of blocks) {
    const header = block.match(/^([\w.-]+):\s*$/m);
    if (!header) continue;
    const name = header[1];
    const body = block.slice(block.indexOf('\n') + 1);
    const route = {};
    const stack = [{ obj: route, indent: 0 }];
    for (const line of body.split('\n')) {
      if (!line.trim() || line.trim().startsWith('#')) continue;
      const m = line.match(/^(\s*)([^:#]+):\s*(.*)$/);
      if (!m) continue;
      const key = m[2].trim();
      const val = m[3].trim();
      const indent = m[1].length;
      if (indent < 2) break; // next top-level block
      while (stack.length > 1 && stack[stack.length - 1].indent >= indent) stack.pop();
      const parent = stack[stack.length - 1].obj;
      if (val === '') {
        parent[key] = {};
        stack.push({ obj: parent[key], indent });
      } else if (val.startsWith('- ')) {
        if (!Array.isArray(parent[key])) parent[key] = [];
        parent[key].push(val.slice(2));
      } else {
        parent[key] = val;
      }
    }
    routes[name] = route;
  }
  return routes;
}

// --- config.yml: targeted extraction (line-based) ---
function extractBlock(text, topKey) {
  const lines = text.split('\n');
  const start = lines.findIndex((l) => l === `${topKey}:`);
  if (start === -1) return '';
  const out = [];
  for (let i = start + 1; i < lines.length; i++) {
    const l = lines[i];
    if (/^\S/.test(l)) break; // next top-level key ends the block
    out.push(l);
  }
  return out.join('\n');
}

function parseListItems(blockText) {
  const items = [];
  for (const line of blockText.split('\n')) {
    const m = line.match(/^\s*-\s*(.*)$/);
    if (m) items.push(m[1].replace(/^["']|["']$/g, ''));
  }
  return items;
}

function parseConfig() {
  const text = readYml(CONFIG_YML);
  if (!text) return null;
  const cfg = { middlewares: [], aclAllow: [], aclDeny: [], autocertDomains: [], autocertProvider: null };

  const entry = extractBlock(text, 'entrypoint');
  const mwMatch = entry.match(/^\s*middlewares:\s*$/m);
  if (mwMatch) {
    const mwBlock = entry.slice(mwMatch.index + mwMatch[0].length);
    const mwLines = [];
    for (const line of mwBlock.split('\n')) {
      if (/^\S/.test(line)) break;
      const u = line.match(/^\s{4}-\s*use:\s*(\S+)/);
      if (u) mwLines.push(u[1]);
    }
    cfg.middlewares = mwLines;
  }

  const aclBlock = extractBlock(text, 'acl');
  const allowMatch = aclBlock.match(/^\s*allow:\s*$/m);
  if (allowMatch) {
    cfg.aclAllow = parseListItems(aclBlock.slice(allowMatch.index + allowMatch[0].length));
  }
  const denyMatch = aclBlock.match(/^\s*deny:\s*$/m);
  if (denyMatch) {
    cfg.aclDeny = parseListItems(aclBlock.slice(denyMatch.index + denyMatch[0].length));
  }

  const acBlock = extractBlock(text, 'autocert');
  const prov = acBlock.match(/^\s*provider:\s*(\S+)/);
  if (prov) cfg.autocertProvider = prov[1];
  const doms = acBlock.match(/^\s*domains:\s*$/m);
  if (doms) {
    cfg.autocertDomains = parseListItems(acBlock.slice(doms.index + doms[0].length));
  }
  return cfg;
}

// --- docker label routes ---
function dockerRoutes() {
  const r = run('docker', ['ps', '-q']);
  if (r.code !== 0) return { routes: {}, error: r.stderr.trim() };
  const ids = r.stdout.trim().split('\n').filter(Boolean);
  if (ids.length === 0) return { routes: {} };
  const insp = run('docker', ['inspect', ...ids]);
  if (insp.code !== 0) return { routes: {}, error: insp.stderr.trim() };
  let containers;
  try {
    containers = JSON.parse(insp.stdout);
  } catch {
    return { routes: {}, error: 'failed to parse docker inspect' };
  }
  const routes = {};
  for (const c of containers) {
    const labels = c.Config?.Labels || {};
    if (labels['proxy.exclude'] === 'true') continue;
    const name = c.Name?.replace(/^\//, '');
    const aliases = (labels['proxy.aliases'] || name || '').split(',').map((s) => s.trim()).filter(Boolean);
    const ports = (c.NetworkSettings?.Ports || {});
    for (const alias of aliases) {
      const prefix = `proxy.${alias}.`;
      let port = labels[`${prefix}port`] || labels[`proxy.${alias.replace(/^host/, '')}.port`];
      if (!port) {
        const first = Object.keys(ports)[0];
        port = first ? first.split('/')[0] : '';
      }
      routes[alias] = {
        target: `${labels[`${prefix}scheme`] || 'http'}://${name || alias}:${port || '?'}`,
        scheme: labels[`${prefix}scheme`] || 'http',
        port: port || '?',
        middlewares: labels[`${prefix}middlewares`] || labels['proxy.middlewares'] || '',
        source: 'docker',
        container: name,
      };
    }
  }
  return { routes };
}

const CMD_HELP = `usage: godoxy-axi [command] [args] [flags]
commands:
  (none)=overview, routes, route, hostapps, containers, acl, config
flags: --help (after command)

examples:
  godoxy-axi
  godoxy-axi routes
  godoxy-axi route netdata
  godoxy-axi acl
  godoxy-axi containers`;

const COMMANDS = {
  'routes': `All proxy routes (hostapps.yml + docker labels)
flags: --source <hostapps|docker>, --limit <n>, --help
examples:
  godoxy-axi routes
  godoxy-axi routes --source docker`,
  'route': `Detail for one route
args: <name>
flags: --help
examples:
  godoxy-axi route netdata`,
  'hostapps': `Routes defined in hostapps.yml
flags: --help`,
  'containers': `Routes derived from docker container labels
flags: --help`,
  'acl': `Access control allow/deny lists
flags: --help`,
  'config': `Entrypoint summary: middlewares, autocert, ACL counts
flags: --help`,
};

function cmdHelp(c) {
  return `usage: godoxy-axi ${c}\n${COMMANDS[c]}`;
}

function routeTarget(r) {
  if (r.target) return r.target;
  const port = String(r.port || '').replace(/^:/, '');
  const host = r.host || (r.port?.startsWith(':') ? '127.0.0.1' : r.container) || '?';
  return `${r.scheme || 'http'}://${host}:${port || '?'}`;
}

function mwString(r) {
  const m = r.middlewares;
  if (Array.isArray(m)) return m.join(', ').slice(0, 40) || '-';
  if (m && typeof m === 'object') return Object.keys(m).join(', ').slice(0, 40) || '-';
  return String(m || '-').slice(0, 40);
}

function fmtVal(v) {
  if (v && typeof v === 'object') {
    if (Array.isArray(v)) return v.join(', ');
    return `{${Object.entries(v).map(([k, val]) => `${k}: ${fmtVal(val)}`).join(', ')}}`;
  }
  return v;
}

async function main() {
  const [cmd0, ...rest] = process.argv.slice(2);
  if (cmd0 === '--help' || cmd0 === '-h') { process.stdout.write(CMD_HELP + '\n'); process.exit(0); }
  const cmd = cmd0 || 'overview';

  if (!(cmd in COMMANDS) && cmd !== 'overview') {
    usageError(`unknown command: ${cmd}`, [`valid commands: overview, routes, route, hostapps, containers, acl, config`, `Run \`godoxy-axi --help\` for usage`]);
  }

  const haText = readYml(HOSTAPPS_YML);
  const hostapps = haText ? parseHostapps(haText) : {};
  const { routes: dockerR, error: dockerErr } = dockerRoutes();
  const cfg = parseConfig();

  if (cmd === 'overview') {
    const f = parseFlags(rest, {});
    if (f.help) { process.stdout.write(CMD_HELP + '\n'); process.exit(0); }
    const all = { ...hostapps, ...dockerR };
    const names = Object.keys(all);
    const out = [
      `bin: ${collapseHome(process.argv[1])}`,
      'description: GoDoxy reverse proxy routes for the selfhost stack (config-view)',
      `routes: ${names.length} (${Object.keys(hostapps).length} hostapps, ${Object.keys(dockerR).length} docker)`,
      `middlewares: ${cfg ? cfg.middlewares.length : 0}`,
      `acl: ${cfg ? `${cfg.aclAllow.length} allow / ${cfg.aclDeny.length} deny` : 'n/a'}`,
    ];
    if (dockerErr) out.push(`docker: warning - ${dockerErr}`);
    if (names.length > 0) {
      const rows = names.slice(0, 10).map((n) => ({ name: n, target: routeTarget(all[n]), source: all[n].source || 'hostapps' }));
      out.push(list('routes', ['name', 'target', 'source'], rows, { total: names.length }));
      out.push(help([
        `Run \`godoxy-axi routes\` for all routes`,
        `Run \`godoxy-axi route <name>\` for a route's detail`,
      ]));
    }
    process.stdout.write(out.join('\n') + '\n');
    process.exit(0);
  }

  if (cmd === 'routes') {
    const f = parseFlags(rest, { values: ['source', 'limit'] });
    if (f.help) { process.stdout.write(cmdHelp('routes') + '\n'); process.exit(0); }
    const source = f.source;
    let all = { ...hostapps, ...dockerR };
    if (source === 'hostapps') all = hostapps;
    if (source === 'docker') all = dockerR;
    const limit = Math.min(parseInt(f.limit || '100', 10) || 100, 500);
    const names = Object.keys(all).slice(0, limit);
    const rows = names.map((n) => ({
      name: n,
      target: routeTarget(all[n]),
      middlewares: mwString(all[n]),
      source: all[n].source || 'hostapps',
    }));
    const out = [];
    if (names.length === 0) {
      out.push('routes: 0 routes found');
    } else {
      out.push(list('routes', ['name', 'target', 'middlewares', 'source'], rows, { total: Object.keys(all).length }));
      out.push(help([`Run \`godoxy-axi route <name>\` for details`]));
    }
    process.stdout.write(out.join('\n') + '\n');
    process.exit(0);
  }

  if (cmd === 'route') {
    const f = parseFlags(rest, {});
    if (f.help) { process.stdout.write(cmdHelp('route') + '\n'); process.exit(0); }
    if (f._.length !== 1) usageError('route requires exactly one argument: <name>', ['Run `godoxy-axi route --help`']);
    const name = f._[0];
    const ha = hostapps[name];
    const dr = dockerR[name];
    if (!ha && !dr) {
      fail(`route not found: ${name}`, 'NOT_FOUND', [`Run \`godoxy-axi routes\` to list routes`]);
    }
    const route = ha || dr;
    const out = [`name: ${name}`];
    for (const [k, v] of Object.entries(route)) {
      out.push(`${k}: ${fmtVal(v)}`);
    }
    if (ha && dr) out.push('note: defined in both hostapps.yml and docker labels (hostapps wins)');
    process.stdout.write(out.join('\n') + '\n');
    process.exit(0);
  }

  if (cmd === 'hostapps' || cmd === 'containers') {
    const f = parseFlags(rest, {});
    if (f.help) { process.stdout.write(cmdHelp(cmd) + '\n'); process.exit(0); }
    const src = cmd === 'hostapps' ? hostapps : dockerR;
    const srcName = cmd === 'hostapps' ? 'hostapps' : 'containers';
    const names = Object.keys(src);
    const rows = names.map((n) => ({ name: n, target: routeTarget(src[n]) }));
    const out = [];
    if (names.length === 0) {
      out.push(`${srcName}: 0 routes found`);
    } else {
      out.push(list(srcName, ['name', 'target'], rows));
    }
    process.stdout.write(out.join('\n') + '\n');
    process.exit(0);
  }

  if (cmd === 'acl') {
    const f = parseFlags(rest, {});
    if (f.help) { process.stdout.write(cmdHelp('acl') + '\n'); process.exit(0); }
    if (!cfg) fail('config.yml not found', 'CONFIG_MISSING', [`Expected at ${CONFIG_YML}`]);
    const out = [
      list('allow', ['entry'], cfg.aclAllow.map((a) => ({ entry: a }))),
      list('deny', ['entry'], cfg.aclDeny.map((a) => ({ entry: a }))),
    ];
    process.stdout.write(out.join('\n') + '\n');
    process.exit(0);
  }

  if (cmd === 'config') {
    const f = parseFlags(rest, {});
    if (f.help) { process.stdout.write(cmdHelp('config') + '\n'); process.exit(0); }
    if (!cfg) fail('config.yml not found', 'CONFIG_MISSING', [`Expected at ${CONFIG_YML}`]);
    const out = [
      `autocert: ${cfg.autocertProvider || '?'} (${cfg.autocertDomains.length} domains)`,
      list('middlewares', ['name'], cfg.middlewares.map((m) => ({ name: m }))),
      `acl: ${cfg.aclAllow.length} allow / ${cfg.aclDeny.length} deny`,
    ];
    if (cfg.aclAllow.length || cfg.aclDeny.length) {
      out.push(help([`Run \`godoxy-axi acl\` for the full lists`]));
    }
    process.stdout.write(out.join('\n') + '\n');
    process.exit(0);
  }
}

main().catch((e) => fail(e.message, 'INTERNAL'));
