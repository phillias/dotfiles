---
name: webapp-design
description: >
  House design + product contract for web applications. Load when building, reviewing, or
  architecting webapp work (any repo, any stack) to apply the house taste guardrails and stack
  escalation rule, and to scaffold a project's per-project PRODUCT.md/DESIGN.md from the seed
  templates in references/.
---

# WebApp Design — House Contract

House defaults for web application work in this home. Apply unless the project's own
PRODUCT.md / DESIGN.md overrides them (the normal outcome of scaffolding).

## Stack & escalation rule

Language choice is **performance-first, decided per project** by the constellation of input
requirements. The default language for bootstrapping, internally-facing projects, and when
all else is equal is **Go**; **Rust** is the escalation when external-facing performance or
safety guarantees justify it.

- **Go default**: stdlib `http.ServeMux` (Go 1.22+ method routing) + a-h/templ + SQLite
  (modernc.org/sqlite, pure-Go static) + embedded htmx 2.x — single-binary hypermedia,
  hyper-optimized for cheap VPS/OCI hosting. No node, no build step beyond `templ generate`.
- **Rust (Axum/tokio) + HTMX + SQLite (sqlx)**: preferred when externally-facing and the
  compiler's guarantees are load-bearing, or raw throughput/latency is the spec. Rust has an
  emerging pattern ecosystem but not yet a reliable breadth of foot-gun-free patterns — budget
  for that when choosing it.
- **Alpine.js 3.x** is the default client-interactivity layer, embedded like htmx: pure
  browser-local state (dropdowns, modals, tabs, accordions, client-side filtering). htmx owns
  server round-trips; Alpine owns UI state. ~15KB, no build step. Standard build needs
  `script-src 'unsafe-eval'`; the CSP build drops it for strict policies.
- Escalate a single island to React + Radix UI + TypeScript only when a feature genuinely
  needs complex accessible interactivity (dialogs, comboboxes, menus, rich editors, complex forms).
- TypeScript earns its place per-island; never the default runtime; Radix never appears in the HTMX layer.
- PWA (service worker + manifest) is static assets — backend-agnostic, orthogonal to the above.

## Deployment escalation (self-host -> Cloudflare Workers)

Default: single-binary self-host — Go (CGO-free, ~15–25MB static) or Rust (musl static) —
with SQLite (WAL) + **Litestream** continuous replication to object storage. On the house's
OCI setup: one `VM.Standard.A1.Flex` (2 OCPU / 12 GB since the June 2026 halving), SQLite on a
Balanced-tier block volume at `/var/lib/<app>/`, one Litestream process replicating all DBs to
OCI Object Storage (S3-compat endpoint, `region: us-east-1`, Customer Secret Keys, DELETE-only
lifecycle rules — never IA/Archive, `sync-interval: 1m` to respect the 50K req/mo cap), behind
Caddy or a tunnel to the home Godoxy. Escalate to Cloudflare Workers when one or more hold:

- Global edge distribution matters (low latency everywhere, no single region).
- Zero-ops serverless (scale-to-zero, no idle billing, managed everything).
- Per-tenant isolation at scale (thousands of small databases, not one big one).
- Real-time or coordinated state (WebSocket, presence, multiplayer, per-user state).
- Prototyping on the free tier (no infra, no card).

Cloudflare resources to use when escalating:

- **D1** = managed serverless SQL with SQLite semantics — the default Cloudflare relational
  layer. Read-heavy, free global read replicas, HTTP API for non-Worker tools, scale-out via
  per-tenant databases (10 GB / DB cap, 100 cols, 2 MB rows, 100 KB SQL).
- **Durable Objects (SQLite-backed)** = stateful per-entity compute + storage colocated:
  single-threaded, globally unique, strictly serializable. Use for real-time WebSockets,
  presence, coordination, and per-user/per-entity state (~1,000 req/s soft limit per object;
  unlimited objects; 10 GB per object). Same SQL pricing as D1.
- **R2** = object storage for PWA assets, images, media (no egress charges).
- **KV** = configuration / routing metadata only (not relational data).

Stay on the self-host default when: the app is single-region or small, writes are heavy,
SQL is complex/large (D1 caps: 10 GB/DB, 100 cols, 2 MB rows), or in-process sqlite latency
matters more than edge distribution. Frontend (HTMX, Radix islands, PWA) is unchanged in
either deployment — Workers still serves server-rendered HTML fragments.

## Taste guardrails (anti-slop)

Deterministic checks, not vibes. Enforce in CI when a tool can:
- No em-dashes / en-dashes in UI copy. No hero-label cliches, scroll cues, decorative status dots.
- No AI-purple gradients or glow as a default treatment. No lorem ipsum — real data.
- Semantic HTML, accessible-first (keyboard, focus order, aria). Motion restraint
  (default ease-out; `:active { scale(0.97) }`; nothing animates without meaning).
- Run `npx impeccable detect` as a CI quality gate over generated HTML when a Node toolchain exists.

## Agent troubleshooting (debuggability bias)

The house stack is designed so an agent can troubleshoot it fast and reliably: server-owned
state is agent-visible, client-owned state is a black box.

- **Prefer server round-trips (htmx) over client state (Alpine) for anything correctness-
  related** — filters, form progress, flags, lists. An agent reads server-rendered HTML,
  request logs, and the `HX-Request` contract; it cannot easily introspect Alpine component
  state. Alpine stays for purely cosmetic / pure-UI state.
- **Fast, decisive feedback loops**: sub-second `templ generate`; snapshot tests over rendered
  HTML fragments; every handler asserted for both full-page and `HX-Request` responses;
  Playwright driving real swaps. A check an agent runs returns a definitive pass/fail.
- Keep Alpine components testable: any state an agent must verify has a server-rendered
  baseline or an `HX-Trigger` sync to assert against.

## Scaffolding a project (run at project intake)

1. Copy `references/PRODUCT.md` and `references/DESIGN.md` into the project root as
   `PRODUCT.md` and `DESIGN.md`.
2. Fill every `DECIDE:` field with the real per-product decision. House defaults elsewhere apply
   as-is; never inherit a decision blindly.
3. Commit both files before build work starts so the contract is reviewable.

## Engineering patterns

The per-project DESIGN.md template carries the full engineering patterns — Go (templ +
modernc SQLite + Litestream) and Rust (askama/maud + sqlx) stacks, HTMX + Alpine patterns, forms,
performance, security, testing, Docker. When a new hard-won pattern recurs, fold it into the
template, not this skill, so every scaffolded project inherits it.

## Loading

Load this skill whenever a task involves webapp design, build, review, or architecture. It is
the design side of the house contract; product-side decisions live in the scaffolded PRODUCT.md.
