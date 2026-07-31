#!/usr/bin/env node
// libsql-axi — read-only queries against the selfhost libSQL (Turso) server over its HTTP API.
// Auth: Ed25519 JWT signed with the private key matching SQLD_AUTH_JWT_KEY (EdDSA, per sqld source).
import { existsSync, readFileSync } from 'node:fs';
import { createPrivateKey, sign } from 'node:crypto';
import { list, kv, help, fail, usageError, parseFlags, collapseHome, truncate } from './common.mjs';

const URL_BASE = process.env.LIBSQL_URL || 'http://127.0.0.1:7087';
const KEY_ENV = process.env.LIBSQL_PRIVATE_KEY || null;
const KEY_FILE = process.env.LIBSQL_PRIVATE_KEY_FILE || null;

function b64url(buf) {
  return Buffer.from(buf).toString('base64url');
}

function loadPrivateKey() {
  let material = KEY_ENV;
  if (!material && KEY_FILE && existsSync(KEY_FILE)) material = readFileSync(KEY_FILE, 'utf8').trim();
  if (!material) return null;
  // PEM PKCS#8
  if (material.includes('PRIVATE KEY')) {
    return createPrivateKey(material);
  }
  // base64url / base64 raw DER (PKCS#8)
  const der = Buffer.from(material, material.includes('+') || material.includes('/') ? 'base64' : 'base64url');
  try {
    return createPrivateKey({ key: der, format: 'der', type: 'pkcs8' });
  } catch {
    return null;
  }
}

function mintToken(privateKey, claims = {}) {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'EdDSA', typ: 'JWT' }));
  const payload = b64url(JSON.stringify({ exp: now + 300, ...claims }));
  const sig = sign(null, Buffer.from(`${header}.${payload}`), privateKey);
  return `${header}.${payload}.${b64url(sig)}`;
}

async function pipeline(sql, opts = {}) {
  const privateKey = loadPrivateKey();
  if (!privateKey) {
    fail('libSQL private key not available', 'AUTH_REQUIRED', [
      'Set LIBSQL_PRIVATE_KEY (PKCS#8 PEM or base64url DER) or LIBSQL_PRIVATE_KEY_FILE',
      'It must pair with SQLD_AUTH_JWT_KEY (LIBSQL_JWT_KEY in ~/docker/selfhost/.env)',
      'Run `libsql-axi doctor` to diagnose',
    ]);
  }
  const token = mintToken(privateKey, opts.namespace ? { id: opts.namespace } : {});
  const path = opts.namespace ? `/v2/pipeline/${encodeURIComponent(opts.namespace)}` : '/v2/pipeline';
  const res = await fetch(URL_BASE + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ requests: [{ type: 'execute', stmt: { sql } }] }),
    signal: AbortSignal.timeout(15000),
  });
  const text = await res.text();
  if (res.status === 401) {
    fail(`libSQL auth rejected (${text.slice(0, 100)})`, 'AUTH_REJECTED', [
      'Check that LIBSQL_PRIVATE_KEY matches SQLD_AUTH_JWT_KEY',
    ]);
  }
  if (!res.ok) {
    fail(`libSQL HTTP ${res.status}: ${text.slice(0, 200)}`, 'HTTP_ERROR');
  }
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    fail('libSQL returned invalid JSON', 'PARSE_ERROR');
  }
  const result = body.results?.[0]?.response;
  if (result?.error) {
    fail(`sql error: ${result.error.message}`, 'SQL_ERROR');
  }
  return result?.result || null;
}

const READ_OK = /^(select|show|describe|explain|with)\b/i;
function guard(sql) {
  const clean = sql.trim().replace(/^\/\*.*?\*\//s, '').trim();
  if (!READ_OK.test(clean)) {
    usageError('read-only AXI: only SELECT/SHOW/DESCRIBE/EXPLAIN/WITH allowed', [
      'Mutating SQL is intentionally rejected by libsql-axi',
    ]);
  }
  if (!/\blimit\s+\d+/i.test(clean)) return clean + ' LIMIT 50';
  return clean;
}

const CMD_HELP = `usage: libsql-axi [command] [args] [flags]
commands:
  (none)=overview, dbs, tables, query, doctor
flags: --help (after command)

examples:
  libsql-axi
  libsql-axi dbs
  libsql-axi tables
  libsql-axi query "select * from users" --limit 20
  libsql-axi doctor`;

const COMMANDS = {
  'dbs': `List databases (namespaces) on the server
flags: --help
examples:
  libsql-axi dbs`,
  'tables': `List tables in the default (or --namespace) database
flags: --namespace <name>, --help
examples:
  libsql-axi tables`,
  'query': `Run a capped read-only query
args: <sql>
flags: --limit <n> (default 50), --full, --namespace <name>, --help
examples:
  libsql-axi query "select * from users"
  libsql-axi query "select id, body from posts limit 1" --full`,
  'doctor': `Check key, server reachability, and auth round-trip
flags: --help`,
};

function cmdHelp(c) {
  return `usage: libsql-axi ${c}\n${COMMANDS[c]}`;
}

async function main() {
  const [cmd0, ...rest] = process.argv.slice(2);
  if (cmd0 === '--help' || cmd0 === '-h') { process.stdout.write(CMD_HELP + '\n'); process.exit(0); }
  const cmd = cmd0 || 'overview';

  if (!(cmd in COMMANDS) && cmd !== 'overview') {
    usageError(`unknown command: ${cmd}`, [`valid commands: overview, dbs, tables, query, doctor`, `Run \`libsql-axi --help\` for usage`]);
  }

  if (cmd === 'overview') {
    const f = parseFlags(rest, {});
    if (f.help) { process.stdout.write(CMD_HELP + '\n'); process.exit(0); }
    const hasKey = !!loadPrivateKey();
    const out = [
      `bin: ${collapseHome(process.argv[1])}`,
      `description: libSQL (${URL_BASE}) — read-only queries against the selfhost Turso server`,
      `auth_key: ${hasKey ? 'present' : 'MISSING'}`,
    ];
    if (!hasKey) {
      out.push(help([
        `Set LIBSQL_PRIVATE_KEY or LIBSQL_PRIVATE_KEY_FILE to enable queries`,
        `Run \`libsql-axi doctor\` for diagnostics`,
      ]));
      process.stdout.write(out.join('\n') + '\n');
      process.exit(0);
    }
    // reachability + table count
    try {
      const res = await pipeline("SELECT count(*) AS n FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%'");
      out.push(`server: ok`);
      out.push(`tables: ${res?.rows?.[0]?.[1] ?? '?'}`);
      out.push(help([
        `Run \`libsql-axi tables\` to list tables`,
        `Run \`libsql-axi query "<sql>"\` to query`,
      ]));
    } catch (e) {
      out.push(`server: unreachable (${e.message})`);
    }
    process.stdout.write(out.join('\n') + '\n');
    process.exit(0);
  }

  if (cmd === 'doctor') {
    const f = parseFlags(rest, {});
    if (f.help) { process.stdout.write(cmdHelp('doctor') + '\n'); process.exit(0); }
    const out = [];
    const key = loadPrivateKey();
    out.push(`private_key: ${key ? 'ok' : 'MISSING'}`);
    if (!key) {
      out.push(help([
        'Provide the Ed25519 private key that pairs with SQLD_AUTH_JWT_KEY:',
        'export LIBSQL_PRIVATE_KEY="<pkcs8 pem or base64url der>"   (or LIBSQL_PRIVATE_KEY_FILE=/path/key.pem)',
      ]));
    }
    try {
      const res = await fetch(URL_BASE + '/v2/pipeline', { method: 'POST', signal: AbortSignal.timeout(5000) });
      out.push(`server: reachable (HTTP ${res.status} without auth — expected)`);
    } catch (e) {
      out.push(`server: unreachable (${e.message})`);
    }
    if (key) {
      try {
        const r = await pipeline('select 1 as ok');
        out.push(`auth_roundtrip: ok`);
        if (r?.rows?.[0]) out.push(`server_time: ${r.rows[0][1]}`);
      } catch (e) {
        out.push(`auth_roundtrip: failed (${e.message})`);
      }
    }
    process.stdout.write(out.join('\n') + '\n');
    process.exit(0);
  }

  if (cmd === 'dbs') {
    const f = parseFlags(rest, {});
    if (f.help) { process.stdout.write(cmdHelp('dbs') + '\n'); process.exit(0); }
    const res = await fetch(URL_BASE + '/v1/namespaces', {
      headers: { Authorization: `Bearer ${mintToken(loadPrivateKey())}` },
      signal: AbortSignal.timeout(5000),
    });
    if (res.status === 404) {
      process.stdout.write('namespaces: single-database mode (endpoint not exposed)\n');
      process.exit(0);
    }
    if (res.ok) {
      const namespaces = await res.json();
      const rows = namespaces.map((n) => ({ name: n }));
      const out = rows.length
        ? [list('namespaces', ['name'], rows), help([`Run \`libsql-axi tables --namespace <name>\` to explore one`])]
        : ['namespaces: 0 databases found'];
      process.stdout.write(out.join('\n') + '\n');
      process.exit(0);
    }
    fail(`namespaces: HTTP ${res.status}`, 'HTTP_ERROR');
  }

  if (cmd === 'tables') {
    const f = parseFlags(rest, { values: ['namespace'] });
    if (f.help) { process.stdout.write(cmdHelp('tables') + '\n'); process.exit(0); }
    const res = await pipeline("SELECT name, type FROM sqlite_schema WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' ORDER BY name", { namespace: f.namespace });
    const rows = (res?.rows || []).map((r) => ({ name: r[1], type: r[2] }));
    const out = [];
    if (rows.length === 0) {
      out.push(`tables: 0 tables found${f.namespace ? ` in namespace "${f.namespace}"` : ''}`);
    } else {
      out.push(list('tables', ['name', 'type'], rows));
      out.push(help([`Run \`libsql-axi query "select * from <table> limit 5"${f.namespace ? ` --namespace ${f.namespace}` : ''}\` to peek`]));
    }
    process.stdout.write(out.join('\n') + '\n');
    process.exit(0);
  }

  if (cmd === 'query') {
    const f = parseFlags(rest, { bools: ['full'], values: ['limit', 'namespace'] });
    if (f.help) { process.stdout.write(cmdHelp('query') + '\n'); process.exit(0); }
    if (f._.length !== 1) usageError('query requires exactly one argument: <sql>', ['Run `libsql-axi query --help`']);
    const sql = guard(f._[0]);
    const limit = Math.min(parseInt(f.limit || '50', 10) || 50, 500);
    const res = await pipeline(sql, { namespace: f.namespace });
    if (!res) {
      process.stdout.write('query: 0 rows returned\n');
      process.exit(0);
    }
    const cols = res.columns || [];
    const rows = (res.rows || []).slice(0, limit).map((row) => {
      const o = {};
      cols.forEach((c, i) => {
        // hrana cell = [type, value]
        const cell = Array.isArray(row[i]) ? row[i][1] : row[i];
        o[c] = f.full ? cell : truncate(cell ?? '', 120);
      });
      return o;
    });
    const out = [];
    if (rows.length === 0) {
      out.push('query: 0 rows returned');
    } else {
      out.push(list('result', cols, rows, { total: res.rows.length }));
      out.push(help([`Run \`libsql-axi query "${sql}" --limit 500\` for more rows`]));
    }
    process.stdout.write(out.join('\n') + '\n');
    process.exit(0);
  }
}

main().catch((e) => fail(e.message, 'INTERNAL'));
