# Codeburn Federation Deployment Plan

## Overview

Deploy codeburn as a federated service across three servers via systemd:
- **OCI primary** (`primary55522`): Master dashboard + share service
- **kalione** (`cabinkali`): Share service reporting to OCI primary
- **kali**: Share service reporting to OCI primary

## Architecture (Hub-and-Spoke)

```
┌─────────────────────────────────────────────────────────────┐
│                      OCI Primary (Master)                   │
│  ┌─────────────────┐    ┌─────────────────┐                │
│  │ codeburn web    │    │ codeburn share  │                │
│  │ :4747           │    │ :7777           │                │
│  └────────┬────────┘    └────────┬────────┘                │
│           │                      │                         │
│           │              cb.phillias.cc                     │
│           │              (godoxy)                           │
└───────────┼──────────────────────┼──────────────────────────┘
            │                      │
            │                      │ Aggregates usage from:
            │                      │ - cm.phillias.us (kalione)
            │                      │ - cm.phillias.kali (kali)
            │                      │
┌───────────┼──────────────────────┼──────────────────────────┐
│           │        kalione       │                          │
│           │              ┌───────┴────────┐                 │
│           │              │ codeburn share │                 │
│           │              │ :7777          │                 │
│           │              └────────────────┘                 │
│           │              cm.phillias.us                     │
│           │              (cloudflared)                      │
└───────────┼─────────────────────────────────────────────────┘
            │
┌───────────┼─────────────────────────────────────────────────┐
│           │          kali                                   │
│           │              ┌───────┴────────┐                 │
│           │              │ codeburn share │                 │
│           │              │ :7777          │                 │
│           │              └────────────────┘                 │
│           │              cm.phillias.kali                   │
│           │              (cloudflared)                      │
└───────────┴─────────────────────────────────────────────────┘
```

## Cloudflared Routes

| Hostname | Target | Server |
|----------|--------|--------|
| `cm.phillias.cc` | `https://localhost:7777` | OCI primary |
| `cm.phillias.us` | `https://localhost:7777` | kalione |
| `cm.phillias.kali` | `https://localhost:7777` | kali |
| `cb.phillias.cc` | `https://localhost:4747` | OCI primary (godoxy) |

## Service Requirements

| Server | Services | Ports | Purpose |
|--------|----------|-------|---------|
| OCI primary | `codeburn-web` | 4747 | Web dashboard |
| OCI primary | `codeburn-share` | 7777 | Expose usage to federation |
| kalione | `codeburn-share` | 7777 | Expose usage to federation |

---

## Implementation

### Step 1: Install codeburn on both servers

```bash
# On both OCI primary and kalione
npm install -g codeburn@latest

# Verify installation
codeburn --version
```

### Step 2: Create systemd service files

#### On both servers: codeburn-share.service

Create `/etc/systemd/system/codeburn-share.service`:

```ini
[Unit]
Description=CodeBurn Share Service (Federation)
After=network.target
Documentation=https://github.com/getagentseal/codeburn

[Service]
Type=simple
User=phillias
Group=phillias
WorkingDirectory=/home/phillias
ExecStart=/home/phillias/.npm-global/bin/codeburn share --always --port 7777
Restart=always
RestartSec=10
Environment=NODE_ENV=production
Environment=HOME=/home/phillias

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/home/phillias/.config/codeburn
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

#### On OCI primary only: codeburn-web.service

Create `/etc/systemd/system/codeburn-web.service`:

```ini
[Unit]
Description=CodeBurn Web Dashboard
After=network.target
Documentation=https://github.com/getagentseal/codeburn

[Service]
Type=simple
User=phillias
Group=phillias
WorkingDirectory=/home/phillias
ExecStart=/home/phillias/.npm-global/bin/codeburn web --no-open --port 4747
Restart=always
RestartSec=10
Environment=NODE_ENV=production
Environment=HOME=/home/phillias

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/home/phillias/.config/codeburn /home/phillias/.local/share/opencode
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

### Step 3: Enable and start services

```bash
# On OCI primary
sudo systemctl daemon-reload
sudo systemctl enable codeburn-web codeburn-share
sudo systemctl start codeburn-web codeburn-share

# On kalione
sudo systemctl daemon-reload
sudo systemctl enable codeburn-share
sudo systemctl start codeburn-share
```

### Step 4: Verify services are running

```bash
# Check status
sudo systemctl status codeburn-share
sudo systemctl status codeburn-web  # OCI primary only

# Check logs
journalctl -u codeburn-share -f
journalctl -u codeburn-web -f  # OCI primary only

# Verify ports are listening
ss -tlnp | grep 7777
ss -tlnp | grep 4747  # OCI primary only
```

### Step 5: Add hostapps.yml route (OCI primary only)

Add to `~/docker/selfhost/godoxy/config/hostapps.yml`:

```yaml
codeburn:
  port: :4747
  scheme: http
  homepage:
    name: CodeBurn
    icon: "@selfhst/codeburn.svg"
    description: AI token usage tracker
    category: monitoring
  healthcheck:
    disable: false
  middlewares:
    oidc: {}
```

Restart godoxy after updating:

```bash
cd ~/docker/selfhost
docker compose restart app
```

---

## Federation Setup

### Step 1: Generate pairing PIN on kalione

```bash
# On kalione
codeburn share --pair

# Note the PIN displayed (e.g., 123456)
```

### Step 2: Add kalione to OCI primary

```bash
# On OCI primary
codeburn devices add cm.phillias.us --port 443 --pin <pin-from-step-1>

# Verify pairing
codeburn devices
```

### Step 3: Generate pairing PIN on OCI primary

```bash
# On OCI primary
codeburn share --pair

# Note the PIN displayed
```

### Step 4: Add OCI primary to kalione

```bash
# On kalione
codeburn devices add cm.phillias.cc --port 443 --pin <pin-from-step-2>

# Verify pairing
codeburn devices
```

### Step 5: Verify federation

```bash
# On either server
codeburn devices

# Should show combined usage from both servers
```

---

## Post-Deployment

### Access Dashboard

- **URL**: https://codeburn.phillias.cc
- **Auth**: OIDC via Pocket ID

### Create OIDC Client

1. Visit https://pocketid.phillias.us
2. Go to Applications → Add Application
3. Create client for codeburn:
   - **Name**: CodeBurn
   - **Callback URLs**: `https://codeburn.phillias.cc/auth/callback`
   - **Client Launch URL**: `https://codeburn.phillias.cc`
4. Update `~/docker/selfhost/godoxy/config/hostapps.yml` with client_id/client_secret

### Monitor Services

```bash
# Check share status
codeburn share status

# Check paired devices
codeburn devices

# View logs
journalctl -u codeburn-share -n 100
journalctl -u codeburn-web -n 100  # OCI primary only
```

---

## Troubleshooting

### Dashboard not accessible

1. Check service is running: `sudo systemctl status codeburn-web`
2. Verify port is listening: `ss -tlnp | grep 4747`
3. Check godoxy route in hostapps.yml
4. Review godoxy logs: `docker compose logs app | grep codeburn`

### Federation not working

1. Verify share service is running on both servers: `sudo systemctl status codeburn-share`
2. Check cloudflared routes are active
3. Test connectivity: `curl -sk https://cm.phillias.cc/`
4. Re-pair devices if needed
5. Check firewall rules (port 7777 must be accessible via cloudflared)

### Data not showing

1. Check codeburn can read session files
2. Run `codeburn doctor` to diagnose
3. Verify user permissions on session directories

---

## Security Considerations

1. **OIDC Authentication**: Dashboard requires authentication via Pocket ID
2. **Federation PINs**: Temporary, used only for initial pairing
3. **mTLS**: Codeburn share uses device certificates for mutual TLS
4. **Network**: Share service only accessible via cloudflared tunnels
5. **Data**: Session data stays local, only usage summaries are shared

---

## Rollback Plan

If issues occur:

1. **Stop services**: `sudo systemctl stop codeburn-web codeburn-share`
2. **Disable services**: `sudo systemctl disable codeburn-web codeburn-share`
3. **Remove hostapps.yml entry**: Revert changes to godoxy config
4. **Unpair devices**: `codeburn devices rm <device-name>`

---

## Next Steps

1. Install codeburn on both servers
2. Create and enable systemd services
3. Add hostapps.yml route for dashboard
4. Create OIDC client in Pocket ID
5. Set up federation pairing
6. Verify dashboard access and federation

---

*Plan created: 2026-07-25*
*Last updated: 2026-07-25*
