# Captain preferences

<!-- memory tiers: see the stow skill -->

- Cloudflare tunnels on phillias.cc infrastructure are managed CLOUD-SIDE ONLY: ingress changes go through the Zero Trust dashboard (connectors run token-mode/remotely-managed and hot-reload), never by editing server-side cloudflared configs or restarting those daemons. SSH through those tunnels is the critical path for fleet administrative access; a blip or misconfiguration there can sever it. (set 2026-08-22)

## Knowledge Portability Directive

I want my knowledge to be portable across my fleet (all servers running Firstmate).

Whenever a new learning is added to `data/learnings.md`, a preference is updated in `data/captain.md`, or a project is added to `data/projects.md`, you must immediately run `axi-memory-add` to sync that exact same material into the global memory store.

Use the same title and a concise summary of the body for the memory. This ensures my knowledge is searchable and available from any of my servers.
