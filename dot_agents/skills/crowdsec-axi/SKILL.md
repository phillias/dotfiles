---
name: crowdsec-axi
description: CrowdSec WAF operations for agents — decisions, alerts, bouncers, and bans for the selfhost stack. Use whenever the user asks about bans, blocked IPs, CrowdSec decisions or alerts, bouncers, security events, or wants to ban/unban an IP. Also use when the user mentions "crowdsec", "cscli", "ban", "blocked ip", "WAF".
---

# crowdsec-axi — CrowdSec decisions, alerts, bouncers

Read-only inspection by default; bans require `--execute`. TOON output.

## How it connects

- Talks to cscli **inside the `crowdsec` container**: `docker exec crowdsec cscli`
  (the host `cscli` config points at a stale LAPI — container path is authoritative)
- Override with `CROWDSEC_EXEC` (full command) or `CROWDSEC_CONTAINER` (name)

Run `crowdsec-axi status` first to confirm LAPI reachability.

## Quick Reference

```bash
crowdsec-axi                          # overview: decisions, alerts/24h, bouncers
crowdsec-axi decisions                # active decisions (bans)
crowdsec-axi alerts --since 24h       # recent alerts
crowdsec-axi bouncers                 # registered bouncers
crowdsec-axi ban 1.2.3.4 --execute    # ban an IP (4h default)
crowdsec-axi ban 1.2.3.4 --duration 24h --reason "bruteforce" --execute
crowdsec-axi unban 1.2.3.4 --execute  # remove decisions for an IP
crowdsec-axi status                   # LAPI connectivity + version
```

## Safety rules

- `ban`/`unban` are **dry-run by default** — output shows the planned action, no mutation
- Re-running a ban on an already-banned IP is a `no-op` (exit 0)
- Re-running `unban` with no active decisions is a `no-op` (exit 0)
- Add `--execute` only after reviewing the plan output

## Errors

Errors go to stdout in TOON shape with a `code:` and actionable `help[n]:` hints.
Exit codes: 0 = success (incl. no-ops), 1 = error, 2 = usage error.
