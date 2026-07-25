# Plan: Agency-Agents Auto-Loading Skill Deployment

**Status**: Draft
**Created**: 2026-07-09
**Initiator**: User request — "create a plan for this deployment in .omo/plan"

---

## Objective

Deploy `msitarzewski/agency-agents` personas as auto-resolved, lazily-loaded skills within oh-my-openagent's orchestration. Sisyphus automatically loads the matching agency-agents persona on every `task()` delegation based on the classified category — zero manual specification by the user.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        SISYPHUS ORCHESTRATOR                       │
│                                                                     │
│  User: "build a login page"                                        │
│       │                                                             │
│       ▼                                                             │
│  IntentGate → category: visual-engineering                         │
│       │                                                             │
│       ▼                                                             │
│  Persona Resolver Rule (AGENTS.md)                                  │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ visual-engineering → load_skills=["aa-frontend-developer"]  │   │
│  │ ultrabrain          → load_skills=["aa-architect"]          │   │
│  │ security-research   → load_skills=["aa-pentest-tester"]     │   │
│  │ testing             → load_skills=["aa-reality-checker"]    │   │
│  │ ...                                                         │   │
│  └─────────────────────────────────────────────────────────────┘   │
│       │                                                             │
│       ▼                                                             │
│  task(category="visual-engineering",                                │
│       load_skills=["aa-frontend-developer"],                        │
│       prompt="Build a login page...")                               │
│       │                                                             │
│       ▼                                                             │
│  SISYPHUS-JUNIOR runs with:                                         │
│    • Category-optimized model (Gemini 3.1 Pro)                     │
│    • agency-agents Frontend Developer persona injected as context   │
└─────────────────────────────────────────────────────────────────────┘
```

### Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Skill format** | One `SKILL.md` per persona, stored under `.omo/skills/agency-agents/` | Each is independently loadable via `load_skills`; no monolithic dispatcher needed |
| **Registration** | Project-local in `.omo/skills/` | Portable, no global install; works with any OpenCode project using oh-my-openagent |
| **Resolver location** | In `AGENTS.md` as a behavior rule (not plugin code) | Zero-config — Sisyphus reads this as instructions; no TypeScript changes needed |
| **Upstream source** | Local conversion from cloned agency-agents repo | Avoids runtime dependency on GitHub; cache is controllable |
| **Agent limit** | 0 agents registered in `.opencode/agents/` | Skills bypass OpenCode's ~119-agent cap entirely |
| **Persona count** | Initial subset (~20-30 high-use personas) | Full 239 is overkill; expand on demand |

---

## Phase 1 — Persona Catalog Extraction

**Goal**: Convert selected agency-agents personas into oh-my-openagent-compatible SKILL.md files.

### Steps

1. **Clone agency-agents** (fresh pull into known cache location):
   ```
   git clone --depth=1 --filter=blob:none \
     https://github.com/msitarzewski/agency-agents \
     /tmp/agency-agents-cache
   ```

2. **Select initial persona set** — map by division (start with ~25 high-value personas):

   | Category | Personas to Extract | Source Division |
   |----------|-------------------|-----------------|
   | `visual-engineering` | frontend-developer, designer, ui-designer | engineering, design |
   | `ultrabrain` | architect, agents-orchestrator, data-scientist | specialized, engineering |
   | `deep` | data-scientist, researcher, strategist | specialized, academic |
   | `quick` | backend-developer, devops-engineer | engineering |
   | `artistry` | brand-designer, visual-storyteller | design |
   | `security-research` | penetration-tester, appsec-engineer | security |
   | `testing`/QA | reality-checker, api-tester, performance-tester | testing |
   | `writing` | content-strategist, technical-writer | marketing, specialized |
   | `unspecified-high` | agents-orchestrator, project-shepherd | specialized, project-management |

3. **For each persona, create a SKILL.md** in `.omo/skills/agency-agents/`:

   ```
   .omo/skills/agency-agents/
   ├── SKILL.md                               # catalog index (describes all available)
   ├── aa-frontend-developer.md
   ├── aa-ui-designer.md
   ├── aa-architect.md
   ├── aa-data-scientist.md
   ├── aa-backend-developer.md
   ├── aa-devops-engineer.md
   ├── aa-penetration-tester.md
   ├── aa-reality-checker.md
   ├── aa-content-strategist.md
   ├── aa-agents-orchestrator.md
   └── ...
   ```

4. **SKILL.md format** for each persona:

   ```yaml
   ---
   name: aa-frontend-developer
   description: "agency-agents Frontend Developer persona - expert in modern web technologies, responsive design, accessibility"
   ---
   
   # Frontend Developer (agency-agents)
   
   You are operating as the **Frontend Developer** persona from the agency-agents library.
   
   ## Your Identity & Memory
   [content from agency-agents agent body]
   
   ## Your Core Mission
   [content from agency-agents agent body]
   
   ## Critical Rules
   [content from agency-agents agent body]
   
   ## Technical Deliverables
   [content from agency-agents agent body]
   
   ## Workflow Process
   [content from agency-agents agent body]
   ```

5. **Validation**: Each SKILL.md must load without error via `skill(name="aa-frontend-developer")`.

### Deliverable
> `.omo/skills/agency-agents/` directory with ~25 SKILL.md files, each independently loadable.

---

## Phase 2 — Category→Persona Resolver Map

**Goal**: Define the mapping that Sisyphus uses to auto-resolve personas from task categories.

### Implementation

Add a section to Sisyphus's behavior instructions (in `AGENTS.md` or equivalent rules file):

```markdown
## Agency-Agents Auto-Loading Protocol

Sisyphus MUST apply the following mapping on EVERY `task()` delegation.
Do NOT ask the user to specify a persona. Resolve automatically from the classified category.

### Resolution Logic

1. After IntentGate classifies the task category
2. Check the map below for a matching persona
3. If found, pass `load_skills=["<persona-name>"]` in the `task()` call
4. If no match → delegate normally without persona injection
5. If multiple personas match a category → load the first listed

### Mapping Table

| IntentGate Category | `load_skills` Value |
|---|---|
| `visual-engineering` — UI/frontend work | `load_skills=["aa-frontend-developer"]` |
| `visual-engineering` — design/visual only | `load_skills=["aa-ui-designer"]` |
| `ultrabrain` — architecture decisions | `load_skills=["aa-architect"]` |
| `ultrabrain` — system design | `load_skills=["aa-agents-orchestrator"]` |
| `deep` — data analysis | `load_skills=["aa-data-scientist"]` |
| `deep` — general deep research | `load_skills=["aa-strategist"]` |
| `quick` — backend changes | `load_skills=["aa-backend-developer"]` |
| `quick` — infrastructure | `load_skills=["aa-devops-engineer"]` |
| `artistry` — creative work | `load_skills=["aa-brand-designer"]` |
| `security-research` — penetration testing | `load_skills=["aa-penetration-tester"]` |
| `security-research` — code audit | `load_skills=["aa-appsec-engineer"]` |
| `testing` / QA | `load_skills=["aa-reality-checker"]` |
| `writing` — content | `load_skills=["aa-content-strategist"]` |
| `unspecified-high` — complex unclear | `load_skills=["aa-agents-orchestrator"]` |
| All others | No persona (skip) |

### Refinement Heuristic

If the task's specific domain keyword (e.g., "mobile", "game", "machine learning") matches a more
specific persona not in the main table, Sisyphus may override the default with a better match.
Document these overrides in a secondary table as they emerge.
```

### Deliverable
> Resolver rules added to Sisyphus's instruction set (in `AGENTS.md` or `opencode.json` rules).

---

## Phase 3 — Skill Registration

**Goal**: Wire the skills so `load_skills` resolves correctly.

### Steps

1. **Create the skill index** at `.omo/skills/agency-agents/SKILL.md`:
   ```yaml
   ---
   name: agency-agents
   description: "Agency-agents persona library — auto-loaded by Sisyphus per category"
   ---
   
   # Agency-Agents Persona Library
   
   This directory contains agency-agents personas converted to oh-my-openagent skill format.
   Each file is independently loadable via `load_skills=["aa-<persona-name>"]`.
   
   ## Available Personas
   
   | File | Category Trigger | Description |
   |------|-----------------|-------------|
   | `aa-frontend-developer` | visual-engineering | Frontend specialist |
   | `aa-ui-designer` | visual-engineering (design) | UI/visual design |
   | `aa-architect` | ultrabrain | System architecture |
   | `aa-penetration-tester` | security-research | Security auditing |
   | `aa-reality-checker` | testing | Validation/testing |
   | ... | ... | ... |
   ```

2. **Verify loadability** — each file must be loadable:
   ```
   skill(name="aa-frontend-developer")  → returns persona prompt
   skill(name="aa-architect")           → returns persona prompt
   ```

3. **No `skill add` needed** — `.omo/skills/` is automatically discoverable by oh-my-openagent as a skill directory.

### Deliverable
> Skills directory registered and loadable. Confirmed via manual `skill()` calls.

---

## Phase 4 — Sisyphus Integration

**Goal**: Make Sisyphus actually apply the resolver rule in production.

### Steps

1. **Inject the resolver rule** into Sisyphus's system prompt or persistent rules. Location depends on how Sisyphus reads its instructions:
   - Option A: Append to `AGENTS.md` in the project root (best — version-controlled)
   - Option B: Add to `opencode.json` `rules` array
   - Option C: Reference in a top-level `CLAUDE.md` or `AGENTS.md` that Sisyphus loads on start

   **Recommendation**: Option A (project `AGENTS.md`).

2. **Test a delegation** — verify Sisyphus enriches a `task()` call:
   ```
   User: "build a login form"
   Expected: Sisyphus classifies visual-engineering, calls:
     task(category="visual-engineering",
          load_skills=["aa-frontend-developer"],
          ...)
   ```

3. **Test no-match fallback** — category without a persona:
   ```
   User: "list files in /tmp"
   Expected: delegated normally, no load_skills injection
   ```

### Deliverable
> Sisyphus consistently auto-loads personas on matching categories. Confirmed via test prompts.

---

## Phase 5 — Verification

**Goal**: Confirm the full pipeline works end-to-end.

### Test Scenarios

| # | Test | Input | Expected Behavior |
|---|------|-------|-------------------|
| 1 | UI task | "Build a responsive navbar" | Sisyphus delegates with `load_skills=["aa-frontend-developer"]`; subagent shows frontend persona influence |
| 2 | Security audit | "Audit this JWT implementation" | Delegates with `load_skills=["aa-penetration-tester"]`; subagent follows pentest methodology |
| 3 | Architecture | "Design the microservice boundaries" | Delegates with `load_skills=["aa-architect"]`; persona emphasizes structured architecture |
| 4 | No match | "What time is it?" | Delegated normally, no persona injection |
| 5 | Multi-turn | Chain of 3 tasks across categories | Each delegation loads correct persona independently |

### Success Criteria

- [ ] All 25 initial SKILL.md files load without errors via `skill(name="...")`
- [ ] Sisyphus's delegation logs show `load_skills` populated for matching categories
- [ ] Subagent behavior observably influenced by agency-agents persona content
- [ ] No startup performance regression (skills loaded on-demand, not eagerly)
- [ ] No OpenCode agent cap hit (0 agents in `.opencode/agents/`)
- [ ] Fallback works: categories without a mapping delegate normally

---

## Timeline & Dependencies

| Phase | Effort | Dependencies | Parallelizable |
|-------|--------|-------------|----------------|
| P1 — Catalog extraction | Medium | agency-agents repo cloned | ✅ Personas can be converted in parallel |
| P2 — Resolver map | Small | Phase 1 complete (knows persona names) | ❌ |
| P3 — Skill registration | Small | Phase 1 complete (files exist) | ✅ (with P2) |
| P4 — Sisyphus integration | Small | Phase 2 complete (rules defined) | ❌ |
| P5 — Verification | Medium | All prior phases complete | ❌ |

**Estimated total**: ~2-3 hours of focused execution.

---

## Future Expansion

- **Full catalog sync**: Script to pull all 239 personas from upstream and auto-generate SKILL.md files
- **Dynamic resolution**: Instead of a static map, Sisyphus queries a `divisions.json`-like index to auto-match
- **Performance telemetry**: Track which personas are most-used; prune unused ones
- **Upstream drift detection**: CI check that compares cached personas against upstream repo, flags changes

---

## Rollback

If the auto-loading causes issues:
1. Remove or comment out the resolver rules in `AGENTS.md`
2. Delete `.omo/skills/agency-agents/` directory
3. No changes to oh-my-openagent's core code — pure content + configuration
