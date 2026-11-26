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
reached over the tunnel fallback.

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

The file is `/var/lib/cloudflare-warp/mdm.xml`, mode `0600`, root-owned.

Start Bash for this block; do not paste it into the assumed zsh login shell:

```bash
sudo mkdir -p /var/lib/cloudflare-warp
if ! read -r -p 'Client ID: ' CLIENT_ID < /dev/tty || [[ -z "$CLIENT_ID" ]]; then
  printf 'Client ID is required\n' >&2
  exit 1
fi
if ! read -r -s -p 'Client secret: ' CLIENT_SECRET < /dev/tty || [[ -z "$CLIENT_SECRET" ]]; then
  printf '\nClient secret is required\n' >&2
  exit 1
fi
printf '\n' >&2
sudo install -o root -g root -m 600 /dev/null /var/lib/cloudflare-warp/mdm.xml
{
  printf '<dict>\n  <key>organization</key>\n  <string>phillias</string>\n'
  printf '  <key>auth_client_id</key>\n  <string>%s</string>\n' "$CLIENT_ID"
  printf '  <key>auth_client_secret</key>\n  <string>%s</string>\n</dict>\n' "$CLIENT_SECRET"
} | sudo tee /var/lib/cloudflare-warp/mdm.xml > /dev/null
unset CLIENT_ID CLIENT_SECRET
```

Enter the two BWS values only at the prompts; do not put them in a command or
heredoc. The block exits before creating the file if either value is empty.
Verify the key names landed (values are deliberately not printed):

```bash
sudo grep -o '<key>[^<]*</key>' /var/lib/cloudflare-warp/mdm.xml
```

Expect exactly three keys: `organization`, `auth_client_id`,
`auth_client_secret`.

> **Gotcha.** The keys are `auth_client_id` and `auth_client_secret` — not
> `unique_client_id`/`unique_client_secret`, and not the
> `warp_fleet_enrollment_*` names used by the older
> `scripts/install-warp-fleet.sh`. The MDM file is the enrollment credential
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
primary=http://127.0.0.1:14001
kali=http://100.96.0.3:4096
kalione=http://100.96.0.2:4096
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

Keep the autossh tunnel units on disk but **stopped and disabled** until Mesh
proves reliable over a few days of real traffic:

```bash
systemctl --user stop opencode-tunnel-<node>.service
systemctl --user disable opencode-tunnel-<node>.service
```

`run_fleet-tunnels.sh` enables and starts every installed tunnel on each
`chezmoi apply`. The automatic `chezmoi-sync-cron` job runs every 30 minutes,
running `chezmoi-axi sync --force` and re-applying the chezmoi source. The
tunnel unit is managed source at
`dot_config/systemd/user/opencode-tunnel-<node>.service`, so stopping,
disabling, or moving it aside alone is undone by the next sync. Suspend the
automatic sync for the reliability period; the node will not receive dotfiles
updates while it is suspended:

```bash
crontab -l | grep -v chezmoi-sync-cron | crontab -
```

Then move each unit out of `~/.config/systemd/user/` so the hook's glob cannot
find it during the reliability period:

```bash
mkdir -p ~/.config/systemd/user-disabled
mv ~/.config/systemd/user/opencode-tunnel-<node>.service ~/.config/systemd/user-disabled/
systemctl --user daemon-reload
```

The unit remains on disk, but is outside the apply hook's scan path. Do not
`rm` it or run a manual apply that restores it during this period.

To roll back to the tunnels, first point fleet-chat back at them, then move
each unit back, reload, and re-enable and start it.

In `~/.config/opencode/fleet-chat.nodes`, restore each affected entry to its
tunnel's localhost forward, for example:

```text
primary=http://127.0.0.1:14001
kali=http://127.0.0.1:14002
kalione=http://127.0.0.1:14003
oci1=http://127.0.0.1:14004
```

If `FLEET_CHAT_NODES` is set, restore the corresponding entry there too:

```text
<node>=http://127.0.0.1:<local-forward-port>
```

```bash
mv ~/.config/systemd/user-disabled/opencode-tunnel-<node>.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now opencode-tunnel-<node>.service
```

If Mesh is unreliable and this rollback completes, restore automatic sync
immediately:

```bash
( crontab -l 2>/dev/null; echo '*/30 * * * * /bin/sh -c ". $HOME/.profile; chezmoi-sync-cron"' ) | crontab -
```

After Mesh is proven reliable, restore the automatic sync entry:

```bash
( crontab -l 2>/dev/null; echo '*/30 * * * * /bin/sh -c ". $HOME/.profile; chezmoi-sync-cron"' ) | crontab -
```

Use the existing local-forward port for the node (`14001` for
`primary`, `14002` for `kali`, `14003` for `kalione`, `14004` for
`oci1`, and the next assigned port for a new node), then run
`fleet-chat list-nodes` to verify the tunnel path.

## Out of scope for this runbook

- CIDR routes, Access private apps, and Gateway network rules per node.
- `kalione`/`phillias.org` specifics, cloudflared tunnel config, DNS records,
  and nftables rules.
- The `warp-fleet` skill update.
