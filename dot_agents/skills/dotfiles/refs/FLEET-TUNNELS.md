# Fleet Tunnels — opencode serve cross-node mesh

Fleet nodes (kalione, primary55522, kali) each run a headless `opencode serve`
bound to `127.0.0.1:4096`. Nodes reach each other's serve through persistent
autossh tunnels, so every firstmate's opencode agent sees remote fleet agents
as localhost ports. The tunnel is the security boundary — it rides existing
passphraseless SSH keys; no firewall changes, no public exposure.

## Architecture

```
kalione opencode agent ──> localhost:14001 ──autossh──> primary55522 ──> 127.0.0.1:4096 (remote serve)
kalione opencode agent ──> localhost:14002 ──autossh──> kali ────────────> 127.0.0.1:4096 (remote serve)
```

Each node runs BOTH:
- `opencode-serve.service` — own serve on 127.0.0.1:4096
- `opencode-tunnel-<node>.service` — one autossh tunnel per remote node

## Units (chezmoi: `dot_config/systemd/user/`)

| Unit | Purpose |
|---|---|
| `opencode-serve.service` | `opencode serve --port 4096 --hostname 127.0.0.1`, EnvironmentFile reads the age-encrypted `~/.config/opencode/opencode-serve.env` (OPENCODE_SERVER_PASSWORD etc.) |
| `opencode-tunnel-primary55522.service` | autossh `-L 14001:127.0.0.1:4096 primary55522` |
| `opencode-tunnel-kali.service` | autossh `-L 14002:127.0.0.1:4096 kali` |

Tunnel hardening flags: `-M 0` (systemd owns restarts; no monitoring port),
`ServerAliveInterval=15 ServerAliveCountMax=3` (dead-peer detection),
`ExitOnForwardFailure=yes`, `AUTOSSH_GATETIME=0` (start even if network flaps),
`Restart=on-failure RestartSec=5`.

## Port assignments (sequential, localhost only)

| Local port | Remote node | SSH alias |
|---|---|---|
| 14001 | primary55522 | `primary55522` (rides cloudflared proxy, no -p) |
| 14002 | kali | `kali` (rides cloudflared proxy, no -p) |
| 14003… | future nodes | next sequential |

The remote serve port is always 4096. Local ports only need per-node uniqueness.

## System prerequisites (NOT mise-pinnable)

`autossh` is an apt package (no GitHub releases; not in mise registry). Install
on every fleet node:

```bash
sudo apt-get install -y autossh
```

mise's `not_found_system_fallback = true` resolves the shim to the system
binary, but there is no pin — treat it like openssh-client as a system
dependency.

## Operations

```bash
# after chezmoi apply on a node:
systemctl --user daemon-reload
systemctl --user restart opencode-serve.service
systemctl --user enable --now opencode-tunnel-<node>.service  # each remote node

# validate serve: 401 on /doc = auth required = healthy
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:4096/doc

# validate tunnel: remote serve through tunnel
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:14001/doc

# tunnel diagnostics
ss -tlnp | grep -E '1400[12]'           # tunnel listening
journalctl --user -u opencode-tunnel-kali.service -n 15
```

`channel N: open failed: connect failed: Connection refused` in tunnel logs
means the tunnel is UP but the remote serve is not — deploy dotfiles on the
remote node (pull + chezmoi apply + daemon-reload + restart serve).

## Adding a node

1. Ensure the node has an SSH config alias + passphraseless key from every other node.
2. Assign the next sequential local port (14003, 14004, …).
3. Add `opencode-tunnel-<alias>.service` to `dot_config/systemd/user/` on every OTHER node.
4. Ship; on each node pull + `chezmoi apply` + `systemctl --user enable --now opencode-tunnel-<alias>`.
5. On the new node itself: `sudo apt-get install -y autossh`, then serve + its own tunnels to the others.

## Agent-to-agent usage

The opencode HTTP API is the transport: create a session on the remote serve,
`POST /api/session/:id/prompt` to message the remote firstmate's agent.
Password auth comes from `opencode-serve.env` (age-encrypted in chezmoi;
OPENCODE_SERVER_USERNAME/PASSWORD).
