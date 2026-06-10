---
name: mcp-policy-enforce
description: >
  Enforce policy-as-code on every MCP tool call using protect-mcp. Supports Cedar
  policies (AWS authorization engine), JSON policies, or external PDP (OPA/Cerbos).
  Produces Ed25519-signed cryptographic receipts for every allow/deny decision —
  tamper-evident audit trail verifiable offline. Shadow mode logs without blocking;
  enforce mode blocks policy violations. Auto-suggests minimal Cedar permit() rules
  when tools are denied for rapid policy iteration. Integrates with Claude Code hooks.
  Trigger: user mentions "policy enforcement", "Cedar policy", "MCP governance",
  "audit trail", "signed receipts", "tool allowlist", "access control", "governance",
  "/mcp-policy-enforce"
license: MIT
compatibility: opencode
metadata:
  tools: protect-mcp
  mcp-risk-layer: governance
  owasp-mcp-coverage: MCP-03,MCP-04,MCP-06,MCP-07,MCP-09
---

## What This Skill Does

Deploys **protect-mcp**, a policy enforcement gateway for MCP tool calls. Every tool invocation is evaluated against a policy before execution, and every decision produces an Ed25519-signed cryptographic receipt.

**Three policy engines:**
- **JSON policies** — Simple per-tool rules (block, rate-limit, require-approval)
- **Cedar policies** — AWS Cedar authorization language (declarative, composable, WASM-evaluated)
- **External PDP** — OPA, Cerbos, or any HTTP Policy Decision Point

**Two modes:**
| Mode | Behavior | Use Case |
|------|----------|----------|
| `shadow` (default) | Log + sign every decision, block nothing | Testing policies, building allowlists |
| `enforce` | Block policy violations, sign every decision | Production enforcement |

**Key capabilities:**
- Ed25519-signed receipts for every tool call decision
- Per-tool policies: `block`, `rate_limit`, `min_tier`, `require_approval`
- Trust tier system (unknown → seen → signed-known → approved)
- Policy simulation against recorded calls (safe dry-run)
- Auto-suggest permit() rules when tools are denied (rapid policy iteration)
- Swarm tracking for multi-agent sessions
- Compliance reports from receipts (JSON or Markdown)

## Prerequisites

- **Node.js >= 18** and **npx** (both required)
- Verify: `node --version && npx --version`

No installation needed — runs via `npx`. Receipt verification: `npx @veritasacta/verify`.

## Policy Templates

### JSON Policy (simplest — recommended for most users)

Write this to `protect-mcp.json`:

```json
{
  "default_tier": "unknown",
  "tools": {
    "execute_*": { "block": true },
    "shell_*": { "block": true },
    "run_*": { "block": true },
    "system_*": { "block": true },
    "delete_*": { "block": true },
    "remove_*": { "block": true },
    "drop_*": { "block": true },
    "truncate_*": { "block": true },
    "destroy_*": { "block": true },
    "format_*": { "block": true },
    "wipe_*": { "block": true },
    "send_email": { "block": true },
    "post_message": { "block": true },
    "read_env": { "block": true },
    "read_environment": { "block": true },
    "getenv": { "block": true },
    "write_file": { "require_approval": true, "rate_limit": "10/minute" },
    "http_request": { "rate_limit": "5/minute" },
    "fetch": { "rate_limit": "10/minute" },
    "read_file": { "rate_limit": "30/minute" },
    "query_database": { "rate_limit": "20/minute" },
    "search_code": { "allow": true },
    "list_directory": { "allow": true },
    "glob": { "allow": true },
    "grep": { "allow": true },
    "*": { "rate_limit": "100/hour" }
  },
  "signing": {
    "key_path": "./keys/gateway.json",
    "issuer": "protect-mcp",
    "enabled": true
  }
}
```

### Cedar Policy (declarative — best for complex rules)

Write this to `policies/agent.cedar`:

```cedar
// ============================================================
// MCP Tool Policy — Cedar Authorization Language
// ============================================================

// Allow read-only information gathering tools for all principals
permit(
  principal,
  action == Action::"MCP::Tool::call",
  resource in [
    Tool::"read_file",
    Tool::"list_directory",
    Tool::"search_code",
    Tool::"grep",
    Tool::"glob",
    Tool::"read_database",
    Tool::"query_database",
    Tool::"read_resource",
    Tool::"list_resources",
    Tool::"list_tools",
    Tool::"list_prompts"
  ]
);

// Allow read-write tools with moderate trust
permit(
  principal,
  action == Action::"MCP::Tool::call",
  resource in [
    Tool::"write_file",
    Tool::"edit_file",
    Tool::"create_file",
    Tool::"append_file",
    Tool::"patch_file",
    Tool::"http_request",
    Tool::"fetch"
  ]
) when {
  principal.tier >= 2
};

// ============================================================
// Forbid rules — these are authoritative and cannot be overridden
// ============================================================

// Block all command execution
forbid(
  principal,
  action == Action::"MCP::Tool::call",
  resource in [
    Tool::"execute_command",
    Tool::"execute_shell",
    Tool::"shell_exec",
    Tool::"run_script",
    Tool::"exec",
    Tool::"system",
    Tool::"spawn",
    Tool::"popen",
    Tool::"run_command",
    Tool::"cmd",
    Tool::"bash",
    Tool::"sh"
  ]
);

// Block all destructive operations
forbid(
  principal,
  action == Action::"MCP::Tool::call",
  resource in [
    Tool::"delete_file",
    Tool::"delete_directory",
    Tool::"remove_file",
    Tool::"rm",
    Tool::"drop_table",
    Tool::"truncate_table",
    Tool::"destroy",
    Tool::"format_disk",
    Tool::"wipe"
  ]
);

// Block credential / secret access
forbid(
  principal,
  action == Action::"MCP::Tool::call",
  resource in [
    Tool::"read_environment",
    Tool::"read_env",
    Tool::"getenv",
    Tool::"environ",
    Tool::"read_ssh_key",
    Tool::"read_aws_creds",
    Tool::"read_kube_config"
  ]
);

// Block outbound data exfiltration tools
forbid(
  principal,
  action == Action::"MCP::Tool::call",
  resource in [
    Tool::"send_email",
    Tool::"post_message",
    Tool::"send_slack",
    Tool::"send_discord",
    Tool::"send_telegram",
    Tool::"send_webhook"
  ]
);

// Require explicit human approval for database mutation
forbid(
  principal,
  action == Action::"MCP::Tool::call",
  resource in [
    Tool::"alter_table",
    Tool::"create_table",
    Tool::"delete_rows",
    Tool::"update_rows",
    Tool::"insert_rows",
    Tool::"drop_view",
    Tool::"create_index"
  ]
) unless {
  principal has human_approval && principal.human_approval == true
};
```

Deploy with:
```bash
npx protect-mcp --cedar ./policies/ --enforce -- node original-server.js
```

## Step-by-Step Execution

### Step 1: Determine requirements

Ask the user:
1. Which MCP server to protect? (command or URL)
2. What threat model? (read-only, read-write, full access)
3. JSON or Cedar policies? (JSON is simpler, Cedar is more powerful)
4. Signing enabled? (recommended for audit trails)
5. Shadow or enforce mode? (always start in shadow)

### Step 2: Initialize keys and config templates

```bash
mkdir -p .protect-mcp policies keys

# Generate Ed25519 keypair + JSON policy template
npx protect-mcp init

# Files created:
#   keys/gateway.json    — Ed25519 signing keypair
#   protect-mcp.json     — Default JSON policy
```

### Step 3: Write the policy

Based on the user's requirements (see templates above), write either:
- `protect-mcp.json` (JSON policy)
- `policies/agent.cedar` + more `.cedar` files (Cedar policy)

Start with a baseline that blocks:
1. All command/shell execution tools
2. All destructive/delete operations
3. All credential/environment variable readers
4. All outbound data exfiltration (email, messaging, webhooks)
5. All database mutation (require approval)
6. Rate limits on network calls
7. Rate limits on file reads

### Step 4: Deploy in shadow mode (safe first step)

```bash
echo "=== Deploying protect-mcp in SHADOW mode ==="
echo "Mode: shadow (log + sign decisions, block nothing)"

# JSON policy
npx protect-mcp --policy protect-mcp.json -- node original-server.js

# OR Cedar policy
# npx protect-mcp --cedar ./policies/ -- node original-server.js

echo "Proxy started. All decisions are logged and signed."
echo "Run 'npx protect-mcp status' to see statistics."
```

### Step 5: Simulate and verify

```bash
# Run simulation against recorded calls (no enforcement)
npx protect-mcp simulate --policy protect-mcp.json

# Check setup is correct
npx protect-mcp doctor

# View decision statistics
npx protect-mcp status

# View receipts
npx protect-mcp receipts
```

### Step 6: After user confirmation, switch to enforce mode

```bash
# Kill shadow proxy, restart in enforce mode
npx protect-mcp --policy protect-mcp.json --enforce -- node original-server.js
```

### Step 7: Generate MCP client config

```json
{
  "mcpServers": {
    "{server-name}": {
      "command": "npx",
      "args": [
        "-y",
        "protect-mcp",
        "--policy", "{PWD}/protect-mcp.json",
        "--enforce",
        "--", "node", "original-server.js"
      ]
    }
  }
}
```

### Step 8: Present report

```markdown
## MCP Policy Enforcement Deployed

**Policy Engine**: {JSON | Cedar | External PDP}
**Mode**: {shadow | enforce}
**Signing**: Ed25519 {enabled | disabled}

### Active Policies
| Tool Pattern | Action | Details |
|-------------|--------|---------|
| execute_*, shell_*, run_* | 🚫 BLOCK | Command execution |
| delete_*, remove_*, drop_* | 🚫 BLOCK | Destructive ops |
| read_env, getenv | 🚫 BLOCK | Credential access |
| send_email, post_message | 🚫 BLOCK | Data exfiltration |
| write_file | ⏸️ APPROVAL | Requires human OK |
| http_request, fetch | ⏱️ RATE LIMIT | 5/min, 10/min |
| read_file | ⏱️ RATE LIMIT | 30/min |
| * (default) | ⏱️ RATE LIMIT | 100/hour |

### Receipts
- Public key: {key_id}
- Receipts generated: {N}
- Verify: `npx @veritasacta/verify .protect-mcp-receipts.jsonl`

### To Integrate Permanently
Add to your MCP client config:
```json
{mcp_config_json}
```
```

## Policy Iteration: Handling Denied Tool Calls

When a tool is blocked in enforce mode, the agent receives a structured error. **protect-mcp auto-suggests the minimal Cedar permit() rule** to allow it. This enables rapid policy iteration:

1. User: "I need to allow http_request for my weather app"
2. Agent: Checks current policy, sees it's rate-limited
3. Agent: Updates policy to add a specific exception
4. Agent: Restarts the proxy with `npx protect-mcp doctor` to verify

## Compliance Reporting

```bash
# Generate compliance report from receipts
npx protect-mcp report --format markdown

# Export offline-verifiable audit bundle
npx protect-mcp bundle --output audit-bundle.json

# Generate human-readable activity summary
npx protect-mcp digest
```

## Important Constraints

- **Always start in shadow mode first.** Never enforce without user confirmation.
- Cedar `forbid` rules are **authoritative** — they cannot be overridden even by other permits.
- Key files are auto-gitignored. Never commit `keys/gateway.json`.
- protect-mcp runs entirely locally. No cloud dependency for policy evaluation.
- The hook server (`protect-mcp serve`) is for Claude Code integration. The stdio proxy is for all MCP clients.
- If the policy is invalid, protect-mcp fails closed — it will not start rather than silently pass traffic.
