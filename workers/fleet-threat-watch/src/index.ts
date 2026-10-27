// Fleet external threat-awareness watch — passive third-party lookups only.
//
// Cron-scheduled Worker: polls Shodan (hosted api.shodan.io lookups plus the
// keyless InternetDB) and the Censys Platform host-lookup API for the
// watch-list targets, diffs observed exposure against the last-seen
// fingerprint in KV, pushes new/changed findings to ntfy, and optionally
// files phillias/selfhost issues for NEW weaknesses via the GitHub REST API.
// The Censys leg needs CENSYS_PAT; when it is unset the leg is skipped with
// one structured skip line and the run continues on Shodan + InternetDB.
//
// Passive by construction: no nmap, no port probes, no banners grabbed from
// the fleet itself — only what Shodan/Censys already observe from outside.
// Keys arrive as wrangler secrets (see DEPLOY.md) and are never logged.
// No finding means no push after the initial baseline inventory.
// State advances only after successful delivery, so a failed push or issue
// call re-reports on the next run instead of dropping findings.
//
// Failure contract: a missing secret, an unresolvable watch target, or a
// failed API call throws one `fleet-threat-watch error: ...` line, which the
// cron run surfaces as a failure — never a silent success. The one deliberate
// tolerance: a target Shodan or Censys has simply never seen (HTTP 404)
// records as empty exposure, not as an error.
import { WATCH_DOMAINS, WATCH_IPS } from "./watch-list.ts";

export interface Env {
  FLEET_THREAT_STATE: KVNamespace;
  SHODAN_API_KEY: string;
  CENSYS_PAT?: string;
  CENSYS_ORG_ID?: string;
  GODOXY_NTFY_TOKEN: string;
  GH_ISSUE_TOKEN: string;
  FILE_ISSUES?: string;
  NTFY_URL?: string;
  NTFY_TOPIC?: string;
}

export interface CertificateFingerprint {
  issuer: string;
  expires: string;
}

export interface TargetFingerprint {
  label: string;
  ports: number[];
  services: string[];
  vulns: string[];
  certs: Record<string, CertificateFingerprint>;
}

export type FindingKind = "new-target" | "new-port" | "new-vuln" | "cert-change" | "removed-port" | "service-change";

export interface Finding {
  kind: FindingKind;
  ip: string;
  detail: string;
  summary: string;
}

const STATE_KEY = "fingerprint.json";

export function fail(message: string): never {
  throw new Error(`fleet-threat-watch error: ${message}`);
}

function required(value: string | undefined, name: string): string {
  if (!value) fail(`${name} is unset (wrangler secret, see DEPLOY.md)`);
  return value as string;
}

function safeUrl(url: string): string {
  return url.replace(/([?&]key=)[^&]*/g, "$1[REDACTED]");
}

async function fetchJson(
  url: string,
  init?: RequestInit,
  allowNotFound = false,
): Promise<{ status: number; json: unknown; headers: Headers }> {
  let res: Response;
  try {
    res = await fetch(url, init);
  } catch {
    fail(`request failed: ${safeUrl(url)}`);
  }
  if (res.status === 404 && allowNotFound) return { status: 404, json: {}, headers: res.headers };
  if (!res.ok) fail(`API call failed: ${safeUrl(url)} (HTTP ${res.status})`);
  try {
    return { status: res.status, json: await res.json(), headers: res.headers };
  } catch {
    fail(`non-JSON response: ${safeUrl(url)} (HTTP ${res.status})`);
  }
}

function asRecord(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value !== null ? (value as Record<string, unknown>) : {};
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function asString(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function asNumber(value: unknown): number | null {
  return typeof value === "number" ? value : null;
}

// Coerce stored KV state into fingerprints; corrupt entries are dropped,
// never trusted blindly.
function asFingerprints(value: unknown): Record<string, TargetFingerprint> {
  const out: Record<string, TargetFingerprint> = {};
  for (const [key, entry] of Object.entries(asRecord(value))) {
    const r = asRecord(entry);
    if (typeof r["label"] !== "string" || !Array.isArray(r["ports"])) continue;
    out[key] = {
      label: r["label"],
      ports: r["ports"].filter((p): p is number => typeof p === "number"),
      services: asArray(r["services"]).map(String),
      vulns: asArray(r["vulns"]).map(String),
      certs: Object.fromEntries(Object.entries(asRecord(r["certs"])).flatMap(([port, cert]) => {
        const c = asRecord(cert);
        return typeof c["issuer"] === "string" || typeof c["expires"] === "string"
          ? [[port, { issuer: asString(c["issuer"]), expires: asString(c["expires"]) }]]
          : [];
      })),
    };
  }
  return out;
}

// Normalize one target's raw API payloads into a comparable fingerprint.
// Every access is defensive: unknown shapes degrade to empty, never throw.
export function normalizeTarget(
  label: string,
  shodan: unknown,
  internetdb: unknown,
  censys: unknown,
): TargetFingerprint {
  const sh = asRecord(shodan);
  const idb = asRecord(internetdb);
  const ce = asRecord(censys);
  const ports = new Set<number>();
  const services = new Set<string>();
  const vulns = new Set<string>();
  const certs: Record<string, CertificateFingerprint> = {};

  for (const entry of asArray(sh["data"])) {
    const e = asRecord(entry);
    const port = asNumber(e["port"]);
    if (port === null) continue;
    ports.add(port);
    const mod = asString(asRecord(e["_shodan"])["module"]) || "tcp";
    const product = asString(e["product"]).trim();
    services.add(product ? `${port}/${mod} ${product}` : `${port}/${mod}`);
    const v = e["vulns"];
    if (Array.isArray(v)) {
      for (const id of v) vulns.add(String(id));
    } else {
      for (const id of Object.keys(asRecord(v))) vulns.add(id);
    }
    const certRec = asRecord(asRecord(e["ssl"])["cert"]);
    const issuer = asRecord(certRec["issuer"]);
    if (!certs[String(port)]) {
      const certificate = {
        issuer: asString(issuer["O"]) || asString(issuer["CN"]),
        expires: asString(certRec["expires"]),
      };
      if (certificate.issuer || certificate.expires) certs[String(port)] = certificate;
    }
  }
  for (const id of asArray(sh["vulns"])) vulns.add(String(id));
  for (const port of asArray(idb["ports"])) {
    const p = asNumber(port);
    if (p !== null) ports.add(p);
  }
  for (const id of asArray(idb["vulns"])) vulns.add(String(id));

  // Censys Platform host asset: result.resource.services[] with port,
  // transport_protocol, software[] (product/vendor/version), cert.parsed
  // (issuer_dn, validity_period.not_after), and compromises[]/exposures[]
  // risk ids. Every access stays defensive; unknown shapes degrade to empty.
  const resource = asRecord(asRecord(ce["result"])["resource"]);
  for (const svc of asArray(resource["services"])) {
    const s = asRecord(svc);
    const port = asNumber(s["port"]);
    if (port === null) continue;
    ports.add(port);
    const proto = asString(s["transport_protocol"]) || "tcp";
    const software = asArray(s["software"]);
    const product = asString(asRecord(software[0])["product"]).trim();
    services.add(product ? `${port}/${proto} ${product}` : `${port}/${proto}`);
    for (const list of [
      asArray(s["compromises"]),
      asArray(s["exposures"]),
      asArray(s["vulns"]),
      asArray(s["threats"]),
    ]) {
      for (const risk of list) {
        const id = asString(risk) || asString(asRecord(risk)["id"]) || asString(asRecord(risk)["name"]);
        if (id) vulns.add(id);
      }
    }
    if (!certs[String(port)]) {
      const parsed = asRecord(asRecord(s["cert"])["parsed"]);
      const certificate = {
        issuer: asString(parsed["issuer_dn"]),
        expires: asString(asRecord(parsed["validity_period"])["not_after"]),
      };
      if (certificate.issuer || certificate.expires) certs[String(port)] = certificate;
    }
  }

  return {
    label,
    ports: [...ports].sort((a, b) => a - b),
    services: [...services].sort(),
    vulns: [...vulns].sort(),
    certs: Object.fromEntries(Object.entries(certs).sort(([a], [b]) => Number(a) - Number(b))),
  };
}

// Diff current fingerprints against last-seen state. Pure: no I/O.
export function diffFingerprints(
  old: Record<string, TargetFingerprint>,
  current: Record<string, TargetFingerprint>,
): Finding[] {
  const findings: Finding[] = [];
  for (const ip of Object.keys(current).sort()) {
    const cur = current[ip];
    const prev = old[ip];
    if (prev && JSON.stringify(prev) === JSON.stringify(cur)) continue;
    if (!prev) {
      findings.push({ kind: "new-target", ip, detail: ip, summary: `target ${cur.label} is newly watched` });
      for (const p of cur.ports) {
        findings.push({ kind: "new-port", ip, detail: String(p), summary: `NEW port ${p} on ${cur.label}` });
      }
      for (const v of cur.vulns) {
        findings.push({ kind: "new-vuln", ip, detail: v, summary: `NEW vulnerability ${v} on ${cur.label}` });
      }
      continue;
    }
    const oldPorts = new Set(prev.ports);
    const newPorts = new Set(cur.ports);
    const oldVulns = new Set(prev.vulns);
    for (const p of cur.ports) {
      if (!oldPorts.has(p)) {
        findings.push({ kind: "new-port", ip, detail: String(p), summary: `NEW port ${p} on ${cur.label}` });
      }
    }
    for (const p of prev.ports) {
      if (!newPorts.has(p)) {
        findings.push({ kind: "removed-port", ip, detail: String(p), summary: `exposure removed: port ${p} gone on ${cur.label}` });
      }
    }
    for (const v of cur.vulns) {
      if (!oldVulns.has(v)) {
        findings.push({ kind: "new-vuln", ip, detail: v, summary: `NEW vulnerability ${v} on ${cur.label}` });
      }
    }
    const oldServices = new Set(prev.services);
    const newServices = new Set(cur.services);
    for (const service of cur.services) {
      if (!oldServices.has(service)) findings.push({ kind: "service-change", ip, detail: service, summary: `NEW service ${service} on ${cur.label}` });
    }
    for (const service of prev.services) {
      if (!newServices.has(service)) findings.push({ kind: "service-change", ip, detail: service, summary: `service removed: ${service} on ${cur.label}` });
    }
    for (const port of new Set([...Object.keys(prev.certs), ...Object.keys(cur.certs)])) {
      const oldCert = prev.certs[port];
      const newCert = cur.certs[port];
      if (newCert && JSON.stringify(oldCert) !== JSON.stringify(newCert)) {
        findings.push({
          kind: "cert-change",
          ip,
          detail: `${port}: ${newCert.issuer}/${newCert.expires}`,
          summary: `cert change on ${cur.label} port ${port}: issuer=${newCert.issuer} expiry=${newCert.expires}`,
        });
      }
    }
  }
  return findings;
}

async function fileIssues(
  repo: string,
  token: string,
  findings: Finding[],
): Promise<void> {
  const headers = {
    Authorization: `Bearer ${token}`,
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
    "Content-Type": "application/json",
    "User-Agent": "fleet-threat-watch",
  };
  const openTitles = new Set<string>();
  let nextUrl: string | null = `https://api.github.com/repos/${repo}/issues?state=open&per_page=100`;
  while (nextUrl) {
    const listed = await fetchJson(nextUrl, { headers });
    for (const issue of asArray(listed.json)) openTitles.add(asString(asRecord(issue)["title"]));
    nextUrl = listed.headers.get("Link")?.match(/<([^>]+)>;\s*rel="next"/)?.[1] || null;
  }
  for (const f of findings) {
    if (f.kind !== "new-port" && f.kind !== "new-vuln") continue;
    const title = `[fleet-threat] ${f.summary}`;
    if (openTitles.has(title)) {
      console.log(`issue already open: ${title}`);
      continue;
    }
    await fetchJson(`https://api.github.com/repos/${repo}/issues`, {
      method: "POST",
      headers,
      body: JSON.stringify({
        title,
        body: `Passive external observation (Shodan/Censys) diffed against last-seen state. Detail: ${f.detail} on ${f.ip}. Triage from outside; no fleet-side scan was run.`,
      }),
    });
    openTitles.add(title);
    console.log(`issue filed: ${title}`);
  }
}

async function pushNtfy(url: string, topic: string, token: string, findings: Finding[], baseline = false): Promise<void> {
  const body = findings.length ? findings.map((f) => `- ${f.summary}`).join("\n") : "- no current ports or vulnerabilities observed";
  const title = baseline ? "fleet-threat-watch: initial baseline inventory" : `fleet-threat-watch: ${findings.length} new/changed finding(s)`;
  let res: Response;
  try {
    res = await fetch(`${url}/${topic}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, Title: title, Priority: "high" },
      body,
    });
  } catch {
    fail(`ntfy push failed: ${url}/${topic}`);
  }
  if (!res.ok) fail(`ntfy push failed: ${url}/${topic} (HTTP ${res.status})`);
  console.log(`pushed ${findings.length} finding(s) to ${url}/${topic}`);
}

export async function runPoll(env: Env): Promise<string> {
  const shodanKey = required(env.SHODAN_API_KEY, "SHODAN_API_KEY");
  // Censys Platform leg degrades gracefully: without a PAT the run continues
  // on Shodan + InternetDB instead of failing as a whole.
  const censysPat = env.CENSYS_PAT || "";
  const censysOrgId = env.CENSYS_ORG_ID || "";
  if (!censysPat) {
    console.log(
      "fleet-threat-watch skip: Censys leg skipped (CENSYS_PAT unset); continuing with Shodan + InternetDB",
    );
  }
  const ntfyUrl = env.NTFY_URL || "https://ntfy.phillias.cc";
  const ntfyTopic = env.NTFY_TOPIC || "fleet-threat";
  const repo = "phillias/selfhost";
  const filingEnabled = (env.FILE_ISSUES ?? "1") !== "0";

  if (WATCH_DOMAINS.length === 0 && WATCH_IPS.length === 0) fail("watch list is empty");

  // Resolve domains passively through Shodan's hosted DNS API (one call).
  const dns = await fetchJson(
    `https://api.shodan.io/dns/resolve?hostnames=${WATCH_DOMAINS.join(",")}&key=${shodanKey}`,
  );
  const dnsRec = asRecord(dns.json);
  const targets = new Map<string, string>();
  for (const domain of WATCH_DOMAINS) {
    const ip = asString(dnsRec[domain]);
    if (!ip) fail(`watch domain does not resolve via Shodan: ${domain}`);
    targets.set(ip, `${domain} (${ip})`);
  }
  for (const ip of WATCH_IPS) {
    if (!targets.has(ip)) targets.set(ip, ip);
  }

  const censysHeaders: Record<string, string> = {
    Authorization: `Bearer ${censysPat}`,
    Accept: "application/vnd.censys.api.v3.host.v1+json",
  };
  if (censysOrgId) censysHeaders["X-Organization-ID"] = censysOrgId;
  const current: Record<string, TargetFingerprint> = {};
  for (const [ip, label] of [...targets.entries()].sort()) {
    const shodan = await fetchJson(`https://api.shodan.io/shodan/host/${ip}?key=${shodanKey}`, undefined, true);
    const internetdb = await fetchJson(`https://internetdb.shodan.io/${ip}`, undefined, true);
    // Platform host lookup (per-IP GET; free tier includes host lookup).
    // Unseen hosts 404 into empty exposure via fetchJson, like other legs.
    const censys = censysPat
      ? await fetchJson(`https://api.platform.censys.io/v3/global/asset/host/${ip}`, {
        headers: censysHeaders,
      }, true)
      : { status: 0, json: {} };
    current[ip] = normalizeTarget(label, shodan.json, internetdb.json, censys.json);
  }

  const stored = await env.FLEET_THREAT_STATE.get(STATE_KEY, "json");
  const firstRun = stored === null;
  const old = firstRun ? {} : asFingerprints(asRecord(stored)["targets"]);
  const findings = diffFingerprints(old, current);

  if (firstRun) {
    await pushNtfy(
      ntfyUrl,
      ntfyTopic,
      required(env.GODOXY_NTFY_TOKEN, "GODOXY_NTFY_TOKEN"),
      findings,
      true,
    );
    await env.FLEET_THREAT_STATE.put(STATE_KEY, JSON.stringify({ targets: current }));
    return `pushed initial baseline inventory for ${Object.keys(current).length} target(s)`;
  }

  if (findings.length === 0) {
    await env.FLEET_THREAT_STATE.put(STATE_KEY, JSON.stringify({ targets: current }));
    const summary = "no changes; no push sent";
    console.log(summary);
    return summary;
  }

  if (filingEnabled) {
    await fileIssues(repo, required(env.GH_ISSUE_TOKEN, "GH_ISSUE_TOKEN"), findings);
  }
  await pushNtfy(ntfyUrl, ntfyTopic, required(env.GODOXY_NTFY_TOKEN, "GODOXY_NTFY_TOKEN"), findings);
  await env.FLEET_THREAT_STATE.put(STATE_KEY, JSON.stringify({ targets: current }));
  return `pushed ${findings.length} finding(s)`;
}

export default {
  async scheduled(_event: ScheduledEvent, env: Env, _ctx: ExecutionContext): Promise<void> {
    await runPoll(env);
  },
};
