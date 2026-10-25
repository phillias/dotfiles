#!/bin/sh
# Resolve fleet vault secrets (BWS phillias profile via the shared loader),
# then exec the given script under node. Used by systemd units
# (dynamic-audit, d1-registry-refresh) so timer-driven runs authenticate
# with live vault tokens instead of stale env-file copies.
#
# Secrets resolved: CF_AI_GATEWAY_TOKEN (gateway route API),
# VERCEL_TOKEN, CLOUDFLARE_DEPLOY_TOKEN (wrangler D1 mirror auth;
# canonical wrangler/D1 token going forward — dot-prefixed *.secrets
# are being retired).
# On BWS fetch failure load-keys.sh falls back to the 5-minute (max 24h)
# cache at ~/.agents/keys/.bws-cache-*.json; a fully stale cache means
# the token is simply absent and the script fails loudly (audit_error).
. "$HOME/.agents/keys/load-keys.sh"
# wrangler reads CLOUDFLARE_API_TOKEN; the canonical value now lives in
# CLOUDFLARE_DEPLOY_TOKEN, so map it before exec.
if [ -n "$CLOUDFLARE_DEPLOY_TOKEN" ]; then
  export CLOUDFLARE_API_TOKEN="$CLOUDFLARE_DEPLOY_TOKEN"
fi
exec "$HOME/.local/share/mise/shims/node" "$1"
