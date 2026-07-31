---
name: mariadb-axi
description: Read-only MariaDB inspection for the selfhost stack — databases, tables, queries, processlist, status. Use whenever the user asks about the MariaDB database, schema, tables, running queries, DB sizes, or wants to peek at data. Also use when the user mentions "mariadb", "mysql", "sandbox db", "database", "tables", "processlist".
---

# mariadb-axi — read-only MariaDB inspection

Inspect the selfhost MariaDB (11.4, localhost:3306). TOON output, read-only enforced.

## How it connects

- Host `mariadb` client → `127.0.0.1:3306`
- Credentials auto-discovered from `~/docker/selfhost/.env` (`MYSQL_USER`/`MYSQL_PASSWORD`)
- Override with `MARIADB_HOST`/`MARIADB_PORT`/`MARIADB_USER`/`MARIADB_PASSWORD`/`MARIADB_DATABASE`
- Override client with `MARIADB_BIN`

## Quick Reference

```bash
mariadb-axi                            # server status (version, uptime, threads, queries)
mariadb-axi dbs                        # databases with size + table counts
mariadb-axi tables <db>                # tables with estimated rows
mariadb-axi query "<sql>"              # capped read-only query (auto LIMIT 50)
mariadb-axi query "<sql>" --limit 200  # more rows
mariadb-axi query "<sql>" --full       # untruncated cell values
mariadb-axi status                     # key global status variables
mariadb-axi processlist                # running queries (slowest first)
```

## Safety rules

- **Read-only by construction**: only `SELECT`/`SHOW`/`DESCRIBE`/`EXPLAIN`/`WITH` pass the guard
- Mutating SQL (`INSERT`/`UPDATE`/`DELETE`/`DROP`/`ALTER`/...) is rejected with exit 2
- Queries without a `LIMIT` get one appended (default 50)
- Long cell values are truncated with a size hint; `--full` removes truncation

## Errors

Errors go to stdout in TOON shape with a `code:` and actionable `help[n]:` hints.
Exit codes: 0 = success, 1 = error, 2 = usage error.
