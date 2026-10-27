#!/usr/bin/env bash
# Fleet external threat-awareness watch — passive third-party lookups only.
#
# Polls Shodan (hosted api.shodan.io lookups plus the keyless InternetDB) and
# the Censys v2 search API for the watch-list targets, diffs the observed
# exposure against the last-seen fingerprint, pushes new/changed findings to
# ntfy, and optionally files phillias/selfhost issues for NEW weaknesses.
#
# Passive by construction: no nmap, no port probes, no banners grabbed from
# the fleet itself — only what Shodan/Censys already observe from outside.
# Keys come from the environment via ~/.agents/keys/load-keys.sh and are
# never written to files. No finding means no push (silent exit 0).
#
# Failure contract: a missing key, an unresolvable watch target, or a failed
# API call prints exactly one `fleet-threat-watch error: ...` line on stderr
# and exits non-zero — never a silent zero-exit. Run detail goes to the log
# file under the state dir. The one deliberate tolerance: a target Shodan or
# Censys has simply never seen (HTTP 404) records as empty exposure, not as
# an error.
#
# Overrides (tests and manual runs):
#   FLEET_THREAT_WATCH_LIST  path to watch-list.toml
#   FLEET_THREAT_STATE_DIR   state dir (default ~/.local/state/fleet-threat)
#   FLEET_THREAT_FILE_ISSUES 0 disables issue filing, 1 forces it on
set -euo pipefail

PROG="fleet-threat-watch"
WATCH_LIST="${FLEET_THREAT_WATCH_LIST:-$HOME/.config/fleet-threat/watch-list.toml}"
STATE_DIR="${FLEET_THREAT_STATE_DIR:-$HOME/.local/state/fleet-threat}"
STATE_FILE="$STATE_DIR/fingerprint.json"
LOG_FILE="$STATE_DIR/fleet-threat-watch.log"

fail() {
  printf '%s error: %s\n' "$PROG" "$1" >&2
  exit 1
}

log() {
  printf '%s %s\n' "$(date -u +%FT%TZ)" "$1" >>"$LOG_FILE"
}

command -v curl >/dev/null 2>&1 || fail "curl is not installed"
command -v python3 >/dev/null 2>&1 || fail "python3 is not installed"

# shellcheck source=/dev/null
[ -f "$HOME/.agents/keys/load-keys.sh" ] && source "$HOME/.agents/keys/load-keys.sh"

[ -n "${SHODAN_API_KEY:-}" ] || fail "SHODAN_API_KEY is unset (vault via load-keys.sh)"
[ -n "${CENSYS_API_ID:-}" ] || fail "CENSYS_API_ID is unset (vault via load-keys.sh)"
[ -n "${CENSYS_API_TOKEN:-}" ] || fail "CENSYS_API_TOKEN is unset (vault via load-keys.sh)"
[ -f "$WATCH_LIST" ] || fail "watch list not found: $WATCH_LIST"

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

# --- watch-list parsing (fixed schema: single-line arrays, bare booleans) ---
cfg_val() {
  awk -v sec="[$1]" -v key="$2" '
    /^\[/ { in_sec = ($0 == sec) }
    in_sec && $0 ~ "^" key "[[:space:]]*=" { sub(/^[^=]*=[[:space:]]*/, ""); print; exit }
  ' "$WATCH_LIST"
}

cfg_list() {
  # Raw `["a", "b"]` value on stdin -> one item per line.
  tr ',' '\n' | sed -n 's/^[^"]*"\([^"]*\)".*/\1/p'
}

DOMAINS=$(cfg_val targets domains | cfg_list)
IPS=$(cfg_val targets ips | cfg_list)
AUTO_IP=$(cfg_val targets auto_detect_ip)
NOTIFY_URL=$(cfg_val notify url | sed -n 's/^"\([^"]*\)"$/\1/p')
NOTIFY_TOPIC=$(cfg_val notify topic | sed -n 's/^"\([^"]*\)"$/\1/p')
CFG_FILE_ISSUES=$(cfg_val options file_issues)
SELFHOST_REPO=$(cfg_val options selfhost_repo | sed -n 's/^"\([^"]*\)"$/\1/p')
NOTIFY_URL=${NOTIFY_URL:-https://ntfy.phillias.cc}
NOTIFY_TOPIC=${NOTIFY_TOPIC:-fleet-threat}
SELFHOST_REPO=${SELFHOST_REPO:-phillias/selfhost}

case "${FLEET_THREAT_FILE_ISSUES:-${CFG_FILE_ISSUES:-true}}" in
  1|true|yes) FILE_ISSUES=1 ;;
  0|false|no) FILE_ISSUES=0 ;;
  *) fail "invalid file_issues value (want true/false or FLEET_THREAT_FILE_ISSUES=0/1)" ;;
esac

# --- HTTP helper (curl stderr suppressed: fail() owns the one error line) ---
fetch_into() {
  # fetch_into <url> <outfile> [curl-args...]: 200 -> body saved; 404 -> `{}`
  # (target unseen by that source); anything else -> fail.
  local url outfile code resp
  url=$1
  outfile=$2
  shift 2
  resp=$(curl -s --max-time 30 -w '\n%{http_code}' "$@" "$url" 2>/dev/null) || \
    fail "request failed: $url"
  code=$(printf '%s\n' "$resp" | tail -n 1)
  case "$code" in
    200) printf '%s\n' "$resp" | sed '$d' >"$outfile" ;;
    404) printf '{}' >"$outfile" ;;
    *) fail "API call failed: $url (HTTP $code)" ;;
  esac
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$outfile" 2>/dev/null || \
    fail "non-JSON response: $url (HTTP $code)"
}

# --- build the IP watch set ---
TMP_RAW=$(mktemp -d "${TMPDIR:-/tmp}/fleet-threat-raw.XXXXXXXXXX")
trap 'rm -rf -- "$TMP_RAW"' EXIT

LABELS="$TMP_RAW/labels.txt"
: >"$LABELS"

if [ -n "${DOMAINS:-}" ]; then
  joined=$(printf '%s' "$DOMAINS" | paste -sd ',' -)
  fetch_into "https://api.shodan.io/dns/resolve?hostnames=${joined}&key=${SHODAN_API_KEY}" \
    "$TMP_RAW/dns.json"
  while IFS= read -r dom; do
    [ -n "$dom" ] || continue
    ip=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2]) or "")' \
      "$TMP_RAW/dns.json" "$dom" 2>/dev/null) || fail "DNS lookup failed for $dom"
    [ -n "$ip" ] || fail "watch domain does not resolve via Shodan: $dom"
    printf '%s\t%s (%s)\n' "$ip" "$dom" "$ip" >>"$LABELS"
  done <<<"$DOMAINS"
fi

while IFS= read -r ip; do
  [ -n "$ip" ] || continue
  printf '%s\t%s\n' "$ip" "$ip" >>"$LABELS"
done <<<"${IPS:-}"

if [ "${AUTO_IP:-true}" = "true" ]; then
  self_ip=$(curl -s -f --max-time 20 https://api.ipify.org 2>/dev/null) || \
    fail "auto-detect-public-IP failed (api.ipify.org)"
  case "$self_ip" in
    *[!0-9a-fA-F.:]*|'') fail "auto-detect-public-IP returned garbage" ;;
  esac
  printf '%s\tself (auto-detected %s)\n' "$self_ip" "$self_ip" >>"$LABELS"
fi

[ -s "$LABELS" ] || fail "watch list produced zero targets"

# --- passive lookups per IP ---
while IFS=$'\t' read -r ip label; do
  [ -n "${ip:-}" ] || continue
  safe=$(printf '%s' "$ip" | tr -c 'A-Za-z0-9' '_')
  printf '%s' "$label" >"$TMP_RAW/$safe.label"
  fetch_into "https://api.shodan.io/shodan/host/${ip}?key=${SHODAN_API_KEY}" \
    "$TMP_RAW/$safe.shodan.json"
  fetch_into "https://internetdb.shodan.io/${ip}" "$TMP_RAW/$safe.internetdb.json"
  query=$(printf '{"q":"ip: %s","per_page":5}' "$ip")
  fetch_into "https://search.censys.io/api/v2/hosts/search" "$TMP_RAW/$safe.censys.json" \
    -u "${CENSYS_API_ID}:${CENSYS_API_TOKEN}" \
    -H 'Content-Type: application/json' -d "$query"
done <"$LABELS"

# --- normalize + diff (python owns the JSON; one line per finding out) ---
FINDINGS="$TMP_RAW/findings.txt"
NEW_STATE="$TMP_RAW/new-state.json"
python3 - "$TMP_RAW" "$STATE_FILE" "$FINDINGS" "$NEW_STATE" <<'PYEOF' >"$TMP_RAW/pyout.txt" 2>"$TMP_RAW/pyerr.txt" || PY_FAILED=1
import json, os, sys

rawdir, state_file, findings_file, new_state_file = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}

def shodan_fp(data):
    ports, services, vulns, issuer, expires = [], [], set(), "", ""
    for entry in data.get("data") or []:
        port = entry.get("port")
        if port is None:
            continue
        mod = entry.get("_shodan", {}).get("module", "")
        prod = (entry.get("product") or "").strip()
        svc = "%s/%s" % (port, mod or "tcp")
        if prod:
            svc += " %s" % prod
        services.append(svc)
        ports.append(port)
        v = entry.get("vulns")
        if isinstance(v, dict):
            vulns.update(v.keys())
        elif isinstance(v, list):
            vulns.update(str(x) for x in v)
        ssl = entry.get("ssl") or {}
        cert = ssl.get("cert") or {}
        iss = cert.get("issuer") or {}
        issuer = issuer or iss.get("O") or iss.get("CN") or ""
        expires = expires or cert.get("expires") or ""
    for v in data.get("vulns") or []:
        vulns.add(str(v))
    return ports, services, sorted(vulns), issuer, expires

def censys_fp(data):
    ports, services = [], []
    hits = ((data.get("result") or {}).get("hits")) or []
    for hit in hits:
        for svc in hit.get("services") or []:
            port = svc.get("port")
            if port is None:
                continue
            name = svc.get("service_name") or svc.get("transport_protocol") or ""
            services.append("%s/%s" % (port, name or "tcp"))
            ports.append(port)
    return ports, services

current = {}
for name in os.listdir(rawdir):
    if not name.endswith(".shodan.json"):
        continue
    safe = name[: -len(".shodan.json")]
    with open(os.path.join(rawdir, safe + ".label")) as f:
        label = f.read().strip()
    ip = label.split()[-1].strip("()") if "(" in label else label
    sh = load(os.path.join(rawdir, safe + ".shodan.json"))
    idb = load(os.path.join(rawdir, safe + ".internetdb.json"))
    ce = load(os.path.join(rawdir, safe + ".censys.json"))
    s_ports, s_svcs, s_vulns, issuer, expires = shodan_fp(sh)
    c_ports, c_svcs = censys_fp(ce)
    ports = sorted(set(s_ports) | set(c_ports) | set(idb.get("ports") or []))
    services = sorted(set(s_svcs) | set(c_svcs))
    vulns = sorted(set(s_vulns) | set(str(v) for v in (idb.get("vulns") or [])))
    if not issuer:
        for hit in ((ce.get("result") or {}).get("hits") or []):
            for svc in hit.get("services") or []:
                leaf = (((svc.get("tls") or {}).get("certificates") or {}).get("leaf")) or {}
                issuer = issuer or leaf.get("issuer_dn") or ""
                expires = expires or ((leaf.get("validity") or {}).get("end") or "")
                if issuer:
                    break
            if issuer:
                break
    current[ip] = {"label": label, "ports": ports, "services": services,
                   "vulns": vulns, "cert_issuer": issuer, "cert_expires": expires}

old = {}
if os.path.exists(state_file):
    old = (load(state_file).get("targets")) or {}

first_run = not os.path.exists(state_file)
findings = []
for ip in sorted(current):
    cur, prev = current[ip], old.get(ip, {})
    if prev == cur and prev:
        continue
    if not prev:
        if not first_run:
            findings.append(("new-target", ip, ip,
                             "target %s is newly watched" % cur["label"]))
        for p in cur["ports"]:
            if not first_run:
                findings.append(("new-port", ip, str(p),
                                 "NEW port %s on %s" % (p, cur["label"])))
        for v in cur["vulns"]:
            if not first_run:
                findings.append(("new-vuln", ip, v,
                                 "NEW vulnerability %s on %s" % (v, cur["label"])))
        continue
    for p in cur["ports"]:
        if p not in prev.get("ports", []):
            findings.append(("new-port", ip, str(p),
                             "NEW port %s on %s" % (p, cur["label"])))
    for p in prev.get("ports", []):
        if p not in cur["ports"]:
            findings.append(("removed-port", ip, str(p),
                             "exposure removed: port %s gone on %s" % (p, cur["label"])))
    for v in cur["vulns"]:
        if v not in prev.get("vulns", []):
            findings.append(("new-vuln", ip, v,
                             "NEW vulnerability %s on %s" % (v, cur["label"])))
    if ((cur.get("cert_issuer") or cur.get("cert_expires")) and
            (cur.get("cert_issuer"), cur.get("cert_expires")) !=
            (prev.get("cert_issuer"), prev.get("cert_expires"))):
        findings.append(("cert-change", ip,
                         "%s/%s" % (cur.get("cert_issuer"), cur.get("cert_expires")),
                         "cert change on %s: issuer=%s expiry=%s" %
                         (cur["label"], cur.get("cert_issuer"), cur.get("cert_expires"))))

with open(new_state_file, "w") as f:
    json.dump({"targets": current}, f, indent=2, sort_keys=True)
with open(findings_file, "w") as f:
    for kind, ip, detail, summary in findings:
        f.write("%s|%s|%s|%s\n" % (kind, ip, detail, summary))
print("targets=%d findings=%d first_run=%s" % (len(current), len(findings), first_run))
PYEOF
if [ "${PY_FAILED:-0}" = "1" ]; then
  log "diff stage failed: $(head -n 1 "$TMP_RAW/pyerr.txt")"
  fail "diff stage failed (see $LOG_FILE)"
fi
log "$(cat "$TMP_RAW/pyout.txt")"

if [ ! -s "$FINDINGS" ]; then
  mv "$NEW_STATE" "$STATE_FILE"
  if grep -q 'first_run=True' "$TMP_RAW/pyout.txt"; then
    echo "$PROG: baseline established; no push sent (first run)"
  else
    echo "$PROG: no changes; no push sent"
  fi
  exit 0
fi

# --- issue filing for NEW weaknesses (deduped by open issue title) ---
if [ "$FILE_ISSUES" = "1" ]; then
  command -v gh >/dev/null 2>&1 || fail "gh is not installed (needed for issue filing)"
  open_titles=$(gh issue list --repo "$SELFHOST_REPO" --state open --limit 100 \
    --json title 2>/dev/null | python3 -c 'import json,sys; print("\n".join(i["title"] for i in json.load(sys.stdin)))') || \
    fail "gh issue list failed for $SELFHOST_REPO"
  while IFS='|' read -r kind ip detail summary; do
    case "$kind" in
      new-port|new-vuln) ;;
      *) continue ;;
    esac
    title="[$PROG] $summary"
    if printf '%s\n' "$open_titles" | grep -Fxq "$title"; then
      log "issue already open: $title"
      continue
    fi
    gh issue create --repo "$SELFHOST_REPO" --title "$title" \
      --body "Passive external observation (Shodan/Censys) diffed against last-seen state. Detail: $detail on $ip. Triage from outside; no fleet-side scan was run." \
      >/dev/null 2>&1 || fail "gh issue create failed for $SELFHOST_REPO"
    log "issue filed: $title"
  done <"$FINDINGS"
fi

# --- ntfy push (high priority) ---
[ -n "${GODOXY_NTFY_TOKEN:-}" ] || fail "GODOXY_NTFY_TOKEN is unset (vault via load-keys.sh)"
body=$(awk -F'|' '{print "- " $4}' "$FINDINGS")
count=$(wc -l <"$FINDINGS")
title="$PROG: $count new/changed finding(s)"
curl -s -f --max-time 30 \
  -H "Authorization: Bearer ${GODOXY_NTFY_TOKEN}" \
  -H "Title: ${title}" \
  -H "Priority: high" \
  -d "$body" \
  "${NOTIFY_URL}/${NOTIFY_TOPIC}" >/dev/null 2>&1 || \
  fail "ntfy push failed: ${NOTIFY_URL}/${NOTIFY_TOPIC}"
mv "$NEW_STATE" "$STATE_FILE"
log "pushed $count finding(s) to ${NOTIFY_URL}/${NOTIFY_TOPIC}"
printf '%s: pushed %s finding(s)\n' "$PROG" "$count"
