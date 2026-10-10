---
name: seeding
description: >
  Runbook for the RapidSeedbox seeding operation — rTorrent 0.9.8 box at
  45.152.210.245 (SSH root key, ruTorrent XML-RPC over HTTPS), tracker
  portfolio (MyAnonamouse, SeedPool, AnimeZ), official tracker API usage
  (Gazelle + UNIT3D), ratio-yield ranking method, the invite-pathway ladder
  from the trackerpathways dataset, and known-failed troubleshooting paths.
  Use when the captain asks about the seedbox, seeding ratio, tracker
  strategy, torrent portfolio analysis, or invite pathways.
compatibility: opencode
metadata:
  stacks: rapidseedbox
  services: rtorrent,rutorrent,mam,seedpool,animez,speedapp,prowlarr
  tools: ssh,curl,xml,sqlite3
---

# Seeding Operation Runbook

## Access (verified 2026-10-07)

All commands run from the kali firstmate home unless noted.

```bash
# SSH (rapidseedbox alias — root key login)
ssh rapidseedbox

# ruTorrent XML-RPC (digest auth — plain -u gives 401)
PW=$(cat ~/.agents/keys/default/.rapidseedbox-utorrent-password)
curl -s --digest -u "user:$PW" -X POST \
  -H 'Content-Type: text/xml' \
  -d '<methodCall><methodName>system.client_version</methodName></methodCall>' \
  https://45-152-210-245.a.seedbox.vip/rutorrent/plugins/rpc/rpc.php
```

- HTTP auth user is literally `user`; password file is 11 bytes, value never
  written anywhere else.
- The rpc.php endpoint is a raw XML-RPC passthrough to rTorrent's SCGI socket
  (127.0.0.1:5000 on box). Any rTorrent methodCall works: `download_list`,
  `d.*`, `load.start`, etc. A bare GET on it 500s with "Link to XMLRPC
  failed" — misleading; it means empty POST body, not a downed client.

## Box facts (verified 2026-10-07)

- rTorrent 0.9.8 in screen session `rtorrent-user`; ruTorrent + Deluge also
  present (Deluge has no torrents verified; portfolio lives in rTorrent).
- NIC venet0 reports 10000 Mbps — treat as 10Gbps-class, verify empirically
  before promising speeds.
- Disk 1.2T (ploop); downloads land in `/home/user/Downloads`.
- Session dir on box: `/var/www/session/user` (one `.torrent` + sidecars
  per item; count only `*.torrent` for true torrent totals).
- **Memory ceiling: 2.5 GiB cgroup (max 2,684,354,560 bytes) — page cache
  from downloads counts fully against it.** On 2026-10-09 a 263 GiB
  download pinned the cgroup to 99.9% and the host flipped the rootfs
  read-only ~12h later (all web services died; panel Stop+Start did NOT
  fix it; RapidSeedbox replaced/re-attached the disk after a support
  ticket, ~4h). Guardrails for every large grab:

  - Check before and after: `ssh rapidseedbox 'cat /proc/meminfo | grep -E "MemTotal|MemFree|Cached:|MemAvailable"'`
    and the cgroup counter (`cat /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory.current`
    on cgroup v2, or `/sys/fs/cgroup/memory/memory.limit_in_bytes` +
    `memory.usage_in_bytes` on v1 — the Virtuozzo host has used v1).
  - One large download (>50 GiB) at a time; before starting the next
    big grab, current usage should sit under ~70% of the ceiling.
  - Recheck within the hour after any big add. If usage pins >95%,
    pause the newest download (`rpc d.stop "<hash>"`) until the
    oldest completes — let the kernel reclaim rather than burst.
  - Outage signature (repeat): web dead but SSH fine + writes fail
    with read-only errors → do NOT reinstall the container; email
    `support@rapidseedbox.com` (sent from the captain's Gmail via
    Composio `GMAIL_REPLY_TO_THREAD`/`GMAIL_SEND_EMAIL`, gws-axi is
    drafts-only). Reference ticket: 2026-10-09, fixed by Carlos's team.

## Portfolio (verified 2026-10-07: 58 torrents, 193G on disk)

| Tracker | Torrents | Notes (yield verified 2026-10-08) |
|---|---|---|
| MyAnonamouse (MAM) | 36 | Gazelle; the invite gateway (34 routes); 50.75 GiB up, 363 MiB/day |
| SeedPool (SP) | 14 | UNIT3D; young 0-day tracker (b. 2024); 74.80 GiB up, 495 MiB/day |
| AnimeZ | 8 | 68.06 GiB up, 486 MiB/day — highest per-torrent yield (Captain Tsubasa S02: 65 GiB alone); no API, but RSS feed verified (key file + enclosure downloads); software unidentified (non-UNIT3D `announce7` path; API tokens disabled) |

2026-10-08 lifecycle test: + Magic Knight Rayearth BD Remux (263.37 GiB,
AnimeZ freeleech), − Newsweek.International.2021.01.22.pdf (MAM, zero
upload in 154 days). Portfolio: 36 MAM / 14 SeedPool / 8 AnimeZ.

Refresh method (avoids the SCGI hang, see Known-failed):

```bash
ssh rapidseedbox 'grep -h -o "https\?://[a-zA-Z0-9.-]*" /var/www/session/user/*.torrent 2>/dev/null \
  | sort | uniq -c | sort -rn'
```

## Official tracker APIs (verified 2026-10-08; no scraping ever)

- **MAM — mam_id cookie, NOT an API-key header.** Every official
  integration (Prowlarr, Jackett, Readarr, Listenarr) authenticates with
  the `mam_id` cookie generated at Preferences > Security. Key file (the
  cookie value, saved by the captain): `~/.agents/keys/default/.map-api-key`
  — odd name, verified live against MAM. Sanctioned surfaces (from
  Prowlarr's indexer source, `MyAnonamouse.cs`):
  - User stats: `GET https://www.myanonamouse.net/jsonLoad.php` with
    `Cookie: mam_id=<value>` → JSON: classname, ratio, uploaded_bytes,
    downloaded_bytes, seedbonus, wedges, uid, username. Verified output
    2026-10-08: **Power User, ratio 92, 50.75 GiB up, 60 wedges**.
  - Search: `GET /tor/js/loadSearchJSONbasic.php?tor[text]=&tor[searchType]=fl`
    (`fl`=freeleech, `all`, `active`, `VIP`, `nVIP`) plus
    `tor[cat][]=0`, `tor[startNumber]=0`, `perpage=100` → envelope
    `{data:[rows], found:<total>, total, perpage, start}`; rows use
    lowercase keys: id, title, seeders, leechers, size (a formatted
    string like "332.5 KiB" — parse units), added, times_completed,
    free, fl_vip, personal_freeleech, vip, w, lang_code. Verified
    2026-10-08: searchType=fl → 1071 freeleech found.
  - Download: `/tor/download.php?tid=<id>` (add `&fl=1` to spend a wedge).
  - HTTP 403 = mam_id expired/invalid.
- **SeedPool (UNIT3D 9.1.5 custom) — Bearer token, verified 2026-10-08.**
  `GET https://seedpool.org/api/torrents/filter?perPage=100&sortField=seeders&sortDirection=desc`
  with `Authorization: Bearer $(cat ~/.agents/keys/default/.seedpool-api-token)`.
  Freeleech-only filter: `&free[]=100`. Rows at `data[].attributes`: seeders,
  leechers, times_completed, size, freeleech %, double_upload, featured,
  created_at, details_link, download_link. Token from Settings → API Key.
  RSS Keys (RID) also exist at Settings > RSS Keys (sanctioned automation).
- **SpeedApp (speedapp.io, UNIT3D-family JSON API) — Bearer token,
  verified live 2026-10-08.** `GET
  https://speedapp.io/api/torrent?itemsPerPage=100&sort=torrent.createdAt&direction=desc`
  with `Authorization: Bearer $(cat ~/.agents/keys/default/.speedapp.io-api-token)`
  (token is 427 chars, JWT-shaped). Other params: `search=`, `categories[]=`,
  `imdbId`, `page`. Rows (JArray): id, name, seeders, leechers, size
  (bytes), download_volume_factor (0 = freeleech), upload_volume_factor,
  is_freeleech, is_double_upload, times_completed, created_at, category,
  url. Download: `api/torrent/<id>/download` (same Bearer header).
  `api/login` (email/password → token) exists — never use it; token only.
  Rules INGESTED 2026-10-08 via one-time PHPSESSID cookie read (see Rules
  compliance). Footer confirms API + RSS as official site features.
- **AnimeZ — RSS feed, verified live 2026-10-08 (no API; tokens 404).**
  Feed pattern:
  `https://animez.to/rss/torrents/<filter>/<key>` with filters: all,
  featured, freeleech, half-download, double-upload, dying, dead, reseed,
  anime, manga, my-uploads, bookmarks. Key file (64-char hex, saved by
  the captain): `~/.agents/keys/default/.animez.to-rss-key`. The
  freeleech feed returns 50 items; item tags (namespaced — strip the
  `}`): title, link, guid, pubDate, description, creator, category,
  enclosure, fileName, contentLength (bytes), infoHash (lowercase),
  seeds, peers, hash. The enclosure URL
  `https://animez.to/rss/download/<key>/<id>` is the sanctioned
  key-embedded .torrent download — fetch it ON the box, then
  `load.start` (see Lifecycle). No session-cookie login, ever.
- **Prowlarr (self-hosted, 66 indexers incl. seedpool (API)):**
  `GET https://prowlarr.phillias.cc/api/v1/indexer` with
  `X-Api-Key: $(cat ~/.agents/keys/default/.prowlarr.phillias.cc-api-key)`.
  No MAM or AnimeZ in it. Captain's rule: gentle rates, don't crash it.

## Ratio-yield ranking method

For "which torrents generate the highest ratio on my trackers":

1. Pull the live seeding list from rTorrent (`download_list` + per-hash
   `d.*` calls: size, uploaded, ratio, timestamp) or parse session files.
2. Join against tracker API data: `leechers`, `seeders`, `freeleech` flag.
3. Rank candidates by modeled yield: leecher/seeder ratio × size ×
   freeleech multiplier (free torrents: all upload counts, downloaded=0).
4. Prefer: new free torrents in the first hours after upload, small
   seeder counts, sustained demand (check twice, hours apart, before
   committing disk).
5. Disk budget: keep ~100G free headroom of the 1.2T.

MAM specifics: bonus-point economy rewards seed time even when upload
stalls — keep everything seeding, spend points on VIP (freeleech) months
or upload credit per the captain's preference.

Verified snapshot (2026-10-08, 58 torrents, ~1.34 GiB/day aggregate):
per-tracker play — MAM = evergreen long-tail (sizes are small and FL
swarms are saturated with 300+ seeders; catch NEW freeleech releases
fresh via searchType=fl sorted by added, not the old backlog) + bonus
economy; SeedPool = fresh 0-day freeleech within hours of upload
(`free[]=100&sortField=created_at`, REMUX sizes carry the yield, 10-day
seed floor); SpeedApp = fresh freeleech UHD REMUXes (best instant
demand seen: 45-80 GiB titles with 0-3 seeders); AnimeZ = keep
everything seeding (no API, manual only).

## Lifecycle: add and remove a torrent (verified 2026-10-08)

Helper (define once per shell):

```bash
PW=$(cat ~/.agents/keys/default/.rapidseedbox-utorrent-password)
RPC="https://45-152-210-245.a.seedbox.vip/rutorrent/plugins/rpc/rpc.php"
rpc() { curl -s --digest -u "user:$PW" -X POST -H 'Content-Type: text/xml' \
  --data "<methodCall><methodName>$1</methodName><params><param><value><string>$2</string></value></param></params></methodCall>" "$RPC"; }
```

Add (AnimeZ example; MAM/SeedPool/SpeedApp: fetch the .torrent on box
via their sanctioned download URLs with the cookie/Bearer header):

```bash
# 1. fetch the .torrent ON the box (RSS enclosure embeds the key)
ssh rapidseedbox \
  "curl -s -o /home/user/rl-<id>.torrent 'https://animez.to/rss/download/<key>/<id>'"
# 2. load + start — TWO params: empty-string target, then the on-box path
curl -s --digest -u "user:$PW" -X POST -H 'Content-Type: text/xml' \
  --data "<methodCall><methodName>load.start</methodName><params><param><value><string></string></value></param><param><value><string>/home/user/rl-<id>.torrent</string></value></param></params></methodCall>" \
  "$RPC"   # → i4 0 on success
```

Verify add: `rpc download_list ""` (count grows by one), `rpc d.name "<hash>"`,
`rpc d.state "<hash>"` = 1 (started), `rpc d.down.rate "<hash>"` shows
active download speed, `rpc d.base_path "<hash>"` the target directory.
**The hash is the param value** — pass it as the single string param of
`d.<cmd>` (e.g. `rpc d.state "<hash>"`). Hash-suffixed method names like
`d.state.<hash>` are "not defined" on rTorrent 0.9.8 via rpc.php
(corrected 2026-10-09 after a live fault). Same form for
`d.close`/`d.erase` and `d.stop`.

Remove (safe order — close, erase, then delete data):

```bash
rpc d.close "<hash>"   # stop cleanly
rpc d.erase "<hash>"   # remove from rTorrent + session dir
ssh rapidseedbox 'rm -rf "/home/user/Downloads/<content-dir-or-file>"'  # data only after confirming nothing else needs it
```

Before any removal, confirm the torrent is outside every tracker's
seed window (MAM 72h/30d HnR, SeedPool 10-day floor, SpeedApp Art 21
48h/30d) and has no upload promise worth keeping. Deletion candidates:
zero-upload + aged + low forward demand.

First full lifecycle executed 2026-10-08: **added** Magic Knight
Rayearth BD Remux (263.37 GiB, AnimeZ freeleech, id 34662, top-ranked
candidate at 7 seeds/1 leecher — 14.4 MiB/s download observed);
**removed** Newsweek.International.2021.01.22.pdf (MAM, 154 days old,
zero bytes ever uploaded) — both ends verified live. Rayearth survived
the 2026-10-09 outage complete and is seeding (verified 2026-10-09:
state=1, complete=1, 345 MiB up).

## Invite-pathway ladder (trackerpathways dataset, Sep 2026)

Dataset: `github.com/handokota/trackerpathways` → `src/data/trackers.json`
(MIT). Shape: `trackerInfo[name]` (182 trackers), `unlockInviteClass[name]`
= [days, reqs], `routeInfo[source][dest]` = {days, reqs, active, updated}.
Re-clone on demand (site itself is a JS SPA; fetch the repo, not the page).

Ladder given current portfolio and box (10Gbps, ~900G free):

1. **MAM is ALREADY Power User** (verified live via `/jsonLoad.php`
   2026-10-08: ratio 92, 50.75 GiB up, wedges 60). The trackerpathways
   "1 TiB uploaded" string is stale vs the live class — the PU-gated
   invite forum (34 routes) is plausibly open NOW. Confirm inside the
   invite threads before applying; each thread adds its own profile-link
   and age requirements.
2. **At PU, MAM invite forum** (days=0 routes): DigitalCore.Club and Milkie
   (0-day/general), Luminarr and ReelFliX (HD movies) — burst-yield picks
   for a fast pipe; seedpool (already have); BakaBT, TheGeeks, RetroFlix,
   Unwalled (25 seeded uploads) etc. as demand fits.
3. **6 months in (180d routes):** Blutopia — "9 months or 6 months and
   10+ uploads"; big free general, top per-TB yield on a fast box.
   PixelHD needs 3× 6-month profile links (MAM qualifies).
4. **9 months (270d):** LST (large general), ShareIsland ("9mo or 10+
   uploads").
5. **12 months (365d):** Immortal-s, Phoenix Project. (Secret Cinema route
   inactive.)
6. **SeedPool side track:** SuperPool class = 6 months, 1 TiB seedsize,
   ratio ≥ 1 — seedsize-based, trivial for the box; SeedPool itself has no
   recorded outgoing routes (young tracker), so treat it as an end node.

Shazbat and XSpeeds require MAM VIP+ (beyond PU). All route data as of the
dataset's ~Sep 2026 timestamps — re-verify requirements in the invite
threads before applying; forums can change reqs without the dataset
noticing.

## Rules compliance (reviewed 2026-10-08 — read before any tracker action)

**MAM (rules.php, rule 1.7 "Bots, Automation, and Scraping" = anchor
`#rsc68`):** only functions in the API documentation (/api/list.php,
login-gated) or admin-approved surfaces may be automated; this explicitly
covers AI assistants and LLM tools. Never automate login with
email/password; never give login credentials to an agent; the `mam_id`
cookie is the sanctioned agent credential. No scraping, ever. Other
binding rules: 1.2 seedbox/VPN use must be declared to staff (ticket) —
and if the browsing IP differs from the client IP, the Dynamic Seedbox
API (thread /f/t/78248) authorizes the client; 1.4/2.4 global ratio
≥ 1.0; 2.5 every torrent must seed 72h within 30 days (HnR); 2.8
unsatisfied-torrent caps by class (User 50 / PU 100 / VIP 150); 2.3
whitelisted clients only (`/tor/allowed_clients.php` — verify rTorrent
0.9.8 is whitelisted, disable auto-update); 2.2 never reuse MAM
.torrent files on other sites; 2.7 no partial downloads.

**SeedPool (UNIT3D 9.1.5; FAQ ingested 2026-10-09 via one-time `_t`
read):** global minimum ratio 1:1 (no per-torrent ratio). **Min seed
time 10 days for ALL releases, freeleech included** — schedule nothing
for deletion before day 10; torrents go unsatisfied after 3 days (72h)
offline; unsatisfieds shrink download slots (eventually to 1) and clear
only by completing the seed time or paying a fine; <10%-downloaded
torrents are exempt. Freeleech = all individual TV episodes, all
individual anime episodes, all remuxes, all music packs — freeleech
never exempts seed time. Clients: qBittorrent/Deluge/rTorrent allowed
(rTorrent 0.9.8 on the box is fine), **uTorrent banned**. Uploading is
restricted to trusted members. SuperPool+ with >1 TiB seedpool unlocks
site-wide freeleech. IRC: irc.seedpool.org:6697 SSL, nick = site
username, server password = passkey, #lobby !help. Official API + RSS
keys are the sanctioned surfaces; keep request rates gentle.

**SpeedApp (rules ingested 2026-10-08, translated from Romanian):** Art
21(2) — every download MUST seed 30 min uninterrupted immediately after
completing, then per-torrent ratio 1.0 OR 48h cumulative seed within 30
days; violations are H&R. Ratio <0.95 risks limits until User class;
global ≤0.2 → 7-day download limit. >4 unsatisfied bars new users from
<24h-old torrents; H&R>9 → 24h-limited, >29 → 7d-limited. Scripts that
cheat seeding stats = disable; **excessive upload throttling is
punishable** (never throttle seeding on this tracker). Unconnectable ≠
H&R. API + RSS are official site features (sanctioned surfaces); no
AI/automation ban clause exists.

**AnimeZ:** ToS has no AI/automation clause; forbidden: circumventing
rate limits/security/filtering, interfering with the service, collecting
other users' info. The RSS feed (key-embedded) is the sanctioned
surface; use it instead of the site. No session-cookie automation.

**Cookie lesson (one-time rules reads):** Discourse forums
(forums.seedpool.org) rotate `_forum_session` on nearly every request —
a copied value goes stale and 302s to SSO. Request the `_t` remember-me
cookie instead (long-lived; Discourse mints a fresh session from it).
SpeedApp's PHPSESSID worked fine for a single read. Cookie values are
used once, never stored anywhere.

**Prowlarr:** self-hosted; only rule is don't crash it.

**General posture:** one-off gentle API reads from the kali home; bulk
swarm interaction happens on the box via rTorrent; never touch a site's
HTML with automation when a JSON/RSS surface exists.

## Known-failed / avoid (verified 2026-10-07)

- **SCGI nested multicall hangs rTorrent 0.9.8:** `d.multicall2` with
  nested `t.multicall=d.url=` deadlocks the client (socket timeout, needs
  screen restart). Avoid raw nested multicalls over SCGI; use simple
  methodCalls, the ruTorrent RPC passthrough, or grep session files.
- **rTorrent 0.9.8 quirks over rpc.php:** `d.timestamp.added` is NOT
  defined (use session-file mtime as add-time proxy); `d.multicall2`
  with any view target faults ("" → "Could not find view", named views
  → -501 unsupported target type); classic `d.multicall` undefined.
  Bulk stats DO work via standard XML-RPC `system.multicall` batching
  per-hash simple calls — verified: 348 entries in ONE POST
  (d.name, d.size_bytes, d.up.total, d.down.total, d.ratio per hash;
  `d.ratio` returns permille, e.g. 92000 = ratio 92.0).
- **Basic auth against ruTower proxies 401s** — the Apache gate is
  `AuthType Digest`. `curl --digest` is mandatory.
- **trackerpathways.org direct fetch** 403s / renders empty (JS SPA);
  chrome-devtools-axi was flaky against it. Use the GitHub repo clone.
- Torrent counts: don't count sidecars (`.libtorrent_resume`, `.rtorrent`) — 177 files ≠ 58 torrents.
- **Service-check traps on this box:** rTorrent's process comm is
  `rtorrent main` — `pgrep -x rtorrent` false-negatives; use
  `ss -ltnp | grep :5000` (SCGI) instead. `deluged` runs OUTSIDE
  systemd — `systemctl is-active deluged` reports inactive while it is
  actually up. ruTorrent alive = HTTP 401 on anonymous GET of
  `https://45-152-210-245.a.seedbox.vip/rutorrent/`.
- **Hash-suffixed rpc methods** (`d.state.<hash>`) are "not defined";
  always pass the hash as the param value.

## Records

- Backlog task tracking this line of work: `seeding-ops-q2` (firstmate
  kali home). Setup task `rapidseedbox-mgmt-q1` is done.
- This skill lives under chezmoi-managed `~/.agents/` — added to chezmoi
  source 2026-10-08 with captain approval (dotfiles PR); portability to
  other machines rides the normal apply/sync flow.
- Secrets live only under `~/.agents/keys/default/`; never write values
  into this skill, memory, or chat.
