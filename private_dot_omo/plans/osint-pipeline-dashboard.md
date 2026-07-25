# OSINT Multi-Stage Pipeline & Dashboard

## Overview

Build a self-hosted web dashboard that chains OSINT tools across 5 stages — Identity Sweep, Enrichment, Geospatial, Public Records, and Report Generation. Backend runs on Docker (Kali-based container for tools), frontend is a web UI, and an MCP server exposes everything to AI agents.

---

## Architecture

```
                         ┌─────────────────────────────┐
                         │         Web Dashboard        │
                         │  (React/Vue + FastAPI backend)│
                         └──────────┬──────────────────┘
                                    │ HTTP/WS
              ┌─────────────────────┼─────────────────────┐
              │                     │                     │
              ▼                     ▼                     ▼
   ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
   │  MCP Server        │   │  REST API         │   │  Task Queue       │
   │  (Ichi94 container)│   │  (FastAPI)         │   │  (Celery/ARQ)    │
   │  - sync tools      │   │  - web UI calls    │   │  - SpiderFoot    │
   │  - direct queries  │   │  - auth + quotas   │   │  - Maigret       │
   └──────────┬─────────┘   └────────┬──────────┘   │  - Amass         │
              │                      │               │  - long runs     │
              ▼                      ▼               └────────┬─────────┘
   ┌──────────────────┐   ┌──────────────────┐                │
   │  Tool Container    │   │  External APIs    │               │
   │  (Kali Docker)    │   │  - OpenSanctions  │               │
   │  - Omniscan       │   │  - CourtListener  │               │
   │  - SpiderFoot     │   │  - PACER          │               │
   │  - Sherlock       │   │  - IntelX         │               │
   │  - Holehe         │   │  - Nominatim      │               │
   │  - Maigret        │   │  - HIBP           │               │
   │  - theHarvester   │   │  - Shodan         │               │
   │  - Overpass Turbo │   └──────────────────┘               │
   │  - Nominatim      │                                       │
   └──────────────────┘                                       │
                                                              │
                              ┌───────────────────────────────┘
                              ▼
                   ┌─────────────────────┐
                   │  PostgreSQL / SQLite │
                   │  - scan cache        │
                   │  - result store      │
                   │  - evidence ledger   │
                   └─────────────────────┘
```

---

## Stage 1 — Identity Sweep

**Input:** Email, username, phone number, full name

| Tool | What It Does | Cost | Notes |
|------|-------------|------|-------|
| **Omniscan** | Chains Sherlock (400 sites) + Holehe (120 sites) + Maigret (500-2500 sites) + GHunt + PhoneInfoga | Free CLI | Python package. Wraps the identity triad into one command. |
| **theHarvester** | Emails, subdomains, employees from public sources | Free | Included in Ichi94 container |
| **BlackEyes / Blackbird** | Username enum (581 sites), sticker-based Telegram de-anonymization | Free | Included in Ichi94 container |
| **PhoneInfoga** | Phone number reconnaissance | Free | Included in Ichi94 container |

**Output:** Mapping of input → discovered accounts, associated names, emails, phone numbers, profile data

**Goal:** Maximize coverage with the Omniscan triad, then run theHarvester for domain-based email discovery.

---

## Stage 2 — Enrichment

**Input:** Domains, IPs, emails, usernames from Stage 1

| Tool | What It Does | Cost | Notes |
|------|-------------|------|-------|
| **SpiderFoot** | 200+ modules: DNS, WHOIS, Shodan, breach DBs, social media, dark web | Free, self-hosted | 5-30 min scans. Needs API keys for some modules. Heavy. |
| **OpenSanctions** | Sanction lists, PEP, wanted persons, adverse media | Free API | REST API, structured JSON. 40k+ entities. |
| **IntelX** | Leaked data, paste sites, dark web | Free tier (100 credits), paid from $10/mo | Good for breach correlation |
| **HaveIBeenPwned** | Breach data by email | Free API tier | Rate-limited, 1500 req/mo on free |
| **Dehashed** | Breach search (email, username, IP, domain, name, phone, address) | Paid (~$5-15/mo) | BEST breach coverage. Worth the cost. |
| **Shodan** | Internet device intelligence | Free tier (limited), paid from $59/mo | Optional — adds port/banner context |
| **Censys** | Internet asset inventory | Free tier (250/mo), paid from $75/mo | Alternative to Shodan |
| **GreyNoise** | IP scanner reputation | Free tier | Filters background noise from scan results |
| **VirusTotal** | File/IP/domain reputation | Free API tier | 500 req/day free |

**Output:** Technical context around discovered assets — domain/IP relationships, breach histories, infrastructure overlap

**Goal:** SpiderFoot is the orchestrator here. Run SpiderFoot on discovered domains/emails/IPs. Complement with OpenSanctions if the subject is a business entity.

---

## Stage 3 — Geospatial

**Input:** Addresses, coordinates, locations from Stages 1-2

| Tool | What It Does | Cost | Notes |
|------|-------------|------|-------|
| **Overpass Turbo** (Overpass API) | Query OpenStreetMap — buildings, infrastructure, boundaries | Free | Learn Overpass QL syntax. Export GeoJSON. |
| **Nominatim** | Geocoding: address ↔ coordinates | Free | Rate-limits apply. Self-hostable. |
| **OSIRIS AI** (osirisai.live) | Geospatial dashboard — flights, CCTV, weather, map layers | Free (MIT) | Map dashboard. Integrates multiple tile layers. |
| **Google Maps Static / Street View API** | Satellite imagery, street-level photos | Free $200/mo credit, then ~$0.002-0.007 per request | Useful for location verification |
| **Mapillary / KartaView** | Crowd-sourced street-level imagery | Free | Alternative to Google Street View |

**Output:** Maps, coordinates, OSM data, geolocation context, street-level imagery

**Goal:** If the investigation has a location component, run Overpass queries for site features, then visualize on OSIRIS map.

---

## Stage 4 — Public Records

**Input:** Names, business entities, SSN fragments, DOBs from Stages 1-2

| Tool | What It Does | Cost | Notes |
|------|-------------|------|-------|
| **CourtListener** | Federal + state court opinions, RECAP archive, PACER docket API | Free (REST API) | RECAP = crowd-sourced PACER documents. API is generous. |
| **PACER** | Federal court dockets and documents | $0.10/page, waived under $30/qtr | Direct. CourtListener's RECAP covers many docs already. |
| **OpenCorporates** | Company records, directors, officers | Free tier (limited), API paid | Largest open database of companies |
| **OpenSanctions** | Sanctions, PEP, wanted persons | Free | Already listed in Stage 2 — cross-reference here |
| **Judici / uniCourt** | County court records | Paid (~$30-100/mo) | Depends on jurisdiction coverage |
| **BRB Publications** | State/county public records directory | Free (reference) | Not a tool — a reference for where to look |
| **FamilySearch / WikiTree** | Genealogical records | Free | Useful for deceased subject background |
| **TruePeopleSearch / FastPeopleSearch** | US person search (name → address, phone, relatives, associates) | Free | Aggregates public data. Good for lead generation. |

**Output:** Court filings, company records, property records, sanctions hits, person profiles

**Goal:** CourtListener + PACER for federal litigation. OpenCorporates for business entities. Free person search aggregators for individual lookup. Premium only when the free path fails.

---

## Stage 5 — Report Generation

**Input:** All results from Stages 1-4

| Component | What It Does | Notes |
|-----------|-------------|-------|
| **Cross-reference engine** | Correlate results across stages — same email from Stage 1, domain from Stage 2, location from Stage 3 | SQL queries + Python logic |
| **Evidence ledger** | Timestamped, source-cited record of every finding | Immutable log. Critical for PI admissibility. |
| **HTML/PDF report** | Formatted dossier with all findings, maps, source links | WeasyPrint / Puppeteer for PDF |
| **JSON/CSV export** | Machine-readable output for downstream | Structured data for case management |
| **MCP tool for AI** | "Generate a full investigative dossier on target@email.com" | Chains all stages and returns a report |

**Goal:** One-click dossier generation from a single identifier.

---

## Tool Tiers by Cost

### Free & Self-Hosted (core stack)

| Tool | Stage | License |
|------|-------|---------|
| Omniscan | 1 | MIT |
| Sherlock | 1 | MIT |
| Holehe | 1 | GPL |
| Maigret | 1 | MIT |
| PhoneInfoga | 1 | GPL |
| theHarvester | 1 | GPL |
| SpiderFoot | 2 | MIT |
| OpenSanctions | 2, 4 | MIT (data under various licenses) |
| Overpass Turbo / Nominatim | 3 | ODbL / MIT |
| OSIRIS AI | 3 | MIT |
| CourtListener | 4 | AGPL (API free) |
| OpenCorporates | 4 | Free tier |
| Blackbird | 1 | MIT |

### Free Tier APIs (works without payment)

| Tool | Stage | Free Limit |
|------|-------|-----------|
| HaveIBeenPwned | 2 | 1500 req/mo |
| IntelX | 2, 4 | 100 credits free |
| Shodan | 2 | Limited results |
| VirusTotal | 2 | 500 req/day |
| GreyNoise | 2 | 10000 req/mo |
| Censys | 2 | 250 queries/mo |

### Paid but Worth the Cost

| Tool | Stage | Cost | Why Worth It |
|------|-------|------|-------------|
| **Dehashed** | 2 | ~$5-15/mo | Best breach coverage, multi-identifier search |
| **PACER** | 4 | ~$0-3/qtr (waived under $30) | Only source for federal court dockets |
| **Censys paid** | 2 | $75/mo | Full internet scan data |
| **Shodan paid** | 2 | $59/mo | IoT/device intelligence |
| **uniCourt / DocketAlarm** | 4 | $30-150/mo | State court normalization |

---

## Tech Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| **Container runtime** | Docker + Docker Compose | Kali container for tools, Ubuntu host fine |
| **Tool container** | Ichi94/pentest-osint-mcp-server (modified) | 19 tools, Streamable HTTP, Bearer auth — best starting point |
| **SpiderFoot** | Standalone container (smicallef/spiderfoot) | Has its own web UI + REST API. Better to run separately than inside the MCP container. |
| **Backend** | FastAPI | Async, MCP-compatible, Python-native |
| **Task queue** | ARQ (Redis-backed) | Lightweight async queue for long-running tools (SpiderFoot, Maigret, Amass) |
| **Database** | PostgreSQL (+ SQLite for scratch) | Structured results + evidence ledger |
| **Frontend** | React / Next.js with MapLibre (geospatial) | Dashboard + map visualization |
| **MCP** | FastMCP Streamable HTTP | Expose tools to AI agents remotely |
| **Reverse proxy** | Caddy | Automatic TLS, IP whitelisting, rate limiting |

---

## Deployment Architecture

### Container 1: Tools (Kali-based)

Based on Ichi94/pentest-osint-mcp-server but modified:
- Add **Omniscan** (`pip install omniscan`)
- Add **PhoneInfoga** (already included)
- Add **Overpass Turbo** wrapper (Python HTTP client to Overpass API — no need to self-host Overpass)
- Add **Nominatim** wrapper (HTTP client — use public API or self-host)
- Mount output volume for scan results

### Container 2: SpiderFoot (standalone)

SpiderFoot runs better as its own container:
- `smicallef/spiderfoot` image
- Exposes REST API on port 5001
- More stable with its own DB, not competing for resources with the MCP tools

### Container 3: Web Dashboard Backend

FastAPI application:
- Routes API calls to appropriate tool container
- Manages task queue for long-running scans
- Stores results in PostgreSQL
- Cost tracking / usage limits for paid APIs
- Authentication + user management

### Container 4: Web Dashboard Frontend

React / Next.js:
- Dashboard views for each stage
- Map component (MapLibre GL) for geospatial
- Report generation UI
- Search interface — enter identifier, see all results

### Container 5: Caddy (reverse proxy)

Single entry point:
- `osint.yourdomain.com` → frontend
- `osint.yourdomain.com/api` → backend
- `osint.yourdomain.com/mcp` → MCP server
- `osint.yourdomain.com/spiderfoot` → SpiderFoot web UI
- IP allow-list (your IP / VPN)
- Bearer token auth for MCP
- Rate limiting: 10 req/min per IP on heavy tools
- TLS automatic

---

## Implementation Phases

### Phase 1 — Foundation (Week 1)
- [ ] Deploy Ichi94/pentest-osint-mcp-server container
- [ ] Add Omniscan + Overpass wrapper to the container
- [ ] Stand up SpiderFoot standalone container
- [ ] Configure Caddy with TLS + IP lock + auth
- [ ] Verify MCP tools work remotely from AI client

### Phase 2 — Backend API (Week 2)
- [ ] FastAPI backend with PostgreSQL
- [ ] Stage orchestration — trigger Stage 1 → pass results to Stage 2, etc.
- [ ] Task queue for long-running tools
- [ ] Result caching (don't re-run same scan)
- [ ] Cost tracker for paid API usage

### Phase 3 — Web Dashboard (Week 3)
- [ ] Basic React frontend with search input
- [ ] Stage-by-stage result display
- [ ] Map component (MapLibre) for geospatial
- [ ] Report generation UI + PDF export

### Phase 4 — Integration & Polish (Week 4)
- [ ] Full pipeline: one identifier → complete dossier
- [ ] Evidence ledger with immutable timestamps
- [ ] MCP "full investigation" tool that chains all stages
- [ ] Rate limiting, auth, usage monitoring

---

## Cost Controls for Premium Services

| Service | Cost Cap Strategy |
|---------|------------------|
| **Dehashed** | Prepaid API key with $10/mo budget. Dashboard tracks query count. |
| **PACER** | Set quarterly budget cap and send alert before $30 threshold (where billing kicks in). |
| **Shodan** | Free tier mostly sufficient for PI work. Upgrade only if needed. |
| **IntelX** | Free tier covers light usage. $10/mo for 100,000 credits. |
| **Censys** | Free tier at 250/mo. Upgrade gated behind explicit user confirmation. |
| **APIs in general** | All paid API calls logged with cost. Dashboard must show "Cost to run this pipeline: $X" before execution. |

---

## Container OS Question

**No, the Ichi94/pentest-osint-mcp-server does NOT need to run on a Kali host.** It uses `FROM kalilinux/kali-rolling:latest` in its Dockerfile, so the container itself IS Kali Linux. Docker abstracts the OS — it runs identically on any Linux host with Docker:
- Ubuntu Server 20.04+ ✅
- Debian 11+ ✅
- Fedora / RHEL ✅
- macOS (Docker Desktop) ✅
- Windows (Docker Desktop/WSL2) ✅

The host just needs Docker Engine. The container carries its own Kali installation inside it with all tools pre-installed.
