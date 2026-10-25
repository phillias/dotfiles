# AIOS SECRET_KEY Re-Key

Re-key aiostreams USERS.config after a SECRET_KEY rotation, preserving user UUIDs and addon URLs.

## When to use

After rotating the AIOS `SECRET_KEY` (e.g. post-leak). The dashboard shows "encryption service" errors because stored user configs are encrypted with the old key. This reference re-encrypts them offline with the new key. Verified end-to-end 2026-10-25.

## Encryption scheme (aiostreams)

- **SECRET_KEY**: 64-char hex, env var `SECRET_KEY` in `AIOS.env` (BWS: `PIRATE_AIOS_SECRET_KEY` in phillias project). Used raw (32 bytes) for `encryptString`/`decryptString`.
- **encryptString**: `deflateSync(data, {level: 9})` → `AES-256-CBC` (key=Buffer.from(secretKey,'hex'), iv=random 16B) → `{i: iv.b64, e: ct.b64, t: 'a'}` → urlsafe-b64 JSON.
- **decryptString**: inverse. `isEncrypted` checks `t` in `['aioEncrypt', 'a']`.
- **USERS.config key**: `PBKDF2-SHA512(\`${password}:${SECRET_KEY}\`, Buffer.from(config_salt, 'hex'), 100000, 32, 'sha512')`. The password is the user's addon-config password (env `ADDON_PASSWORD` for env-provisioned users, or manually set in UI). `config_salt` is the bcrypt genSalt(10) string (29 chars, `$2b$10$...`).
- **settings.api.configAccessKey**: `encryptString` envelope `{"__enc": "<urlsafe-b64>"}`. Decrypt requires `inflateSync` after AES decrypt, then `JSON.parse` (settings store). Gate key also stored in BWS as `PIRATE_AIOS_CONFIG_ACCESS_KEY`.
- **Addon URL password**: `encryptString` with raw SECRET_KEY (NOT PBKDF2). Changing SECRET_KEY breaks all distributed addon URLs — new ones must be generated.
- **deflate level 9 is deterministic**: re-encrypting identical plaintext with the same key produces identical blob length (different IV, same length).

## Procedure

### 1. Gather keys and DB path

```
LIVE_ENV=~/firstmate/projects/pirate/AIOS.env        # current (new) key
BACKUP_ENV=/tmp/opencode/aios-rotate/AIOS.env         # pre-rotation (old) key (from phase backup tarball)
DB=~/firstmate/projects/pirate/AIOS/data/db.sqlite
```

Both env files: `SECRET_KEY=<hex>` (may be quoted or unquoted). Also need `ADDON_PASSWORD` from old env (the user's config password).

### 2. Verify offline decryption

```js
// host node with --experimental-sqlite, or container /nodejs/bin/node
const key = crypto.pbkdf2Sync(
  Buffer.from(`${oldAddonPw}:${oldSecretKey}`, 'utf-8'),
  Buffer.from(row.config_salt, 'hex'),  // bcrypt salt, $2b$10$... — hex decode yields ~empty buffer, mirrors app exactly
  100000, 32, 'sha512'
);
const plaintext = zlib.inflateSync(decryptString(row.config, key));
JSON.parse(plaintext.toString('utf-8'));  // must be valid JSON
```

If decryption fails for non-env-provisioned users (password set in UI), the captain must supply their password or those users are left broken.

### 3. Re-encrypt and write

```js
const newKey = crypto.pbkdf2Sync(
  Buffer.from(`${oldAddonPw}:${newSecretKey}`, 'utf-8'),
  Buffer.from(row.config_salt, 'hex'),
  100000, 32, 'sha512'
);
const newBlob = encryptConfig(plaintext, newKey);  // deflate → AES → envelope → urlsafe-b64
// CAS update: UPDATE USERS SET config=? WHERE uuid=? AND config=oldBlob → assert changes===1
```

**Guards**: container stopped, cold backup (`sqlite3 DB '.backup dest'` folds WAL), drift check (row.config === oldBlob file), exactly-1-row CAS update, post-commit re-read proof (decrypt with new key, assert === plaintext).

### 4. Access key alignment (if needed)

The addon URL manifest endpoint calls `assertConfigAccessKey(config)`: when `settings.api.authRequired=true`, `config.accessKey` must match the gate key from `settings.api.configAccessKey`.

If they mismatch (pre-existing or after migration), align `config.accessKey = gateKey` in the plaintext before re-encrypting:

```js
// Decrypt gate key from settings (MUST inflateSync + JSON.parse, NOT raw decryptString)
const enc = JSON.parse(settingsRow.value).__enc;
const gateKey = JSON.parse(zlib.inflateSync(decryptString(enc, newRawKey)).toString('utf-8'));
// Set in plaintext config
plaintext.accessKey = gateKey;
// Then re-encrypt + CAS update as above
```

**Gotcha**: settings values are `encryptString` output = deflated. Forgetting `inflateSync` gives binary garbage, not the key string. The roundtrip proof must decrypt and `JSON.parse` the result, not just compare blob-to-blob.

### 5. Generate new addon URL password

```js
const newUrlPassword = encryptString(oldAddonPw, Buffer.from(newSecretKey, 'hex'));
const newUrl = `https://aios.phillias.cc/stremio/${uuid}/${newUrlPassword}/manifest.json`;
```

Old distributed URLs (encrypted with old key) will fail — new URLs must be distributed to downstream Stremio users. Old-URL requests appear in aios logs as decrypt-failure lines (no IPs logged; traffic source detail only via Cloudflare dashboard).

## Reference artifacts

- Container source: `/app/packages/core/dist/utils/crypto.js`, `/app/packages/core/dist/utils/auth.js`, `/app/packages/server/dist/db/repositories/users.js`, `/app/packages/server/dist/db/repositories/settings-store.js`
- Container node: `/nodejs/bin/node` (minimal image, no ls/cat/grep/printenv in PATH)
- Host node: `~/.local/bin/node --experimental-sqlite` for `node:sqlite` `DatabaseSync`
- DB: SQLite WAL mode, `sqlite3 .backup` folds WAL into cold backup
- Cold backups retained in `~/firstmate/projects/pirate/AIOS/data/db.sqlite.rekey-backup-*.db`
- Public route: cloudflared CF Tunnel (systemd `cloudflared.service`) → localhost:3000; NOT godoxy

## Failure modes

- **`bad decrypt`**: wrong key or password. For env-provisioned users, password = `ADDON_PASSWORD` from old env. For UI-provisioned users, captain must supply.
- **`Invalid addon password`** (USER_INVALID_CONFIG): config.accessKey ≠ gate key. Align access key (step 4).
- **`Failed to decrypt data: incorrect header check`**: encryptString/decryptString mismatch (forgot deflate in encrypt or inflate in decrypt).
- **Settings decrypt gives garbage**: forgot `inflateSync` + `JSON.parse` on settings envelope.
- **Manifest 404 after re-key**: pre-existing config data issue (e.g. stale Prowlarr API key 401), not encryption. Fix from dashboard.
