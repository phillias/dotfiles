#!/usr/bin/env node
// godoxy-axi — reverse proxy routes for the selfhost stack (API-view).
// Reads live state from the GoDoxy local API (/api/v1) — routes, containers, config files.
// Read-only. Requires GODOXY_LOCAL_API_ADDR to be set on the godoxy deployment
// (unauthenticated loopback-only listener; the main API is behind browser OIDC auth).
import { list, kv, help, fail, usageError, parseFlags, collapseHome } from './common.mjs';

const API_URL = process.env.GODOXY_API_URL || 'http://127.0.0.1:8889';
const BASE = `${API_URL}/api/v1`;

async function apiGet(path) {
  let res;
  try {
    res = await fetch(`${BASE}${path}`, { signal: AbortSignal.timeout(8000) });
  } catch (e) {
    fail(`godoxy API unreachable at ${API_URL}`, 'API_UNREACHABLE', [
      `Is godoxy running with GODOXY_LOCAL_API_ADDR set? (add to ~/docker/selfhost/.env, then restart godoxy)`,
      `Override the API base with GODOXY_API_URL (default http://127.0.0.1:8889)`,
    ]);
  }
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    fail(`godoxy API ${res.status} on GET ${path}${body ? `: ${body.slice(0, 200)}` : ''}`, `API_${res.status}`);
  }
  return res.json();
}

// --- routes: GET /api/v1/route/list (live effective state, incl. docker-derived) ---
async function getRoutes() {
  const arr = await apiGet('/route/list');
  return Array.isArray(arr) ? arr : [];
}

// --- containers: GET /api/v1/docker/containers ---
async function getContainers() {
  const arr = await apiGet('/docker/containers');
  return Array.isArray(arr) ? arr : [];
}

// --- config.yml content via file API (same file Godoxy manages — cannot diverge) ---
// The file/content endpoint returns raw YAML text, not JSON.
async function getConfigYml() {
  let res;
  try {
    res = await fetch(`${BASE}/file/content?type=config&filename=config.yml`, { signal: AbortSignal.timeout(8000) });
  } catch (e) {
    fail(`godoxy API unreachable at ${API_URL}`, 'API_UNREACHABLE', [
      `Is godoxy running with GODOXY_LOCAL_API_ADDR set? (add to ~/docker/selfhost/.env, then restart godoxy)`,
      `Override the API base with GODOXY_API_URL (default http://127.0.0.1:8889)`,
    ]);
  }
  if (!res.ok) {
    fail(`godoxy API ${res.status} on GET /file/content`, `API_${res.status}`);
  }
  return res.text();
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

function parseConfig(text) {
  const cfg = { middlewares: [], aclAllow: [], aclDeny: [], autocertDomains: [], autocertProvider: null };

  const entry = extractBlock(text, 'entrypoint');
  const mwMatch = entry.match(/^\s*middlewares:\s*$/m);
  if (mwMatch) {
    const mwBlock = entry.slice(mwMatch.index + mwMatch[0].length);
    for (const line of mwBlock.split('\n')) {
      if (/^\S/.test(line)) break;
      const u = line.match(/^\s{4}-\s*use:\s*(\S+)/);
      if (u) cfg.middlewares.push(u[1]);
    }
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

// --- route helpers ---
function routeTarget(r) {
  const pick = (u) => (u && !/^[a-z]+:\/\/:0$/.test(u) && !/:0$/.test(u) ? u : null);
  return pick(r.purl) || pick(r.lurl) || '-';
}

function routeSource(r) {
  return r.container ? 'docker' : 'hostapps';
}

// excluded = container opted out of proxying (proxy.exclude) — still listed by the API
function isExcluded(r) {
  return !!(r.container && r.container.is_excluded);
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
  'routes': `All proxy routes (live state from GoDoxy API)
flags: --source <hostapps|docker>, --limit <n>, --help
examples:
  godoxy-axi routes
  godoxy-axi routes --source docker`,
  'route': `Detail for one route
args: <name>
flags: --help
examples:
  godoxy-axi route netdata`,
  'hostapps': `Routes defined in config (not from container labels)
flags: --help`,
  'containers': `Containers known to GoDoxy (from the API, with route target where proxied)
flags: --help`,
  'acl': `Access control allow/deny lists
flags: --help`,
  'config': `Entrypoint summary: middlewares, autocert, ACL counts
flags: --help`,
};

function cmdHelp(c) {
  return `usage: godoxy-axi ${c}\n${COMMANDS[c]}`;
}

async function main() {
  const [cmd0, ...rest] = process.argv.slice(2);
  if (cmd0 === '--help' || cmd0 === '-h') { process.stdout.write(CMD_HELP + '\n'); process.exit(0); }
  const cmd = cmd0 || 'overview';

  if (!(cmd in COMMANDS) && cmd !== 'overview') {
    usageError(`unknown command: ${cmd}`, [`valid commands: overview, routes, route, hostapps, containers, acl, config`, `Run \`godoxy-axi --help\` for usage`]);
  }

  if (cmd === 'overview') {
    const f = parseFlags(rest, {});
    if (f.help) { process.stdout.write(CMD_HELP + '\n'); process.exit(0); }
    const [routes, cfgText] = await Promise.all([getRoutes(), getConfigYml()]);
    const cfg = parseConfig(cfgText);
    const active = routes.filter((r) => !isExcluded(r));
    const docker = active.filter((r) => routeSource(r) === 'docker').length;
    const hostapps = active.length - docker;
    const excluded = routes.length - active.length;
    const out = [
      `bin: ${collapseHome(process.argv[1])}`,
      `api: ${API_URL}`,
      'description: GoDoxy reverse proxy routes for the selfhost stack (API-view)',
      `routes: ${active.length} (${hostapps} hostapps, ${docker} docker${excluded ? `, ${excluded} excluded` : ''})`,
      `middlewares: ${cfg.middlewares.length}`,
      `acl: ${cfg.aclAllow.length} allow / ${cfg.aclDeny.length} deny`,
    ];
    if (active.length > 0) {
      const rows = active.slice(0, 10).map((r) => ({ name: r.alias, target: routeTarget(r), source: routeSource(r) }));
      out.push(list('routes', ['name', 'target', 'source'], rows, { total: routes.length }));
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
    if (source && source !== 'hostapps' && source !== 'docker') {
      usageError(`invalid --source: ${source}`, [`valid values: hostapps, docker`]);
    }
    const routes = await getRoutes();
    let all = routes.filter((r) => !isExcluded(r));
    if (source === 'hostapps') all = all.filter((r) => routeSource(r) === 'hostapps');
    if (source === 'docker') all = all.filter((r) => routeSource(r) === 'docker');
    const limit = Math.min(parseInt(f.limit || '100', 10) || 100, 500);
    const names = all.slice(0, limit);
    const rows = names.map((r) => ({
      name: r.alias,
      target: routeTarget(r),
      middlewares: mwString(r),
      source: routeSource(r),
    }));
    const out = [];
    if (rows.length === 0) {
      out.push('routes: 0 routes found');
    } else {
      out.push(list('routes', ['name', 'target', 'middlewares', 'source'], rows, { total: all.length }));
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
    const routes = await getRoutes();
    const r = routes.find((x) => x.alias === name);
    if (!r) {
      fail(`route not found: ${name}`, 'NOT_FOUND', [`Run \`godoxy-axi routes\` to list routes`]);
    }
    const detail = {
      name: r.alias,
      target: routeTarget(r),
      source: routeSource(r),
      scheme: r.scheme,
      host: r.host,
      port: r.port?.proxy ?? '',
      middlewares: mwString(r),
    };
    if (r.container) {
      detail.container = r.container.container_name || '';
      detail.state = r.container.state || '';
    }
    if (r.health?.status) {
      detail.health = r.health.status;
      if (r.health.latency) detail.latency = `${Math.round(r.health.latency)}ms`;
      if (r.health.uptime) detail.uptime = `${Math.round(r.health.uptime)}s`;
    }
    process.stdout.write(kv(detail) + '\n');
    process.exit(0);
  }

  if (cmd === 'hostapps') {
    const f = parseFlags(rest, {});
    if (f.help) { process.stdout.write(cmdHelp('hostapps') + '\n'); process.exit(0); }
    const routes = await getRoutes();
    const all = routes.filter((r) => !isExcluded(r) && routeSource(r) === 'hostapps');
    const rows = all.map((r) => ({ name: r.alias, target: routeTarget(r) }));
    const out = [];
    if (rows.length === 0) {
      out.push('hostapps: 0 routes found');
    } else {
      out.push(list('hostapps', ['name', 'target'], rows));
    }
    process.stdout.write(out.join('\n') + '\n');
    process.exit(0);
  }

  if (cmd === 'containers') {
    const f = parseFlags(rest, {});
    if (f.help) { process.stdout.write(cmdHelp('containers') + '\n'); process.exit(0); }
    const [containers, routes] = await Promise.all([getContainers(), getRoutes()]);
    const targetByContainer = new Map(
      routes.filter((r) => r.container?.container_name).map((r) => [r.container.container_name, routeTarget(r)])
    );
    const rows = containers.map((c) => {
      const name = (c.name || '').replace(/^\//, '');
      return {
        name,
        state: c.state || '',
        image: (c.image || '').split('@')[0],
        target: targetByContainer.get(name) || '-',
      };
    });
    const out = [];
    if (rows.length === 0) {
      out.push('containers: 0 containers found');
    } else {
      out.push(list('containers', ['name', 'state', 'image', 'target'], rows));
    }
    process.stdout.write(out.join('\n') + '\n');
    process.exit(0);
  }

  if (cmd === 'acl') {
    const f = parseFlags(rest, {});
    if (f.help) { process.stdout.write(cmdHelp('acl') + '\n'); process.exit(0); }
    const cfgText = await getConfigYml();
    const cfg = parseConfig(cfgText);
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
    const cfgText = await getConfigYml();
    const cfg = parseConfig(cfgText);
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
