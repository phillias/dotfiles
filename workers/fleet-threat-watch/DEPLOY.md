# Deploying fleet-threat-watch
This Worker is deploy-only source: it runs on Cloudflare's cron, not on fleet boxes.
Nothing here is installed to home; `workers/` is chezmoi-ignored.
Secrets are set at deploy time and never committed.
Prerequisites: a Cloudflare account with Workers and KV, plus `wrangler` logged in.
Create the KV namespace that holds the last-seen fingerprint: `wrangler kv namespace create FLEET_THREAT_STATE` (run inside `workers/fleet-threat-watch/`).
Paste the returned namespace id into `wrangler.jsonc` over `REPLACE_WITH_KV_NAMESPACE_ID`.
Set the five secrets (values never touch the repo): `wrangler secret put SHODAN_API_KEY`, `wrangler secret put CENSYS_API_ID`, `wrangler secret put CENSYS_API_TOKEN`, `wrangler secret put GODOXY_NTFY_TOKEN`, `wrangler secret put GH_ISSUE_TOKEN` (a fine-grained personal access token scoped to issues on `phillias/selfhost`).
To disable issue filing without touching secrets, set vars `FILE_ISSUES` to `"0"` in `wrangler.jsonc`.
Regenerate full binding types before deploying: `wrangler types` (replaces the minimal `src/worker-env.d.ts` stub used for offline checks).
Validate without deploying: `wrangler deploy --dry-run`.
Deploy: `wrangler deploy`.
Verify the cron: `wrangler tail` across the next `0 */6 * * *` boundary, or trigger once via the dashboard's "Test cron" for the Worker.
Rotate secrets with `wrangler secret put <NAME>` again; no code change is needed.
