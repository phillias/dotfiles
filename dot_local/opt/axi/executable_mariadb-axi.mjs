#!/usr/bin/env node
// mariadb-axi — read-only MariaDB inspection for the selfhost stack. TOON output.
import { existsSync, readFileSync } from 'node:fs';
import { list, kv, help, fail, usageError, parseFlags, run, collapseHome, truncate } from './common.mjs';

const CLIENT = process.env.MARIADB_BIN || 'mariadb';
const ENV_FILE = process.env.MARIADB_ENV_FILE || `${process.env.HOME}/docker/selfhost/.env`;

// --- connection config: env first, then selfhost .env discovery ---
function creds() {
  let env = {};
  if (existsSync(ENV_FILE)) {
    for (const line of readFileSync(ENV_FILE, 'utf8').split('\n')) {
      const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
      if (m) env[m[1]] = m[2].replace(/^["']|["']$/g, '');
    }
  }
  return {
    host: process.env.MARIADB_HOST || '127.0.0.1',
    port: process.env.MARIADB_PORT || '3306',
    user: process.env.MARIADB_USER || env.MYSQL_USER || 'root',
    password: process.env.MARIADB_PASSWORD || env.MYSQL_PASSWORD || env.MYSQL_ROOT_PASSWORD || '',
    database: process.env.MARIADB_DATABASE || env.MYSQL_DATABASE || '',
  };
}

function client(args, opts = {}) {
  const c = creds();
  const base = [CLIENT, '-h', c.host, '-P', c.port, '-u', c.user, '-B', '--column-names=1', '--connect-timeout=5'];
  return run(CLIENT, [...base.slice(1), ...args], {
    env: { MYSQL_PWD: c.password, ...(opts.env || {}) },
    timeout: opts.timeout || 20000,
  });
}

// --- read-only guard ---
const READ_OK = /^(select|show|describe|desc|explain|with)\b/i;
function guard(sql) {
  const clean = sql.trim().replace(/^\/\*.*?\*\//s, '').trim();
  if (!READ_OK.test(clean)) {
    usageError('read-only AXI: only SELECT/SHOW/DESCRIBE/EXPLAIN/WITH allowed', [
      'Mutating SQL is intentionally rejected by mariadb-axi',
      'Use the mariadb client directly for writes',
    ]);
  }
  if (/^(select|with)\b/i.test(clean) && !/\blimit\s+\d+/i.test(clean)) {
    return clean + ' LIMIT 50';
  }
  return clean;
}

// --- parse batch output into {cols, rows} ---
function parseBatch(stdout) {
  const lines = stdout.split('\n').filter((l) => l !== '');
  if (lines.length === 0) return { cols: [], rows: [] };
  const cols = lines[0].split('\t');
  const rows = lines.slice(1).map((l) => {
    const parts = l.split('\t');
    const o = {};
    cols.forEach((c, i) => { o[c] = parts[i] ?? ''; });
    return o;
  });
  return { cols, rows };
}

const CMD_HELP = `usage: mariadb-axi [command] [args] [flags]
commands:
  (none)=overview, dbs, tables, query, status, processlist
flags: --help (after command)

examples:
  mariadb-axi
  mariadb-axi dbs
  mariadb-axi tables sandbox
  mariadb-axi query "select * from users where active = 1" --limit 20
  mariadb-axi processlist`;

const COMMANDS = {
  'dbs': `List databases with size and table counts
flags: --help
examples:
  mariadb-axi dbs`,
  'tables': `List tables in a database with estimated rows
args: <database>
flags: --limit <n> (default 100), --help
examples:
  mariadb-axi tables sandbox`,
  'query': `Run a capped read-only query
args: <sql>
flags: --limit <n> (default 50), --full (untruncated cells), --help
examples:
  mariadb-axi query "select * from users"
  mariadb-axi query "select id, body from posts where id = 42" --full`,
  'status': `Server status summary (uptime, connections, queries)
flags: --help
examples:
  mariadb-axi status`,
  'processlist': `Running queries
flags: --limit <n> (default 20), --full, --help
examples:
  mariadb-axi processlist
  mariadb-axi processlist --full`,
};

function cmdHelp(c) {
  return `usage: mariadb-axi ${c}\n${COMMANDS[c]}`;
}

function connError(r) {
  const msg = r.stderr.split('\n').find((l) => /error/i.test(l)) || r.stderr.trim() || r.stdout.trim();
  fail(`mariadb: ${msg.slice(0, 300) || 'connection failed'}`, 'DB_ERROR', [
    `Checked ${creds().user}@${creds().host}:${creds().port}`,
    `Set MARIADB_USER/MARIADB_PASSWORD or fix ${ENV_FILE}`,
  ]);
}

async function main() {
  const [cmd0, ...rest] = process.argv.slice(2);
  if (cmd0 === '--help' || cmd0 === '-h') { process.stdout.write(CMD_HELP + '\n'); process.exit(0); }
  const cmd = cmd0 || 'overview';

  if (!(cmd in COMMANDS) && cmd !== 'overview') {
    usageError(`unknown command: ${cmd}`, [`valid commands: overview, dbs, tables, query, status, processlist`, `Run \`mariadb-axi --help\` for usage`]);
  }

  if (cmd === 'overview') {
    const f = parseFlags(rest, {});
    if (f.help) { process.stdout.write(CMD_HELP + '\n'); process.exit(0); }
    const r = client(['-e', "SELECT VERSION() v, (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME='Uptime') uptime, (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME='Threads_connected') threads, (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME='Queries') queries"]);
    if (r.code !== 0) connError(r);
    const { rows } = parseBatch(r.stdout);
    const st = rows[0] || {};
    const out = [
      `bin: ${collapseHome(process.argv[1])}`,
      `description: MariaDB (${creds().host}:${creds().port}) — read-only inspection for the selfhost stack`,
      `version: ${st.v || '?'}`,
      `uptime: ${st.uptime ? Math.floor(Number(st.uptime) / 3600) + 'h' : '?'}`,
      `threads: ${st.threads ?? '?'}`,
      `queries: ${st.queries ?? '?'}`,
    ];
    process.stdout.write(out.join('\n') + '\n');
    process.exit(0);
  }

  if (cmd === 'dbs') {
    const f = parseFlags(rest, {});
    if (f.help) { process.stdout.write(cmdHelp('dbs') + '\n'); process.exit(0); }
    const r = client(['-e', "SELECT s.schema_name AS db, COALESCE(ROUND(SUM(t.data_length+t.index_length)/1048576,1),0) AS mb, COALESCE(COUNT(t.table_name),0) AS tables FROM information_schema.schemata s LEFT JOIN information_schema.tables t ON t.table_schema = s.schema_name WHERE s.schema_name NOT IN ('information_schema','performance_schema','mysql','sys') GROUP BY s.schema_name ORDER BY mb DESC"]);
    if (r.code !== 0) connError(r);
    const { rows } = parseBatch(r.stdout);
    const out = [];
    if (rows.length === 0) {
      out.push('databases: 0 databases found');
    } else {
      out.push(list('databases', ['db', 'mb', 'tables'], rows));
      out.push(help([`Run \`mariadb-axi tables <db>\` to list tables`]));
    }
    process.stdout.write(out.join('\n') + '\n');
    process.exit(0);
  }

  if (cmd === 'tables') {
    const f = parseFlags(rest, { values: ['limit'] });
    if (f.help) { process.stdout.write(cmdHelp('tables') + '\n'); process.exit(0); }
    if (f._.length !== 1) usageError('tables requires exactly one argument: <database>', ['Run `mariadb-axi tables --help`']);
    const db = f._[0];
    const limit = Math.min(parseInt(f.limit || '100', 10) || 100, 1000);
    const r = client(['-e', `SELECT table_name AS tbl, table_rows AS est_rows, ROUND((data_length+index_length)/1048576,1) AS mb FROM information_schema.tables WHERE table_schema = '${db.replace(/'/g, "''")}' ORDER BY table_name LIMIT ${limit}`]);
    if (r.code !== 0) connError(r);
    const { rows } = parseBatch(r.stdout);
    const out = [`database: ${db}`];
    if (rows.length === 0) {
      out.push(`tables: 0 tables found in "${db}"`);
    } else {
      out.push(list('tables', ['tbl', 'est_rows', 'mb'], rows, { total: rows.length }));
      out.push(help([`Run \`mariadb-axi query "select * from ${db}.<table>" --limit 20\` to peek`]));
    }
    process.stdout.write(out.join('\n') + '\n');
    process.exit(0);
  }

  if (cmd === 'query') {
    const f = parseFlags(rest, { bools: ['full'], values: ['limit'] });
    if (f.help) { process.stdout.write(cmdHelp('query') + '\n'); process.exit(0); }
    if (f._.length !== 1) usageError('query requires exactly one argument: <sql>', ['Run `mariadb-axi query --help`']);
    const sql = guard(f._[0]);
    const limit = Math.min(parseInt(f.limit || '50', 10) || 50, 500);
    const finalSql = sql.replace(/\blimit\s+\d+\s*;?\s*$/i, (m) => `LIMIT ${limit}`) + (/\blimit\s+\d+/i.test(sql) ? '' : ` LIMIT ${limit}`);
    const r = client(['-e', finalSql], { timeout: 30000 });
    if (r.code !== 0) connError(r);
    const { cols, rows } = parseBatch(r.stdout);
    const out = [];
    if (rows.length === 0) {
      out.push(`query: 0 rows returned`);
    } else {
      const shown = rows.slice(0, limit);
      out.push(list('result', cols, shown.map((row) => {
        const o = {};
        for (const c of cols) o[c] = f.full ? row[c] : truncate(row[c], 120);
        return o;
      }), { total: rows.length }));
      out.push(help([`Run \`mariadb-axi query "${sql}" --limit 500\` for more rows`, `Run \`mariadb-axi query "<sql>" --full\` for untruncated cells`]));
    }
    process.stdout.write(out.join('\n') + '\n');
    process.exit(0);
  }

  if (cmd === 'status') {
    const f = parseFlags(rest, {});
    if (f.help) { process.stdout.write(cmdHelp('status') + '\n'); process.exit(0); }
    const r = client(['-e', "SELECT VARIABLE_NAME AS k, VARIABLE_VALUE AS v FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME IN ('Uptime','Threads_connected','Threads_running','Queries','Questions','Slow_queries','Aborted_connects','Max_used_connections','Bytes_received','Bytes_sent')"]);
    if (r.code !== 0) connError(r);
    const { rows } = parseBatch(r.stdout);
    const o = {};
    for (const row of rows) o[row.k] = row.v;
    if (o.Uptime) o.Uptime = Math.floor(Number(o.Uptime) / 3600) + 'h';
    process.stdout.write(kv(o) + '\n');
    process.exit(0);
  }

  if (cmd === 'processlist') {
    const f = parseFlags(rest, { bools: ['full'], values: ['limit'] });
    if (f.help) { process.stdout.write(cmdHelp('processlist') + '\n'); process.exit(0); }
    const limit = Math.min(parseInt(f.limit || '20', 10) || 20, 200);
    const r = client(['-e', `SELECT Id, User, Host, db, Command, Time, State, Info FROM information_schema.PROCESSLIST ORDER BY Time DESC LIMIT ${limit}`]);
    if (r.code !== 0) connError(r);
    const { rows } = parseBatch(r.stdout);
    const out = [];
    if (rows.length === 0) {
      out.push('processlist: 0 running queries');
    } else {
      const shown = rows.map((row) => ({
        ...row,
        Info: f.full ? row.Info : truncate(row.Info, 80),
      }));
      out.push(list('processes', ['Id', 'User', 'db', 'Command', 'Time', 'State', 'Info'], shown));
    }
    process.stdout.write(out.join('\n') + '\n');
    process.exit(0);
  }
}

main().catch((e) => fail(e.message, 'INTERNAL'));
