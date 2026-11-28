---
name: et-migration
description: Migrate a fleet node from sslh port-demux to the no-sslh direct pattern behind a cloudflared orange-cloud tunnel. Use when executing a per-node slice from dotfiles issue #577.
---

# ET Migration (sslh → no-sslh + cloudflared)

Execute a per-node slice of dotfiles #577: retire sslh, move ET+SSH behind a
cloudflared orange-cloud tunnel.

Each tunnel exposes only SSH (port 22) and ET (port 2022) via Access-gated
ingress rules. Rescue sshd has been decommissioned across the fleet.

## Prerequisites (before starting any slice)

- Captain confirmed CF DNS records for this node (orange-cloud for et+ssh)
- Captain confirmed tunnel route points to this node
- Rollback snapshot exists
- Captain-approved execution window
- iptables rate limiting is owned by the chezmoi hook `run_onchange_fleet-firewall.sh.tmpl`
  (loopback/Docker exemptions included); confirm `chezmoi apply` has run on the node

## Slice checklist

1. **Pre-flight**: record current state
   ```bash
   systemctl is-active sslh et sshd
   ss -tlnp | grep -E ':(22|2022|55554)\b'
   ```

2. **Cloudflared tunnel** (if not already locally-managed):
   - If currently token-based (remotely managed), convert to locally-managed:
     ```bash
     cloudflared tunnel ingress validate
     # Copy existing config from dashboard or create config.yml
     ```
   - Ensure tunnel config has ingress for SSH (port 22) and ET (port 2022)
   - Restart cloudflared tunnel service
   - Verify: `cloudflared access tcp --hostname <node> --url 127.0.0.1:2222`
     then `ssh -p 2222 <user>@localhost` succeeds

3. **Deactivate sslh**:
   ```bash
   sudo systemctl stop sslh
   sudo systemctl disable sslh
   sudo rm -f /etc/sslh.cfg /etc/default/sslh /etc/systemd/system/sslh.service
   sudo systemctl daemon-reload
   ```

4. **Reconfigure ET** (if still bound to 127.0.0.1):
   - Update `/etc/et.cfg`: `port = 2022`, `bind_ip` unset (0.0.0.0)
   - `sudo systemctl restart et`

5. **Validate in-node**:
   ```bash
   systemctl is-active sslh    # inactive/not-found
   systemctl is-active et      # active
   ss -tlnp | grep ':2022'     # 0.0.0.0:2022
   ```

6. **External validation**:
   - From another fleet node: `ssh fleet-<node>` succeeds
   - From laptop: `cloudflared access ssh --hostname <node>` succeeds

7. **Attest**: sha256-prefix lines only

## Node-specific scripts

| Node | Script | Notes |
|------|--------|-------|
| oci1 | `scripts/install-fleet-networking.sh` | ubuntu variant (supersedes deprecated `install-et-no-sslh.sh`) |
| kali | `scripts/install-fleet-networking.sh` | phillias variant: removes legacy :55554 (supersedes deprecated `install-et-no-sslh-phillias.sh`) |
| kalione | Manual (canary complete) | Already locally-managed tunnel |
| primary | Complete | Tunnel `d8787ea7`, ssh.phillias.cc + et.phillias.cc |

## Safety rules

- If any validation step fails, stop and report. Do not continue.
- Captain gates: CF DNS, tunnel routes, execution windows
- sslh installer removal is a fleet-wide final step, not per-node

## Related

- Issue #577 (this workstream)
- Issue #642 (cloudflared config-managed migration)
- Issue #597 (closed by fleet-chat mesh rework in warp-fleet skill)
- `dot_agents/skills/cloudflare-one/SKILL.md` (general CF One reference)
- `dot_agents/skills/dotfiles/refs/FLEET-TUNNELS.md` (current fleet mesh doc)
