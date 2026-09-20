---
name: provider-catalog
description: Agent-agnostic provider and model catalog for the Cloudflare AI Gateway `opencode` gateway and Vercel AI Gateway fallback — provider roles, gateway URL segments, token location, retry semantics, virtual models, cost metrics, and live statuses. Also covers non-gateway providers (TypeSafe Jev, TSFM.ai time-series forecasting). Use when checking which provider/model to use, routing through the gateway, or debugging provider auth/URLs across pi, opencode, or any other agent.
---

# Provider Catalog

Chat and completion providers route through Cloudflare AI Gateway `opencode` (BYOK) as primary, with Vercel AI Gateway as fallback (zero-markup, virtual models, dedicated harness surfaces). Specialized providers (TypeSafe Jev, TSFM.ai time-series forecasting) use direct API endpoints. This skill is the shared, agent-agnostic reference; per-agent chain *design* lives in each agent's own config (`~/.pi/fallback-chains.json` for pi, `~/.config/opencode/opencode-fallback.jsonc` for opencode).

**Live quota and headroom come from `quota-axi`, never from this catalog** — cost/limit rows here are reference facts, not usage state.

Read `references/PROVIDERS.md` for the provider table, gateway URL segments, BYOK mechanics, and known live statuses.

## Deterministic dynamic-route audit

Route health prefers `~/.config/opencode/scripts/dynamic-audit.mjs` (scheduled; hourly cron), never a live LLM probe: transcript at `~/.local/state/opencode-fleet/dynamic-audit.jsonl` ("dynamic-audit.jsonl"). See `references/PROVIDERS.md` §"Deterministic dynamic-route audit" for the test list, log schema, and the interactive-LLM interrogation procedure. Ask the captain before mutating any gateway route — `served_model` counts in the audit log are the evidence base.

## Catalog maintenance pre-approval (captain, 2026-09-14)

Whenever a review effort touches this catalog — route rebuilds, model swaps, pricing or staleness findings — the reviewing agent is pre-approved to, without asking per instance:

1. Update `references/PROVIDERS.md` and `models.snapshot.json` in place, in both the installed copy and the dotfiles source (`~/.local/share/chezmoi/dot_agents/skills/provider-catalog/`).
2. Commit, push a branch, and open a PR to the dotfiles repo.

Verify facts against live lanes before recording; record a price only when verified upstream or explicitly marked as a family-band carry. This pre-approval covers catalog files and dotfiles PRs only — gateway route mutation still follows the ask-first rule above unless the captain ordered that exact route change.
