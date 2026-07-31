---
name: godoxy-axi
description: GoDoxy reverse proxy routes for the selfhost stack — list routes, inspect a route, ACL rules, middlewares. Use whenever the user asks about reverse proxy routes, subdomains, proxy config, hostapps, what domain points where, or proxy ACL/middlewares. Also use when the user mentions "godoxy", "reverse proxy", "routes", "hostapps", "proxy config", "subdomain".
---

# godoxy-axi — GoDoxy reverse proxy routes (config-view)

Inspect the GoDoxy route table, ACL, and entrypoint middlewares. TOON output, read-only.

## How it reads state

- `~/docker/selfhost/godoxy/config/hostapps.yml` — static host-app routes
- `~/docker/selfhost/godoxy/config/config.yml` — entrypoint, middlewares, ACL, autocert
- Live docker labels (`proxy.*`) on running containers — container-derived routes
- Override the config dir with `GODOXY_DIR`

Note: the GoDoxy WebUI/API port (8080) is occupied by another app in this deployment, so
this AXI reads configuration + docker labels rather than the live API.

## Quick Reference

```bash
godoxy-axi                      # overview: route counts, middlewares, ACL
godoxy-axi routes               # all routes (target, middlewares, source)
godoxy-axi routes --source docker
godoxy-axi route <name>         # one route's detail
godoxy-axi hostapps             # routes from hostapps.yml
godoxy-axi containers           # routes from docker labels
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
