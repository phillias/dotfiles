# Fleet Mesh — opencode serve cross-node transport

Fleet nodes (kalione, primary, kali, oci1) each run a headless `opencode serve`
on port 4096. WARP mesh is the primary inter-node transport: every node
reaches every other node's serve directly at `<node>.mesh:4096`. The autossh
tunnel layer that used to forward localhost `:14001-14004` to each remote
serve is RETIRED. cloudflared is reserved for break-the-glass SSH access from
an administrator's laptop.

## Architecture

```
  kalione ──WARP mesh──> primary.mesh:4096     kali ──WARP mesh──> oci1.mesh:4096
  primary ──WARP mesh──> kali.mesh:4096        ...  every node -> every other node
```

- `<node>.mesh` resolves through the fleet dnsmasq: `dot_config/dnsmasq/d/mesh-hosts.tmpl`
  seeds it from each node's `mesh_ip` in `.chezmoidata/fleet.toml`, and
  `mesh-ddns` rewrites it at runtime from the live WARP Mesh IPs.
- TCP/4096 is accepted by the chezmoi hook `run_onchange_fleet-firewall.sh.tmpl`
  (port list `.fleet.ports` in `fleet.toml`, alongside rate-limited :22/:2022).

## Units (chezmoi: `dot_config/systemd/user/`)

| Unit | Purpose |
|---|---|
| `opencode-serve.service` | `opencode serve --port 4096 --hostname 0.0.0.0`, rooted at `~/firstmate` for hosted sessions and using the shared `~/.config/opencode` config tree plus the serve-only `~/.config/opencode/opencode-serve.json` `OPENCODE_CONFIG` overlay; EnvironmentFile reads `~/.config/opencode/opencode-serve.env` (OPENCODE_SERVER_PASSWORD etc.) — rendered by chezmoi template `private_opencode-serve.env.tmpl`, age-decrypting each secret from its own age file (serve password in `.chezmoitemplates/opencode-serve-password.age`) |

The four `opencode-tunnel-{primary,kali,kalione,oci1}.service` autossh units
are no longer shipped. `run_fleet-tunnels.sh` (runs on every `chezmoi apply`)
disables and removes any tunnel unit still deployed on a host (a unit whose
`disable --now` fails is kept and fails the apply, so the next apply retries),
daemon-reloads, `enable --now`s `opencode-serve.service`, and fails the apply if
any deployed opencode unit is still disabled. autossh is no longer a node prerequisite.

## SSH aliases

The `fleet-*` SSH aliases are DATA-DRIVEN: `dot_ssh/config.tmpl` renders one
Host block per `.fleet.nodes` entry in `.chezmoidata/fleet.toml`
(`ssh_alias`, `access_host`, `ssh_user`), so registering a node in fleet.toml
gives every fleet node its alias on next apply. `tunnel_port` is kept in
fleet.toml as a record of the retired tunnel's local port; nothing consumes it.

## Operations

```bash
# after chezmoi apply on a node (run_fleet-tunnels.sh already ran):
systemctl --user restart opencode-serve.service

# validate serve: 401 on /doc = auth required = healthy
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:4096/doc

# validate a remote serve over the mesh
curl -s -o /dev/null -w '%{http_code}\n' http://primary.mesh:4096/doc

# mesh diagnostics
getent hosts primary.mesh                 # mesh DNS resolves
sudo iptables -S INPUT | grep 4096        # firewall hook applied
```

A connection refused on `<node>.mesh:4096` with DNS resolving means the remote
serve is down or its firewall hook has not run — deploy dotfiles on the remote
node (pull + chezmoi apply + restart serve).

## Adding a node

1. Run `scripts/setup.sh` on the new node. Its fleet-registration PR
   (Phase 6b) adds the `fleet.toml` node entry WITH mesh fields
   (`ssh_alias`, `access_host`, `ssh_user`, `mesh_ip`) and the per-host
   restic password.
2. Merge the PR. Every EXISTING node picks up the new node's alias
   (data-driven `fleet-*` block in `dot_ssh/config.tmpl`) and its
   `<node>.mesh` entry on next sync+apply.
3. On the new node itself, setup.sh Phase 7b (post-apply) probes every
   fleet alias with accept-new to record host keys into
   `~/.ssh/known_hosts`, syncs all `chezmoi@*` deploy keys from
   phillias/dotfiles into `~/.ssh/authorized_keys` (so every node can SSH
   in), and enables `opencode-serve.service`.
4. Add the node to the `fleet-chat` built-in map
   (`dot_local/bin/executable_fleet-chat`) or a `fleet-chat.nodes` file.
   Validate per Operations above.

## Agent-to-agent usage

Use the small `fleet-chat` adapter for agent-to-agent prompts:

```bash
fleet-chat list-nodes
fleet-chat send --node primary --prompt "Please inspect the failing job"
fleet-chat latest --node primary --session <session-id>
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

The adapter uses Basic auth only against these local/mesh endpoints and
loads `OPENCODE_SERVER_USERNAME/PASSWORD` from the mode-0600
`~/.config/opencode/opencode-serve.env`. Credentials are never command-line
arguments, output, logs, URLs, or committed files. Scratch sessions must be
deleted after testing with `DELETE /session/{id}`; do not enumerate or mutate
another agent's existing sessions without an ownership contract.
