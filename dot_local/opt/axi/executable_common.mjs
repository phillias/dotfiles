// AXI shared helpers — TOON output, flag parsing, errors, truncation.
// Used by the local AXI builds in ~/.local/opt/axi/. Node >= 20.
import { execFileSync } from 'node:child_process';
import { homedir } from 'node:os';

export const HOME = homedir();

export function collapseHome(p) {
  return p.replace(HOME, '~');
}

// --- TOON collection output ---
// list("tasks", ["id","title","state"], rows, {count, total})
export function list(name, fields, rows, opts = {}) {
  const lines = [];
  const n = rows.length;
  if (opts.total !== undefined && opts.total > n) {
    lines.push(`count: ${n} of ${opts.total} total`);
  }
  lines.push(`${name}[${n}]{${fields.join(',')}}:`);
  for (const r of rows) {
    lines.push('  ' + fields.map((f) => fmt(r[f])).join(','));
  }
  return lines.join('\n');
}

// --- TOON key/value detail ---
export function kv(obj) {
  return Object.entries(obj)
    .map(([k, v]) => `${k}: ${fmt(v)}`)
    .join('\n');
}

export function fmt(v) {
  if (v === null || v === undefined) return '';
  if (typeof v === 'string') {
    if (v.includes(',') || v.includes('\n') || v.includes(':')) {
      return `"${v.replace(/"/g, "'")}"`;
    }
    return v;
  }
  return String(v);
}

export function help(lines) {
  return lines.map((l, i) => `help[${i + 1}]: ${l}`).join('\n');
}

// --- Structured errors to stdout (exit 1) ---
export function fail(message, code = 'ERROR', helpLines = []) {
  const out = [`error: ${message}`, `code: ${code}`];
  if (helpLines.length) out.push(help(helpLines));
  process.stdout.write(out.join('\n') + '\n');
  process.exit(1);
}

// Usage error (unknown flag / missing required) — exit 2
export function usageError(message, helpLines = []) {
  const out = [`error: ${message}`, `code: USAGE`];
  if (helpLines.length) out.push(help(helpLines));
  process.stdout.write(out.join('\n') + '\n');
  process.exit(2);
}

// --- Truncation ---
export function truncate(s, max = 500, fullHintCmd = null) {
  if (s === undefined || s === null) return '';
  const str = String(s);
  if (str.length <= max) return str;
  const head = str.slice(0, max);
  const note = `... (truncated, ${str.length} chars total)`;
  let out = head + '\n' + note;
  if (fullHintCmd) out += '\n' + help([`Run \`${fullHintCmd}\` for full content`]);
  return out;
}

// --- Flag parsing with unknown-flag rejection ---
// spec: { bools: ['full'], values: ['limit'] } ; global bools always allowed: help, version
export function parseFlags(args, spec = {}) {
  const bools = new Set(['help', ...(spec.bools || [])]);
  const values = new Set(spec.values || []);
  const flags = { help: false, _: [] };
  const valid = [...bools, ...values];
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--') { flags._.push(...args.slice(i + 1)); break; }
    if (a.startsWith('--')) {
      const eq = a.indexOf('=');
      const name = eq > 0 ? a.slice(2, eq) : a.slice(2);
      if (name === 'help') { flags.help = true; continue; }
      if (bools.has(name)) {
        flags[name] = true;
        continue;
      }
      if (values.has(name)) {
        if (eq > 0) {
          flags[name] = a.slice(eq + 1);
        } else {
          const v = args[i + 1];
          if (v === undefined || v.startsWith('--')) {
            usageError(`--${name} requires a value`, [`valid flags: --${valid.join(', --')} (--help always allowed)`]);
          }
          flags[name] = v;
          i++;
        }
        continue;
      }
      usageError(`unknown flag --${name}`, [`valid flags for this command: --${valid.join(', --')} (--help always allowed)`]);
    }
    flags._.push(a);
  }
  return flags;
}

// --- Safe command execution (capture, no shell) ---
export function run(cmd, args, opts = {}) {
  try {
    const stdout = execFileSync(cmd, args, {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: opts.timeout || 20000,
      env: { ...process.env, ...(opts.env || {}) },
      maxBuffer: 16 * 1024 * 1024,
    });
    return { code: 0, stdout, stderr: '' };
  } catch (e) {
    return { code: e.status ?? 1, stdout: e.stdout?.toString() ?? '', stderr: e.stderr?.toString() ?? '' };
  }
}

// --- Secret redaction helpers ---
const SECRET_KEYS = /(passw|secret|token|key|auth|credential)/i;
export function redactKeys(obj) {
  const out = {};
  for (const [k, v] of Object.entries(obj)) {
    out[k] = SECRET_KEYS.test(k) ? '***' : v;
  }
  return out;
}

export function redactString(s) {
  if (!s) return s;
  // Redact common secret patterns: passwords after ':', URLs with creds, jwt-like tokens
  return String(s)
    .replace(/(password|passwd|secret|token|api[_-]?key)=([^\s&]+)/gi, '$1=***')
    .replace(/(?<=:\/\/)[^@\s]+@/g, '***@');
}
