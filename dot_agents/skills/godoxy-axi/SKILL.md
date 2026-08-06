---
name: godoxy-axi
description: GoDoxy reverse proxy routes for the selfhost stack — list routes, inspect a route, ACL rules, middlewares. Use whenever the user asks about reverse proxy routes, subdomains, proxy config, hostapps, what domain points where, or proxy ACL/middlewares. Also use when the user mentions "godoxy", "reverse proxy", "routes", "hostapps", "proxy config", "subdomain".
---

# godoxy-axi — GoDoxy reverse proxy routes (API-view)

Inspect the GoDoxy route table, ACL, and entrypoint middlewares. TOON output, read-only.

## How it reads state

Reads **live state from the GoDoxy local API** (`/api/v1`), not config files:

- `GET /api/v1/route/list` — all routes, live/effective state from the entrypoint
  (includes docker-label routes, config routes, and the webui route)
- `GET /api/v1/docker/containers` — containers known to GoDoxy
- `GET /api/v1/file/content?type=config&filename=config.yml` — entrypoint middlewares, ACL, autocert

Containers with `proxy.exclude=true` are filtered out of route views (count surfaced in overview).

## Prerequisites

The deployment must expose GoDoxy's **local API** (unauthenticated, loopback-only):

- `~/.docker/selfhost/.env` → `GODOXY_LOCAL_API_ADDR=127.0.0.1:8889`, then restart godoxy
- The main API (`GODOXY_API_ADDR`, default 127.0.0.1:8888) is **not** used: it sits behind
  browser-only OIDC auth (PocketID), which rejects non-HTML clients.
- Override the API base with `GODOXY_API_URL` (default `http://127.0.0.1:8889`) for other instances.

## Quick Reference

```bash
godoxy-axi                      # overview: route counts, middlewares, ACL
godoxy-axi routes               # all routes (target, middlewares, source)
godoxy-axi routes --source docker
godoxy-axi route <name>         # one route's detail (incl. health)
godoxy-axi hostapps             # routes from config (not container labels)
godoxy-axi containers           # containers known to GoDoxy (with route target)
godoxy-axi acl                  # allow/deny lists
godoxy-axi config               # entrypoint: middlewares, autocert, ACL counts
```

## Typical workflows

- "What does X subdomain point to?" → `godoxy-axi routes` then `godoxy-axi route <name>`
- "Is anything blocked by the ACL?" → `godoxy-axi acl`
- "What middlewares run on the entrypoint?" → `godoxy-axi config`

## Errors

Errors go to stdout in TOON shape with a `code:` and actionable `help[n]:` hints.
Exit codes: 0 = success, 1 = error, 2 = usage error.
`API_UNREACHABLE` means the local API isn't up — check `GODOXY_LOCAL_API_ADDR` and that godoxy is running.
