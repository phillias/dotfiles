---
name: vercel-ai-gateway
description: Manage Vercel AI Gateway virtual models and routing rules via the Vercel CLI. Use when creating, listing, inspecting, editing, or removing virtual models (vmc/<slug>), when managing routing rules (rewrites/denies), when checking gateway credits/spend, or when the user mentions "vercel gateway", "virtual model", "vmc", or "vercel ai gateway".
---

# Vercel AI Gateway

Manage virtual models and routing rules on the Vercel AI Gateway via the `vercel` CLI. TOON output preferred.

## Auth

Two tokens, different purposes:

| Token | Prefix | Purpose | Location |
|-------|--------|---------|----------|
| `VERCEL_TOKEN` | `vcp_` | Platform management (CLI commands) | `~/.agents/keys/<profile>/.vercel-token` |
| `AI_GATEWAY_API_KEY` | `vck_` | Inference (API calls) | `~/.agents/keys/default/.vercel-gateway-key` |

Both loaded by `load-keys.sh`. Team scope: `phils-projects-336d7fca`.

```bash
# Verify management auth
vercel whoami --token "$VERCEL_TOKEN"

# Verify inference auth
curl -s -H "Authorization: Bearer $AI_GATEWAY_API_KEY" https://ai-gateway.vercel.sh/v1/credits
```

## Quick Reference

```bash
# Virtual models
vercel ai-gateway virtual-models list --scope phils-projects-336d7fca --token "$VERCEL_TOKEN"
vercel ai-gateway virtual-models inspect <slug> --scope phils-projects-336d7fca --token "$VERCEL_TOKEN"
vercel ai-gateway virtual-models create <slug> --model <provider/model> --kind alias --scope phils-projects-336d7fca --token "$VERCEL_TOKEN"
vercel ai-gateway virtual-models edit <slug> --config '<json>' --scope phils-projects-336d7fca --token "$VERCEL_TOKEN"
vercel ai-gateway virtual-models rm <slug> --scope phils-projects-336d7fca --token "$VERCEL_TOKEN"
vercel ai-gateway virtual-models restore <slug> --scope phils-projects-336d7fca --token "$VERCEL_TOKEN"

# Routing rules
vercel ai-gateway rules list --scope phils-projects-336d7fca --token "$VERCEL_TOKEN"
vercel ai-gateway rules add --scope phils-projects-336d7fca --token "$VERCEL_TOKEN"
vercel ai-gateway rules edit <rule-id> --scope phils-projects-336d7fca --token "$VERCEL_TOKEN"
vercel ai-gateway rules remove <rule-id> --scope phils-projects-336d7fca --token "$VERCEL_TOKEN"

# Spend tracking
curl -s -H "Authorization: Bearer $AI_GATEWAY_API_KEY" "https://ai-gateway.vercel.sh/v1/credits"
curl -s -H "Authorization: Bearer $AI_GATEWAY_API_KEY" "https://ai-gateway.vercel.sh/v1/report?start_date=2026-09-01&end_date=2026-09-30&group_by=model"
```

## Virtual Model Rules

- **Slug is immutable** after creation. All other settings are editable.
- **Slug format:** letters, numbers, hyphens, underscores, periods only. NO slashes.
- **Callable name:** `vmc/<slug>` — the `vmc/` prefix is automatic. Slug `pr-gate` → callable as `vmc/pr-gate`. Do NOT prefix slugs with `vmc-`.
- **Kind:** `alias` (single model, default) or `router` (multi-model with fallback ladders).

## Creating a Virtual Model

### Simple alias (one model)

```bash
vercel ai-gateway virtual-models create my-model \
  --model anthropic/claude-sonnet-4 \
  --kind alias \
  --display-name "My Model" \
  --description "Description here" \
  --scope phils-projects-336d7fca --token "$VERCEL_TOKEN"
```

### Router with cost sorting (fallback ladder)

```bash
vercel ai-gateway virtual-models create pr-gate \
  --model deepseek/deepseek-v4-flash \
  --kind router \
  --display-name "pr-gate (economy CI)" \
  --description "Economy ladder for no-mistakes gate" \
  --config '{"sort":"cost"}' \
  --scope phils-projects-336d7fca --token "$VERCEL_TOKEN"
```

### Router with explicit provider order

```bash
vercel ai-gateway virtual-models create my-router \
  --model anthropic/claude-sonnet-4 \
  --kind router \
  --config '{"order":["anthropic","openai","deepseek"],"sort":"cost"}' \
  --scope phils-projects-336d7fca --token "$VERCEL_TOKEN"
```

## Per-Model Settings (via --config JSON)

| Key | Type | Description |
|-----|------|-------------|
| `order` | `string[]` | Ordered provider list to try |
| `only` | `string[]` | Restrict to specific providers |
| `models` | `string[]` | Fallback model chain (replaces request chain) |
| `sort` | `"cost"` \| `"ttft"` \| `"tps"` | Rank providers by cost, latency, or throughput |
| `serviceTier` | `"flex"` \| `"priority"` \| `"fast"` | Service tier |
| `caching` | `"auto"` | Prompt caching mode |
| `tags` | `string[]` | Observability tags for spend attribution |

## Verification

After creating or editing a virtual model, verify inference works:

```bash
curl -s -X POST https://ai-gateway.vercel.sh/v1/chat/completions \
  -H "Authorization: Bearer $AI_GATEWAY_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"vmc/<slug>","messages":[{"role":"user","content":"Reply OK"}],"max_tokens":5}' \
  | jq -r '.choices[0].message.content // .error.message // "NO RESPONSE"'
```

Expected: model content (e.g. "OK") or a recognizable model response. If "Model not found", check slug spelling and that the callable name is `vmc/<slug>` (not `vmc/vmc-<slug>`).

## Current Inventory

| Slug | Kind | Target/Head | Purpose |
|------|------|-------------|---------|
| `pr-gate` | router | deepseek-v4-flash | Economy CI gate (no-mistakes) |
| `pr-reviewer` | router | deepseek-v4-flash → gpt-5.6-luna | Review second-set-of-eyes |
| `tui` | router | qwen3.7-flash | Daily driver |
| `high` | router | glm-5.3 | High reasoning |
| `claude` | router | claude-sonnet-5 | Claude family |
| `codex` | router | gpt-5.6-luna | OpenAI family |
| `grok` | router | grok-4.1-fast-reasoning | xAI family |
| `kimi` | router | kimi-k3 | Kimi family |
| `muse` | router | muse-spark-1.2 | Meta family |

## Gotchas

- **Head-node poisoning:** a provider returning HTTP 200 with an error JSON body is treated as success — fallback never fires. Put suspect providers LAST in the order.
- **Slug vs callable:** the CLI help says "callable as vmc/<slug>" — the prefix is automatic. A slug named `vmc-pr-gate` becomes `vmc/vmc-pr-gate` (wrong).
- **Inference key vs management key:** `vck_` (AI_GATEWAY_API_KEY) is for inference only. `vcp_` (VERCEL_TOKEN) is for CLI management. They are different tokens.
- **Team scope required:** all CLI commands need `--scope phils-projects-336d7fca`. Omitting it yields "No team selected" errors.
- **Cache:** inference responses may be cached. Bypass with `cf-aig-skip-cache: true` header for health probes.
- **Routing rules vs virtual models:** rules are team-wide rewrites/denies that apply BEFORE virtual model resolution. Separate from virtual models.

## CF AI Gateway Comparison

| Feature | CF Dynamic Routes | Vercel Virtual Models |
|---------|-------------------|----------------------|
| Management | REST API (POST versions + deploy) | CLI (`vercel ai-gateway virtual-models`) |
| Slug format | Route ID (any string) | Letters/hyphens/underscores only |
| Fallback | Linear ladder in route graph | `models` array or `sort` auto-routing |
| Cost routing | None | `sort: "cost"` |
| Cache | 1800s TTL, bypass header | Proper caching with invalidation |
| Error handling | 200-wrapped errors pass through | Proper provider failover |
| Provider prefix | `custom-<name>` required | Native provider names |
| Observability | Gateway logs only | `GET /v1/generation` + `/v1/report` |
