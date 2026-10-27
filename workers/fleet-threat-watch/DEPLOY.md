# Deploying fleet-threat-watch
This Worker is deploy-only source: it runs on Cloudflare's cron, not on fleet boxes.
Nothing here is installed to home; `workers/` is chezmoi-ignored.
Secrets are set at deploy time and never committed.
Prerequisites: a Cloudflare account with Workers and KV, plus `wrangler` logged in.
Create the KV namespace that holds the last-seen fingerprint: `wrangler kv namespace create FLEET_THREAT_STATE` (run inside `workers/fleet-threat-watch/`).
Paste the returned namespace id into `wrangler.jsonc` over `REPLACE_WITH_KV_NAMESPACE_ID`.
Set the secrets (values never touch the repo): `wrangler secret put SHODAN_API_KEY`, `wrangler secret put CENSYS_PAT`, `wrangler secret put GODOXY_NTFY_TOKEN`, `wrangler secret put GH_ISSUE_TOKEN` (a fine-grained personal access token scoped to issues on `phillias/selfhost`).
The Censys leg uses the Platform host-lookup API, which authenticates with a Personal Access Token, not the decommissioned legacy Search ID/secret pair (legacy Search returned 404/403 for every call after 2026-09-30, so the old pair is not read at all).
The captain creates the PAT under the Censys Platform account and adds it to the bws project phillias as CENSYS_PAT (load-keys.sh auto-exports env-shaped vault keys, so no code change is needed once it exists).
Without CENSYS_PAT the Worker logs one structured skip line per run and continues on Shodan plus InternetDB, so the PAT can land after deploy.
If the Platform API answers 4xx demanding an organization scope, set optional cleartext var CENSYS_ORG_ID to the organization ID in `wrangler.jsonc` vars (ids are not secrets).
To disable issue filing without touching secrets, set vars `FILE_ISSUES` to `"0"` in `wrangler.jsonc`.
Regenerate full binding types before deploying: `wrangler types` (replaces the minimal `src/worker-env.d.ts` stub used for offline checks).
Validate without deploying: `wrangler deploy --dry-run`.
Deploy: `wrangler deploy`.
Verify the cron: `wrangler tail` across the next `0 */6 * * *` boundary, or trigger once via the dashboard's "Test cron" for the Worker.
Rotate secrets with `wrangler secret put <NAME>` again; no code change is needed.
