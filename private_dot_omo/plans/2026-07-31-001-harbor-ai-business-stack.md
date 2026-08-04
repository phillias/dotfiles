---
title: "Harbor AI Business Stack — Production Stack + Voice/SMS Agent Layer"
type: feat
created: 2026-07-31
status: active
origin: Research synthesis of harborseo.ai + weareastromarketing + Clerk/Convex/Stripe/Resend/Vercel/Turnstile/GitHub + voice/SMS vendor analysis (2026-07-31)
---

# Harbor AI Business Stack — Production Stack + Voice/SMS Agent Layer

## Problem Frame

Harbor (harborseo.ai) is an AI-native SEO content workspace (€24/39/83 tiers, "all API costs included") serving agencies and in-house teams. The production stack behind it — Clerk (auth), Convex (backend/DB), Stripe (billing), Resend (email), Vercel (hosting), Cloudflare Turnstile (bot protection), GitHub (repo/CI) — costs ~$110–150/mo fixed at 2–5k MAU, plus revenue-scaled Stripe fees. The stack is missing: (1) a **voice calling layer** (AI agent on real phone numbers), (2) an **SMS/text layer** (2-way conversational), (3) **session replay/UX observability**, and (4) a **niche-validation data pipeline** (SERP-level sponsored/map-pack detection before agents commit content strategy).

**Key decisions already researched (2026-07-31, official pricing pages fetched live):**
- **Telnyx Voice AI** ≈ $0.056/min all-in (voice engine $0.05/min incl. STT/TTS + LLM ~$0.004/min + telephony $0.0032/min), numbers $0.25/mo, SMS on same platform, HIPAA included, PAYG $0 platform fee — **recommended production vendor**
- **LiveKit Cloud** Build $0/mo (1k free agent-min + 1 free US number) — recommended **dev sandbox**; ~$0.067/min all-in via their inference
- **Vapi** $0.05/min hosting + at-cost models = $0.12–0.42/min real all-in — fastest to a polished agent, fallback (numbers port to Telnyx free)
- **PostHog** (free: 1M events + 5k session replays/mo) — closes analytics + replay + feature flags
- **DataForSEO** SERP API (pay-per-use, has MCP server) — the only component that can programmatically detect "no sponsored / no map-pack" niches; GSC cannot (your own site only)
- **rankexpand.com** (Niche Validator) — human-facing niche scoring gate with live Google data
- **Harbor (the product)** — strong candidate for the content engine, but **NOT undeniable**: Koala Writer ($9–25), Neuronwriter ($19–49), Surfer ($49), TopicMojo ($29–39), and a DIY agent pipeline on this stack's own Convex+model keys all sit in/under its price range. **Paid Harbor is gated behind a free-plan quality evaluation.**

## Scope Boundaries

### In Scope
- Core SaaS stack standup (Astro + Convex + Clerk + Stripe + Resend + Cloudflare Pages + Turnstile + GitHub CI)
- Agent workflow: niche validation → site blueprint (pageBlueprint schema) → content generation → Astro static build → rank tracking
- Comms layer: one US number for voice + SMS (Telnyx), 10DLC registration, branded caller ID
- Observability: PostHog (replay + analytics + flags)
- Sales loop pilot: buzz.ai free seat → Calendly → Convex webhook

### Out of Scope
- Custom CMS (Astro content collections only)
- Multi-region / enterprise infra (no SSO, no data residency, no HIPAA workloads this phase)
- WhatsApp rollout beyond Meta's 1,000 free service conversations/mo
- Multi-tenant agency portal internals (post-launch phase)

### Deferred to Follow-Up
- DataForSEO beyond SERP-API niche detection (backlinks/rank APIs when volume justifies ~$50–200/mo)
- Vercel Pro migration if Cloudflare Pages DX becomes a bottleneck
- Harbor API/MCP integration into the agent pipeline (after paid-gate passes)

## Key Technical Decisions

### D1: Astro + Cloudflare Pages over Next.js + Vercel
**Decision**: Frontend is Astro (content-first, zero-JS, islands) on Cloudflare Pages (free tier). Vercel Pro ($20) is the documented fallback.
**Rationale**: Harbor's own thesis is "ship SEO content that ranks" — Astro is the framework built for exactly that (Core Web Vitals, static-first). Convex owns the data layer, so SSR needs are minimal. Cloudflare Pages free tier (unlimited static) fits the $0 startup bias. `@convex-dev/astro` adapter + official Convex "Astro Starter" template confirmed.

### D2: Telnyx as single voice + SMS vendor (production)
**Decision**: One Telnyx US local number carries both voice (Voice AI engine, ~$0.056/min all-in) and SMS (10DLC-registered, ~$0.008/msg all-in). LiveKit Build = free dev sandbox; Vapi = documented fallback (free number porting).
**Rationale**: Best unit economics ($0.056 vs Vapi $0.12–0.42), one number/one invoice/one 10DLC brand for both channels, HIPAA included, no platform fee, 500 concurrent calls on PAYG. LiveKit has no SMS; Vapi is 3–6x costlier at volume.

### D3: Content generated from a Convex content model (blueprint-driven)
**Decision**: All pages derive from a `pageBlueprint` table in Convex (archetype, template, intent, keyword cluster, internal-link rules, schema.org type). Astro `getStaticPaths` renders templated location pages at build time. Uniqueness gate: >70% unique content per templated page (doorway-page penalty avoidance).
**Rationale**: Makes the site a product of the model — agents fill blueprints, templates render, QA is checkable, scale is linear.

### D4: Niche selection is data-gated, not vibes-gated
**Decision**: Agents only accept niches passing: rankexpand validation (live Google data) + DataForSEO SERP API scoring (0 sponsored, no map pack) + top-10 **authority proxy** below configurable threshold (via DataForSEO Domain Analytics/Backlinks API — SERP API does **not** expose third-party Ahrefs DR; referring-domains/domain-rank used instead) + ≥3 low-competition long-tail clusters. Scores stored in `nicheScore` table.
**Rationale**: "No sponsored / no map pack" is only trustworthy when measured per-keyword from live SERPs; GSC cannot see niches you don't rank in.

### D5: Paid Harbor is a gated purchase, not a foundation assumption
**Decision**: Evaluate Harbor free plan (3 articles/mo) against Koala Writer / Neuronwriter / DIY agent pipeline on output quality, agency-workspace fit, and per-article cost. Pay monthly (never the annual lock — math shows annual ≥ monthly cost). No founder-deadline-driven purchase.
**Rationale**: Alternatives exist in/under the price range; "founder pricing" annual billing (€290/yr vs €288 monthly-equivalent) offers no actual discount — FOMO has no mathematical basis.

## Implementation Units

### U1: Foundation (Week 1)
**Goal**: Working repo with the full core stack deployed.
**Requirements**:
- GitHub repo + Actions CI; branch protection
- Convex project (free tier) with `pageBlueprint` and `nicheScore` schema seed
- Clerk Hobby wired to Convex auth (workspace-scoped orgs)
- Astro app (Convex starter template) deployed to Cloudflare Pages
- Turnstile on signup + "Analyze" form; Resend free tier for dev email
- Stripe test mode with €-denominated subscription plans (Solo/Growth/Powerhouse shapes)

**Definition of Done**: `astro build` green on Cloudflare Pages; Convex deployment green; Clerk sign-in → Convex mutation round-trips in production URL; Turnstile token verified server-side.

**QA Scenarios**:
1. Tool: bash. `npx astro build && npx convex deploy` → exit code 0, no TypeScript errors.
2. Tool: browser. Visit prod URL → Clerk sign-up → workspace loads → create a `pageBlueprint` doc via UI → row appears in Convex dashboard within 30s.
3. Tool: curl. POST to `Analyze` endpoint with a freshly-fetched Turnstile token → HTTP 200 + job queued; POST with garbage token → HTTP 400/403 (token rejected server-side).

### U2: 10DLC + Number Procurement (Week 1, DAY 1 — critical path)
**Goal**: US A2P 10DLC brand + campaign registered; number provisioned.
**Requirements**:
- Telnyx account, brand registration (~$4), campaign (~$15), monthly campaign fees budgeted
- Start 10DLC approval (2–4 wk lead) on day one — parallel with everything
- Provision one Telnyx US local number ($0.25/mo) for voice + SMS
- Enable Branded Call Display (STIR/SHAKEN) on the number

**Definition of Done**: 10DLC campaign in "approved" status; number answers a test call; SMS send/receive round-trips via Telnyx webhooks into Convex.

**QA Scenarios**:
1. Tool: Telnyx Mission Control portal. Brand status = "Approved", campaign status = "Approved" (screenshot captured with timestamps).
2. Tool: curl + test phone. Send SMS via Telnyx API to test number → message received ≤ 30s; reply from test phone → `conversation` row appears in Convex dashboard with valid Telnyx webhook signature (HMAC verified).
3. Tool: phone call. Dial the number → call connects and agent persona responds → call event + transcript appear in Convex ≤ 60s after hangup.
4. Tool: caller-ID check. Place call to a T-Mobile and a Verizon handset → display shows brand name (not "Unknown"), verified via Branded Call Display.

### U3: Niche Validation Pipeline (Week 2)
**Goal**: Agents can score any candidate niche against live SERP data.
**Requirements**:
- Convex action calling DataForSEO SERP API (labs/map + sponsored parsing) → `nicheScore` writes; authority proxy via DataForSEO Domain Analytics (referring domains / domain rank) — NOT Ahrefs DR (not exposed by SERP API); rankexpand serves as the human cross-check
- rankexpand manual validation as human gate (agent presents candidates, human scores)
- Agent prompt contract: "only accept niches where sponsored=0, map-pack=absent, top-10 DR<50"

**Definition of Done**: Running a candidate keyword through the pipeline yields a scored record with sponsored count, map-pack presence, and DR; a demo niche passes and another fails.

**QA Scenarios**:
1. Tool: Convex dashboard (function runner). Invoke `nicheScan(keyword: "best crm for small agencies")` → returns record with `sponsoredCount: 0`, `mapPack: false`, `top10DR: [..]`, `verdict: PASS` per gate rule.
2. Tool: Convex dashboard (function runner). Invoke `nicheScan(keyword: "plumber austin")` → returns `mapPack: true`, `verdict: FAIL`.
3. Tool: rankexpand.com. Run the same two keywords through rankexpand manually → directional agreement with pipeline verdicts (document any disagreement in the plan issue).
4. Tool: script. Assert gate logic: verdict only PASS when sponsored=0 AND mapPack=false AND top10 authority-proxy median < configured threshold; document the proxy↔Ahrefs-DR mapping used.

### U4: Site Blueprint + Generation (Weeks 2–3)
**Goal**: 8 core + 2 service + 20–30 templated location + 9 supporting pages generated from the model.
**Requirements**:
- `pageBlueprint` seed: archetypes (core/service/location/supporting), templates, schema.org types (LocalBusiness/Service/FAQPage/BreadcrumbList), internal-link hub-and-spoke rules
- Location template with unique-content slots (address, service-area, landmarks, local testimonials, local FAQ) + >70% uniqueness check
- Content source: Harbor free plan eval (U5) OR Koala/Neuronwriter OR DIY Convex+model pipeline — one must pass the gate
- Auto-generated sitemap.xml + robots.txt; GSC verification

**Definition of Done**: `astro build` emits all 39–41 pages; uniqueness gate passes on every location page; sitemap validates; internal links per blueprint verified by script.

**QA Scenarios**:
1. Tool: bash. `npx astro build && find dist -name "*.html" | wc -l` → count between 39 and 41; spot-check 1 page per archetype renders correct template + schema.
2. Tool: python script. Pairwise Jaccard similarity on text of all location pages → every pair < 0.30 (i.e., >70% unique).
3. Tool: xmllint. `xmllint --noout dist/sitemap.xml` → no errors; every URL resolves to a built page.
4. Tool: script. Internal-link audit: every location page links to its service page; every service page links to its core page → 100% pass.
5. Tool: jsonld validator. Parse JSON-LD on 1 location page + 1 service page → LocalBusiness/Service schema valid.

### U5: Harbor Paid Gate (Week 2–3, decision point)
**Goal**: Decide Harbor paid (€24–39/mo) vs alternative on evidence.
**Requirements**:
- Generate the same 3 articles with Harbor free plan, Koala, Neuronwriter, and the DIY pipeline
- Score on: SERP-aware quality, internal linking, publish friction, per-article effective cost
- Decision rule: adopt highest quality-per-euro; do not buy founder annual (monthly only)

**Definition of Done**: Comparison table with a documented pick; if Harbor wins, upgrade monthly Solo/Growth; else swap content source, stack unchanged.

**QA Scenarios**:
1. Tool: spreadsheet + rubric. Generate the same 3 articles (same seed keyword, same site) in Harbor free, Koala, Neuronwriter, and DIY pipeline → score each 1–5 on SERP-awareness, internal linking, publish friction.
2. Tool: calculator. Effective cost/article per source (plan price ÷ monthly article allowance; DIY = measured model API spend ÷ articles).
3. Tool: decision record. Write the pick + scores to the plan issue tracker; if Harbor wins, upgrade to monthly Solo/Growth (annual billing forbidden).

### U6: Comms Agents (Weeks 2–4, parallel with U3–U5)
**Goal**: Voice agent + SMS flows live on the provisioned number.
**Requirements**:
- Dev sandbox: LiveKit Build (free number + 1k min) prototypes the agent persona (inbound demo/RSVP + outbound trial follow-up)
- Production: Telnyx Voice AI agent (assistant config, tools → Convex actions, KB from Convex docs), webhooks → Convex for call events/transcripts
- SMS: 2-way via Telnyx webhooks → Convex conversation table; transactional templates (rank-drop alert, publish confirm, event reminder); STOP/opt-out handling
- Dependency note: voice goes live before 10DLC approval (same number, STIR/SHAKEN only); SMS follows approval — U6 voice tracks are not blocked by U2's 2–4 wk SMS lead time
- TCPA guardrails: consent recorded per number, opt-out honored, no marketing calls without prior express consent

**Definition of Done**: Inbound call answered by agent with tools working; outbound call placed from Convex action; SMS 2-way round-trip; opt-out flow verified.

**QA Scenarios**:
1. Tool: phone call. Inbound call → agent answers in correct persona → agent invokes a Convex tool (e.g., lookup order) mid-call → transcript + tool result in Convex ≤ 60s post-hangup.
2. Tool: Convex dashboard (function runner). Invoke `placeCall(phone: <test>)` → call connects, agent speaks, hangup event logged with duration.
3. Tool: SMS. Text "STOP" to the number → `conversation.optedOut=true` recorded; send attempt after opt-out → blocked (no message sent, error logged); text "START" → opt-out cleared.
4. Tool: SMS. Trigger rank-drop template (simulate GSC event) → SMS delivered ≤ 60s with correct template variable substitution.

### U7: Observability + Sales Loop (Weeks 4–5)
**Goal**: PostHog live; buzz.ai pilot integrated.
**Requirements**:
- PostHog: identify() on Clerk user id, pageview/feature events, session replay on key flows, feature flag for Harbor-free-plan UI
- buzz.ai free seat: one outbound campaign (ICP: marketing agencies), Calendly connected; webhook → Convex lead record → SMS confirm + voice-agent follow-up (U6)

**Definition of Done**: Replay available for a real session in PostHog; a buzz.ai-booked meeting creates a Convex lead and triggers an SMS confirmation.

**QA Scenarios**:
1. Tool: browser + PostHog dashboard. Complete a real user flow (signup → analyze → article draft) → session replay renders ≤ 5 min later; identify() shows the Clerk user id on the event.
2. Tool: PostHog dashboard. Flip feature flag "free-plan-upsell" on → UI changes within 60s without redeploy; flip off → reverts.
3. Tool: buzz.ai + Calendly + phone. Book a meeting via buzz.ai campaign → Calendly webhook creates `lead` row in Convex → SMS confirmation delivered to the prospect's phone ≤ 60s.

## Costs

### Startup phase (pre-revenue)
| Line | Monthly | Notes |
|---|---|---|
| Astro + Cloudflare Pages | $0 | unlimited static |
| Convex free tier | $0 | 1M fn execs |
| Clerk Hobby | $0 | 50k MRU |
| Stripe | $0 | +2.9%+30¢ on revenue |
| Resend free | $0 | 100/day cap (dev only) |
| Turnstile / GitHub | $0 | |
| LiveKit Build (dev voice) | $0 | 1k min + 1 number |
| Telnyx number + SMS | ~$1–5 | 10DLC one-time ~$19–40 |
| **Total** | **~$0–5 + one-time 10DLC** | |

### Launch (2–5k MAU)
| Line | Monthly |
|---|---|
| Infra (Clerk Pro + Convex Pro + Resend Pro + Pages) | ~$65–95 |
| Telnyx voice+SMS @ 300 min + 2k msgs | ~$25–45 |
| PostHog (free tier) | $0 |
| DataForSEO SERP API (optional) | ~$20–50 |
| Content source (Harbor/Koala/DIY) | €24–83 |
| **Total** | **~$120–270 + Stripe %** |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Harbor product churn (2-yr-old, thin margins) | Medium | Monthly billing, articles exportable, Koala/Neuronwriter/DIY swap keeps stack intact |
| 10DLC approval > 4 weeks | High | Day-1 submission; toll-free fallback (~1–5 day verify) |
| Per-article model cost eats Harbor margins | High | Track effective cost/article in U5 gate; DIY pipeline fallback |
| Doorway-page penalty on templated location pages | Medium | >70% uniqueness gate + per-location unique content slots |
| TCPA violation on outbound voice/SMS | High | Consent records, opt-out first-class, marketing-call consent required |
| Vercel-free-bias reverses at scale | Low | Documented Pro fallback |
| Founder-pricing deadline reappears/extended | — | Expected; purchase decision never rides on it |

## Open Questions
1. Harbor agency-workspace fit vs DIY — resolved by U5 evidence
2. PostHog vs Clarity — PostHog default (unified analytics+replay+flags); revisit only if replay volume exceeds 5k sessions/mo
3. LiveKit dev agent persona — inbound demo-request vs outbound trial follow-up first? (Proposal: inbound first — lower TCPA surface)
4. Niche vertical for first client site — needs U3 pipeline run (proposal: agency-adjacent services niche)
5. EUR vs USD Stripe settlement — Harbor prices in EUR; confirm currency conversion handling (Stripe 2% FX)

## Follow-Up Work
- Harbor API/MCP integration into agent pipeline (post-gate)
- DataForSEO rank-tracking + backlinks APIs at scale
- WhatsApp channel rollout past free tier
- Multi-tenant agency portal internals
- Vercel Pro migration if needed
