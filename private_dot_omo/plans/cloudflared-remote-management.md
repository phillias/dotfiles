# Convert Cloudflared Tunnel to Remote Management

## Overview

Migrate the Cloudflare Tunnel from local config-file management to remote (dashboard) management. This enables dashboard log streaming, replica management, and centralized ingress configuration.

---

## Current State

| Property | Value |
|----------|-------|
| **Connection Mode** | Remote (dashboard) management ✅ |
| **Service** | User systemd (`cloudflared-tunnel.service`) |
| **Token File** | `~/.cloudflared/token` |
| **Tunnel Name** | `kalione` |
| **Tunnel ID** | `b0d2b018-be3e-49aa-958e-0b819fd2d6c9` |
| **cloudflared** | 2026.7.3 (upgraded from 2026.5.2) |
| **Ingress Source** | Cloudflare Dashboard (auto-imported) |

### Current Ingress Rules

| Hostname | Service |
|----------|---------|
| `ssh.phillias.org` | `ssh://localhost:22` |
| `*` (catch-all) | `http_status:404` |

---

## ⚠️ Clarification Needed

**Two different tunnel IDs exist:**
- **kalione** (`b0d2b018-be3e-49aa-958e-0b819fd2d6c9`) — currently running via systemd
- **kalione** (`7269342a-9e96-4a6c-aa32-96622c5e6520`) — mentioned as target

**Questions to resolve before proceeding:**
1. Are you converting the **existing running tunnel** (kalione) to remote management?
2. Or are you **replacing** kalione with kalione?
3. If replacing: does kalione already have ingress rules configured in the dashboard, or is it empty?

---

## Plan

### Phase 1 — Preparation

#### 1.1 Document current ingress rules
Current `/etc/cloudflared/config.yml`:
```yaml
tunnel: kalione
credentials-file: /home/phillias/.cloudflared/b0d2b018-be3e-49aa-958e-0b819fd2d6c9.json

ingress:
  - hostname: ssh.phillias.org
    service: ssh://localhost:22
  - service: http_status:404
```

- [x] Documented: `ssh.phillias.org → ssh://localhost:22`, catch-all 404
- [x] Verified: no unexpected services using tunnel (logs checked, only normal reconnections)

#### 1.2 Obtain tunnel token
```bash
# Via API (preferred — requires CLOUDFLARE_API_TOKEN env var)
curl "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/cfd_tunnel/<TUNNEL_ID>/token" \
  --request GET \
  --header "Authorization: Bearer $CLOUDFLARE_API_TOKEN"

# Or via Dashboard:
# Tunnels → select tunnel → Overview → Install connector → copy eyJ... token
```

#### 1.3 Backup current config
```bash
sudo cp /etc/cloudflared/config.yml /etc/cloudflared/config.yml.bak
sudo cp /home/phillias/.cloudflared/b0d2b018-be3e-49aa-958e-0b819fd2d6c9.json /home/phillias/.cloudflared/creds.bak.json
```

---

### Phase 2 — Stop & Reconfigure

#### 2.1 Stop cloudflared
```bash
sudo systemctl stop cloudflared
```

#### 2.2 Update systemd unit to token mode
```bash
sudo cloudflared service install eyJhIjoiYTdmYTE5OGRkNWIzNTlhMTg3YzY3MTA2NGZlNmIzNmUiLCJ0IjoiYjBkMmIwMTgtYmUzZS00OWFhLTk1OGUtMGI4MTlmZDJkNmM5IiwicyI6IjNIMVRBdUY4Z3hlNERzbjNoYnRJcmRBVWdqVmRMaVhPeWxrZHcyN1U3T0U9In0=
```

#### 2.3 Rename config files (prevent accidental pickup)
```bash
sudo mv /etc/cloudflared/config.yml /etc/cloudflared/config.yml.disabled
sudo mv /home/phillias/.cloudflared/b0d2b018-be3e-49aa-958e-0b819fd2d6c9.json /home/phillias/.cloudflared/creds.bak.json
```

---

### Phase 3 — Start & Verify Connection

#### 3.1 Start cloudflared
```bash
sudo systemctl daemon-reload
sudo systemctl start cloudflared
sudo systemctl status cloudflared
```

#### 3.2 Verify dashboard connection
- Go to Cloudflare Dashboard → Tunnels → kalione
- Confirm status shows **Connected** / **Healthy**
- Check logs: `journalctl -u cloudflared -f`

---

### Phase 4 — Recreate Ingress Rules in Dashboard

#### 4.1 Navigate to Routes tab
Dashboard → Tunnels → kalione → **Routes**

#### 4.2 Add routes

| Type | Hostname | Service |
|------|----------|---------|
| Public hostname | `ssh.phillias.org` | `ssh://localhost:22` |
| *(Optional)* Catch-all | N/A | Not needed (dashboard handles implicitly) |

#### 4.3 Additional routes (if needed)
- Private network routes: Add CIDR ranges for internal access
- TCP/SSH tunnels: Configure as needed

---

### Phase 5 — Verify & Cleanup

#### 5.1 Test connectivity
```bash
ssh -v ssh.phillias.org  # Test SSH tunnel
curl -v https://ssh.phillias.org  # Should get 404 or connection refused (expected)
```

#### 5.2 Cleanup old files
```bash
# Once verified working for 24+ hours
sudo rm /etc/cloudflared/config.yml.disabled
sudo rm /home/phillias/.cloudflared/creds.bak.json
```

#### 5.3 Update documentation
- [x] Migration executed: token-based user service deployed and running
- [x] Confirmed: DNS CNAME records remain unchanged (tunnel UUID stays the same)

---

## Key Points

- **Tunnel ID stays the same** — only the launch method changes
- **DNS CNAME records** pointing to the tunnel UUID don't need to change
- **Dashboard log streaming** becomes available after migration
- **Replica management** enabled for scaling tunnel connectors

---

## Rollback Plan

If migration fails:
```bash
sudo systemctl stop cloudflared
sudo mv /etc/cloudflared/config.yml.disabled /etc/cloudflared/config.yml
sudo mv /home/phillias/.cloudflared/creds.bak.json /home/phillias/.cloudflared/b0d2b018-be3e-49aa-958e-0b819fd2d6c9.json
sudo systemctl start cloudflared
```
