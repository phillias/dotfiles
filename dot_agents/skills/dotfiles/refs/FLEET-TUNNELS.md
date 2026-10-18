# Fleet Tunnels — opencode serve cross-node mesh

Fleet nodes (kalione, primary55522, kali) each run a headless `opencode serve`
bound to `127.0.0.1:4096`. This is a FULL MESH: every node tunnels to every
other node's serve through persistent autossh tunnels, so every firstmate's
opencode agent sees all remote fleet agents as localhost ports. The tunnel is
the security boundary — it rides existing passphraseless SSH keys; no firewall
changes, no public exposure.

## Architecture

```
                    ┌─────────────────────────────────────┐
                    │        localhost :14xxx namespace    │
                    └─────────────────────────────────────┘

  kalione ───14001──> primary55522 serve      primary55522 ───14002──> kali serve
  kalione ───14002──> kali serve              primary55522 ───14003──> kalione serve
  kali ─────14001──> primary55522 serve       kali ────14003──> kalione serve
```

Every node runs:
- `opencode-serve.service` — own serve on 127.0.0.1:4096
- `opencode-tunnel-<remote>.service` — one autossh tunnel per OTHER node
  (its own-target unit is hostname-ignored via `.chezmoiignore`)

## Units (chezmoi: `dot_config/systemd/user/`)

| Unit | Purpose |
|---|---|
| `opencode-serve.service` | `opencode serve --port 4096 --hostname 127.0.0.1 --pure`, EnvironmentFile reads `~/.config/opencode/opencode-serve.env` (OPENCODE_SERVER_PASSWORD etc.) — rendered by chezmoi template `private_opencode-serve.env.tmpl`, age-decrypting each secret from its own age file (serve password in `.chezmoitemplates/opencode-serve-password.age`) |
| `opencode-tunnel-primary55522.service` | autossh `-L 14001:127.0.0.1:4096 primary55522` |
| `opencode-tunnel-kali.service` | autossh `-L 14002:127.0.0.1:4096 kali` |
| `opencode-tunnel-kalione.service` | autossh `-L 14003:127.0.0.1:4096 kalione` |

Tunnel hardening flags: `-M 0` (systemd owns restarts; no monitoring port),
`ServerAliveInterval=15 ServerAliveCountMax=3` (dead-peer detection),
`ExitOnForwardFailure=yes`, `AUTOSSH_GATETIME=0` (start even if network flaps),
`Restart=on-failure RestartSec=5`, `ConditionFileIsExecutable=/usr/bin/autossh`
(unit skips cleanly on a host without autossh instead of restart-looping).

## Per-host application (hostname-gated)

`.chezmoiignore` drops each host's own-target tunnel unit, so each node
applies only the units that tunnel to the OTHER nodes:

| Host (hostname) | Serve | Gets tunnels to | Local endpoints |
|---|---|---|---|
| kalione (`InspironOne`) | 4096 | primary55522, kali | 14001, 14002 |
| primary55522 (`primary`) | 4096 | kali, kalione | 14002, 14003 |
| kali (`CabinInspiron22Kali`) | 4096 | primary55522, kalione | 14001, 14003 |

Enablement is idempotent: `run_fleet-tunnels.sh` (runs on every `chezmoi
apply`) daemon-reloads and `enable --now`s every installed tunnel unit.

## Port assignments (sequential, localhost only)

| Local port | Remote node | SSH alias |
|---|---|---|
| 14001 | primary55522 | `primary55522` (rides cloudflared proxy, no -p) |
| 14002 | kali | `kali` (rides cloudflared proxy, no -p) |
| 14003 | kalione | `kalione` (direct port 22) |
| 14004… | future nodes | next sequential |

The remote serve port is always 4096. Local ports only need per-node uniqueness.
The SSH aliases resolve host+port via `~/.ssh/config` (cloudflared access
carries the connection; no `-p` flags needed).

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
# after chezmoi apply on a node (run_fleet-tunnels.sh already ran):
systemctl --user restart opencode-serve.service

# validate serve: 401 on /doc = auth required = healthy
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:4096/doc

# validate tunnel: remote serve through tunnel
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:14001/doc

# tunnel diagnostics
ss -tlnp | grep -E '1400[123]'          # tunnel listening
journalctl --user -u opencode-tunnel-kali.service -n 15
```

`channel N: open failed: connect failed: Connection refused` in tunnel logs
means the tunnel is UP but the remote serve is not — deploy dotfiles on the
remote node (pull + chezmoi apply + daemon-reload + restart serve).

## Adding a node

1. Ensure the node has an SSH config alias + passphraseless key from every other node.
2. Assign the next sequential local port (14004, 14005, …).
3. Add `opencode-tunnel-<alias>.service` to `dot_config/systemd/user/` and a
   matching self-ignore rule in `.chezmoiignore` (`eq .chezmoi.hostname "<new>"`).
4. Ship; on each existing node pull + `chezmoi apply` (the run script enables the new tunnel).
5. On the new node itself: `sudo apt-get install -y autossh`, then serve + `chezmoi apply`
   (hostname gating brings its own tunnels to the others).

## Agent-to-agent usage

Use the small `fleet-chat` adapter for agent-to-agent prompts:

```bash
fleet-chat list-nodes
fleet-chat send --node primary55522 --prompt "Please inspect the failing job"
fleet-chat latest --node primary55522 --session <session-id>
```

`send` creates a remote session with `POST /api/session` unless an existing
session is supplied, then sends the machine-readable admission request:

```http
POST /api/session/{id}/prompt
Content-Type: application/json

{"prompt":{"text":"..."},"resume":false}
```

The successful `200 application/json` response includes `admittedSeq`, the
message id, `sessionID`, prompt, delivery, and `timeCreated`. For completion
events use SSE `GET /api/event` or `GET /api/session/{id}/event`; for the V1
message/parts representation read `GET /session/{id}/message`. `fleet-chat
latest` returns the newest assistant response and truncates long text unless
`--full` is supplied.

For fire-and-forget delivery, the correct V1 route is
`POST /session/{id}/prompt_async` (without `/api`), which returns `204 No
Content`. `POST /api/session/{id}/prompt_async` is incorrect and is not a
registered route: it falls through to the TUI SPA and returns `200 text/html`.
This path distinction is the known source of the old HTML symptom.

The adapter uses Basic auth only against these localhost/tunnel endpoints and
loads `OPENCODE_SERVER_USERNAME/PASSWORD` from the mode-0600
`~/.config/opencode/opencode-serve.env`. Credentials are never command-line
arguments, output, logs, URLs, or committed files. Scratch sessions must be
deleted after testing with `DELETE /session/{id}`; do not enumerate or mutate
another agent's existing sessions without an ownership contract.
