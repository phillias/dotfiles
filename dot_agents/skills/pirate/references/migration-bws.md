# Pirate BWS Secrets Migration — Runbook

Lessons from the 2026-10 migration of the pirate stack's secrets from
`~/docker/pirate` env files to the Bitwarden Secrets Manager (BWS) vault
(project `phillias`, prefix `PIRATE_`; live deploy PRs #2/#3). Verified
2026-10-25.

## How setup.sh renders secrets

- `setup.sh` reads `$STAGE/.env` (mode 600, rendered by `render_dotenv`)
  whose values are populated from BWS via `load-keys.sh` (`PIRATE_` prefix →
  bare var names). `REQUIRED_VARS` (~line 296) gates completeness before any
  write; `setup.sh` writes all rendered configs in one pass (~line 350).
- `render_flask_secret()`: `SHELFMARK_FLASK_SECRET` is **base64 of the
  actual secret** — the renderer `base64 --decode`s it. A vault value that
  isn't valid base64 breaks shelfmark at init. (Fixed once during migration
  by regenerating the vault value.)
- `HTTP_CONTROL_SERVER_AUTH` (decypharr) must be the **full JSON document**,
  not a bare token — it is passed through verbatim into `.env`.
- `render_nzbhydra()`: envsubst over `templates/nzbhydra2/nzbhydra.yml` with
  `NZBHYDRA2_PASSWORD`, `NZBHYDRA2_API_KEY`, `TORBOX_API_KEY`,
  `NZBNOOB_API_KEY`, `SCENENZBS_API_KEY`, `MIATRIX_API_KEY`.

## nzbhydra2 overwrite hazard

`nzbhydra.yml` is **app-managed**: NZBHydra2 (Java) rewrites it in place on
every UI change, so the static template drifts from live config (template
had 6 indexers; live had 7+ incl. keyless Binsearch/NZBIndex variants).
The migration's clean overwrite broke live indexers and the file had to be
restored from the premigration backup.

**Rule until `pirate-nzbhydra-template-complete` lands:** after any
`setup.sh` run, restore the premigration `nzbhydra.yml` from backup, or
better, inject only the secret values into the live file (sed/envsubst on
existing keys) instead of rewriting structure.

## Vault discipline

- BWS is the fleet-wide secrets backend; **never delete old vault entries**
  (standing rule) — rotate values in place instead.
- PIRATE_ prefix maps to the `phillias` project; SelfHost-Prod secrets use
  `BWS_` names in the `SelfHost-Prod` project.

## Cross-service rotation chains

- Rotating the Prowlarr API key breaks every consumer holding the old key —
  notably the AIOS Prowlarr addon (401s in aios logs until the key is
  updated in AIOS dashboard → extensions). Jackett and NZBHydra2 consumers
  behave the same way.
- AIOS `SECRET_KEY` rotation is NOT a plain env swap: stored user configs,
  the addon-URL password, and the config access-key gate are all key-bound.
  See [aios-rekey.md](aios-rekey.md) for the offline re-key procedure.

## Warp gotcha

A degraded masque tunnel presents as HTTPS stalls with HTTP still flowing
through socks5. `docker restart warp` heals it in ~25s; warp self-registers,
so never reintroduce an init container for it.
