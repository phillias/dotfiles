---
name: docker-axi
description: Use docker-axi to discover, plan, build, run, debug, publish, inspect, and clean up Docker apps through safe TOON CLI workflows.
---

# docker-axi

Use `docker-axi` when a task involves Dockerfiles, Docker Compose, containers, images, logs, inspect output, local dev stacks, registry publishing, cleanup, or Docker safety checks.

## Install

```bash
git clone --depth 1 https://github.com/thatdudealso/docker-axi ~/.local/opt/axi/docker-axi
(cd ~/.local/opt/axi/docker-axi && npm install)
ln -sf ~/.local/opt/axi/docker-axi/bin/docker-axi.js ~/.local/bin/docker-axi
```

(The `docker-axi` package is not on the npm registry — it is a git distribution, unlike the other thatdudealso AXIs. `npx -y docker-axi` will NOT work.)

## Quick Reference

```bash
docker-axi                     # live context: CLI/daemon health + running container count
docker-axi doctor              # before Docker work — CLI, daemon, compose, context
docker-axi discover            # discover targets (compose projects, containers)
docker-axi plan --target <id> --environment <name>   # plan before mutating
docker-axi <mutation> --execute                       # mutations require --execute
```

Safety model: mutations are dry-run by default and require `--execute`.
