# simplefin-axi

Agent-ergonomic CLI for SimpleFIN financial data stored in Cloudflare D1.

## When to use

Load when the user asks about bank accounts, balances, transactions, financial data, SimpleFIN, or any task that involves reading or syncing their financial information. Also load when the user says "simplefin", "bank balance", "transactions", "accounts".

## Commands

```
simplefin-axi                     # dashboard — accounts overview, next steps
simplefin-axi init                # create D1 schema (idempotent, safe to re-run)
simplefin-axi fetch               # pull latest from SimpleFIN Bridge into D1
simplefin-axi accounts            # list all accounts
simplefin-axi account <id>        # one account's detail
simplefin-axi balances            # balance summary across all accounts
simplefin-axi transactions        # recent transactions
  --days <N>                      # lookback window (default 30)
  --account <id>                  # filter to one account
  --limit <N>                     # max rows (default 100)
```

## Auth

SIMPLEFIN_ACCESS_URL resolved from env var, then from BWS project phillias (key SIMPLEFIN_ACCESS_URL). The access URL is Basic Auth over HTTPS to bridge.simplefin.org; no IP restrictions.

## D1 database

Database name: `simplefin-store` on the phillias Cloudflare account. Schema: `accounts` (id PK, name, balance, available_balance, currency, balance_date, institution, org_domain, last_four), `transactions` (id PK, account_id FK, amount, description, date, posted_date, category, fit_id, pending, memo), `sync_log`. Indices on transactions(account_id, date) and transactions(date).

## Rate limits

SimpleFIN Bridge: 24 requests/day per access URL. `fetch` makes 1 request; do not call it in a loop.

## Output

TOON format on stdout. Structured errors on stdout with exit codes: 0 success, 1 error, 2 usage error. Progress/debug on stderr.

## Typical flow

1. `simplefin-axi init` (once)
2. `simplefin-axi fetch` (daily or on demand)
3. `simplefin-axi balances` or `simplefin-axi transactions` to read
