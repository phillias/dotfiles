---
name: crd
description: >
  Chrome Remote Desktop on headless Linux (kali laptop CabinInspiron22Kali): healthcheck
  ladder, revival without reinstall (start-host registration, session-file repair),
  disconnect triage, and hardening. Use when CRD sessions drop on connect, the host
  won't register, the service restart-loops (exit 41/1), or a revival/healthcheck of
  chrome-remote-desktop@<user> is requested.
compatibility: opencode
metadata:
  stacks: desktop
  services: chrome-remote-desktop
  tools: systemctl,start-host,ss,journalctl
---

# Chrome Remote Desktop (headless Linux)

Authoritative runbook for the `chrome-remote-desktop` Debian package on this host.
Core fact: CRD never attaches to an existing local X session — it launches its own
virtual display + session stack. Every failure mode below is a broken link in that
stack. Package reinstall is almost never the fix.

## 1. Architecture

```
systemd template: chrome-remote-desktop@<user>.service   (User=%i, PAMName, X11 session class)
  └─ /opt/google/chrome-remote-desktop/chrome-remote-desktop --start --new-session
       ├─ registration: ~/.config/chrome-remote-desktop/host#<hex>.json
       │    (service_account/xmpp_login + oauth_refresh_token + host private key)
       │    RUNTIME STATE — never chezmoi-managed, never a remediation target
       ├─ virtual X server (own Xvfb, FIRST_X_DISPLAY_NUMBER = 20 → :20)
       ├─ session script (first existing wins):
       │    ~/.chrome-remote-desktop-session  OR  /etc/chrome-remote-desktop-session
       │    content: exec /etc/X11/Xsession '<DE exec from /usr/share/xsessions/*.desktop>'
       └─ user-scoped env unit: chrome-remote-desktop-environment.service
            (injects CHROME_REMOTE_DESKTOP_SESSION=1 + SSH_AUTH_SOCK via
             systemctl --user set-environment when a CRD graphical session starts)
```

Access gate: the target user must be in the `chrome-remote-desktop` group
(`getent group chrome-remote-desktop`) — the daemon restricts sessions by group
and fails silently without it.

Exit-code semantics in the journal:
- `status=41` = `RELAUNCH_EXIT_CODE` — benign: the host asks systemd to relaunch
  itself (e.g. for a new-session start). Only a concern when it repeats forever.
- `status=1` right after = fatal start failure — almost always a missing/invalid
  host config or session script.

## 2. Healthcheck ladder (run in order)

1. **Session file**: at least one of `~/.chrome-remote-desktop-session`,
   `/etc/chrome-remote-desktop-session` exists and its `<DE exec>` binary exists.
2. **Registration**: `~/.config/chrome-remote-desktop/host#*.json` present
   (contains `service_account`/`xmpp_login` + `oauth_refresh_token`).
3. **Sockets**: the child process holds ESTABLISHED connections (443/5222 to
   Google remoting endpoints): `ss -tnp | grep chrome-remote` — zero sockets =
   not connected, regardless of service state.
4. **Daemon**: `chrome-remote-desktop --get-status` (STARTED is process-level
   only, not connectivity) and `systemctl is-active chrome-remote-desktop@$USER`.
5. **Journal**: `sudo journalctl -u chrome-remote-desktop@<user> -n 50` — look
   for "X session" errors (session-script failure), exit 41→1 loops (config
   gone), relaunch storms.

Verdict guide: service green + no sockets + config missing = zombie (post-wipe
state seen 2026-09-02). Connect succeeds then drops = session-script link.
Device listed at remotedesktop.google.com but unreachable = stale registration.

## 3. Revival runbook (no reinstall)

1. **Repair the session file** (root-owned global or user-local):
   ```
   grep '^Exec=' /usr/share/xsessions/xfce.desktop     # take the Exec command
   sudo bash -c "echo \"exec /etc/X11/Xsession startxfce4\" > /etc/chrome-remote-desktop-session"
   ```
   (Host has XFCE; prefer the user-local `~/.chrome-remote-desktop-session` when
   only one user should be affected.)
2. **Register the host** — from https://remotedesktop.google.com/headless (Chrome,
   signed into the owning Google account) → Set up another computer → Authorize →
   copy the Debian command. Run it **as the target user, NOT sudo** (the config and
   private key must land in that user's `~/.config/chrome-remote-desktop/`):
   ```
   DISPLAY= /opt/google/chrome-remote-desktop/start-host \
     --code="4/..." \
     --redirect-url="https://remotedesktop.google.com/_/oauthredirect" \
     --name=$(hostname)
   ```
   - The `DISPLAY=` empty prefix is deliberate: it clears any inherited display so
     authorization never attaches an existing X session. Keep it.
   - The code is single-use and expires in minutes — generate, run immediately.
   - Prompts for the 6-digit PIN used at every connect. Never commit or echo it.
3. **Restart + verify**: `sudo systemctl restart chrome-remote-desktop@<user>`,
   then re-run the healthcheck ladder top to bottom (sockets are the truth).

## 4. Disconnect triage (connects, then drops)

| Cause | Diagnostic | Fix |
|---|---|---|
| Session file missing/broken | healthcheck step 1; journal "X session" errors | create/repair session file, restart |
| DE exec not installed | `command -v <exec>` fails | point the file at an installed DE |
| Local session conflict (lightdm/gdm + same user logged in locally) | `loginctl list-sessions`; DM active | log out the local session; some GDM versions also block local login while CRD runs |
| DE single-session limit (GNOME/KDE) | DE docs; two sessions same user | use a different DE for CRD or the session chooser |
| Stale/lost registration | healthcheck steps 2-3 | re-run start-host (§3) |

On this host: lightdm is ACTIVE — check for a local phillias session before blaming
the session file. Prefer physical access or SSH for repairs; never repair CRD over
CRD.

## 5. Host facts (CabinInspiron22Kali)

- Package: `chrome-remote-desktop` (Beta channel, 144.x) — dpkg-managed; apt repo
  may or may not be configured; stable deb available from dl.google.com if the
  Beta channel ever needs abandoning.
- DE available: XFCE (`xfce.desktop`) + lightdm-xsession; lightdm runs.
- `phillias` is in the `chrome-remote-desktop` group.
- 2026-09-02 incident wiped `~/.config/chrome-remote-desktop` (registration) and
  both session files — expect both links broken until §3 has been run once.
- The config dir is runtime state: excluded from chezmoi, and from every cleanup /
  stale-path / no-mistakes remediation by the post-incident guardrails.

## 6. Hardening

- Healthcheck timer (systemd user or host cron): session file + host#*.json +
  established sockets; alert via ntfy on any failure. A green service alone is a
  false positive (zombie precedent).
- Keep ~/.config/chrome-remote-desktop out of every "stale path" or cleanup sweep.
- If the host shows offline at remotedesktop.google.com after revival, remove the
  old device entry there first, then re-register — orphaned entries confuse the
  access list.
