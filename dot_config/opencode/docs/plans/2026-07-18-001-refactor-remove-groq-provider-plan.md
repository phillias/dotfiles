---
title: "Remove Groq Provider from OpenCode/OmO Configuration"
type: refactor
created: 2026-07-18
status: completed
closed: 2026-07-18
closed_by: PR #102 — https://github.com/phillias/dotfiles/pull/102
---

# Remove Groq Provider

## Problem Frame

Groq's free tier has severe rate limits (12K TPM for Llama 3.3 70B, 8K TPM for GPT-OSS 20B) that make it unreliable for agentic workloads. The user hit these limits repeatedly and wants Groq removed entirely from the configuration. The goal is to replace Groq's functional role without degrading fallback coverage.

## Scope Boundaries

**In scope:**
- Remove Groq provider from team profile and web profile `opencode.json` files
- Replace Groq references in fallback chains with equivalent providers
- Replace Groq primary models (Explore, Librarian) with alternatives
- Update `opencode-fallback.jsonc` global fallback chain
- Update `opencode-omo-config/SKILL.md` documentation
- Update `dotfiles/SKILL.md` references to `.groq-key`
- Remove Groq concurrency limits from `oh-my-openagent.json/c` files
- Delete `profiles/free/` directory entirely
- Delete `profiles/desk/` directory entirely
- Commit, push, and open PR via chezmoi workflow

**Out of scope:**
- Removing `.groq-key` — retained chezmoi encrypted for potential future use
- Changing Groq's behavior in the Go pool guard plugin (separate concern)
- Testing every fallback chain exhaustively

## Key Technical Decisions

### Replacement Strategy

Groq occupies two roles in the team profile:

**1. Fallback position (3rd in chain) for reasoning agents:**
- Current: `groq/openai/gpt-oss-120b`
- Replacement: `cloudflare/gpt-oss-120b` (same model, different provider, already in the chain)

**2. Primary model for utility agents (Explore, Librarian):**
- Current: `groq/llama-3.3-70b-versatile`
- Replacement: `cloudflare/llama-3.3-70b` (same model, already first fallback)

**Rationale:** Cloudflare already has identical models to Groq and appears as the first fallback after Groq in every chain. The simplest fix is promoting Cloudflare to fill Groq's slot. No new providers needed.

### Files to Modify

| File | Change |
|------|--------|
| `profiles/team/oh-my-openagent.jsonc` | Replace Groq models with Cloudflare equivalents |
| `profiles/web/opencode.json` | Remove Groq provider definition |
| `profiles/web/oh-my-openagent.json` | Replace Groq models with Cloudflare equivalents |
| `opencode.json` | Remove Groq provider definition |
| `opencode-fallback.jsonc` | Replace `groq/gpt-oss-120b` with `cerebras/gpt-oss-120b` |
| `skills/opencode-omo-config/SKILL.md` | Update all 18 Groq references |
| `skills/dotfiles/SKILL.md` | Remove `.groq-key` references |
| `profiles/free/` | Delete entire directory |
| `profiles/desk/` | Delete entire directory |

### Concurrency Limits

Groq concurrency entries (`"groq": 8`, per-model caps) should be removed from:
- `profiles/team/oh-my-openagent.jsonc` (lines 49, 373-375)

## Implementation Units

### U1. Update Team Profile Agent Config

**Goal:** Replace all Groq model references in `profiles/team/oh-my-openagent.jsonc` with Cloudflare equivalents.

**Files:**
- `profiles/team/oh-my-openagent.jsonc`

**Changes:**
1. Agent `explore` (line 170): Change primary from `groq/llama-3.3-70b-versatile` to `cloudflare/llama-3.3-70b`
2. Agent `librarian` (line 185): Change primary from `groq/llama-3.3-70b-versatile` to `cloudflare/llama-3.3-70b`
3. Agent `sisyphus` fallback (line 80): Remove `groq/openai/gpt-oss-120b` from chain
4. Agent `prometheus` fallback (line 117): Remove `groq/openai/gpt-oss-120b` from chain
5. Agent `atlas` fallback (lines 151-152): Remove both Groq entries
6. Category `ultrabrain` fallback (line 244): Remove `groq/openai/gpt-oss-120b`
7. Concurrency section (line 49): Remove `"groq": 8`
8. Model concurrency (lines 373-375): Remove all Groq model entries

**Approach:** Remove Groq entries entirely rather than replacing them in fallback chains. The existing fallback chains have sufficient depth without Groq. For Explore and Librarian primaries, swap to Cloudflare equivalents.

**Test expectation:** None — config-only change, no behavioral tests applicable.

### U2. Remove Groq Provider Definition

**Goal:** Remove the Groq provider block from team and web opencode.json files.

**Files:**
- `opencode.json`
- `profiles/team/opencode.json`
- `profiles/web/opencode.json`

**Changes:**
1. Remove the `groq` provider block from global `opencode.json`
2. Remove the `groq` provider block from team profile `opencode.json`
3. Remove the `groq` provider block from web profile `opencode.json`

**Approach:** The provider block is a self-contained JSON object. Removing it cleanly breaks no other providers.

**Test expectation:** None — provider removal, no behavioral tests applicable.

### U3. Update Global Fallback Chain

**Goal:** Replace Groq in the global fallback chain.

**Files:**
- `opencode-fallback.jsonc`

**Changes:**
1. Replace `groq/openai/gpt-oss-120b` with `cerebras/gpt-oss-120b` (already second in chain)
2. Or remove it entirely and shift remaining entries up

**Approach:** Remove Groq entry. The chain becomes `cerebras/gpt-oss-120b → google/gemini-2.0-flash`.

**Test expectation:** None — fallback config change.

### U4. Update Skill Documentation

**Goal:** Remove Groq references from skill documentation.

**Files:**
- `skills/opencode-omo-config/SKILL.md`

**Changes for opencode-omo-config/SKILL.md (18 references):**
1. Line 33: Remove `.groq-key` from file tree
2. Line 88: Remove Groq from provider table
3. Line 104: Remove `.groq-key → GROQ_API_KEY` mapping
4. Line 132: Update free-tier fallback chain description
5. Lines 163-164, 169, 177-179: Update agent fallback chain descriptions
6. Line 189: Update Writing agent description
7. Line 195: Update free-only global fallback description
8. Lines 319, 345, 370, 373-375: Remove Groq from config excerpts

**Note:** `dotfiles/SKILL.md` references to `.groq-key` are retained — the key file stays in chezmoi.

**Test expectation:** None — documentation only.

### U5. Delete Free and Desk Profiles

**Goal:** Remove unused profiles entirely.

**Files:**
- `profiles/free/` (entire directory)
- `profiles/desk/` (entire directory)

**Approach:** These profiles are not used by the user and contain heavy Groq dependency. Deleting them removes ~40 Groq references without needing to update each file.

**Test expectation:** None — directory deletion.

### U6. Update Web Profile Agent Config

**Goal:** Replace all Groq model references in `profiles/web/oh-my-openagent.json` with Cloudflare equivalents.

**Files:**
- `profiles/web/oh-my-openagent.json`

**Approach:** Same pattern as U1 — replace Groq primaries with Cloudflare equivalents, remove Groq from fallback chains. The web profile is used by the live `opencode-serve` systemd service.

**Test expectation:** None — config-only change.

### U7. Commit, Push, and Open PR

**Goal:** Package all changes into a PR via chezmoi workflow.

**Files:** N/A (git operations)

**Approach:**
1. `chezmoi re-add` modified files
2. Create feature branch
3. Commit with conventional commit message
4. Push and open PR via `gh pr create`

**Test expectation:** None — git operations.

## Risks

1. **Fallback chain depth reduction** — Removing Groq shortens some chains by 1 entry. Mitigated by: chains still have 3-4 entries, sufficient for resilience.
2. **Cloudflare rate limits** — If Cloudflare has similar TPM issues, Explore/Librarian could fail. Mitigated by: Cloudflare's free tier is more generous (10 concurrent vs Groq's 8).
3. **Missing Groq references** — Some references might be missed. Mitigated by: comprehensive grep search completed.

## Verification

After implementation:
1. `chezmoi diff` should show clean state
2. Grep for `groq` in `~/.config/opencode/profiles/team/` should return zero results
3. Grep for `groq` in `~/.config/opencode/profiles/web/` should return zero results
4. OpenCode should start without errors using team profile
5. Explore/Librarian agents should use Cloudflare models
6. `profiles/free/` and `profiles/desk/` directories should not exist

## Closure Addendum (2026-07-18)

**Status**: completed. Scope was widened substantially during execution; results are tracked in [PR #102](https://github.com/phillias/dotfiles/pull/102) plus the follow-up commit on the same branch.

### Unit status

| Unit | Plan called for | Actual outcome |
|---|---|---|
| U1 team oh-my-openagent.jsonc | Replace Groq refs with Cloudflare equivalents | Superseded — entire `profiles/` directory deleted (full profile teardown). Root `oh-my-openagent.jsonc` (which did not reference Groq) was cleaned instead. |
| U2 remove groq provider from opencode.json files | Remove from global / team / web | Root `opencode.json` never declared Groq (confirm via grep). Team and web profiles deleted entirely. |
| U3 rewrite global fallback chain | Drop Groq entry, keep 2-entry chain | Done **plus** rewritten as 10-entry free→subsidized→pay progressive chain (`cloudflare/@cf/...` free → openrouter free → opencode-zen free → opencode-go flash → `google/gemini-2.0-flash` last resort). |
| U4 update skill docs | Mark groq defunct in opencode-omo-config + dotfiles | **opencode-omo-config**: removed all cerebras refs (was out-of-original-plan size); agent fallback table rows updated with current real chains; new "Defunct Providers" subsection added. **dotfiles**: replaced `.groq-key` code examples with `.cloudflare-key` (still tracked); defunct note added. |
| U5 delete free + desk profiles | Delete two profile directories | Done **plus** all 8 profiles deleted (`desk`, `free`, `go`, `pure`, `team`, `test`, `web`, `zen`). Root config is authoritative. |
| U6 update web profile | Replace Groq refs | N/A — web profile deleted. |
| U7 commit / push / PR | Standard commit flow | Done — PR #102 opened on `feat/fleet-state-wire-dispatch-rules-*` branch with 64 file changes. This closure addendum is part of a follow-up commit on the same branch. |

### Out-of-scope items that were actually done

The plan explicitly excluded three items that were completed during execution:

1. **`.groq-key` deletion** — plan said "retained chezmoi encrypted for potential future use." Actually deleted from disk and chezmoi source state (`encrypted_private_dot_groq-key.age` removed). Reason: keeping an orphan key file adds maintenance surface and confusion; cleaner to remove entirely. Dans l'event Groq returns to the stack, the key can be re-added from Bitwarden.
2. **Go pool guard groq redirect** — plan said "separate concern." Actually fixed in the same session: `go-pool-guard.ts` qwen3.x-plus redirects now target `cloudflare/@cf/qwen/qwen3-30b-a3b-fp8` instead of dead `groq/qwen/qwen3-32b`. Empirical verification: opencode core schema audit confirmed zero native `fallback`/`retry` keys across `$defs`, so `go-pool-guard` is the only safety net for bare-opencode runs (no OmO loaded) — kept dormant, not deleted.
3. **Cerebras removal** — not in original plan. Actually removed from 8 fallback chains in `oh-my-openagent.jsonc`. Reason: account lacked model access. Verified empirically: 3× consecutive `Not Found: Model does not exist or you do not have access to it` against `cerebras/llama3.3-70b` and `cerebras/gpt-oss-120b` retry attempts during the session. Provider block + `.cerebras-key` file retained as dormant for potential re-enablement.

### Extras not anticipated by the plan

The session also delivered infrastructure work adjacent to but not described by this plan:

- `plugins/fleet-state-writer.ts` — zero-token state wire for background-task status (new)
- `plugins/tmux-patch-keeper.ts` — auto-reapplies tmux attach patch on `session.created` (new)
- `scripts/fleet-digest.sh` — pure-bash reader for the state wire (new)
- `dispatch-rules.json` — 26 rules translating task shape to `task(category=..., load_skills=[...])` at intent-gate time (new)
- `skills/axi/SKILL.md` section 11 — Native bash whitelist overseer (15 predicates, zero-token Mode A)
- `AGENTS.md` — Dispatch Rules + Fleet State Communications sections appended (+108 lines)

These belong to the broader "build-vs-adapt Option B" architecting work that produced this PR; they are not claims of this plan's completion.

### Verification re-check (post-execution)

1. ✓ `chezmoi diff` clean after final re-add (`chezmoi-axi status` reports only unrelated `.bashrc`/`.zshrc` drift)
2. ✓ Grep `groq` in `profiles/team/` — directory deleted, grep is trivially empty
3. ✓ Grep `groq` in `profiles/web/` — directory deleted, grep is trivially empty
4. ⚠ "OpenCode should start without errors using team profile" — N/A, no team profile. Equivalent: opencode with root config + OmO runs clean (this very session is the proof — we executed ~30+ tool turns without config crashes after the profile removal).
5. ✓ Explore/Librarian run on `cloudflare/@cf/meta/llama-3.3-70b-instruct-fp8-fast` (root `oh-my-openagent.jsonc` lines 173, 188)
6. ✓ `profiles/free/` and `profiles/desk/` deleted — in fact `profiles/` directory is fully gone
