---
name: prowlarr-db-recovery
description: >
  Recover Prowlarr from SQLite database corruption and deserialization errors.
  Covers DB clone recovery, fixing NULL/empty dates, tags, config contracts, and
  truncated JSON in Settings fields. Always creates a backup before any destructive
  operation.
compatibility: opencode
---

# Prowlarr DB Recovery

## Trigger
User reports Prowlarr is down, throwing "database disk image is malformed", JSON
deserialization errors (`JsonException`, `DataException`), or indexers failing to
load after a crash.

## Critical Rule: Backup First

Before ANY destructive operation on the Prowlarr DB, create a timestamped backup:

```bash
# Stop Prowlarr first
cd ~/docker/pirate && docker compose --profile stremio stop prowlarr

# Backup the live DB
sudo cp /var/lib/docker/volumes/pirate_prowlarr-secrets/_data/prowlarr.db \
  /var/lib/docker/volumes/pirate_prowlarr-secrets/_data/prowlarr.db.$(date +%Y%m%d_%H%M%S).pre-fix

# Also backup the daily backups just in case
```

## Recovery Procedure

### Step 1: Diagnose

Copy the live DB and run diagnostics:

```bash
sudo cp /var/lib/docker/volumes/pirate_prowlarr-secrets/_data/prowlarr.db /tmp/prowlarr_check.db
sudo chmod 644 /tmp/prowlarr_check.db

# Check structural integrity
sqlite3 /tmp/prowlarr_check.db "PRAGMA integrity_check;"
# Expected: "ok"
# If "malformed" → proceed to clone recovery

# Check common data issues
sqlite3 /tmp/prowlarr_check.db "
SELECT Id, Name, ConfigContract, Added, Tags, LENGTH(Settings)
FROM Indexers
WHERE ConfigContract IS NULL OR ConfigContract = ''
   OR Added IS NULL OR Added = ''
   OR Tags IS NULL OR Tags = ''
   OR Settings IS NULL OR Settings = '';

-- Check for non-JSON Tags values
SELECT Id, Name, Tags FROM Indexers
WHERE Tags NOT LIKE '[%' AND Tags NOT LIKE '{%';
"
```

### Step 2: Clone Recovery (if "database disk image is malformed")

```bash
# Clone the corrupted DB into a clean file
sqlite3 /tmp/prowlarr_check.db ".clone /tmp/prowlarr_recovered.db"
sqlite3 /tmp/prowlarr_recovered.db "PRAGMA integrity_check;"
# Must return "ok" before proceeding
```

### Step 3: Fix Indexer Data Issues

```bash
sqlite3 /tmp/prowlarr_recovered.db "
-- Fix NULL Added dates (use a reasonable default)
UPDATE Indexers SET Added = '2026-01-01 00:00:00Z'
WHERE Added IS NULL OR Added = '';

-- Fix NULL Tags (must be '[]' not empty string for Prowlarr)
UPDATE Indexers SET Tags = '[]'
WHERE Tags IS NULL OR Tags = '';

-- Fix empty ConfigContract (must match Settings type)
-- Newznab indexers need 'NewznabSettings', Torznab needs 'TorznabSettings'
-- Cardigann indexers need 'CardigannSettings', etc.
UPDATE Indexers SET ConfigContract = 'NewznabSettings'
WHERE ConfigContract IS NULL OR ConfigContract = '';
"
```

The ConfigContract must match the actual Settings JSON structure. To determine the
correct contract, inspect the Settings content:
```bash
sqlite3 /tmp/prowlarr_recovered.db "
SELECT Id, Name, substr(Settings, 1, 100) FROM Indexers
WHERE ConfigContract IS NULL OR ConfigContract = '';
"
```

Common mappings:
| Settings structure              | ConfigContract              |
|--------------------------------|-----------------------------|
| `baseUrl`, `apiPath`, `apiKey` | `NewznabSettings`           |
| `torrentBaseSettings`, `baseUrl`| `TorznabSettings`          |
| `siteLink`, `username`         | `CardigannSettings`         |
| `ruTrackerSettings`            | `RuTrackerSettings`         |
| `speedAppSettings`             | `SpeedAppSettings`          |

### Step 4: Fix Truncated JSON in Settings

Symptom: `JsonException: Expected start of a property name or value, but instead
reached end of data. Path: $.capabilities.categories[N]`

The Settings field contains a truncated `capabilities` section. Remove it:

```bash
python3 << 'PYEOF'
import sqlite3, json

db = sqlite3.connect('/tmp/prowlarr_recovered.db')
rows = db.execute("SELECT Id, Name, Settings FROM Indexers").fetchall()

for idx_id, name, settings in rows:
    try:
        json.loads(settings)
    except json.JSONDecodeError:
        print(f"Fixing truncated JSON in {name} (ID {idx_id})")
        caps_pos = settings.find('"capabilities"')
        if caps_pos != -1:
            prefix = settings[:caps_pos].rstrip()
            if prefix.endswith(','):
                prefix = prefix[:-1].rstrip()
            new_settings = prefix + '\n}'
            json.loads(new_settings)  # validate
            db.execute("UPDATE Indexers SET Settings = ? WHERE Id = ?",
                       (new_settings, idx_id))
            print(f"  Removed capabilities section, new length: {len(new_settings)}")

db.commit()
db.close()
PYEOF
```

### Step 5: Deploy & Verify

```bash
# Stop Prowlarr
cd ~/docker/pirate && docker compose --profile stremio stop prowlarr

# Copy fixed DB to volume
sudo cp /tmp/prowlarr_recovered.db \
  /var/lib/docker/volumes/pirate_prowlarr-secrets/_data/prowlarr.db
sudo chown 1000:1000 /var/lib/docker/volumes/pirate_prowlarr-secrets/_data/prowlarr.db
sudo chmod 644 /var/lib/docker/volumes/pirate_prowlarr-secrets/_data/prowlarr.db

# Start Prowlarr
docker compose --profile stremio up -d prowlarr

# Wait and check logs
sleep 10
docker logs prowlarr 2>&1 | grep -iE "(error|exception|fatal|corrupt)"
# Should produce no output

# Verify API
API_KEY=$(sudo grep ApiKey /var/lib/docker/volumes/pirate_prowlarr-secrets/_data/config.xml | sed 's/.*<ApiKey>//;s/<\/ApiKey>.*//')
curl -s -H "X-Api-Key: $API_KEY" http://localhost:9696/api/v1/indexer | python3 -c "
import sys, json; d = json.load(sys.stdin)
print(f'{len(d)} indexers returned')
"

# Check health
curl -s -H "X-Api-Key: $API_KEY" http://localhost:9696/api/v1/health
```

## Common Error Patterns

| Error | Root Cause | Fix |
|-------|-----------|-----|
| `database disk image is malformed` | SQLite structural corruption | `.clone` recovery |
| `Error parsing column 7 (Added=...)` | NULL or garbled Added date | `UPDATE ... SET Added = '...'` |
| `Error parsing column 10 (Tags=...)` | NULL or non-JSON Tags | `UPDATE ... SET Tags = '[]'` |
| `Unable to cast NullConfig to ...` | Empty ConfigContract | `UPDATE ... SET ConfigContract = '...'` |
| `$.capabilities.categories[N]` | Truncated capabilities in Settings | Remove capabilities section |
| `Indexers have no definition` | Stale Cardigann definitions | Remove from UI |

## Quick Reference

### Container paths
| Resource | Path |
|----------|------|
| Active Prowlarr DB | `/var/lib/docker/volumes/pirate_prowlarr-secrets/_data/prowlarr.db` |
| Stale bind-mount DB | `~/docker/pirate/prowlarr/data/prowlarr.db` (do not use) |
| Config file | `/var/lib/docker/volumes/pirate_prowlarr-secrets/_data/config.xml` |
| Backups | `/var/lib/docker/volumes/pirate_prowlarr-secrets/_data/prowlarr.db.YYYYMMDD_HHMMSS*` |
| Compose file | `~/docker/pirate/compose.yaml` |

### Useful queries
```sql
-- Count indexers by type
SELECT ConfigContract, COUNT(*) FROM Indexers GROUP BY ConfigContract;

-- Find indexers with issues
SELECT Id, Name, ConfigContract, Added, Tags, LENGTH(Settings)
FROM Indexers
WHERE ConfigContract IS NULL OR ConfigContract = ''
   OR Added IS NULL OR Added = ''
   OR Tags IS NULL OR Tags = ''
   OR Tags = '';

-- Check specific indexer Settings (Newznab/Torznab)
SELECT Id, Name, LENGTH(Settings), substr(Settings, 1, 200)
FROM Indexers
WHERE ConfigContract IN ('NewznabSettings', 'TorznabSettings');

-- List all indexers
SELECT Id, Name, ConfigContract, LENGTH(Settings) FROM Indexers ORDER BY Id;
```

### Tags reference (after schema migration)
Current tag IDs in the deployment:
`1=flare, 2=warp, 4=flarewarp, 5=flareproton, 6=proton, 8=byparr, 9=byparrwarr, 10=byparrproton`
