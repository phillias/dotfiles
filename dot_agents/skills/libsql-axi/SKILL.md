---
name: libsql-axi
description: Read-only queries against the selfhost libSQL/Turso server (127.0.0.1:7087) — list tables and run capped SELECTs. Use whenever the user asks about the libSQL or Turso database, its tables, or wants to peek at data. Also use when the user mentions "libsql", "turso", "sqld", "sqlite server".
---

# libsql-axi — read-only libSQL (Turso) queries

Query the selfhost libSQL server over its HTTP API (`/v2/pipeline`). TOON output, read-only.

## Requirements

The server enforces Ed25519 JWT auth (`SQLD_AUTH_JWT_KEY` / `LIBSQL_JWT_KEY` in
`~/docker/selfhost/.env`). Provide the **private key** that pairs with it:

```bash
export LIBSQL_PRIVATE_KEY="<pkcs8 pem or base64url der>"   # or:
export LIBSQL_PRIVATE_KEY_FILE=/path/to/private-key.pem
```

Run `libsql-axi doctor` — it checks key presence, server reachability, and does an
auth round-trip. If the private key isn't available yet, `libsql-axi` still works for
reachability/status, and errors clearly on queries.

Override the endpoint with `LIBSQL_URL` (default `http://127.0.0.1:7087`).

## Quick Reference

```bash
libsql-axi                            # overview: key status + table count
libsql-axi doctor                     # key, reachability, auth round-trip
libsql-axi dbs                        # namespaces (if exposed)
libsql-axi tables                     # tables in default database
libsql-axi tables --namespace <ns>    # tables in a namespace
libsql-axi query "<sql>"              # capped read-only query (auto LIMIT 50)
libsql-axi query "<sql>" --limit 200
libsql-axi query "<sql>" --full       # untruncated cells
```

## Safety rules

- **Read-only by construction**: only `SELECT`/`SHOW`/`DESCRIBE`/`EXPLAIN`/`WITH` pass the guard
- Mutating SQL is rejected with exit 2
- Queries without a `LIMIT` get one appended (default 50)
- Long cell values are truncated with a size hint; `--full` removes truncation

## Errors

Errors go to stdout in TOON shape with a `code:` and actionable `help[n]:` hints.
Exit codes: 0 = success, 1 = error, 2 = usage error.
