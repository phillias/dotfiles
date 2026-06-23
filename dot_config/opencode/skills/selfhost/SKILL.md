# Selfhost Skill

This skill has moved to `~/docker/selfhost/.opencode/skills/selfhost/SKILL.md`.

<<<<<<< Updated upstream
Authoritative guide for the selfhost Docker Compose stack at `/home/phillias/docker/`.
This covers the selfhost directory plus tightly coupled auth services (pocketid, tinyauth)
that live in their own directories. This is one stack among several — it does not cover
custom Go applications (llpoa, miaction, myastrology) or media/pirate services.

---

## 1. Infrastructure Overview

### Architecture

```
Cloudflare (Tunnel/Proxy, SSL Full/Strict)
  │
  └── Godoxy (reverse proxy, host net, :80/:443)
        │
        ├── CrowdSec (WAF + AppSec, host net, :7422)
        ├── Pocket ID (OIDC provider, port 1411)
        ├── Tinyauth (forward_auth fallback)
        │
        ├── Databases: MariaDB (:3306), PostgreSQL (:5432), MSSQL (:1433),
        │              Redis (:6379), libSQL (:7087), Turso (:8087)
        ├── CloudBeaver (DB web UI, :8978)
        ├── Dockhand (Docker management, :7299)
        ├── CrowdSec Manager (UI, :8287)
        ├── ntfy (push notifications, :3930)
        ├── apprise (notifications, :5832)
        └── netdata (host monitoring, via hostapps.yml, :19999)
```

### All Services

| Directory | Service | Container | Port(s) | Purpose |
|-----------|---------|-----------|---------|---------|
| `selfhost/` | godoxy-proxy | godoxy-proxy | 80, 443 | Reverse proxy (host net) |
| `selfhost/` | crowdsec | crowdsec | 8373, 7422, 6060 | WAF + AppSec (host net) |
| `selfhost/` | crowdsecmgr | crowdsecmgr | 8287 | CrowdSec manager UI |
| `selfhost/` | socket-proxy | socket-proxy | 2375 | Docker API gateway |
| `selfhost/` | mariadb | mariadb | 3306 | MariaDB (host net) |
| `selfhost/` | postgres | postgres | 5432 | PostgreSQL with vchord (host net) |
| `selfhost/` | mssql | mssql | 1433 | Azure SQL Edge (host net) |
| `selfhost/` | redis | redis | 6379 | Valkey/Redis (host net) |
| `selfhost/` | libsql | libsql | 7087 | Turso/libSQL primary |
| `selfhost/` | turso | turso | 8087 | Turso/libSQL secondary |
| `selfhost/` | cloudbeaver | cloudbeaver | 8978 | Database web UI |
| `selfhost/` | dockhand | dockhand | 7299 | Docker management UI |
| `selfhost/` | tinyauth | tinyauth | — | Forward auth provider |
| `selfhost/` | ntfy | ntfy | 3930 | Push notifications |
| `selfhost/` | apprise | apprise | 5832 | Notification service |
| `pocketid/` | pocketid | pocketid | 1411 | OIDC provider |
| `tinyauth/` | tinyauth | tinyauth | — | Auth service (config) |

### Common Conventions

- **PUID=1000, PGID=984** (set in `/home/phillias/docker/.env` and `selfhost/.env`)
- **TZ=America/New_York** for most services (selfhost services use `ETC/UTC`)
- **Secrets in `.env` files** — never committed (`.gitignore` includes `.env`)
- **`restart: unless-stopped`** on all services
- **Named volumes** for persistent data
- **`network_mode: host`** for core infrastructure (crowdsec, godoxy, databases)
- **`bridge` networks** (`selfhost_frontnet`) for app services that need proxy routing

---

## 2. Operations Scope & Approval Gates

### Prime Directive: Service-Scoped Operations Only

- **Every management operation** (`docker compose up`, `docker stop`, `restart`,
  `rm`, etc.) must target **only the specific service** being acted on.
- **Never run `docker compose up -d` without service names.** This starts every
  service including critical path components — see below.
- **Never run `docker compose down`** — use `docker stop` / `docker rm` for
  individual containers.
- **Correct:** `docker compose up -d mariadb` or `docker stop mariadb && docker rm mariadb`
- **Incorrect:** `docker compose up -d`, `docker compose down`

### Critical Path Components — Approval Gate Required

The following services are **critical path**: all other services depend on them
for routing, authentication, or security. **Any operation** targeting these
services — or that might affect them (e.g. full-stack operations) — requires
**explicit user approval** first. Describe what, why, and the expected impact.

| Service | Role | Sensitivity |
|---------|------|-------------|
| **godoxy-proxy** (`app`) | Reverse proxy — all traffic flows through it | Interrupting godoxy drops all routes |
| **crowdsec** | WAF + AppSec — gates godoxy startup (depends_on health) | Restarting crowdsec may block godoxy from restarting until healthy |
| **pocketid** (in `pocketid/`) | OIDC provider — all SSO logins | Passkey registration state, OIDC sessions |

### Godoxy Config (CRITICAL — DO NOT MODIFY WITHOUT APPROVAL)

### PRIME DIRECTIVE
**Never edit `/home/phillias/docker/selfhost/godoxy/config/config.yml` without explicit user approval.** The YAML formatting requirements are specific and look inconsistent but are required by godoxy's parser:
- Bare IPv4 (unquoted, no space): `- ip:162.120.186.139`
- IPv4 with special chars (quoted, space): `- "ip: 147.224.164.153"`
- IPv6 (quoted, space — colons would break unquoted YAML): `- "ip: 2600:6c4a:53f:8285:9c5d:c409:1251:b53b"`

The godoxy config is at `/home/phillias/docker/selfhost/godoxy/config/config.yml` and is bind-mounted to `/app/config` inside the container.

### Godoxy Config Change Safety

**Why past manual edits have been reset:** The Godoxy WebUI (`godoxy.phillias.cc`) has a **Config Editor** that loads, parses, and re-serializes `config.yml` when someone clicks **Save**. Any manual formatting, comments, or syntax that the editor doesn't preserve gets overwritten. This is a known pattern — GitHub issue [#149](https://github.com/yusing/godoxy/issues/149) shows users habitually click **Save Config** in the WebUI to force route discovery.

**The reset scenario:**
1. Manual edit is made to `config.yml` (e.g., adding a header, changing middleware).
2. Later, someone opens the Godoxy WebUI Config Editor and clicks **Save** — perhaps to fix routing or out of habit.
3. The WebUI parses the file into its internal representation, then writes it back. Manual changes are lost.

**Safe manual edit process (verified working):**
```bash
# 1. Back up before any edit
cp ~/docker/selfhost/godoxy/config/config.yml \
   ~/docker/selfhost/godoxy/config/config.yml.bak.$(date +%s)

# 2. Make the surgical edit (one line at a time, preserve formatting)
# Use Edit tool or sed — never rewrite the whole file

# 3. Validate the file is still valid YAML
docker compose -f ~/docker/selfhost/compose.yml config > /dev/null

# 4. Restart godoxy to apply
docker compose -f ~/docker/selfhost/compose.yml restart app

# 5. Verify the header/middleware is active
curl -sI https://<service>.phillias.cc | grep -i <header-name>
```

**Rules to avoid losing edits:**
- **Never use the WebUI Config Editor** after manual edits. Use it only for WebUI-managed state (homepage overrides live in `data/.homepage.json`).
- **Always back up** before editing. The backup timestamp lets you prove when the manual edit was made.
- **Make surgical edits** — change one line, preserve all surrounding whitespace and comments.
- **Track changes**: After editing, note the timestamp. If the file gets reset, compare `stat` timestamps to identify when the WebUI overwrote it.

### Godoxy Key Configuration

See `selfhost/.env` for all godoxy env vars:

| Variable | Value | Purpose |
|----------|-------|---------|
| `TAG` | `v0.29.1` | Godoxy image version |
| `GODOXY_API_JWT_SECRET` | (generated) | API JWT auth |
| `GODOXY_API_USER` | `phillias` | Web UI login |
| `GODOXY_API_PASSWORD` | `2763powers` | Web UI password |
| `GODOXY_OIDC_ALLOWED_USERS` | `Concierge0415` | OIDC whitelist |
| `GODOXY_OIDC_ISSUER_URL` | `https://pocketid.phillias.us` | OIDC provider |
| `GODOXY_OIDC_CLIENT_ID` | (UUID) | OIDC client for Web UI |
| `GODOXY_OIDC_CLIENT_SECRET` | (secret) | OIDC client secret |
| `GODOXY_HTTP_ADDR` | `:80` | HTTP listen |
| `GODOXY_HTTPS_ADDR` | `:443` | HTTPS listen |
| `GODOXY_HTTP3_ENABLED` | `true` | HTTP/3 support |
| `GODOXY_API_ADDR` | `127.0.0.1:8888` | API listen |
| `GODOXY_FRONTEND_ALIASES` | `godoxy` | Web UI subdomain |
| `GODOXY_OIDC_REDIRECT_URL` | (not currently set) | Fixes empty redirect_uri host |

Key config.yml features:
- **Autocert**: Cloudflare DNS-01 challenge for `*.phillias.us` and `phillias.us`
- **CrowdSec middleware**: Routes to `127.0.0.1:7422` (AppSec listener) with API key auth
- **ACL**: IP allow/deny list with ntfy notifications (1h cooldown)
- **OIDC**: Global OIDC config (`GODOXY_OIDC_ISSUER_URL`) enables per-route middleware via Docker labels
- **Cloudflare**: `cloudflare_real_ip` middleware for correct visitor IP detection
- **Security headers**: CSP, HSTS, X-Frame-Options, X-Content-Type-Options, Referrer-Policy
- **Notifications**: ntfy on `ntfy.phillias.cc` topic `SelfHostNetSec`
- **MaxMind**: GeoIP for ACL (account_id + license_key)
- **Homepage**: Godoxy dashboard enabled with default categories

### Godoxy Hostapps

Defined in `/home/phillias/docker/selfhost/godoxy/config/hostapps.yml` for services not managed via Docker labels. Currently:
- **netdata**: Host `172.17.0.1:19999`, HTTP scheme, `forward_auth: {}` placeholder (not yet configured)

### Godoxy Web UI / Management UIs

| URL | Service | Notes |
|-----|---------|-------|
| `godoxy.phillias.us` | Godoxy frontend dashboard | All proxied services listed |
| `crowdsecmgr.phillias.us` | CrowdSec Manager | Port 8287 |

### Cloudflare Zone Security Audit (phillias.cc)

**Last audited:** 2026-06-19 via Cloudflare API

**Zone Plan:** Free Website

**Critical Findings:**

| Setting | Current Value | Risk | Recommendation |
|---------|--------------|------|----------------|
| **SSL/TLS** | `flexible` | 🔴 **CRITICAL** | Change to `Full (Strict)`. Flexible mode encrypts edge-to-browser but sends HTTP from Cloudflare to origin, exposing traffic and breaking OIDC redirects. |
| **Always Use HTTPS** | `off` | 🔴 **HIGH** | Enable to redirect all HTTP to HTTPS. Currently HTTP requests are accepted. |
| **Min TLS Version** | `1.0` | 🔴 **HIGH** | Upgrade to `1.2`. TLS 1.0/1.1 are deprecated and vulnerable to POODLE/BEAST. |
| **Browser Check** | `on` | 🟡 **MEDIUM** | May challenge API clients and bots. Monitor if services break. |

**WAF & DDoS:**
- **Cloudflare Managed Free Ruleset:** Active (26 rules) — blocks Log4j, Shellshock, WordPress CVEs
- **DDoS L7 Ruleset:** Active (automatic HTTP DDoS mitigation)
- **Custom Firewall Rules:** None configured
- **Rate Limiting:** None configured
- **Bot Management:** Not available on Free plan

**Headers:**
- **HSTS at Cloudflare:** Disabled — Godoxy is the sole HSTS source
- **Automatic HTTPS Rewrites:** ON (rewrites HTTP links in HTML responses)
- **Opportunistic Encryption:** ON (serves HTTPS on HTTP subdomains)

**DNS:**
- **DNSSEC:** Disabled
- **Wildcard:** `*.phillias.cc` → origin IP

### Godoxy Response Middleware Audit

The global `response` middleware in `config.yml` sets security headers on **all** proxied traffic. These headers overlap with Cloudflare protections and can break services if misconfigured.

**Current header stack:**
```yaml
- use: response
  set_headers:
    Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD
    Access-Control-Allow-Headers: "*"
    Access-Control-Allow-Origin: "*"          # ⚠️ SECURITY: globally permissive CORS
    Access-Control-Max-Age: 180
    Vary: "*"
    X-XSS-Protection: 1; mode=block           # ℹ️ Deprecated (Chromium removed in 2019)
    Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; object-src 'self'; frame-ancestors 'self'; connect-src 'self' https://api.github.com;
    X-Content-Type-Options: nosniff
    X-Frame-Options: SAMEORIGIN               # ⚠️ Can break iframe embeds
    Referrer-Policy: same-origin              # ⚠️ Can break OAuth callbacks
    Strict-Transport-Security: max-age=63072000; includeSubDomains; preload
```

**Known breakage incidents:**
| Date | Service | Symptom | Cause | Fix |
|------|---------|---------|-------|-----|
| 2026-06-19 | AIOStreams | "Failed to load changelogs" | CSP `default-src 'self'` blocked `fetch()` to `api.github.com` | Added `connect-src 'self' https://api.github.com;` |

**Cloudflare + Godoxy protection overlap:**

| Protection | Cloudflare Layer | Godoxy Layer | Recommendation |
|------------|-----------------|--------------|----------------|
| **SSL/TLS** | `flexible` (broken) → forwards HTTP to origin | Listens on `:80`/`:443`, handles autocert | **URGENT:** Change Cloudflare to `Full (Strict)`. Origin traffic is currently unencrypted between Cloudflare and server. |
| **DDoS** | Always-on DDoS mitigation + L7 ruleset | None | Cloudflare absorbs volumetric attacks before they reach Godoxy. |
| **WAF** | Managed Free Ruleset (26 rules) | CrowdSec AppSec on `127.0.0.1:7422` | CrowdSec provides origin-layer WAF; Cloudflare provides edge WAF. Both active = defense in depth. |
| **Bot Management** | Not available on Free plan | None | Browser Check is ON — may interfere with API clients. |
| **CORS** | No global CORS set | `Access-Control-Allow-Origin: *` globally | **Redundant and risky.** Godoxy sends `*` on every response. Any malicious website can call your APIs. |
| **HSTS** | `max-age=2592000; includeSubDomains` | Removed from Godoxy | Cloudflare handles HSTS at the edge. Godoxy no longer sends the header to avoid duplication. |
| **CSP** | Not set | `Content-Security-Policy` globally | Godoxy CSP is the active layer. Keep but expand `connect-src` as services break. |
| **IP Reputation** | No custom firewall rules | ACL in `config.yml` + CrowdSec decisions | CrowdSec blocks at origin only. No edge-layer IP blocking. |
| **Rate Limiting** | None | None | No brute-force or scraping protection at either layer. |

**Recommendations (prioritized):**

1. **🔴 Change Cloudflare SSL to Full (Strict)** — This is the biggest issue. Flexible mode:
   - Sends unencrypted HTTP from Cloudflare to your origin
   - Breaks OIDC redirect URIs (documented in Lessons Learned)
   - Exposes traffic to interception between Cloudflare and server
   ```bash
   # Fix via API (or use dashboard)
   curl -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/settings/ssl" \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"value":"strict"}'
   ```

2. **🔴 Enable Always Use HTTPS in Cloudflare** — Redirects HTTP to HTTPS at the edge.

3. **🔴 Raise Min TLS Version to 1.2** — TLS 1.0 is deprecated and insecure.

4. **🟡 Remove global CORS headers from Godoxy.** `Access-Control-Allow-Origin: *` on every response is a security risk. Options:
   - Let each service handle its own CORS
   - Use Cloudflare Transform Rules for targeted CORS (Pro plan)
   - Add per-route Godoxy middleware for services that need CORS

5. **🟡 Add rate limiting.** Free plan doesn't support Cloudflare Rate Limiting rules. Consider:
   - CrowdSec rate limiting scenarios
   - Godoxy per-IP connection limits
   - Fail2ban on the host

6. **🟡 Monitor for more CSP breaks.** `default-src 'self'` is strict. Any service fetching external APIs or loading CDN assets will break. Consider:
   - `connect-src 'self' https: wss:;` (broader, fewer incidents)
   - Or maintain per-service allowlists

7. **🟡 Consider enabling HSTS at Cloudflare too** — Redundancy is good. If Godoxy is bypassed, HSTS still protects.

8. **🟡 X-Frame-Options audit.** `SAMEORIGIN` blocks framing. If any service needs embeds, it will fail.

9. **🟡 Referrer-Policy audit.** `same-origin` strips cross-origin referrer. OAuth flows validating `Referer` may break.

10. **🟢 X-XSS-Protection is dead weight.** Deprecated since 2019. Safe to remove.

11. **🟢 HSTS** is handled by Cloudflare (`max-age=2592000; includeSubDomains`). Godoxy no longer sends the header.

### Godoxy Label Convention (Docker)

Services that godoxy should proxy use Docker labels:

```yaml
labels:
  proxy.<name>.port: 8080              # Container port to route
  proxy.<name>.alias: myapp            # Subdomain (myapp.phillias.us)
  proxy.aliases: alt1,alt2             # Additional hostnames
  proxy.exclude: true                  # Exclude from proxy (default for infra)
  proxy.<name>.homepage.show: false    # Hide from dashboard
  proxy.<name>.healthcheck.disable: true
  proxy.<name>.middlewares.forward_auth: |
    route: tinyauth
    auth_endpoint: /api/auth/traefik
  proxy.<name>.middlewares.oidc: |
    client_id: <from-pocket-id>
    client_secret: <from-pocket-id>
    allowed_users:
      - Concierge0415
  proxy.#1.middlewares.cidr_whitelist: |
    status: 403
    allow:
      - 10.0.0.0/8
```

---

## 3. CrowdSec WAF

### Architecture
- Runs in Docker with `network_mode: host`
- **LAPI** on `0.0.0.0:8373` — local API for bouncers
- **AppSec** on `0.0.0.0:7422` — WAF rules evaluation (listens on all interfaces because godoxy is on host net)
- **Prometheus** metrics on `0.0.0.0:6060`
- **Two bouncers registered**: `godoxy` (at host IP 192.168.1.173) and `godoxy@127.0.0.1`
- Healthcheck: `cscli lapi status` — 30s interval, 5 retries, 30s start period

### Collections
Defined via `COLLECTIONS` env var in compose.yml:
- `crowdsecurity/http-cve`
- `crowdsecurity/appsec-virtual-patching`
- `crowdsecurity/appsec-generic-rules`
- `crowdsecurity/appsec-crs`

### AppSec Acquisition Config
Located at `/home/phillias/docker/selfhost/crowdsec/acquis.d/appsec.yaml`:
```yaml
source: appsec
listen_addr: 0.0.0.0:7422
appsec_configs:
  - crowdsecurity/appsec-default
labels:
  type: appsec
```

**Note**: `crowdsecurity/virtual-patching` and `crowdsecurity/generic-rules` are NOT included in the current acquis config due to `id:100` rule conflicts with `appsec-default`. The original setup notes reference them as commented out.

The full setup with comments is documented in `/home/phillias/docker/selfhost/crowdsec-godoxy-setup-notes.txt`:
```
appsec_configs: 
  - crowdsecurity/appsec-default
  #- crowdsecurity/virtual-patching	# some id:100 rule conflict with appsec-default
  #- crowdsecurity/generic-rules	# some id:100 rule conflict with appsec-default
  - crowdsecurity/crs
```

### Godoxy-CrowdSec Integration
In `config.yml`, the crowdsec middleware:
```yaml
- use: crowdsec
  api_key: <bouncer-api-key>
  route: 127.0.0.1
  port: 7422
  log_blocked: true
```

The original setup tested with Docker bridge IP (`172.17.0.1`) but transitioned to `127.0.0.1` which is correct since both godoxy and crowdsec run on host network.

### Parser Whitelists
Located inside the CrowdSec Docker volume at `/etc/crowdsec/parsers/s02-enrich/whitelists.yaml`. Modify via `docker exec`:
```bash
docker exec crowdsec cscli parsers list
docker exec crowdsec vi /etc/crowdsec/parsers/s02-enrich/whitelists.yaml
```

After modifying whitelists, restart the container:
```bash
docker compose -f ~/docker/selfhost/compose.yml restart crowdsec
```

### CrowdSec Manager (UI)
- Image: `hhftechnology/crowdsec-manager:independent`
- Port 8287 (mapped to container port 8080)
- Environment: `INCLUDE_CROWDSEC=true`, `ENVIRONMENT=production`
- Connected to LAPI via `LOCAL_API_URL=http://192.168.1.173:8373`
- Uses `crowdsec-ui` machine credentials from `.env`
- Requires `cscli machines add crowdsec-ui --password <password> -f /dev/null` for LAPI auth

### Common Operations
```bash
# Check bouncers
docker exec crowdsec cscli bouncers list

# Check active decisions (bans)
docker exec crowdsec cscli decisions list

# Check alerts
docker exec crowdsec cscli alerts list

# Check LAPI status
docker exec crowdsec cscli lapi status

# Add a ban
docker exec crowdsec cscli decisions add --ip <IP> --duration 24h

# Remove a ban
docker exec crowdsec cscli decisions delete --ip <IP>

# View logs
docker compose -f ~/docker/selfhost/compose.yml logs crowdsec -f
```

---

## 4. Authentication Layer

### Pocket ID (Primary OIDC Provider)

- **URL**: `pocketid.phillias.us`
- **Port**: 1411 (`127.0.0.1` only — proxied through godoxy)
- **Image**: `ghcr.io/pocket-id/pocket-id:v2` (v2.7.0+)
- **Data**: SQLite database in named volume `pocketid_data`
- **Compose**: `/home/phillias/docker/pocketid/compose.yml`
- **Config**: `/home/phillias/docker/pocketid/.env`
- **Healthcheck**: `/app/pocket-id healthcheck`, 1m30s interval, 15s start period
- **Resource limits**: 0.5 CPU / 256M max, 0.1 CPU / 64M reserved
- **Docker labels**: `proxy.pocketid.port: 1411`, `proxy.pocketid.alias: pocketid`

#### Required Env Vars (`.env`)

```bash
APP_URL=https://pocketid.phillias.us    # MUST be APP_URL, NOT PUBLIC_APP_URL!
ENCRYPTION_KEY=<openssl rand -base64 32>
TRUST_PROXY=true                         # Required behind godoxy
```

#### Setup Flow
Pocket ID is a passkey-only OIDC provider with an admin approval workflow. First-time setup:
1. Visit `https://pocketid.phillias.us/setup` (or the root URL on a fresh database)
2. Register your first passkey — this creates the admin account
3. Create OIDC clients under **Applications → Add Application**
4. Enable **Approval Workflow** under **Settings → Security** for login request approval

#### Godoxy Integration (Per-Route OIDC)
Auth is applied per-service via godoxy's per-route OIDC middleware labels — not globally. The global `GODOXY_OIDC_ISSUER_URL` in `selfhost/.env` is still required even for per-route middleware; without it, the middleware silently does nothing.

```yaml
labels:
  proxy.<name>.port: 8080
  proxy.<name>.alias: myapp
  proxy.<name>.middlewares.oidc: |
    client_id: <from-pocket-id>
    client_secret: <from-pocket-id>
    allowed_users:
      - Concierge0415
```

**Critical env vars in `selfhost/.env`:**
- `GODOXY_OIDC_ISSUER_URL=https://pocketid.phillias.us` — **required** even for per-route; tells godoxy where to redirect
- `GODOXY_OIDC_ALLOWED_USERS=Concierge0415` — global whitelist applied to godoxy's own Web UI OIDC login
- `GODOXY_OIDC_CLIENT_ID` / `GODOXY_OIDC_CLIENT_SECRET` — for godoxy Web UI OIDC login (separate from per-route app clients)

#### OIDC Client Registration
When creating an OIDC client in Pocket ID for a godoxy-proxied app:
- **Callback URLs**: `https://*.phillias.us/auth/callback` (wildcard, preferred) or explicit per-app
- **Client Launch URL**: `https://app.phillias.us` (optional convenience link)
- **Logout Callback URL**: Leave blank (not required by godoxy)
- **Scopes**: Not configured in Pocket ID's form — godoxy requests `openid`, `profile`, `email` at auth time

The godoxy OIDC callback path is always `/auth/callback`. Pocket ID supports wildcard callback URIs.

#### Branding
- **Via Web UI** (Settings → Appearance): Upload logo, change app name, pick accent color. Persisted in database.
- **Via env vars** (declarative, locks UI): Set `UI_CONFIG_DISABLED=true` in `.env`, then use `APP_NAME`, `ACCENT_COLOR`, `HOME_PAGE_URL`, `DISABLE_ANIMATIONS`
- **Approval workflow**: Settings → Security → Approval Workflow — admin approves/denies login requests

#### Selfhost `.env` Pocket ID entries
In addition to pocketid's own `.env`, the `selfhost/.env` also carries Pocket ID vars for reference:
```bash
POCKETID_APP_URL=https://pocketid.phillias.us
POCKETID_ENCRYPTION_KEY=<key>
POCKETID_TRUST_PROXY=true
```

### Tinyauth (Forward Auth Fallback)

- **URL**: `tinyauth.phillias.us`
- **Config**: `/home/phillias/docker/tinyauth/compose.yml` + `selfhost/.env`
- **Image**: `ghcr.io/steveiliop56/tinyauth:v5`
- **Data**: SQLite DB at `./tinyauth/tinyauth.db`

#### Env Vars
```bash
TINYAUTH_APPURL=https://tinyauth.phillias.us
TINYAUTH_AUTH_USERS=phillias:$$2a$$10$$...  # bcrypt hash with doubled $$
```

**Note on bcrypt hashing**: The `$$` in the env file is intentional. Docker Compose interprets `$` as variable expansion, so `$$` becomes a single `$` at runtime. The actual bcrypt hash is `$2a$10$...`.

#### OIDC Client for Forward Auth
Tinyauth has a Pocket ID OIDC client configured in `selfhost/.env`:
```bash
TINYAUTH_OIDC_CLIENT_ID=93d57e02-225e-499f-b445-be1434e1e53f
TINYAUTH_OIDC_CLIENT_SECRET=<secret>
```

Tinyauth can sit between godoxy and Pocket ID as a session manager (forward_auth → Tinyauth → OIDC → Pocket ID), but the current setup uses godoxy-to-Pocket-ID direct per-route OIDC middleware. Tinyauth remains available for services needing password-based forward auth.

---

## 5. Database Layer

All databases run in the `selfhost/` stack with `network_mode: host` for direct host access (except libSQL/Turso which use bridge networking with mapped ports).

| Database | Port | Image | Notes |
|----------|------|-------|-------|
| MariaDB | 3306 | `lscr.io/linuxserver/mariadb:11.4.5` | Root pw in `.env`, healthcheck: `mariadb-admin ping` |
| PostgreSQL | 5432 | `ghcr.io/tensorchord/vchord-postgres:pg18-v1.1.1` | vchord vector extension, HDD storage type, `PUID:PGID` for perms |
| MSSQL | 1433 | `mcr.microsoft.com/azure-sql-edge:latest` | SA pw must be URL-encoded, `ACCEPT_EULA=Y` |
| Redis | 6379 | `docker.io/valkey/valkey:9` | Valkey fork, no auth by default |
| libSQL | 7087 | `ghcr.io/tursodatabase/libsql-server:latest` | JWT auth, primary node, gRPC on 5001 |
| Turso | 8087 | `ghcr.io/tursodatabase/libsql-server:latest` | JWT auth, secondary node, gRPC on 50001 |

### Common Credentials
- `DB_USERNAME=phillias`, `DB_PASSWORD=2763powers`, `DBNAME=sandbox`
- All databases share the same credentials for simplicity

### MariaDB
- Healthcheck: `mariadb-admin ping -h localhost`, 5s interval
- Volume: `mariadb-config:/config`
- Env: `MYSQL_ROOT_PASSWORD`, `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD`

### PostgreSQL (vchord)
- **Important**: Image is `ghcr.io/tensorchord/vchord-postgres:pg18-v1.1.1` — this includes the vchord vector similarity search extension
- `POSTGRES_INITDB_ARGS=--data-checksums` for data integrity
- `DB_STORAGE_TYPE=HDD` (set because not on SSDs)
- Healthcheck: `pg_isready -U postgres`, 10s interval
- Volume: `postgres:/var/lib/postgresql`
- `shm_size: 128mb` required

### MSSQL (Azure SQL Edge)
- `SA_PASSWORD=2763%Powers` — the `%` must stay unencoded in `.env` but Docker Compose may try to expand `%P` as a variable; if issues arise, use `$$` or single-quote. The current value works because `%P` doesn't correspond to a known env var.
- Healthcheck: `/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P '${SA_PASSWORD}' -Q 'SELECT 1' -C`
- `MSSQL_PID=Developer`, `ACCEPT_EULA=Y`

### Redis (Valkey)
- Healthcheck: `redis-cli ping || exit 1`
- No data volume mounted (ephemeral — data lives in container layer; add volume if persistence needed)

### libSQL & Turso
- Both use `ghcr.io/tursodatabase/libsql-server:latest`
- JWT auth keys in `.env`: `LIBSQL_JWT_KEY` and `TURSO_JWT_KEY`
- Healthcheck: `timeout 1s bash -c ':> /dev/tcp/127.0.0.1/8080' || exit 1`
- libSQL is primary (`SQLD_NODE=primary`), Turso is secondary (also set to primary currently)
- Volumes: `libsql:/var/lib/sqld`, `turso:/var/lib/sqld`
- Ports: libSQL on 7087 (HTTP) + 5001 (gRPC), Turso on 8087 (HTTP) + 50001 (gRPC)

### Database URLs (for app connections)

From `.env`:
```bash
DATABASE_URL=jdbc:mariadb://mariadb:3306/grimmory
```

This JDBC URL is used by applications connecting to MariaDB. For other databases, use standard connection strings:
- PostgreSQL: `postgresql://postgres@localhost:5432/sandbox`
- MSSQL: `sqlserver://sa:2763%Powers@localhost:1433`
- Redis: `redis://localhost:6379`
- libSQL: `http://localhost:7087` or `libsql://localhost:7087`

---

## 6. Selfhost Management Services

### Socket Proxy
- Image: `ghcr.io/yusing/socket-proxy:latest`
- Purpose: Secure Docker socket proxy — provides controlled access to the Docker API
- Permissions: `ALLOW_START`, `ALLOW_STOP`, `ALLOW_RESTARTS`, `CONTAINERS`, `EVENTS`, `INFO`, `PING`, `POST`, `VERSION`, `CONTAINERS=1`
- Listen: `127.0.0.1:2375`
- Network: `selfhost_frontnet` bridge
- Volumes: mounts `/var/run/docker.sock` with socket access
- Godoxy connects to socket-proxy via `DOCKER_HOST=tcp://127.0.0.1:2375`

### CrowdSec Manager
- Image: `hhftechnology/crowdsec-manager:independent`
- Port: 8287 (mapped to container 8080)
- Volumes: `selfhost_crowdsecmgr-config`, `selfhost_crowdsecmgr-logs`, `selfhost_crowdsecmgr-data`
- Network: `selfhost_frontnet`
- Depends on crowdsec being healthy

### CloudBeaver
- Image: `dbeaver/cloudbeaver:latest`
- Port: 8978
- Volume: `cloudbeaver:/opt/cloudbeaver/workspace`
- Extra volume: `/home/phillias/docker/:/docker` — mounts the entire docker directory for file access
- No authentication configured (web UI only)

### Dockhand
- Port: 7299
- Docker management via socket-proxy
- Note: Dockhand service is defined in its own directory at `/home/phillias/docker/dockhand/`, not in the selfhost compose

### ntfy
- Port: 3930
- **Auth**: `NTFY_AUTH_DEFAULT_ACCESS=deny-all` — must authenticate with user tokens
- Godoxy uses ntfy for security notifications on `SelfHostNetSec` topic
- Godoxy config has ntfy configured as notification provider:
  ```yaml
  - name: ntfy.phillias.cc
    provider: ntfy
    token: tk_rjw1wkubryjf2cvl0r4mj0z1gv1to
    topic: SelfHostNetSec
    url: https://ntfy.phillias.cc
    format: plain
  ```

### apprise
- Port: 5832 with stateful mode
- Config/attach/plugin volumes for multi-channel notifications

---

## 7. Order of Operations & Dependencies

### Full Stack Startup Sequence

```bash
# 1. Core infrastructure (databases first — they have no inter-dependencies)
cd ~/docker/selfhost
docker compose up -d socket-proxy mariadb postgres mssql redis libsql turso

# 2. Start CrowdSec (health check gates godoxy)
docker compose up -d crowdsec

# 3. Godoxy auto-starts after crowdsec is healthy (depends_on: condition: service_healthy)
#    But if not starting, bring it up explicitly:
docker compose up -d app

# 4. Auth services (separate directories)
cd ~/docker/pocketid && docker compose up -d
cd ~/docker/tinyauth && docker compose up -d

# 5. Management services
cd ~/docker/selfhost
docker compose up -d crowdsecmgr cloudbeaver

# 6. Other services (separate directories)
cd ~/docker/dockhand && docker compose up -d
cd ~/docker/ntfy && docker compose up -d
cd ~/docker/apprise && docker compose up -d
```

### Service Dependency Graph

```
socket-proxy
  └── Everything that needs Docker API (godoxy, dockhand)
crowdsec (service_healthy)
  └── godoxy-proxy (depends_on: condition: service_healthy)
        └── All proxied apps (via Docker labels)
        └── CrowdSec AppSec middleware (127.0.0.1:7422)
mariadb / postgres / mssql / redis / libsql / turso
  └── Apps that connect to them (independent of proxy)
crowdsec (service_healthy)
  └── crowdsecmgr (depends_on: condition: service_healthy)
```

### Validation After Startup

```bash
# Check everything is up
docker ps

# Verify godoxy is routing
curl -sI https://godoxy.phillias.us

# Verify CrowdSec is healthy
docker exec crowdsec cscli lapi status
docker exec crowdsec cscli bouncers list

# Check for active bans
docker exec crowdsec cscli decisions list

# Check godoxy logs for any errors
docker compose -f ~/docker/selfhost/compose.yml logs app --tail 50
```

### Full Stack Shutdown Sequence

```bash
# Reverse order — proxy last
cd ~/docker/selfhost
docker compose down app   # Stop godoxy first (stops routing traffic)

# Then databases
docker compose down turso libsql redis mssql postgres mariadb

# CrowdSec last (no more traffic to analyze)
docker compose down crowdsec crowdsecmgr

# Auth and management services
cd ~/docker/pocketid && docker compose down
cd ~/docker/tinyauth && docker compose down
```

---

## 8. Configuration Management

### `.env` Files

| File | Purpose |
|------|---------|
| `/home/phillias/docker/.env` | Root-level shared: `PUID`, `PGID`, `TZ` |
| `/home/phillias/docker/selfhost/.env` | Main config — godoxy, crowdsec, databases, OIDC, Pocket ID, Tinyauth, ntfy |
| `/home/phillias/docker/pocketid/.env` | Pocket ID: `APP_URL`, `ENCRYPTION_KEY`, `TRUST_PROXY` |
| `/home/phillias/docker/selfhost/.restic-env` | Restic backup: repo URL, password, AWS credentials |

All `.env` files are in `.gitignore` and never committed.

### Critical Secrets

| Secret | Location |
|--------|----------|
| Cloudflare API token | `config.yml` (autocert auth_token) |
| CrowdSec LAPI bouncer key | `config.yml` (crowdsec middleware api_key) |
| CrowdSec machine password | `selfhost/.env` |
| Database passwords | `selfhost/.env` |
| OIDC client secrets | `selfhost/.env` |
| Pocket ID encryption key | `pocketid/.env` |
| ntfy auth token | `config.yml` |
| MaxMind license key | `config.yml` |
| Restic credentials | `.restic-env` (sourced, not in compose) |

### Docker Networks

| Network | Driver | Services | Notes |
|---------|--------|----------|-------|
| `host` | — | CrowdSec, Godoxy, MariaDB, PostgreSQL, MSSQL, Redis | Direct host network access |
| `selfhost_frontnet` | bridge (MTU 1400) | socket-proxy, crowdsecmgr, CloudBeaver, libSQL, Turso | Bridge network for proxied services |
| Default bridge | bridge | Pocket ID, Tinyauth | Isolated from frontnet |

Note: The `host` network provides maximum performance for databases and proxy but means ports are not isolated. Services on `frontnet` are reachable via godoxy's Docker provider.

### Godoxy Label Convention Reference

```yaml
labels:
  # Basic routing
  proxy.<name>.port: 8080              # Container port to route
  proxy.<name>.alias: myapp            # Subdomain (myapp.phillias.us)
  proxy.aliases: alt1,alt2             # Additional hostnames
  proxy.exclude: true                  # Exclude from proxy (infra defaults)
  proxy.<name>.scheme: tcp             # TCP proxy for databases

  # Homepage
  proxy.<name>.homepage.show: false    # Hide from dashboard
  proxy.<name>.homepage.name: My App

  # Healthcheck
  proxy.<name>.healthcheck.disable: true

  # Auth middlewares
  proxy.<name>.middlewares.forward_auth: |
    route: tinyauth
    auth_endpoint: /api/auth/traefik

  proxy.<name>.middlewares.oidc: |
    client_id: <uuid>
    client_secret: <secret>
    allowed_users:
      - username

  # IP whitelist
  proxy.#1.middlewares.cidr_whitelist: |
    status: 403
    allow:
      - 10.0.0.0/8
```

---

## 9. Lessons Learned

### Cloudflare SSL Mode Affects OIDC
Cloudflare's **Flexible SSL** mode sends `X-Forwarded-Proto: https` even though the connection to origin is HTTP. This breaks godoxy's OIDC redirect — it produces `https:///` (empty host). **The zone is currently set to Flexible SSL, which is incorrect and insecure.**

**Fixes:**
- Cloudflare SSL → **Full (Strict)** (urgent)
- Enable **Always Use HTTPS**
- Raise **Min TLS Version** to 1.2
- Or use a Transform Rule to strip `X-Forwarded-Proto`
- Or per-route, set header to empty via middleware

**Why this matters:** Flexible mode encrypts browser-to-Cloudflare but sends plaintext HTTP from Cloudflare to your origin. This exposes traffic and breaks OIDC redirect URI validation.

### GODOXY_OIDC_REDIRECT_URL Fix
Without this env var, godoxy's OIDC callback generates a `redirect_uri` with an empty host (`https:///auth/callback`). Setting `GODOXY_OIDC_REDIRECT_URL=https://app.phillias.us/auth/callback` fixes it. Documented in godoxy wiki/issue #66.

**Current state**: Not currently set in `selfhost/.env`. If OIDC redirect issues recur, add this variable.

### Godoxy Config Bypass/CrowdSec Whitelist Format
The godoxy `config.yml` crowdsec middleware `bypass` entries have specific formatting requirements that look inconsistent but are required:
- Bare IPv4: `- ip:162.120.186.139` (unquoted, no space after `ip:`)
- Problematic IPv4: `- "ip: 147.224.164.153"` (quoted with space — YAML parser needs it)
- IPv6: `- "ip: 2600:6c4a:53f:8285:9c5d:c409:1251:b53b"` (quoted with space — colons break unquoted YAML)

**Never change this formatting.** This is an explicit prime directive.

### CrowdSec AppSec Rule Conflicts
`crowdsecurity/virtual-patching` and `crowdsecurity/generic-rules` have `id:100` rule conflicts with `crowdsecurity/appsec-default`. When both are included, CrowdSec logs errors about duplicate rule IDs. The current acquis config only uses `appsec-default` and `crs`.

### MSSQL SA Password Encoding
The SA password `2763%Powers` contains `%P` which Docker Compose may try to expand as a variable reference. In the current `.env` file it works because `%P` doesn't match any defined variable. If expansion issues arise, escape as `%%P` or use single quotes in the compose file directly.

### Pocket ID Env Var Name — `APP_URL` not `PUBLIC_APP_URL`
Pocket ID v2 uses `APP_URL`, not `PUBLIC_APP_URL`. The older env var name is silently ignored, causing Pocket ID to fall back to `http://localhost:1411`. This breaks WebAuthn because the browser gets a passkey challenge for `localhost` instead of the real domain, producing "an unknown error occurred" on first login. Set `APP_URL=https://pocketid.phillias.us`.

### Pocket ID Setup Requires Fresh Database
If Pocket ID's Docker container starts with `PUBLIC_APP_URL` (wrong name) before being corrected to `APP_URL`, it creates partial database state (WAL file) that prevents the first-run setup wizard from appearing. Users see a login prompt instead of `/setup`. The fix is to destroy the volume and start fresh:

```bash
cd ~/docker/pocketid \
  && docker compose down \
  && docker volume rm pocketid_pocketid_data \
  && docker compose up -d
```

After that, visit `https://pocketid.phillias.us/setup` directly for the admin registration wizard.

### Pocket ID First-Time Passkey Registration
Chrome's WebAuthn dialog defaults to the platform authenticator (Windows Hello / macOS Touch ID / Google Password Manager). Bitwarden is not shown by default — look for "Use a different passkey" or "Another device" in the Chrome passkey prompt to select Bitwarden. Alternatively, use the platform authenticator and Chrome's Google Password Manager saves it automatically.

### GODOXY_OIDC_ISSUER_URL Required for Per-Route OIDC
Even when using per-route OIDC middleware labels (`proxy.<name>.middlewares.oidc`), godoxy still needs `GODOXY_OIDC_ISSUER_URL` set globally in `selfhost/.env`. Without this env var, the middleware silently does nothing — requests pass through without redirecting to Pocket ID. Set `GODOXY_OIDC_ISSUER_URL=https://pocketid.phillias.us`.

### Godoxy v0.27.5 Didn't Support `scope` in OIDC Middleware
In godoxy v0.27.5 (the original version during initial setup), the `scope` field inside `proxy.<name>.middlewares.oidc` YAML config was not recognized — godoxy logged "unknown field scope" but continued, and the middleware could fail silently. Current version is v0.29.1 which may support it. If adding `scope` to OIDC middleware, test before relying on it. The default scopes (`openid`, `profile`, `email`) are requested automatically.

### Pocket ID OIDC Callback URLs
Godoxy's OIDC callback path is always `/auth/callback`. When creating an OIDC client in Pocket ID, the Callback URLs field accepts wildcards: `https://*.phillias.us/auth/callback` is the preferred form as it avoids needing per-app callbacks. Pocket ID supports wildcard callback URIs natively.

### Tinyauth Bcrypt Hash Doubling
Docker Compose uses `$` as its variable expansion prefix. To pass a literal `$` in a Tinyauth bcrypt hash, double it: `$$2a$$10$$...`. At runtime, Docker Compose down-converts `$$` → `$`, producing the correct hash.

### Retired Services (in `.retired/`)
The `.retired/` directory in `/home/phillias/docker/` contains previously tried selfhost-related services:
- **Pangolin**: Alternative reverse proxy — godoxy chosen instead
- **Portainer, Dockge**: Docker management — Dockhand chosen instead
- **watchtower, cupdate**: Auto-updaters — intentionally not used to avoid unexpected breakage

### CrowdSec AppSec Listen Address Must Be `0.0.0.0:7422`
The AppSec acquis config must listen on `0.0.0.0:7422` (all interfaces), not `127.0.0.1:7422`. Godoxy runs in `network_mode: host` and reaches AppSec via the host network. If AppSec only listens on localhost, godoxy's CrowdSec middleware cannot reach it. The bouncer API key connects via `127.0.0.1:7422` (localhost works for same-host communication), but the AppSec listener itself needs `0.0.0.0`.

### Godoxy Depends on CrowdSec Health
The godoxy service in compose.yml has `depends_on: crowdsec: condition: service_healthy`. Godoxy won't start until CrowdSec's LAPI healthcheck (`cscli lapi status`) passes. If CrowdSec is unhealthy, godoxy will wait indefinitely — check CrowdSec logs first if godoxy won't start.

### netdata `forward_auth: {}` Placeholder
The `hostapps.yml` has `forward_auth: {}` (empty object) on the netdata entry. This is a placeholder — no auth is actually configured or active on netdata. It's a YAML structure reserved for future auth integration.

### CrowdSec Socket Access vs Godoxy Socket Proxy
CrowdSec mounts the Docker socket directly (`/run/docker.sock:/var/run/docker.sock:ro`) for log acquisition. Godoxy accesses Docker API through `socket-proxy` (restricted to CONTAINERS/INFO/PING/POST/VERSION/ALLOW_START/STOP/RESTARTS). This is intentional — CrowdSec needs broad Docker access for log analysis, while godoxy only needs container discovery.

### Host IP Reference
The host machine IP `192.168.1.173` is set as `HOSTIP` in `selfhost/.env`. Used for CrowdSec LAPI URL (`http://192.168.1.173:8373`) and other host-referencing configs. All host-network services are also accessible at `127.0.0.1` from other host-network containers.

---

## 10. Troubleshooting

### Godoxy Won't Start

```bash
# Check CrowdSec is healthy first (godoxy depends on it)
docker compose -f ~/docker/selfhost/compose.yml ps crowdsec
docker exec crowdsec cscli lapi status

# Check godoxy logs
docker compose -f ~/docker/selfhost/compose.yml logs app

# Validate YAML composition
docker compose -f ~/docker/selfhost/compose.yml config > /dev/null

# Verify permissions on config dirs
ls -la ~/docker/selfhost/godoxy/config/
```

### OIDC Not Working (Requests Not Redirected)

1. Verify `GODOXY_OIDC_ISSUER_URL` is set in `selfhost/.env`
2. Check Pocket ID is running: `curl -sI https://pocketid.phillias.us`
3. Verify OIDC client is created in Pocket ID with correct callback URL
4. Check godoxy logs for OIDC errors: `docker compose logs app | grep -i oidc`
5. If redirect_uri shows empty host, add `GODOXY_OIDC_REDIRECT_URL`
6. Check Cloudflare SSL is **Full (Strict)**. Currently it is set to **Flexible** which breaks OIDC.

### CrowdSec Issues

```bash
# Check LAPI status
docker exec crowdsec cscli lapi status

# List parsers (check whitelists are active)
docker exec crowdsec cscli parsers list

# Check bouncers are connected
docker exec crowdsec cscli bouncers list

# View CrowdSec logs
docker compose -f ~/docker/selfhost/compose.yml logs crowdsec

# Check AppSec is working
docker compose -f ~/docker/selfhost/compose.yml logs crowdsec | grep appsec

# Verify acquis config is loaded
docker exec crowdsec cat /etc/crowdsec/acquis.d/appsec.yaml
```

### Database Connection Issues

- Databases use `network_mode: host`, so they're accessible at `127.0.0.1` or `192.168.1.173`
- MSSQL: SA password must be correctly encoded (see Lessons Learned)
- MariaDB root pw set via `MYSQL_ROOT_PASSWORD`
- PostgreSQL: check `pg_isready` healthcheck
- Redis/Valkey: no password by default — accessible on localhost:6379

### App Not Reachable via Godoxy

1. Verify the container has correct godoxy labels (`proxy.<name>.port`, `proxy.<name>.alias`)
2. Check godoxy logs: `docker compose -f ~/docker/selfhost/compose.yml logs app | grep <app-name>`
3. Verify container is running and responding on its port
4. Check ACL isn't blocking the IP (`acl.allow`/`acl.deny` in config.yml)
5. Verify the container is on a network godoxy can reach (not isolated)

### Volume Migration / Cleanup

Named volumes managed by Docker:
```bash
# List volumes
docker volume ls | grep selfhost

# Remove a specific volume (after backing up)
docker volume rm selfhost_crowdsec-db

# Note: crowdsec volumes are external: true — created before compose
```

---

## 11. Backup & Recovery (Restic)

### Configuration
Restic backs up to Oracle Cloud Infrastructure Object Storage (S3-compatible). Configuration is in `/home/phillias/docker/selfhost/.restic-env`:

```bash
export RESTIC_REPOSITORY='s3:https://axh7zpa5qpqc.compat.objectstorage.us-chicago-1.oraclecloud.com/<bucket-ocid>'
export RESTIC_PASSWORD='<restic-password>'
export AWS_ACCESS_KEY_ID='<oci-hmac-key-id>'
export AWS_SECRET_ACCESS_KEY='<oci-hmac-secret>'
```

### Usage

```bash
# Source the config and run backup
source ~/docker/selfhost/.restic-env
restic backup ~/docker/selfhost/ --exclude-file=~/docker/selfhost/.gitignore

# List snapshots
restic snapshots

# Restore latest snapshot
restic restore latest --target /tmp/restore

# Check repository integrity
restic check
```

**Note**: `restic` may not be installed locally. Use `apt install restic` or run via Docker: `docker run --rm -v ~/docker:/data restic/restic ...`

---

## 12. Logging, Rotation & Debug

### Docker Log Driver

The Docker daemon at `/etc/docker/daemon.json` uses **`journald`** as the default log driver:

```json
{"log-driver": "journald"}
```

This means all container stdout/stderr goes to the systemd journal by default. No Docker-level log rotation (`max-size`, `max-file`) is configured — neither in `daemon.json` nor in any compose file's `logging:` block. Container logs grow unbounded in the journal.

### Viewing Container Logs

```bash
# Follow logs for a specific container (via journald)
docker compose -f ~/docker/selfhost/compose.yml logs -f app          # godoxy
docker compose -f ~/docker/selfhost/compose.yml logs -f crowdsec     # crowdsec
docker compose -f ~/docker/selfhost/compose.yml logs -f crowdsecmgr  # crowdsecmgr

# Last N lines
docker compose -f ~/docker/selfhost/compose.yml logs --tail 100 app

# Filter by time
docker compose -f ~/docker/selfhost/compose.yml logs --since "1h" app

# Via journalctl directly
journalctl -u docker --since "1 hour ago" | grep godoxy
```

### Godoxy File Logging

Godoxy writes **access logs** and **ACL logs** to files inside the container, bind-mounted to the host:

| Log | Path (container) | Path (host) | Config |
|-----|-----------------|-------------|--------|
| Access log | `/app/logs/entrypoint.log` | `~/docker/selfhost/godoxy/logs/entrypoint.log` | `config.yml` → `entrypoint.access_log` |
| ACL log | `/app/logs/acl.log` | `~/docker/selfhost/godoxy/logs/acl.log` | `config.yml` → `acl.log` |

Access log format is `combined` (Apache-style). The access log also outputs to stdout (`stdout: false` means it does NOT write to stdout — file only). ACL log has `stdout: false` and `log_allowed: false` (denied requests only).

**Note**: No log rotation is configured for these files. They grow unbounded. To manually rotate:

```bash
# Rotate godoxy logs manually
sudo truncate -s 0 ~/docker/selfhost/godoxy/logs/entrypoint.log
sudo truncate -s 0 ~/docker/selfhost/godoxy/logs/acl.log
```

Or add a logrotate config:

```bash
sudo tee /etc/logrotate.d/godoxy-logs << 'EOF'
/home/phillias/docker/selfhost/godoxy/logs/*.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    copytruncate
}
EOF
```

### Godoxy Debug Mode

Enable verbose debug logging in `selfhost/.env`:

```bash
GODOXY_DEBUG=true
```

Restart godoxy to apply:

```bash
docker compose -f ~/docker/selfhost/compose.yml restart app
```

When enabled, godoxy logs additional debug information including detailed routing decisions, middleware processing, and error context. Set back to `false` after debugging to reduce log volume.

### CrowdSec Logging

CrowdSec logs to journald via stdout. Its config at `/home/phillias/docker/selfhost/crowdsec/config/user.yaml` sets `log_media: stdout`, `log_level: info`, `log_dir: /var/log/`.

```bash
# View CrowdSec logs
docker compose -f ~/docker/selfhost/compose.yml logs crowdsec -f

# Via journalctl
journalctl -u docker CONTAINER_NAME=crowdsec --since "1h"

# CrowdSec CLI debugging commands
docker exec crowdsec cscli alerts list          # Active alerts
docker exec crowdsec cscli decisions list        # Active bans/decisions
docker exec crowdsec cscli metrics               # Performance metrics
docker exec crowdsec cscli lapi status           # LAPI health
docker exec crowdsec cscli collections list       # Loaded collections
docker exec crowdsec cscli scenarios list         # Loaded scenarios
docker exec crowdsec cscli parsers list           # Loaded parsers
docker exec crowdsec cscli hub list              # Hub items
```

**CrowdSec log level**: Change from `info` to `debug` in `/home/phillias/docker/selfhost/crowdsec/config/user.yaml` (`log_level: debug`) for verbose WAF troubleshooting. Restart crowdsec after changing.

**CrowdSec simulation mode**: Available at `/home/phillias/docker/selfhost/crowdsec/config/simulation.yaml` but currently **disabled** (commented out). When enabled, triggered alerts do NOT result in decisions — useful for testing new rules without affecting traffic.

**CrowdSec notifications**: The ntfy notification plugin at `/home/phillias/docker/selfhost/crowdsec/config/notifications/ntfy.yaml` sends alerts to `https://ntfy.phillias.cc/SelfHostNetSec` with `log_level: info`.

**Decision profiles**: Default profile at `/home/phillias/docker/selfhost/crowdsec/config/profiles.yaml` — ban for 4h when `Alert.Remediation == true`.

CrowdSec collection installations and parser errors appear in its logs. The acquis config at `/etc/crowdsec/acquis.d/appsec.yaml` controls AppSec log ingestion — if CrowdSec isn't analyzing web requests, check that the acquis config is loaded:

```bash
docker exec crowdsec cscli parsers list
docker exec crowdsec cscli scenarios list
```

### Per-Service Logging Quick Reference

| Service | Log Driver | File Path (host) | Debug Flag |
|---------|-----------|------------------|------------|
| godoxy-proxy | journald + file | `./godoxy/logs/entrypoint.log`, `./godoxy/logs/acl.log` | `GODOXY_DEBUG=true` |
| crowdsec | journald | None (stdout only) | `log_level: debug` in `user.yaml` |
| crowdsecmgr | journald | Volume: `selfhost_crowdsecmgr-logs` | N/A |
| mariadb | journald | Volume: `mariadb-config` | Via custom `my.cnf` |
| postgres | journald | Volume: `postgres` | `ALTER SYSTEM SET log_statement = 'all'` |
| mssql | journald | Volume: `mssql` (`/var/opt/mssql/log/errorlog` inside) | N/A |
| redis/valkey | journald | None (ephemeral) | N/A |
| libsql | journald | Volume: `libsql` | N/A |
| turso | journald | Volume: `turso` | N/A |
| cloudbeaver | journald | Volume: `cloudbeaver` | N/A |
| pocketid | journald | Volume: `pocketid_data` | N/A |
| tinyauth | journald | Volume: `./tinyauth` | N/A |
| socket-proxy | journald | None (tmpfs `/run`) | N/A |

### Database Logging

All databases log to their container stdout (journald), except where noted:

**MariaDB** — Additional file logging possible via `/config` volume. Enable slow query log by adding to a custom `my.cnf` in the config volume.

**PostgreSQL** — Logs to stdout. To enable verbose logging, set env vars:
- `POSTGRES_INITDB_ARGS` already includes `--data-checksums`
- For query logging, exec into container and modify `postgresql.conf`:
  ```bash
  docker exec -it postgres psql -U postgres -c "ALTER SYSTEM SET log_statement = 'all';"
  docker exec -it postgres psql -U postgres -c "SELECT pg_reload_conf();"
  ```

**MSSQL** — Logs to stdout. Error logs available inside container at `/var/opt/mssql/log/errorlog`.

**Redis/Valkey** — Logs to stdout. No persistent log volume.

**libSQL/Turso** — Logs to stdout on ports 7087/8087.

**Pocket ID** — Structured JSON logs to stdout (e.g., `{"level":"info","status":200,"method":"HEAD",...}`).

### Socket Proxy Logging

Socket proxy logs container API access to stdout. Permission denied errors in logs indicate services tried to access Docker API endpoints not in the allow list (`ALLOW_*` env vars).

### System Logrotate

The system at `/etc/logrotate.conf` uses standard Debian defaults:
- `weekly` rotation
- `rotate 4` (keep 4 weeks)
- `create` new files after rotation
- No compression by default (`#compress` is commented out)

Existing logrotate configs in `/etc/logrotate.d/` include: `mariadb`, `postgresql-common`, `redis-server`, `netdata`, `nginx`, `apache2`. None for godoxy, crowdsec, or Docker containers.

### Journal Maintenance

Since Docker uses journald, container logs accumulate in the systemd journal. Check journal size and rotation:

```bash
# Check journal disk usage
journalctl --disk-usage

# Check journal config
cat /etc/systemd/journald.conf

# Vacuum old logs (keep last 7 days)
journalctl --vacuum-time=7d

# Vacuum by size (keep last 500M)
journalctl --vacuum-size=500M
```

### Enabling Log Rotation for Docker Containers

To prevent unbounded log growth, add log rotation to Docker's `daemon.json`:

```bash
sudo tee /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "journald",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
sudo systemctl restart docker
```

**Caution**: Changing the log driver affects all containers. Existing containers must be recreated to pick up the new config. Alternatively, add `logging:` blocks per-service in compose files:

```yaml
services:
  app:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

### Debugging Checklist

When a selfhost service is behaving unexpectedly:

1. **Check container is running**: `docker compose ps`
2. **Follow live logs**: `docker compose logs -f <service>`
3. **Check for errors**: `docker compose logs <service> | grep -iE "error|warn|fatal|panic"`
4. **Verify config**: `docker compose config > /dev/null` (validates YAML + env substitution)
5. **Check resource usage**: `docker stats <container>`
6. **Inspect container state**: `docker inspect <container> | grep -A5 State`
7. **Check journald**: `journalctl -u docker --since "30m" | grep <service>`
8. **Enable debug mode** (godoxy): Set `GODOXY_DEBUG=true` and restart
9. **Verify network connectivity**: `docker exec <container> curl -sI http://target:port`
10. **Check file permissions**: `docker exec <container> ls -la /app/config/`
10. **Check file permissions**: `docker exec <container> ls -la /app/config/`

---

## 13. Godoxy Advanced Topics

This section covers advanced godoxy features that are available but not yet fully utilized in the current selfhost deployment. These features are documented here so they can be leveraged when needed.

### 13.1 — Idle Sleep (Container Auto-Sleep)

Godoxy can automatically put containers to sleep after a period of inactivity and wake them on incoming traffic. This is ideal for development environments, staging servers, or infrequently used services.

**Supported platforms**: Docker, Proxmox LXCs
**Supported protocols**: HTTP, TCP, UDP

#### Quick Reference

| Property | Description | Default | Required |
|----------|-------------|---------|----------|
| `idle_timeout` | Inactivity duration before sleep | Disabled | Yes |
| `wake_timeout` | Wait time for container to wake | `30s` | No |
| `stop_method` | How to stop the container | `stop` | No |
| `stop_timeout` | Timeout for stop command | `10s` | No |
| `stop_signal` | Signal for stop/kill | Docker default | No |
| `start_endpoint` | Wake trigger endpoint path | Any | No |
| `no_loading_page` | Disable wake loading page | `false` | No |

#### How It Works

**Sleep behavior:**
1. Container receives no traffic for `idle_timeout` duration
2. Godoxy executes `stop_method` on the container
3. Container dependencies are stopped in order
4. Traffic to the route triggers wake-up sequence

**Wake behavior:**
1. Request arrives for sleeping route
2. Dependencies start first (if configured)
3. Main container starts
4. Godoxy waits up to `wake_timeout` for readiness
5. Request is proxied to the now-active container

#### Dependency Management

Containers with `depends_on` are managed as a group. Do NOT set `idle_timeout` on dependency containers — only on the main service.

Condition types:
- `service_started`: Dependency process started
- `service_healthy`: Dependency healthcheck passes

#### Docker Label Configuration

```yaml
services:
  app:
    image: myapp:latest
    labels:
      proxy.idle_timeout: 1h30s          # Required
      proxy.wake_timeout: 30s            # Optional
      proxy.stop_method: stop            # Optional: stop, pause, kill
      proxy.stop_timeout: 10s            # Optional
      proxy.stop_signal: SIGINT          # Optional
      proxy.start_endpoint: /api/wake    # Optional
      proxy.no_loading_page: true        # Optional
    depends_on:
      redis:
        condition: service_healthy
      postgres:
        condition: service_healthy
```

#### Duration Format

| Unit | Example |
|------|---------|
| Seconds | `30s` |
| Minutes | `15m` |
| Hours | `1h` |
| Combined | `1h30m15s` |

#### Example: Development Environment

```yaml
services:
  dev-api:
    image: myapp/api:latest
    labels:
      proxy.idle_timeout: 30m
      proxy.wake_timeout: 60s
      proxy.stop_method: kill
      proxy.stop_timeout: 5s
    depends_on:
      dev-db:
        condition: service_healthy
```

#### Best Practices

1. Use healthchecks with `service_healthy` condition for reliable dependencies
2. Set appropriate timeouts based on service startup time
3. Test wake behavior before deploying to production
4. Monitor container logs during initial setup
5. Use consistent stop signals that match your application

---

### 13.2 — Rule-Based Routing

Rule-based routing allows defining custom routing logic with conditions (headers, query params, cookies, etc.) and actions (serve files, proxy, redirect, etc.). This is an **experimental** feature — syntax may change.

#### Rule Structure

Three rule forms:

```yaml
# Default rule (fallback)
default {
  remove resp_header X-Internal
}

# Conditional rule
path glob("/api/*") {
  proxy http://api:8080
}

# Unconditional rule (always matches)
{
  log info /dev/stdout "$req_method $req_path"
}
```

#### Block Syntax (Recommended)

```yaml
path /api {
  # Inline positional form
  rewrite /api /backend

  # Equivalent named-option form
  rewrite {
    from: /api
    to: /backend
  }
}
```

#### YAML Compatibility (Legacy)

```yaml
- name: default
  do: remove resp_header X-Internal
- on: path glob("/api/*")
  do: proxy http://api:8080
```

#### Rule Behavior

- Rules are processed in **pre** and **post** phases
- A default rule runs only when no non-default pre rule matches
- Pre-phase terminating commands stop remaining pre commands
- Post-only commands from already-matched rules can still run in post phase
- Response-based matchers (`status`, `resp_header`) are evaluated in post phase

#### Nested Block Syntax

```yaml
path /example {
  set header X-Mode outer

  method GET {
    set header X-Mode get
  } elif method POST {
    set header X-Mode post
  } else {
    set header X-Mode other
  }
}
```

#### Pattern Matching

| Pattern Type | Syntax | Description |
|---|---|---|
| String | `"value"` or `value` | Exact string match |
| Glob | `glob(pattern)` | Wildcard matching |
| Regex | `regex(pattern)` | Regular expression |

```yaml
# String matching
header X-API-Key "secret-key"

# Glob pattern
header User-Agent glob(Mozilla*)
path glob(/api/v[0-9]/*)

# Regex
header X-API-Key regex("^sk-[a-zA-Z0-9]{32}$")
path regex("^/api/v[0-9]+/users/[a-f0-9-]{36}$")
```

#### Environment Variable Substitution

```yaml
path glob("/service/**") {
  proxy https://${SERVICE_HOST}:${SERVICE_PORT}
}

path /secret {
  error 403 "Forbidden: ${REDACT_REASON}"
}
```

Use `$$` to escape literal `$` in Docker labels.

#### Common Use Cases

**API Gateway with Basic Auth:**
```yaml
path regex("^/api/v[0-9]+/public/.*") {
  proxy http://api-server:8080
}

path glob("/api/v[0-9]/admin/*") &
basic_auth admin "$2y$10$hashed_password" {
  set header X-Admin true
  proxy http://admin-server:8080
}
```

**Security + Allowlist:**
```yaml
header User-Agent glob(*bot*) |
remote 192.168.1.0/24 {
  error 403 "Access denied"
}

host glob(*.example.com) | host example.com {
  pass
}
```

**CORS Preflight:**
```yaml
method OPTIONS &
header Origin &
header Access-Control-Request-Method {
  set resp_header Access-Control-Allow-Origin $header(Origin)
  set resp_header Access-Control-Allow-Methods GET,POST,PUT,PATCH,DELETE,OPTIONS
  set resp_header Access-Control-Allow-Headers $header(Access-Control-Request-Headers)
  set resp_header Access-Control-Allow-Credentials true
  error 204 ""
}
```

**Request Mutation + Proxy:**
```yaml
path glob("/api/**") {
  set header X-Request-Id $header(X-Request-Id)
  add header X-Forwarded-For $remote_host
  remove header X-Secret
  add query debug true
  proxy http://api-server:8080
}
```

**Response-Conditional Logging:**
```yaml
path glob("/api/**") {
  proxy http://api-server:8080
}

status 4xx | status 5xx {
  log error /dev/stderr "Status=$status_code CT=$resp_header(Content-Type)"
}
```

#### Docker Compose Label Configuration

```yaml
services:
  app:
    labels:
      proxy.app.rules: |
        header Connection Upgrade &
        header Upgrade websocket {
          pass
        }
        default {
          rewrite / /report.html
          serve /tmp/access
        }
```

---

### 13.3 — Middleware Complete Reference

Middlewares can be applied at four levels (in order of precedence):
1. **Entrypoint** — Global, ordered, defined in `config.yml`
2. **Middleware Compose** — Reusable configs in `config/middlewares/*.yml`
3. **Docker Labels** — Per-route, unordered (use `priority` for ordering)
4. **Route Files** — Per-route, unordered

Middleware names are **case-insensitive**: `redirectHTTP`, `redirect_http`, `RedirectHttp` are equivalent.

#### Full Middleware Catalog

##### Access Control

**CIDR Whitelist** (`cidr_whitelist`):
```yaml
# Entrypoint
entrypoint:
  middlewares:
    - use: cidr_whitelist
      allow:
        - 10.0.0.0/8
        - 192.168.0.0/16
      status_code: 403
      message: "IP not allowed"

# Docker labels (flat)
proxy.#1.middlewares.cidr_whitelist.allow: 10.0.0.0/8, 192.168.0.0/16
proxy.#1.middlewares.cidr_whitelist.status_code: 403

# Docker labels (YAML block)
proxy.#1.middlewares.cidr_whitelist: |
  allow:
    - 10.0.0.0/8
  status_code: 403
  message: "IP not allowed"
```

**Rate Limiter** (`rate_limit`):
```yaml
entrypoint:
  middlewares:
    - use: rate_limit
      average: 10
      burst: 20
      periods: 1m

# Docker labels
proxy.#1.middlewares.rate_limit: |
  average: 10
  burst: 20
  periods: 1m
```

##### Authentication & Security

**CrowdSec AppSec** (`crowdsec`):
```yaml
entrypoint:
  middlewares:
    - use: real_ip
      header: X-Real-IP
      from: [127.0.0.1, 192.168.0.0/16, 10.0.0.0/8]
    - use: crowdsec
      route: crowdsec
      api_key: "1234567890"
      port: 7422
      log_blocked: true
      timeout: 5s
      bypass:
        - route crowdsec
```

**Forward Auth** (`forward_auth`):
```yaml
entrypoint:
  middlewares:
    - use: forward_auth
      route: tinyauth
      auth_endpoint: /api/auth/traefik
      headers: [Remote-User, Remote-Name, Remote-Email, Remote-Groups]
      bypass:
        - route tinyauth
```

**OIDC** (`oidc`):
```yaml
entrypoint:
  middlewares:
    - use: oidc
      allowed_users: [user1, user2]
      allowed_groups: [group1, group2]
      client_id: client1
      client_secret: secret1
      bypass:
        - route pocket-id
        - route immich & path glob(/api/*)
        - remote 192.168.0.0/16

# Docker labels
proxy.#1.middlewares.oidc: |
  allowed_users: user1, user2
  client_id: client1
  client_secret: secret1
```

**hCaptcha** (`hcaptcha`):
```yaml
entrypoint:
  middlewares:
    - use: hcaptcha
      site_key: your-site-key
      secret_key: your-secret-key
      session_expiry: 24h
```

##### IP Resolution

**Real IP** (`real_ip`):
```yaml
entrypoint:
  middlewares:
    - use: real_ip
      header: X-Real-IP
      from: [127.0.0.1, 192.168.0.0/16]
      recursive: true
```

Recursive mode: `true` = first IP not in `from` list; `false` = last IP not in `from` list.

**Cloudflare Real IP** (`cloudflare_real_ip`):
```yaml
entrypoint:
  middlewares:
    - use: cloudflare_real_ip
# Preset: header=CF-Connecting-IP, from=Cloudflare IPs + local IPs, recursive=true
```

##### Traffic Control

**Redirect HTTP** (`redirect_http`):
```yaml
entrypoint:
  middlewares:
    - use: redirect_http
```

**Custom Error Pages** (`custom_error_pages`):
```yaml
# Enabled by default at entrypoint
proxy.#1.middlewares.custom_error_pages:
```

#### Middleware Bypass Rules

When an entrypoint middleware is active, per-route bypass rules are promoted into the entrypoint middleware for that route only:

```yaml
# config.yml — entrypoint has OIDC
entrypoint:
  middlewares:
    - use: oidc

# Docker labels — this route adds bypass rules for entrypoint OIDC
proxy.myapp.middlewares.oidc.bypass: |
  - path glob(/public/*)
  - path /health
```

#### Reusing Middleware Compositions

Define reusable middleware sets in `config/middlewares/*.yml`:

```yaml
# config/middlewares/whitelist.yml
myWhitelist:
  - use: CloudflareRealIP
  - use: CIDRWhitelist
    allow: [127.0.0.1, 223.0.0.0/8]
```

Reference them with `@file` suffix:
```yaml
# Docker labels
proxy.#1.middlewares.myWhitelist@file:

# Route file
myapp:
  middlewares:
    myWhitelist@file:

# Entrypoint
entrypoint:
  middlewares:
    - use: myWhitelist@file
```

---

### 13.4 — Content Modification

#### Modify HTML (`modify_html`)

Inject or replace HTML content using CSS selectors.

**Configuration:**

| Option | Description | Default |
|--------|-------------|---------|
| `target` | CSS selector | — |
| `html` | HTML to inject | — |
| `replace` | Replace mode (true = replace, false = append) | `false` |

**Supported CSS selectors:** element (`body`), ID (`#main`), class (`.container`), attribute (`[data-test='val']`)

**Examples:**
```yaml
# Inject CSS into head
proxy.myapp.middlewares.modify_html: |
  target: head
  html: '<style>body { background: red; }</style>'

# Replace main content
proxy.myapp.middlewares.modify_html: |
  target: main
  html: '<section><h2>New</h2></section>'
  replace: true
```

#### Themed (`themed`)

Inject theme CSS into HTML for dashboard-style theming.

**Configuration:**

| Option | Description | Conflicts |
|--------|-------------|-----------|
| `theme` | Preset theme | `css` |
| `font_url` | Font URL | — |
| `font_family` | Font name | — |
| `css` | Custom CSS URL | `theme` |

**Available themes:** `dark`, `dark-grey`, `solarized-dark`

**Examples:**
```yaml
proxy.myapp.middlewares.themed: |
  theme: dark
  font_url: https://fonts.googleapis.com/css2?family=Inter:wght@400;700&display=swap
  font_family: Inter

# Custom CSS from theme-park.dev
proxy.myapp2.middlewares.themed.css: https://theme-park.dev/css/base/<app>/<theme>.css
```

---

### 13.5 — Modify Request / Modify Response

#### Modify Request (`modify_request` / `request`)

Modify request headers and paths before proxying upstream.

**Configuration:**

| Option | Description | Default |
|--------|-------------|---------|
| `set_headers` | Replace headers | — |
| `add_headers` | Add headers (append) | — |
| `hide_headers` | Remove headers | — |
| `add_prefix` | Path prefix | — |

**Examples:**
```yaml
# Entrypoint
entrypoint:
  middlewares:
    - use: modify_request
      set_headers:
        X-Custom: value1, value2
        X-Real-IP: $remote_host
      add_headers:
        X-Custom: value1
      hide_headers: X-Real-IP, X-Forwarded-For

# Docker labels
proxy.myapp.middlewares.request.set_headers: |
  X-Custom: value1, value2
  X-Real-IP: $$remote_host
```

#### Modify Response (`modify_response` / `response`)

Modify response headers before sending to client.

**Configuration:**

| Option | Description | Default |
|--------|-------------|---------|
| `set_headers` | Replace headers | — |
| `add_headers` | Add headers (append) | — |
| `hide_headers` | Remove headers | — |

**Examples:**
```yaml
# Entrypoint
entrypoint:
  middlewares:
    - use: modify_response
      set_headers:
        X-Custom: value1, value2
      add_headers:
        X-Custom: value1
      hide_headers: X-Real-IP, X-Forwarded-For

# Docker labels
proxy.myapp.middlewares.response.set_headers: |
  X-Custom: value1, value2
```

#### Variables Reference

All variables use `$variable_name` syntax. Use `$$` in Docker labels to escape `$`.

**Request variables:**

| Variable | Description |
|----------|-------------|
| `req_method` | HTTP method |
| `req_scheme` | URL scheme |
| `req_host` | Host without port |
| `req_port` | Port number |
| `req_addr` | Host:port |
| `req_path` | URL path |
| `req_query` | Query string |
| `req_url` | Full URL |
| `req_uri` | Encoded path?query |
| `req_content_type` | Content-Type header |
| `req_content_length` | Request body length |

**Client variables:**

| Variable | Description |
|----------|-------------|
| `remote_addr` | Client IP |
| `remote_host` | Client IP (parsed) |
| `remote_port` | Client port |

**Response variables:**

| Variable | Description |
|----------|-------------|
| `resp_content_type` | Response Content-Type |
| `resp_content_length` | Response body length |
| `status_code` | HTTP status |

**Upstream variables:**

| Variable | Description |
|----------|-------------|
| `upstream_name` | Server alias |
| `upstream_scheme` | Server scheme |
| `upstream_host` | Server host |
| `upstream_port` | Server port |
| `upstream_addr` | Server address:port |
| `upstream_url` | Full server URL |

**Dynamic functions:**

| Function | Description |
|----------|-------------|
| `header(name)` | Get request header value |
| `resp_header(name)` | Get response header value |
| `arg(name)` | Get query parameter |

---

### 13.6 — Available Label Properties Reference

Complete list of Docker label properties for godoxy service configuration:

**Core routing:**

| Label | Default | Description |
|-------|---------|-------------|
| `proxy.<name>.aliases` | `container_name` | Route hostnames |
| `proxy.<name>.exclude` | `false` | Exclude from proxy |
| `proxy.<name>.network` | First available | Docker network to use |

**Protocol:**

| Label | Default | Description |
|-------|---------|-------------|
| `proxy.<name>.scheme` | Auto-detected | `http`, `https`, `tcp`, `udp`, `fileserver` |
| `proxy.<name>.host` | Docker: client IP | Target hostname/IP |
| `proxy.<name>.port` | Auto-detected | `1-65535` or `from:to` |
| `proxy.<name>.no_tls_verify` | `false` | Skip TLS verification |

**HTTP-specific:**

| Label | Default | Description |
|-------|---------|-------------|
| `proxy.<name>.bind` | `0.0.0.0` | IP address |
| `proxy.<name>.response_header_timeout` | `60s` | Response header timeout |
| `proxy.<name>.max_conns_per_host` | `1000` | Max connections per host |
| `proxy.<name>.disable_compression` | `false` | Disable compression |

**Stream (TCP/UDP):**

| Label | Default | Description |
|-------|---------|-------------|
| `proxy.<name>.port` | `0:lowest_port` | `from:to` |
| `proxy.<name>.bind` | `0.0.0.0` | IP address |
| `proxy.<name>.relay_proxy_protocol_header` | `false` | Proxy Protocol (TCP only) |
| `proxy.<name>.tls_termination` | `false` | TLS termination (TCP on HTTPS only) |

**File Server:**

| Label | Default | Description |
|-------|---------|-------------|
| `proxy.<name>.root` | Required | Directory path |
| `proxy.<name>.spa` | `false` | Single page app mode |
| `proxy.<name>.index` | `/index.html` | Index filename |

**Sleep & Wake:**

| Label | Default | Description |
|-------|---------|-------------|
| `proxy.idle_timeout` | Disabled | Inactivity before sleep |
| `proxy.wake_timeout` | `30s` | Wait for wake completion |
| `proxy.stop_method` | `stop` | `stop`, `pause`, `kill` |
| `proxy.stop_timeout` | `10s` | Stop command timeout |
| `proxy.stop_signal` | Docker default | Signal name |
| `proxy.start_endpoint` | None | Wake trigger path |
| `proxy.no_loading_page` | `false` | Disable loading page |

**Health Check:**

| Label | Default | Description |
|-------|---------|-------------|
| `proxy.*.healthcheck.path` | — | Health check path |
| `proxy.*.healthcheck.interval` | — | Health check interval |
| `proxy.<name>.healthcheck.disable` | — | Disable health checks |

**Homepage:**

| Label | Default | Description |
|-------|---------|-------------|
| `proxy.<name>.homepage.show` | — | Show on dashboard |
| `proxy.<name>.homepage.name` | — | Display name |
| `proxy.<name>.homepage.icon` | — | Icon URL |
| `proxy.<name>.homepage.category` | — | Category |
| `proxy.<name>.homepage.description` | — | Description |

**Rule-Based Routing:**

| Label | Default | Description |
|-------|---------|-------------|
| `proxy.<name>.rules` | — | Rule-based routing DSL block |

**Wildcard alias (route files):**

```yaml
"*.example.com":
  host: 10.0.0.20
  port: 8080
```

---
=======
The selfhost skill was consolidated into the selfhost repo during the June 2026
infrastructure reorganization. Its canonical home is the selfhost git repository
at `~/docker/selfhost/`.
>>>>>>> Stashed changes

Load it by path when working with selfhost infrastructure, or run opencode from
`~/docker/selfhost/` where `.opencode/opencode.json` discovers it automatically.
