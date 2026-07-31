---
name: mcp-runtime-guard
description: >
  Deploy a deterministic stdio-based MCP security proxy (mcpwall) that intercepts
  every tool call and response at runtime. Blocks dangerous tool calls (SSH key
  access, destructive commands, secret leakage), redacts credentials from server
  responses, and detects prompt injection patterns — with zero AI and zero cloud
  dependencies. Supports monitor mode (log only) and enforce mode (block threats).
  Trigger: user mentions "protect MCP server", "runtime guard", "MCP firewall",
  "content inspection", "monitor MCP", "secure my MCP", "/mcp-runtime-guard"
license: Apache-2.0
compatibility: opencode
metadata:
  tools: mcpwall
  mcp-risk-layer: runtime
  owasp-mcp-coverage: MCP-01,MCP-02,MCP-04,MCP-05,MCP-08,MCP-10
---

## What This Skill Does

Deploys **mcpwall**, a deterministic stdio proxy that sits between your AI agent and an MCP server, intercepting every JSON-RPC message in both directions:

**Inbound scanning** (agent → server):
- Block SSH key access (`~/.ssh/`, `id_rsa`, `id_ed25519`)
- Block dangerous shell commands (`rm -rf`, `curl|bash`, reverse shells)
- Block writes outside project directory
- Detect and block secrets/API keys in tool arguments (AWS, GitHub, private keys, high-entropy strings)
- Block reads of sensitive files (`.env`, credentials, browser data)
- Pattern matching via glob, regex, `_any_value` recursive scanning
- Built-in `block-dangerous-commands`, `block-secret-leakage`, `block-ssh-keys` rules

**Outbound scanning** (server → agent):
- Redact leaked secrets in server responses (surgical `[REDACTED BY MCPWALL]` replacement)
- Block prompt injection patterns in responses
- Flag zero-width Unicode characters (ATPA attack)
- Flag or block suspiciously large responses

**Two operating modes** (via `default_action` in config):
- `allow` (default, monitor-like) — Logs threats, never blocks. Safe to deploy anywhere.
- `deny` (enforce mode) — Blocks threats with JSON-RPC error responses.

## Prerequisites

- **Node.js >= 18** and **npx** (both required for `npx mcpwall`)
- Verify: `node --version && npx --version`

No installation needed — runs via `npx`. All detection runs locally with zero cloud dependencies.

## Step-by-Step Execution

### Step 1: Determine the target MCP server

Ask the user what to wrap:

| If the user says... | Transport | Example |
|--------------------|-----------|---------|
| "this command" / "this script" | stdio | `node my-server.js` |
| "my MCP config" / "claude desktop" | Config-based | Read from `claude_desktop_config.json` |

mcpwall currently supports **stdio only** (HTTP/SSE proxy planned in v0.3-0.4).

If unclear, ask: "Which MCP server do you want to protect? Provide the command."

### Step 2: Choose the mode

| Mode | `default_action` | Behavior | When to use |
|------|------------------|----------|-------------|
| `monitor` | `allow` | Forward everything, log threats | First deployment, testing, low-risk servers |
| `enforce` | `deny` | Block matching threats with errors | Production, sensitive data, after reviewing logs |

Default: `allow` for safety. Recommend switching to `deny` only after reviewing initial logs.

### Step 3: Generate or customize config

mcpwall works out of the box with no config — built-in defaults block SSH keys, dangerous commands, and secrets. But for project-specific rules, create a config:

```bash
# Create project-level config
cat > .mcpwall.yml << 'YAML'
version: 1

settings:
  log_dir: .mcpwall/logs
  log_level: info
  default_action: allow       # allow = monitor, deny = enforce

rules:
  # Block reading SSH keys
  - name: block-ssh-keys
    match:
      method: tools/call
      tool: "*"
      arguments:
        _any_value:
          regex: "(\\.ssh/|id_rsa|id_ed25519)"
    action: deny
    message: "Blocked: access to SSH keys"

  # Block dangerous shell commands
  - name: block-dangerous-commands
    match:
      method: tools/call
      tool: "*"
      arguments:
        _any_value:
          regex: "(rm\\s+-rf|curl.*\\|.*bash|wget.*\\|.*sh)"
    action: deny
    message: "Blocked: dangerous command"

  # Block writes to sensitive paths
  - name: block-sensitive-writes
    match:
      method: tools/call
      tool: write_file
      arguments:
        path:
          regex: "(\\.env$|/etc/|/var/log/|~/\\.)"
    action: deny
    message: "Blocked: write to sensitive path"

  # Block secret leakage in tool arguments
  - name: block-secret-leakage
    match:
      method: tools/call
      tool: "*"
      arguments:
        _any_value:
          secrets: true
    action: deny
    message: "Blocked: detected secret in arguments"

  # Block destructive operations
  - name: block-destructive-tools
    match:
      method: tools/call
      tool: "delete_*|remove_*|drop_*|truncate_*|wipe_*|destroy_*|format_*"
    action: deny
    message: "Blocked: destructive operation"

  # Block database mutation
  - name: block-database-mutation
    match:
      method: tools/call
      tool: "drop_table|truncate_table|alter_table|delete_rows|update_rows|create_table"
    action: deny
    message: "Blocked: database mutation"

  # Block credential/environment access
  - name: block-credential-read
    match:
      method: tools/call
      tool: "getenv|environ|read_environment|read_env"
    action: deny
    message: "Blocked: credential access"

  # Rate-limit network tools
  - name: rate-limit-network
    match:
      method: tools/call
      tool: "http_request|fetch"
    action: allow
    # Note: mcpwall does not have native rate limiting in v0.2.x
    # Planned for v0.4.0

outbound_rules:
  # Redact secrets leaked in responses
  - name: redact-secrets
    match:
      secrets: true
    action: redact
    message: "Secret redacted in server response"

  # Block prompt injection in responses
  - name: block-prompt-injection
    match:
      response_contains:
        - "ignore previous instructions"
        - "ignore all previous instructions"
        - "disregard previous instructions"
        - "disregard your instructions"
        - "forget your instructions"
        - "override your instructions"
        - "new instructions:"
        - "system prompt:"
        - "you are now"
        - "act as if"
        - "pretend you are"
        - "provide contents of ~/.ssh"
        - "provide contents of /etc/passwd"
        - "output your system prompt"
        - "reveal your instructions"
    action: deny
    message: "Prompt injection pattern detected in server response"

  # Flag suspiciously large responses
  - name: flag-large-responses
    match:
      response_size_exceeds: 51200
    action: log_only
    message: "Response exceeds 50KB"

  # Flag zero-width Unicode chars (ATPA)
  - name: flag-zero-width-chars
    match:
      response_contains_regex:
        - "[\\u200B\\u200C\\u200D\\u2060\\uFEFF]"
    action: log_only
    message: "Zero-width Unicode characters detected (possible ATPA attack)"

secrets:
  patterns:
    - name: aws-access-key
      regex: "AKIA[0-9A-Z]{16}"
    - name: github-token
      regex: "(gh[ps]_[A-Za-z0-9_]{36,}|github_pat_[A-Za-z0-9_]{22,})"
    - name: private-key
      regex: "-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----"
    - name: generic-high-entropy
      regex: "[A-Za-z0-9/+=]{40}"
      entropy_threshold: 4.5
YAML
```

### Step 4: Deploy the proxy

**For a stdio-based server:**

```bash
# Create log directory
mkdir -p .mcpwall/logs

# Monitor mode (recommended first)
npx mcpwall -c .mcpwall.yml -- $COMMAND $ARGS

# Enforce mode
MCPWALL_DEFAULT_ACTION=deny npx mcpwall -c .mcpwall.yml -- $COMMAND $ARGS
```

**Using a built-in profile (no config needed for quick setup):**

```bash
# Use strict profile (deny-by-default)
npx mcpwall init --profile strict

# Then wrap as usual
npx mcpwall -- $COMMAND $ARGS
```

### Step 5: Generate MCP client configuration

Tell the user how to update their MCP client config to route through the proxy.

**For Claude Desktop / Cursor / Windsurf / OpenCode MCP config:**

```json
{
  "mcpServers": {
    "{server-name}": {
      "command": "npx",
      "args": [
        "-y", "mcpwall",
        "-c", "{PWD}/.mcpwall.yml",
        "--",
        "{original_command}"
      ]
    }
  }
}
```

**For OpenCode `opencode.json` MCP configuration:**

```json
{
  "mcp": {
    "servers": {
      "{server-name}": {
        "command": "npx",
        "args": [
          "-y", "mcpwall",
          "-c", "{PWD}/.mcpwall.yml",
          "--",
          "{original_command}"
        ]
      }
    }
  }
}
```

### Step 6: Verify the deployment

```bash
# Test with the check command
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"write_file","arguments":{"path":"~/.ssh/authorized_keys","content":"ssh-rsa AAAA..."}}}' | \
  npx mcpwall check --input -

# Check proxy logs
cat .mcpwall/logs/*.log 2>/dev/null | tail -20
```

### Step 7: Report status to the user

Produce a deployment summary:

```markdown
## MCP Runtime Guard Deployed

**Target**: {command}
**Transport**: stdio
**Mode**: {allow (monitor) | deny (enforce)}
**Config**: {PWD}/.mcpwall.yml
**PID**: {pid}

### Active Protections
| Protection | Status | Details |
|------------|--------|---------|
| SSH key access | ✅ Active | Regex pattern blocking |
| Dangerous commands | ✅ Active | rm -rf, curl|bash, etc. |
| Secret leakage (inbound) | ✅ Active | AWS, GitHub, private keys, high-entropy |
| Secret redaction (outbound) | ✅ Active | Surgical replacement in responses |
| Prompt injection (outbound) | ✅ Active | 15+ injection patterns |
| Zero-width char detection | ✅ Active | ATPA protection |
| Response size monitoring | ✅ Active | 50KB threshold |

### To Integrate Permanently
Add this to your MCP client config:
```json
{mcp_config_json}
```

### Audit Log
Log file: {PWD}/.mcpwall/logs/
```

## Switching Between Modes

To switch from `allow` (monitor) to `deny` (enforce):

1. Stop the running proxy (Ctrl+C / SIGTERM)
2. Edit `.mcpwall.yml`: change `default_action: allow` to `default_action: deny`
3. Restart with the same command
4. Verify: blocked actions now return JSON-RPC errors

## Testing Rules Without the Proxy

Use the `check` command to dry-run rules against a tool call:

```bash
# Interactive wizard
npx mcpwall check

# Direct input
npx mcpwall check write_file --path /etc/passwd --content test

# Raw JSON-RPC
npx mcpwall check --input '{"method":"tools/call","params":{"name":"write_file","arguments":{"path":"/etc/passwd"}}}'
```

## Teardown (cleanup mode)

If the user asks to remove the guard:

```bash
# Find and kill the proxy process
kill {PID} 2>/dev/null

# Optionally clean up
# rm -rf .mcpwall
```

Report a summary of all blocked/allowed calls from the audit log.

## Known Limitations (mcpwall v0.3.1)

- **Stdio only** — HTTP/SSE proxy planned for v0.3-0.4
- **No rate limiting** — planned for v0.4.0
- **No tool integrity / rug-pull detection** — planned for v0.3.0
- **Config is static** — no hot-reload, requires restart to pick up changes
- **Server stderr not inspected** — passes through to parent process
- **Server side effects not inspected** — file I/O, network calls by the server process itself

## Important Constraints

- Always start in `allow` (monitor) mode first — never switch to `deny` without user confirmation
- The proxy adds minimal latency (~sub-ms for allow, ~1-5ms for deny evaluation)
- mcpwall runs entirely locally — no data leaves your machine
- Do NOT modify the original MCP server — only wrap it
- If the user doesn't specify a server, ask. Do not guess.
- mcpwall looks for `.mcpwall.yml` (project) and `~/.mcpwall/config.yml` (global) automatically
- Built-in default rules apply if no config file is found — no configuration is required for basic protection
