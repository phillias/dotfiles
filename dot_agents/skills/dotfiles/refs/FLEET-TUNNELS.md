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
| `opencode-serve.service` | `opencode serve --port 4096 --hostname 127.0.0.1`, rooted at `~/firstmate` for hosted sessions and using the shared `~/.config/opencode` config tree plus the serve-only `~/.config/opencode/opencode-serve.json` `OPENCODE_CONFIG` overlay; EnvironmentFile reads `~/.config/opencode/opencode-serve.env` (OPENCODE_SERVER_PASSWORD etc.) — rendered by chezmoi template `private_opencode-serve.env.tmpl`, age-decrypting each secret from its own age file (serve password in `.chezmoitemplates/opencode-serve-password.age`) |
| `opencode-tunnel-primary55522.service` | autossh `-L 14001:127.0.0.1:4096 fleet-primary55522` |
| `opencode-tunnel-kali.service` | autossh `-L 14002:127.0.0.1:4096 fleet-kali` |
| `opencode-tunnel-kalione.service` | autossh `-L 14003:127.0.0.1:4096 fleet-kalione` |
| `opencode-tunnel-oci1.service` | autossh `-L 14004:127.0.0.1:4096 fleet-oci` |

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
| kalione (`InspironOne`) | 4096 | primary55522, kali, oci1 | 14001, 14002, 14004 |
| primary55522 (`primary`) | 4096 | kali, kalione, oci1 | 14002, 14003, 14004 |
| kali (`CabinInspiron22Kali`) | 4096 | primary55522, kalione, oci1 | 14001, 14003, 14004 |
| oci1 (`oci1`) | 4096 | primary55522, kali, kalione | 14001, 14002, 14003 |

Enablement is idempotent: `run_fleet-tunnels.sh` (runs on every `chezmoi
apply`) daemon-reloads and `enable --now`s every installed tunnel unit.
`scripts/setup.sh` Phase 7b additionally installs autossh, records host keys
(accept-new probes), syncs fleet deploy keys into authorized_keys, and
enables the units on greenfield hosts.

## Port assignments (sequential, localhost only)

| Local port | Remote node | SSH alias |
|---|---|---|
| 14001 | primary55522 | `fleet-primary55522` (cloudflared access, deploy key) |
| 14002 | kali | `fleet-kali` (cloudflared access, deploy key) |
| 14003 | kalione | `fleet-kalione` (cloudflared access, deploy key) |
| 14004 | oci1 | `fleet-oci` (cloudflared access, deploy key) |
| 14005… | future nodes | next sequential |

The remote serve port is always 4096. Local ports only need per-node uniqueness.
The SSH aliases are DATA-DRIVEN: `dot_ssh/config.tmpl` renders one `fleet-*`
Host block per `.fleet.nodes` entry in `.chezmoidata/fleet.toml`
(`ssh_alias`, `access_host`, `ssh_user`, `tunnel_port`), so registering a
node in fleet.toml gives every fleet node its alias on next apply. The
`tunnel_port` value is what the node's own-target tunnel unit
(`opencode-tunnel-<node>.service`) forwards on the OTHER nodes.

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

1. Run `scripts/setup.sh` on the new node. Its fleet-registration PR
   (Phase 6b) adds the `fleet.toml` node entry WITH mesh fields
   (`ssh_alias`, `access_host`, `ssh_user`, `tunnel_port` = next
   sequential port), the per-host restic password, and (greenfield PRs)
   the node's own-target tunnel unit `opencode-tunnel-<node>.service`
   plus its `.chezmoiignore` self-ignore rule.
2. Merge the PR. Every EXISTING node picks up the new node's alias
   (data-driven `fleet-*` block in `dot_ssh/config.tmpl`) and tunnel unit
   on next sync+apply; `run_fleet-tunnels.sh` enables the unit.
3. On the new node itself, setup.sh Phase 7b (post-apply) installs
   autossh, probes every fleet alias with accept-new to record host keys
   into `~/.ssh/known_hosts`, syncs all `chezmoi@*` deploy keys from
   phillias/dotfiles into `~/.ssh/authorized_keys` (so every node can SSH
   in), and enables the tunnel units it applies (tunnels to the other
   nodes; its own-target unit is hostname-ignored).
4. Serve comes up with the standard dotfiles (`opencode-serve.service`).
   Validate per Operations below.

## Eternal Terminal (oci1: direct exposure)

ET does not ride this mesh. oci1 exposes ET directly, with no autossh tunnel,
no cloudflared and no sslh:

- `et.phillias.net` is a grey-cloud (DNS-only) A record to oci1's reserved IP
  (147.224.180.103); the OCI NSG opens TCP/22 (sshd bootstrap) and TCP/2022
  (etserver on 0.0.0.0).
- Laptop: `et -u ubuntu et-oci1` (`dot_ssh/config.tmpl` alias → `et.phillias.net:22`).
- Server setup + hardening: `scripts/install-et-no-sslh.sh` (hardening
  details: README "Eternal Terminal server setup").
- `et-55522` (`et.phillias.cc`) is stale: primary's grey-cloud IP has no :22
  listener.

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

{"prompt":{"text":"..."}}
```

The successful `200 application/json` response includes `admittedSeq`, the
message id, `sessionID`, prompt, delivery, and `timeCreated`. For completion
events use SSE `GET /api/event` or `GET /api/session/{id}/event`.
`fleet-chat latest` reads the matching V2 projection from
`GET /api/session/{id}/message`, returns the newest assistant response, and
truncates long text unless `--full` is supplied. The older V1
`GET /session/{id}/message` representation remains available for callers that
need raw message/parts data.

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
