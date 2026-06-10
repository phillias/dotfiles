---
name: mcp-security-audit
description: >
  Run an MCP security audit across two defense layers: runtime content
  inspection (mcp-runtime-guard) and policy-as-code enforcement
  (mcp-policy-enforce). Generates a unified security posture report for all
  MCP servers in the project with prioritized remediation roadmap.
  Trigger: user mentions "full security audit", "MCP security review",
  "audit all MCPs", "security posture", "comprehensive audit",
  "security report", "/mcp-security-audit"
license: MIT
compatibility: opencode
metadata:
  tools: mcpwall,protect-mcp
  mcp-risk-layer: runtime,governance
  owasp-mcp-coverage: MCP-01,MCP-02,MCP-03,MCP-04,MCP-06,MCP-08,MCP-09,MCP-10
---

## What This Skill Does

Runs both MCP security skills as a coordinated audit pipeline:

```
Phase 1: RUNTIME CONTENT INSPECTION
  └─ mcp-runtime-guard — Deterministic stdio proxy
     Using: mcpwall (monitor mode)

Phase 2: POLICY GOVERNANCE
  └─ mcp-policy-enforce — Policy-as-code enforcement
     Using: protect-mcp (shadow mode)

Phase 3: CONSOLIDATE
  └─ Merge all findings → unified report with risk scores
```

Each phase runs as an independent sub-task to maintain clear context boundaries.

## How to Use

```bash
# Full audit
/mcp-security-audit

# Audit a specific server
/mcp-security-audit --target http://localhost:3000/mcp

# Audit a stdio server
/mcp-security-audit --target "node my-server.js"
```

## Prerequisites

This skill delegates to two sub-skills. Each has its own prerequisites:

| Skill | Prerequisite | Install |
|-------|-------------|---------|
| mcp-runtime-guard | Node.js 18+ | `npx mcpwall` (auto) |
| mcp-policy-enforce | Node.js 18+ | `npx protect-mcp` (auto) |

The audit will check each prerequisite before running.

## Step-by-Step Execution

### Step 0: Determine audit scope

Ask the user:
- Which MCP servers to audit? (specific URL, specific command)
- Output format? (terminal report, markdown file, both)

Defaults:
- **Scope**: the servers the user specifies
- **Output**: terminal + `mcp-security-audit-report.md`

### Phase 1: Runtime Content Inspection

Load the `mcp-runtime-guard` skill and deploy a monitor-mode proxy for each target MCP server.

Specifically:
1. For each MCP server, generate a `.mcpwall.yml` with default rules
2. Deploy `npx mcpwall -c .mcpwall.yml -- $COMMAND` wrapping the server
3. Make 2-3 test tool calls per server to verify the proxy is capturing traffic
4. Check the audit log for any detected threats
5. Stop the proxy (cleanup)

Store results as `phase1_results`.

### Phase 2: Policy Governance

Load the `mcp-policy-enforce` skill and evaluate policy coverage for each MCP server.

Specifically:
1. For each MCP server, generate a baseline `protect-mcp.json`
2. Run `npx protect-mcp simulate --policy protect-mcp.json` against the server's tool list
3. Identify which tools would be blocked, which need approval, which are allowed
4. Calculate coverage ratio (tools with explicit policy / total tools)

Store results as `phase2_results`.

### Phase 3: Consolidate & Report

Merge both phase results into a unified security posture report:

```markdown
# MCP Security Posture Report

**Generated**: {timestamp}
**Scope**: {specific target}

---

## Executive Summary

| Metric | Value |
|--------|-------|
| MCP Servers audited | {N} |
| Total tools across all servers | {N} |
| Runtime threats detected | {N} |
| Policy coverage | {N}% (explicit rules for {N}/{N} tools) |
| **Overall posture** | 🟢 PASS / 🟡 WARN / 🔴 FAIL |

---

## Per-Server Breakdown

### {server_name} ({server_url_or_command})
| Layer | Status | Details |
|-------|--------|---------|
| 🛡️ Runtime | 🟢 SAFE / 🟡 ACTIVE / ⚫ NOT DEPLOYED | {threats_detected} threats |
| 📜 Governance | 🟢 ENFORCED / 🟡 SHADOW / ⚫ NOT DEPLOYED | {policy_coverage}% coverage |
| **Overall** | **🟢 PASS / 🟡 WARN / 🔴 FAIL** | |

#### Runtime Findings
| Type | Description |
|------|-------------|
| {threat_type} | {details} |

#### Policy Coverage
| Tool | Current Policy | Recommended |
|------|---------------|-------------|
| execute_command | ❌ No rule | BLOCK |
| read_file | ❌ No rule | ALLOW rate_limit 30/min |
| http_request | ❌ No rule | RATE LIMIT 5/min |
| ... | ... | ... |

---

## OWASP MCP Top 10 Coverage

| Risk | Covered By |
|------|------------|
| MCP-01: Prompt Injection | ✅ Phase 1 (outbound rules) |
| MCP-02: Tool Poisoning | ✅ Phase 1 (inbound rules) |
| MCP-03: Excessive Permissions | ✅ Phase 2 (policy) |
| MCP-04: Command Injection | ✅ Phase 1 (arg scan) + Phase 2 (block) |
| MCP-06: Insufficient Logging | ✅ Phase 2 (signed receipts) |
| MCP-08: Context Manipulation | ✅ Phase 1 (outbound rules) |
| MCP-09: Scope Creep | ✅ Phase 2 (policy tiers) |
| MCP-10: Data Leakage | ✅ Phase 1 (secret detect) |

---

## Prioritized Remediation Roadmap

### Immediate (address now)
1. {finding} — {server}/{tool}
2. {finding} — {server}/{tool}

### Short-term (address this week)
1. {finding} — {server}/{tool}
2. {finding} — {server}/{tool}

### Medium-term (address this month)
1. {finding} — {server}/{tool}

---

## Recommended Next Steps

1. **Apply mcp-runtime-guard** to {N} servers: `/mcp-runtime-guard --wrap {server} --mode enforce`
2. **Apply mcp-policy-enforce** to {N} servers: `/mcp-policy-enforce --wrap {server} --policy strict --enforce`
3. **Schedule recurring audits**: `/mcp-security-audit` weekly
```

## Important Constraints

- Phase 1 starts a proxy that must be cleaned up — always stop it before the report
- If a prerequisite tool is missing, report it as unavailable
- If a server is unreachable, report it as OFFLINE and continue with other servers
- All findings are read-only — never modify server configs without user permission
- The report should be saved to `mcp-security-audit-report.md` in the current directory

## Output Files

| File | Contents |
|------|----------|
| `mcp-security-audit-report.md` | Full consolidated report |
| `.mcp-security/phase1-guard.json` | Runtime guard results |
| `.mcp-security/phase2-policy.json` | Policy simulation results |
