---
title: "Remove Groq Provider from OpenCode/OmO Configuration"
type: refactor
created: 2026-07-18
status: pending
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
