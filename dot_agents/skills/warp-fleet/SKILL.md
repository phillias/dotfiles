---
name: warp-fleet
description: Install and enroll WARP client on a fleet node, verify Mesh IP, and rework fleet-chat from autossh SSH tunnels to Cloudflare Mesh (WARP private network routes). Use when executing fleet-chat mesh rework from dotfiles issue #577, installing WARP on a new fleet node, or troubleshooting Mesh connectivity.
---

# WARP Fleet Mesh

Install WARP client, enroll in Zero Trust, verify Mesh IP, and rework
fleet-chat from autossh SSH tunnels to Cloudflare Mesh direct connectivity.

## Architecture change

```
Before: fleet-chat → localhost:14xxx → autossh SSH → cloudflared access ssh → CF edge → remote:4096
After:  fleet-chat → remote:4096 via Mesh IP/CIDR route → CF edge → cloudflared on remote → localhost:4096
```

macOS (captain workstation, not a fleet node): `cloudflared access tcp` forward
replaces autossh+SSH. Simpler, same reliability, no WARP client needed.

## Per-node WARP installation

### 1. Add cloudflareclient apt source (Debian/Kali)

```bash
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ bookworm main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list
sudo apt-get update
```

### 2. Install WARP client

```bash
sudo apt-get install -y cloudflare-warp
```

### 3. Write MDM enrollment file

Service token keys from bws project `phillias`:
- `WARP_FLEET_ENROLLMENT_CLIENT_ID`
- `WARP_FLEET_ENROLLMENT_CLIENT_SECRET`

```bash
sudo mkdir -p /var/lib/cloudflare-warp
sudo tee /var/lib/cloudflare-warp/mdm.xml > /dev/null <<'EOF'
<dict>
  <key>warp_fleet_enrollment_client_id</key>
  <string>CLIENT_ID_VALUE</string>
  <key>warp_fleet_enrollment_client_secret</key>
  <string>CLIENT_SECRET_VALUE</string>
</dict>
EOF
sudo chmod 600 /var/lib/cloudflare-warp/mdm.xml
```

### 4. Enroll in Zero Trust

```bash
warp-cli registration new phillias
```

If `ApiMismatch(Invalidated)`: CF Zero Trust dashboard → Settings → Devices →
Device enrollment → rule must use **Service Auth** action (not just Allow).
First save may not persist — verify and save again if needed.

### 5. Verify enrollment

```bash
warp-axi status
warp-axi registration show
```

Expected: Connected, NetworkHealthy, managed=true, organization=phillias,
Mesh IP in 100.96.0.0/12 range.

### 6. Captain: Configure CF-side routing

For each node, the captain creates 3 things in the CF Zero Trust dashboard:

1. **CIDR route**: Networks → Tunnels → Routes → Add route
   - CIDR: e.g., `192.168.1.224/32` (kalione) or node's LAN IP
   - Tunnel: select the node's cloudflared tunnel

2. **Access private app**: Access → Applications → Add an application →
   Private app
   - Application name: descriptive (e.g., "kalione-lan")
   - Destination: the CIDR range
   - `allow_authenticate_via_warp`: true

3. **Gateway network allow rule**: Gateway → Firewall Policies → Network →
   Add rule
   - Action: Allow
   - Destination: the CIDR range
   - Filters: `l4` (network-layer)

All 3 are required. Missing any one causes silent routing failure.

### 7. Verify Mesh reachability

From another Mesh-enrolled device:
```bash
nc -zv <mesh-ip-or-cidr-host> 4096
```

## CF API token for Mesh route management

Minimum account-level permissions for an API token that can manage CIDR routes,
Access apps, and Gateway rules:

| Permission (API) | Permission (Dashboard) | Covers |
|---|---|---|
| `Cloudflare One Networks Write` | Cloudflare One Networks Edit | Tunnel route CRUD |
| `Access: Apps and Policies Write` | Access: Apps and Policies Edit | Access app + policy CRUD |
| `Zero Trust Write` | Zero Trust Edit | Gateway network rule CRUD |

All are account-level. Access apps for WARP routes use
`/accounts/{id}/access/apps` (account path, not zone).

## warp-cli critical gotcha

`--json` / `-j` is a **global flag** that must appear BEFORE the subcommand:

```bash
warp-cli -j status       # ✅ correct
warp-cli status --json   # ❌ silently ignored, returns text
```

Use `warp-axi` which handles this internally via `callWarpJson()`.

## warp-axi commands

```bash
warp-axi status              # connection status + enrollment info
warp-axi registration show   # enrollment details (org, managed, device ID)
warp-axi connect             # connect to Zero Trust
warp-axi disconnect          # disconnect
warp-axi tunnel dump         # split tunnel route list
warp-axi tunnel stats        # tunnel endpoint stats
warp-axi settings            # client settings display
warp-axi debug               # network diagnostics
```

Output is TOON by default; `--json` for raw JSON. Exit codes: 0=success, 1=error, 2=usage.

## Fleet-chat mesh rework steps

### Step 1: Validate Mesh connectivity between nodes

After both nodes are WARP-enrolled and have CIDR routes:
```bash
# From kalione to kali
nc -zv <kali-mesh-ip-or-cidr> 4096

# From kali to kalione
nc -zv <kalione-mesh-ip-or-cidr> 4096
```

### Step 2: Update fleet-chat node discovery

fleet-chat resolves nodes from `$FLEET_CHAT_NODES` or its built-in map.
Replace `localhost:14xxx` entries with Mesh-reachable addresses (Mesh IPs or
CIDR-routed LAN IPs on port 4096).

### Step 3: Validate fleet-chat over Mesh

```bash
fleet-chat list-nodes                        # all nodes reachable
fleet-chat send --node <peer> --prompt "ping"
fleet-chat latest --node <peer> --session <id>
```

### Step 4: Remove autossh tunnel units

Once fleet-chat works over Mesh for a node pair:
```bash
systemctl --user stop opencode-tunnel-<node>.service
systemctl --user disable opencode-tunnel-<node>.service
rm ~/.config/systemd/user/opencode-tunnel-<node>.service
systemctl --user daemon-reload
```

### Step 5: macOS captain workstation

Replace autossh SSH tunnel with cloudflared access tcp forward:
```bash
# New unit: cloudflared-tunnel-<node>.service
cloudflared access tcp --hostname <node-access-host> --url localhost:14xxx
```

Same localhost:14xxx → remote:4096 forwarding, minus the SSH+autossh layer.

### Step 6: Cleanup

- Remove `autossh` from node prerequisites
- Remove `opencode-tunnel-*.service` templates from dotfiles
- Update `run_fleet-tunnels.sh` (remove autossh enablement)
- Update FLEET-TUNNELS.md
- Close #597

## Safety rules

- **sshd-rescue is always pristine** — never touched by Mesh rework
- If Mesh connectivity fails, autossh tunnels remain as fallback until
  diagnosis completes
- Captain gates: CIDR routes, Access apps, Gateway rules, WARP enrollment
  approval
- Rollback: re-enable autossh tunnel units if Mesh proves unreliable

## WARP split tunnel behavior

Default mode is **Exclude**: RFC 1918 ranges (10/8, 172.16/12, 192.168/16) are
excluded from the WARP tunnel. This means:
- Docker bridge networks (172.17.x.x etc.) work unaffected
- LAN services accessible directly, not through Mesh
- Mesh-reachable CIDR routes are ADDITIONS to the exclude list, routed through
  CF edge
- MTU is a non-issue for Docker: container traffic doesn't transit the mesh

## WARP DNS proxy

WARP client binds `127.0.2.2` and `127.0.2.3` on port 53 as a local DNS proxy,
taking over host DNS resolution. Opt-out mechanisms:
- **Local Domain Fallback**: send specific domains to a private resolver
- **Split Tunnels Exclude**: exclude CIDRs/domains from WARP (IP only, not DNS)
- Split tunnels only affect IP traffic, not DNS — DNS still goes to Gateway
  unless Local Domain Fallback configured

## Rollout order (from #577)

1. kalione canary — ✅ COMPLETE
2. External client validation (macbook + android)
3. kali WARP/MDM enrollment
4. Prove fleet-chat (kalione ↔ kali via Mesh)
5. Remaining fleet

## Related

- Issue #577 (parent issue)
- Issue #597 (closed by this rework)
- Issue #508 (fleet-chat protocol guardrails)
- `dot_agents/skills/et-migration/SKILL.md` (sslh retirement slice)
- `dot_agents/skills/cloudflare-one/SKILL.md` (general CF One reference)
- `dot_agents/skills/dotfiles/refs/FLEET-TUNNELS.md` (current fleet mesh doc)
- `@masculinecache/warp-axi` on npm (warp-cli TOON wrapper)
