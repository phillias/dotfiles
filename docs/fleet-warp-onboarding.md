# Fleet WARP Onboarding — Greenfield Node Runbook

Bringing a new Linux node into the WARP Mesh fleet: enroll the WARP client in
Cloudflare Zero Trust, expose `opencode serve` on the node's Mesh IP, and
register the node in every peer's `fleet-chat.nodes`.

Three steps, in order. Each has a verification gate — do not proceed to the
next step until the current one passes. An operator shell with `sudo` and a
login user on the new node is assumed throughout.

## Prerequisites

Confirm all four before starting.

**Cloudflare Zero Trust account** — the fleet's team name is the
`organization` value (`phillias`). The account already has:

- A **device enrollment rule** using the **Service Auth** action (not plain
  Allow). A plain Allow rule enrolls but yields a null org in `registration
  show` and a device that cannot authenticate.

**BWS enrollment secrets** — the service token pair lives in the BWS project
`phillias`:

| Key | Purpose |
|---|---|
| `WARP_FLEET_ENROLLMENT_CLIENT_ID` | MDM `auth_client_id` |
| `WARP_FLEET_ENROLLMENT_CLIENT_SECRET` | MDM `auth_client_secret` |

Read them with `bws-axi` (values redacted by default; never paste them into
shell history or commit them):

```bash
bws-axi secret phillias WARP_FLEET_ENROLLMENT_CLIENT_ID --full
bws-axi secret phillias WARP_FLEET_ENROLLMENT_CLIENT_SECRET --full
```

**SSH access** — a login account with passwordless `sudo` on the node, plus
`fleet-*` SSH aliases already present in `~/.ssh/config` if the node is also
reached over SSH.

**Target port free** — the node's `opencode serve` will bind `:4096`. Confirm
nothing else holds it: `ss -tlnp | grep 4096` should print nothing (or only
the serve you are about to restart).

## Step 1: WARP enrollment

### 1a. Add the cloudflareclient apt source

Debian bookworm. The keyring and the source file are system paths.

```bash
sudo mkdir -p /usr/share/keyrings /etc/apt/sources.list.d
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ bookworm main" \
  | sudo tee /etc/apt/sources.list.d/cloudflare-client.list
sudo apt-get update
```

Confirm the candidate comes from Cloudflare:

```bash
apt-cache policy cloudflare-warp   # expect a 500 from pkg.cloudflareclient.com bookworm/main
```

### 1b. Install the client

```bash
sudo apt-get install -y cloudflare-warp
warp-cli --version
```

### 1c. Write the MDM enrollment file

The chezmoi `run_onchange_warp-mdm.sh.tmpl` hook sources
`WARP_FLEET_ENROLLMENT_CLIENT_ID` and
`WARP_FLEET_ENROLLMENT_CLIENT_SECRET` from `load-keys.sh`, then writes
`/var/lib/cloudflare-warp/mdm.xml` as a root-owned mode-`0600` file. It fails
when either credential is unavailable so a later apply can retry. On Linux it
also restarts `warp-svc.service` after writing the file.

Verify the key names landed (values are deliberately not printed):

```bash
sudo grep -o '<key>[^<]*</key>' /var/lib/cloudflare-warp/mdm.xml
```

Expect these keys: `organization`, `auth_client_id`, `auth_client_secret`,
`onboarding`, `switch_locked`, `auto_connect`, and `service_mode`.

> **Gotcha.** The keys are `auth_client_id` and `auth_client_secret` — not
> `unique_client_id`/`unique_client_secret`, and not the
> `warp_fleet_enrollment_*` names used by the removed
> `scripts/install-warp-fleet.sh` (superseded by
> `run_onchange_warp-mdm.sh.tmpl`). The MDM file is the enrollment credential
> source; wrong key names silently produce an unenrolled device.
>
> `organization` is the Cloudflare Zero Trust **team name** (here `phillias`),
> not a UUID and not the account ID.

### 1d. Enroll

`--accept-tos` is a **global** `warp-cli` flag and must precede the
subcommand.

```bash
sudo warp-cli --accept-tos registration new phillias
sudo warp-cli --accept-tos connect
```

Accepting the terms once at enrollment is what lets the remaining
`--accept-tos` calls (and unattended restarts) run non-interactively.

If enrollment fails with `ApiMismatch(Invalidated)`, the device enrollment
rule is wrong — Settings → Devices → Device enrollment must use **Service
Auth**. The first dashboard save sometimes does not persist; re-open the rule,
confirm the action, and save again.

### 1e. Verify enrollment

```bash
warp-cli --accept-tos status
warp-cli --accept-tos registration show
```

`status` should report `Status update: Connected` and `Network: healthy`.

`registration show` should report `Organization: phillias`, a non-null
`Account ID`, and a non-null `Device ID`. A null `Organization` here means the
enrollment rule action is wrong, even if status is Connected.

### 1f. Report the Mesh IP

```bash
ip -4 addr show CloudflareWARP
```

Look for an address in `100.96.0.0/12` (typically `100.96.0.x/32` on the
`CloudflareWARP` point-to-point interface). Record it as `<mesh-ip>` — Step 3
and the verification section use it.

Note the WARP split-tunnel default is **Exclude** mode with RFC 1918 ranges
(`10/8`, `172.16/12`, `192.168/16`) excluded. Docker bridge networks and LAN
services therefore keep working, and the Mesh routes are additive to that
exclude list.

## Step 2: opencode-serve bind

`opencode serve` must listen on `0.0.0.0` so Mesh peers can reach it. A
`127.0.0.1` bind makes the port invisible off-box even when the Mesh route is
correct.

The unit is `~/.config/systemd/user/opencode-serve.service` on the node (the
chezmoi source is `dot_config/systemd/user/opencode-serve.service`). Edit the
`ExecStart` line:

```ini
# before
ExecStart=%h/.local/share/mise/shims/opencode serve --port 4096 --hostname 127.0.0.1 --log-level WARN

# after
ExecStart=%h/.local/share/mise/shims/opencode serve --port 4096 --hostname 0.0.0.0 --log-level WARN
```

The chezmoi hook `run_onchange_fleet-firewall.sh.tmpl` accepts TCP/4096 in
iptables INPUT (port list `.fleet.ports` in `.chezmoidata/fleet.toml`) and
persists it to `/etc/iptables/rules.v4`, so a node that has run `chezmoi
apply` needs no manual firewall change.

Then reload and restart:

```bash
systemctl --user daemon-reload
systemctl --user restart opencode-serve.service
systemctl --user is-active opencode-serve.service
```

Verify the bind. You want the serve line to read `0.0.0.0:4096`, not
`127.0.0.1:4096`:

```bash
ss -tlnp | grep 4096
```

Also confirm the service answers (401 on `/doc` = auth required = healthy):

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:4096/doc
```

> **Gotcha.** The committed chezmoi source already carries `--hostname
> 0.0.0.0` on the default branch (changed 2026-11-14 for #577). A freshly
> applied node therefore usually needs only the `daemon-reload` + restart, and
> the edit is a no-op. Check the deployed unit before editing — do not assume
> either value. A host that has drifted back to `127.0.0.1` (local edit,
> reverted branch) is the real case this step exists for.

## Step 3: fleet-chat nodes

`fleet-chat`'s built-in map already covers the core nodes over Mesh
(`primary`, `kali`, `kalione`, `oci1` at `http://<node>.mesh:4096`). A node
outside that map needs a `fleet-chat.nodes` entry (or a map update in
`dot_local/bin/executable_fleet-chat`).

Every node that should reach the new node keeps a `fleet-chat.nodes` file next
to its serve auth env — by default
`~/.config/opencode/fleet-chat.nodes` (i.e. alongside
`~/.config/opencode/opencode-serve.env`).

Format: one `name=url` per line. Blank lines and lines beginning with `#` are
ignored. The name must match `[A-Za-z0-9_.-]+`; the URL must be
`http://` or `https://`.

Add the new node using its Mesh IP from Step 1f:

```bash
# ~/.config/opencode/fleet-chat.nodes  (on every peer that must reach the node)
local=http://127.0.0.1:4096
primary=http://primary.mesh:4096
kali=http://kali.mesh:4096
kalione=http://kalione.mesh:4096
oci1=http://oci1.mesh:4096
newton=http://<mesh-ip>:4096
```

Create the file if it does not exist. If `FLEET_CHAT_NODES` is set in the
environment it takes precedence over the file — either unset it or add the
entry there too.

Verify from the peer:

```bash
fleet-chat list-nodes
```

The new node should appear with status `healthy`.

> `fleet-chat` reads its auth from `~/.config/opencode/opencode-serve.env`,
> which must be mode `0600`; if `list-nodes` dies on permissions, fix the mode
> rather than the node entries.

## Verification

Run these from a peer that is already Mesh-enrolled and has the node in its
`fleet-chat.nodes`.

**Mesh reachability — serve port:**

```bash
nc -zv <mesh-ip> 4096     # expect "open"
```

**Mesh reachability — SSH (fallback path):**

```bash
nc -zv <mesh-ip> 22       # expect "open"
```

**fleet-chat sees every node healthy:**

```bash
fleet-chat list-nodes
```

**End-to-end prompt round-trip** (optional but the real proof):

```bash
fleet-chat send --node <name> --prompt "ping"
fleet-chat latest --node <name> --session <session-id>
```

## Fallback and rollback

The autossh tunnel layer is **retired**: WARP Mesh is the primary inter-node
transport. The `opencode-tunnel-<node>.service` units are no longer shipped,
and `run_fleet-tunnels.sh` disables and removes any that are still deployed on
the next `chezmoi apply` (including the automatic `chezmoi-sync-cron` run).
No manual tunnel stop/disable/move is needed.

If Mesh connectivity to a node fails, diagnose the Mesh path rather than
falling back to tunnels:

```bash
getent hosts <node>.mesh            # mesh DNS resolves (dnsmasq + mesh-ddns)
nc -zv <node>.mesh 4096             # serve reachable
sudo iptables -S INPUT | grep 4096  # on the node: fleet firewall hook applied
```

Restoring the tunnels is a dotfiles revert of the retirement change (units,
their `.chezmoiignore` self-ignores, and the `run_fleet-tunnels.sh`
enablement), not a per-host procedure.

## Out of scope for this runbook

- CIDR routes, Access private apps, and Gateway network rules per node.
- `kalione`/`phillias.org` specifics, cloudflared tunnel config, DNS records,
  and nftables rules.
- The `warp-fleet` skill update.
