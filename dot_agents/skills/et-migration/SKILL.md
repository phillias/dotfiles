---
name: et-migration
description: Migrate a fleet node from sslh port-demux to the no-sslh direct pattern behind a cloudflared orange-cloud tunnel, with rescue sshd on a grey-cloud DNS record. Use when executing a per-node slice from dotfiles issue #577.
---

# ET Migration (sslh → no-sslh + cloudflared)

Execute a per-node slice of dotfiles #577: retire sslh, move ET+SSH behind a
cloudflared orange-cloud tunnel, optionally provision rescue sshd on :10022 via
grey-cloud DNS.

## Prerequisites (before starting any slice)

- Captain confirmed CF DNS records for this node (orange-cloud for et+ssh,
  grey-cloud for rescue sshd)
- Captain confirmed tunnel route points to this node
- Rollback snapshot exists
- Captain-approved execution window
- If node has iptables rate limiting: #602 loopback-exemption patch merged+applied

## Slice checklist

1. **Pre-flight**: record current state
   ```bash
   systemctl is-active sslh et sshd
   ss -tlnp | grep -E ':(22|2022|55554)\b'
   ```

2. **Rescue sshd** (if captain confirmed for this node):
   - Deploy minimal sshd_config to `/etc/ssh/sshd_config_rescue`
     (no rate limiting, no ET, `PasswordAuthentication no`, `Port 10022`)
   - Deploy `sshd-rescue.service` system unit (no `Conflicts=sshd.service`)
   - `sudo systemctl enable --now sshd-rescue.service`
   - Verify: `ssh -p 10022 <node>` responds
   - **Never modify, reconfigure, or depend on sshd-rescue during migration**

3. **Cloudflared tunnel** (if not already locally-managed):
   - If currently token-based (remotely managed), convert to locally-managed:
     ```bash
     cloudflared tunnel ingress validate
     # Copy existing config from dashboard or create config.yml
     ```
   - Ensure tunnel config has ingress for SSH (port 22) and ET (port 2022)
   - Restart cloudflared tunnel service
   - Verify: `cloudflared access tcp --hostname <node> --url 127.0.0.1:2222`
     then `ssh -p 2222 <user>@localhost` succeeds

4. **Deactivate sslh**:
   ```bash
   sudo systemctl stop sslh
   sudo systemctl disable sslh
   sudo rm -f /etc/sslh.cfg /etc/default/sslh /etc/systemd/system/sslh.service
   sudo systemctl daemon-reload
   ```

5. **Reconfigure ET** (if still bound to 127.0.0.1):
   - Update `/etc/et.cfg`: `port = 2022`, `bind_ip` unset (0.0.0.0)
   - `sudo systemctl restart et`

6. **Validate in-node**:
   ```bash
   systemctl is-active sslh    # inactive/not-found
   systemctl is-active et      # active
   ss -tlnp | grep ':2022'     # 0.0.0.0:2022
   ```

7. **External validation**:
   - From another fleet node: `ssh fleet-<node>` succeeds
   - From laptop: `cloudflared access ssh --hostname <node>` succeeds
   - Rescue sshd: `ssh -p 10022 <node>` responds (if provisioned)

8. **Attest**: sha256-prefix lines only

## Node-specific scripts

| Node | Script | Notes |
|------|--------|-------|
| oci1 | `scripts/install-et-no-sslh.sh` | Reference implementation (user: ubuntu) |
| kali | `scripts/install-et-no-sslh-phillias.sh` | Kali adaptation (user: phillias, removes legacy :55554) |
| kalione | Manual (canary complete) | Already locally-managed tunnel |
| primary55522 | Captain gate | Last or skip |

## Safety rules

- **sshd-rescue is always pristine** — no migration step touches it
- If any validation step fails, stop and report. Do not continue.
- Captain gates: CF DNS, tunnel routes, rescue sshd provisioning, execution windows
- sslh installer removal is a fleet-wide final step, not per-node

## Related

- Issue #577 (this workstream)
- Issue #597 (closed by fleet-chat mesh rework in warp-fleet skill)
- `dot_agents/skills/cloudflare-one/SKILL.md` (general CF One reference)
- `dot_agents/skills/dotfiles/refs/FLEET-TUNNELS.md` (current fleet mesh doc)
