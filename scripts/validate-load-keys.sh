#!/usr/bin/env bash
# Loader validation for dot_agents/private_keys/load-keys.sh.
# Picked up by the no-mistakes test/lint steps; offline by design.
#
# Default (offline, deterministic, no network):
#   - shellcheck clean (pinned via mise)
#   - structural: no .age fallback machinery left in the loader
#   - bws-unreachable sim: ONE warning, zero exports, .age canary untouched
#   - fresh-cache sim: cache honored without calling bws; BWS_/BYS_ excluded
#
# --live (networked; run manually pre-merge and for post-merge fleet testing):
#   - fresh `env -i` shell sources the loader copy in this worktree against
#     the real vault and must export all expected env names with zero
#     warnings and zero fallback noise. Expected names are the regression
#     contract (superset assertions pass; removals fail loudly).
set -euo pipefail
cd "$(dirname "$0")/.."
repo=$(git rev-parse --show-toplevel)
loader="$repo/dot_agents/private_keys/load-keys.sh"
fail=0

# Every env name the pre-redesign _keys_map exported (38 mapped) plus the
# derived names for the migrated-but-unmapped secrets (20) — names only,
# never values. 100% coverage of this list is the captain's merge gate.
expected_envs='ABLITERATION_API_KEY
AGNES_API_KEY
AIHUBMIX_KEY
AISA_KEY
AI_GATEWAY_API_KEY
ALTHUB_CO_ZA_API_RSS_KEY
ANIMEZ_TO_RSS_KEY
ANTHROPIC_KEY
ATLASCLOUD_API_KEY
BASETEN_API_KEY
CEREBRAS_API_KEY
CF_AI_GATEWAY_TOKEN
CLOUDFLARE_API_KEY
CLOUDFLARE_API_TOKEN
COMMAND_CODE_API_KEY
COMPOSIO_API_KEY
COMPOSIO_FOR_YOU_KEY
DATAFAST_KEY
DEEPINFRA_API_KEY
EXA_API_KEY
FAL_KEY
FIREWORKS_API_KEY
FRIENDLI_API_KEY
GITHUB_MODELS_API_KEY
GOOGLE_API_KEY
GROQ_API_KEY
HF_API_KEY
INTERN_API_KEY
KENARI_API_KEY
META_KEY
MISTRAL_API_KEY
NOCENSOR_KEY
NVIDIA_API_KEY
OPENCODE_API_KEY
OPENROUTER_API_KEY
PERPLEXITY_KEY
PHOENIXGROVE_API_KEY
PHOENIXGROVE_CODING_PLAN_API_KEY
PROWLARR_PHILLIAS_CC_API_KEY
QWEN_API_KEY
RAPIDSEEDBOX_UTORRENT_PASSWORD
SAMBANOVA_API_KEY
SEEDPOOL_API_TOKEN
SEEVIO_API_KEY
SKYWORK_KEY
SPEEDAPP_IO_API_TOKEN
SYNTHETIC_API_KEY
TELEGRAM_API_KEY
TELEGRAM_CHAT_ID
TELNYX_API_KEY
TELNYX_PUBLIC_KEY
TESTSPRITE_KEY
TOGETHER_API_KEY
TREG_KEY
TSFM_API_KEY
TYPESAFE_KEY
VERCEL_TOKEN
ZHIPU_API_KEY'

tmp_root=""
# shellcheck disable=SC2329  # invoked indirectly via the EXIT trap below
cleanup() {
  case "${tmp_root:-}" in
    /tmp/dotfiles-loadkeys.*|/var/tmp/dotfiles-loadkeys.*)
      rm -rf -- "$tmp_root"
      ;;
  esac
}
trap cleanup EXIT
tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-loadkeys.XXXXXXXXXX")

shellcheck_run() { mise x shellcheck@0.11.0 -- shellcheck "$@"; }

# Fails with context and flips the exit flag.
bail() { echo "FAIL: $*" >&2; fail=1; }
pass() { echo "PASS: $*"; }

# Build a fake HOME with a default profile and a dummy token; never real
# secret material. $1 = fake home dir.
make_fake_home() {
  mkdir -p "$1/.agents/keys/phillias" "$1/.agents/keys/retired/phillias" "$1/.local/bin"
  ln -s "$(command -v jq)" "$1/.local/bin/jq"
  printf 'sim-dummy-token\n' > "$1/.agents/keys/phillias/.bws-token"
  ln -s phillias "$1/.agents/keys/default"
  printf 'BURNED-CANARY\n' > "$1/.agents/keys/retired/phillias/.canary.age"
}

# offline shell with system tools only: jq/sh/date/stat/readlink reachable,
# no bws on PATH, no mise install tree under the (fake) HOME.
sim_path="/usr/local/bin:/usr/bin:/bin"

echo "== shellcheck"
if shellcheck_run "$loader"; then
  pass "shellcheck clean (mise x shellcheck@0.11.0)"
else
  bail "shellcheck reported findings"
fi

echo "== sim: bws binary missing (fake HOME, no bws anywhere)"
fh="$tmp_root/nobws"
make_fake_home "$fh"
out=$(env -i HOME="$fh" PATH="$sim_path" /bin/sh -c ". '$loader'; env" \
      2>"$tmp_root/nobws.err") || true
warn_count=$(grep -c '^load-keys:' "$tmp_root/nobws.err" || true)
[ "$warn_count" -eq 1 ] || bail "expected exactly 1 warning, got $warn_count"
grep -q 'reason=bws-binary-missing' "$tmp_root/nobws.err" \
  || bail "warning does not name reason=bws-binary-missing"
if printf '%s\n' "$out" | grep -q '^SIM_TEST_KEY='; then
  bail "exported a key despite bws being unavailable"
fi
[ -e "$fh/.agents/keys/.bws-fallback.log" ] && bail ".bws-fallback.log created"
[ "$(cat "$fh/.agents/keys/retired/phillias/.canary.age")" = "BURNED-CANARY" ] \
  || bail ".age canary was modified"
[ "$fail" -eq 0 ] && pass "one warning, zero exports, no fallback artifacts"

echo "== sim: bws fetch fails (shim exits 1) — one warning, no exports"
fh="$tmp_root/shimfail"
make_fake_home "$fh"
mkdir -p "$tmp_root/shimbin"
printf '#!/bin/sh\nprintf "call\\n" >> "%s/bws-called"\nexit 1\n' "$tmp_root" \
  > "$tmp_root/shimbin/bws"
chmod +x "$tmp_root/shimbin/bws"
out=$(env -i HOME="$fh" PATH="$tmp_root/shimbin:$sim_path" /bin/sh -c \
      ". '$loader'; env" 2>"$tmp_root/shimfail.err") || true
warn_count=$(grep -c '^load-keys:' "$tmp_root/shimfail.err" || true)
[ "$warn_count" -eq 1 ] || bail "expected exactly 1 warning, got $warn_count"
grep -q 'reason=bws-fetch-failed' "$tmp_root/shimfail.err" \
  || bail "warning does not name reason=bws-fetch-failed"
[ -f "$tmp_root/bws-called" ] || bail "shim never invoked (fetch path not exercised)"
if printf '%s\n' "$out" | grep -q '^SIM_TEST_KEY='; then
  bail "exported a key despite bws fetch failure"
fi
[ "$(cat "$fh/.agents/keys/retired/phillias/.canary.age")" = "BURNED-CANARY" ] \
  || bail ".age canary was modified"
[ "$fail" -eq 0 ] && pass "fetch failure warns once, exports nothing, canary intact"

echo "== sim: fresh cache honored without bws; BWS_/BYS_ excluded"
fh="$tmp_root/cachehit"
make_fake_home "$fh"
rm -f "$tmp_root/bws-called"
cat > "$fh/.agents/keys/.bws-cache-phillias.json" <<'JSON'
[
  {"id":"1","key":"SIM_TEST_KEY","value":"sim-test-value","note":""},
  {"id":"6","key":"ANTHROPIC_KEY","value":"anthropic-vault-value","note":""},
  {"id":"7","key":"ANTHROPIC_API_KEY","value":"stale-cache-value","note":""},
  {"id":"2","key":"BWS_SIM_COMPOSE","value":"never-export","note":""},
  {"id":"3","key":"BYS_SIM_TYPO","value":"never-export","note":""},
  {"id":"4","key":".sim-dot-original","value":"never-export","note":""},
  {"id":"5","key":"SIM_MULTILINE","value":"line1\nline2","note":""}
]
JSON
out=$(env -i HOME="$fh" ANTHROPIC_API_KEY="inherited-value" PATH="$tmp_root/shimbin:$sim_path" /bin/sh -c \
      ". '$loader'; env" 2>"$tmp_root/cachehit.err") || true
[ ! -e "$tmp_root/bws-called" ] || bail "bws was called despite fresh cache"
[ -s "$tmp_root/cachehit.err" ] && bail "fresh-cache path emitted unexpected stderr"
printf '%s\n' "$out" | grep -qx 'SIM_TEST_KEY=sim-test-value' \
  || bail "SIM_TEST_KEY not exported from fresh cache"
printf '%s\n' "$out" | grep -qx 'SIM_MULTILINE=line1' \
  || bail "multi-line value not preserved"
printf '%s\n' "$out" | grep -qx 'line2' \
  || bail "multi-line value second line missing"
printf '%s\n' "$out" | grep -qx 'ANTHROPIC_KEY=anthropic-vault-value' \
  || bail "ANTHROPIC_KEY not exported from fresh cache"
if printf '%s\n' "$out" | grep -q '^ANTHROPIC_API_KEY='; then
  bail "retired ANTHROPIC_API_KEY survived inherited or cached input"
fi
for banned in BWS_SIM_COMPOSE BYS_SIM_TYPO; do
  if printf '%s\n' "$out" | grep -q "^$banned="; then
    bail "excluded namespace was exported: $banned"
  fi
done
if printf '%s\n' "$out" | grep -q '^\.sim-dot-original='; then
  bail "dot-prefixed key was exported"
fi
[ "$(cat "$fh/.agents/keys/retired/phillias/.canary.age")" = "BURNED-CANARY" ] \
  || bail ".age canary was modified"
[ "$fail" -eq 0 ] && pass "cache honored offline, exclusions enforced, multiline safe"

echo "== sim: stale cache (1h old) served when bws fetch fails; backoff stamps cache"
fh="$tmp_root/stalehit"
make_fake_home "$fh"
rm -f "$tmp_root/bws-called"
cat > "$fh/.agents/keys/.bws-cache-phillias.json" <<'JSON'
[
  {"id":"1","key":"SIM_TEST_KEY","value":"sim-test-value","note":""},
  {"id":"2","key":"BWS_SIM_COMPOSE","value":"never-export","note":""}
]
JSON
touch -d '1 hour ago' "$fh/.agents/keys/.bws-cache-phillias.json"
m1=$(stat -c %Y "$fh/.agents/keys/.bws-cache-phillias.json")
out=$(env -i HOME="$fh" PATH="$tmp_root/shimbin:$sim_path" /bin/sh -c \
      ". '$loader'; env" 2>"$tmp_root/stalehit.err") || true
[ -f "$tmp_root/bws-called" ] || bail "stale sim never attempted a live fetch"
[ -s "$tmp_root/stalehit.err" ] && bail "stale-cache fallback emitted unexpected stderr: $(cat "$tmp_root/stalehit.err")"
printf '%s\n' "$out" | grep -qx 'SIM_TEST_KEY=sim-test-value' \
  || bail "SIM_TEST_KEY not exported from stale cache"
if printf '%s\n' "$out" | grep -q '^BWS_SIM_COMPOSE='; then
  bail "excluded namespace was exported from stale cache"
fi
m2=$(stat -c %Y "$fh/.agents/keys/.bws-cache-phillias.json")
[ "$m2" -gt "$m1" ] || bail "failed fetch did not touch the cache (no backoff stamp)"
[ "$fail" -eq 0 ] && pass "stale cache serves exports silently and stamps backoff"

echo "== sim: backoff — next source stays silent without retrying bws"
rm -f "$tmp_root/bws-called"
out=$(env -i HOME="$fh" PATH="$tmp_root/shimbin:$sim_path" /bin/sh -c \
      ". '$loader'; env" 2>"$tmp_root/backoff.err") || true
[ -e "$tmp_root/bws-called" ] && bail "bws retried inside the backoff window"
[ -s "$tmp_root/backoff.err" ] && bail "backoff-window source emitted stderr: $(cat "$tmp_root/backoff.err")"
printf '%s\n' "$out" | grep -qx 'SIM_TEST_KEY=sim-test-value' \
  || bail "SIM_TEST_KEY not exported inside backoff window"
[ "$fail" -eq 0 ] && pass "post-failure sources stay silent for ~5 minutes"

echo "== sim: too-stale cache (25h old) warns once, exports nothing, stays unstamped"
fh="$tmp_root/toostale"
make_fake_home "$fh"
cat > "$fh/.agents/keys/.bws-cache-phillias.json" <<'JSON'
[
  {"id":"1","key":"SIM_TEST_KEY","value":"sim-test-value","note":""}
]
JSON
touch -d '25 hours ago' "$fh/.agents/keys/.bws-cache-phillias.json"
m1=$(stat -c %Y "$fh/.agents/keys/.bws-cache-phillias.json")
out=$(env -i HOME="$fh" PATH="$tmp_root/shimbin:$sim_path" /bin/sh -c \
      ". '$loader'; env" 2>"$tmp_root/toostale.err") || true
warn_count=$(grep -c '^load-keys:' "$tmp_root/toostale.err" || true)
[ "$warn_count" -eq 1 ] || bail "expected exactly 1 warning, got $warn_count"
grep -q 'reason=bws-fetch-failed' "$tmp_root/toostale.err" \
  || bail "warning does not name reason=bws-fetch-failed"
if printf '%s\n' "$out" | grep -q '^SIM_TEST_KEY='; then
  bail "exported a key from a too-stale cache"
fi
m2=$(stat -c %Y "$fh/.agents/keys/.bws-cache-phillias.json")
[ "$m2" -eq "$m1" ] || bail "too-stale cache was stamped (24h bound defeated)"
[ "$fail" -eq 0 ] && pass "ancient cache rejected loudly and left unstamped"

echo "== sim: same-process double source warns only once"
fh="$tmp_root/doublewarn"
make_fake_home "$fh"
env -i HOME="$fh" PATH="$tmp_root/shimbin:$sim_path" /bin/sh -c \
      ". '$loader'; . '$loader'; env" 2>"$tmp_root/doublewarn.err" >/dev/null || true
warn_count=$(grep -c '^load-keys:' "$tmp_root/doublewarn.err" || true)
[ "$warn_count" -eq 1 ] || bail "expected exactly 1 warning across 2 sources, got $warn_count"
[ "$fail" -eq 0 ] && pass "warning suppressed on re-source within one process"

if [ "${1:-}" = "--live" ]; then
  echo "== live: env -i source exports every expected env name (real vault)"
  exports_file="$tmp_root/exports.txt"
  stderr_file="$tmp_root/live.err"
  # PATH without mise shims or ~/.local/bin: forces the loader's own
  # bws resolution (mise latest alias) and proves no ambient variables
  # are required — the fresh-shell contract.
  env -i HOME="$HOME" TERM=dumb PATH="$sim_path" /bin/sh -c \
    ". '$loader'; exec env" > "$exports_file" 2> "$stderr_file" || true
  [ -s "$stderr_file" ] && bail "live source emitted stderr (warnings/fallback noise): $(head -3 "$stderr_file")"
  missing=0
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if ! grep -q "^$name=" "$exports_file"; then
      echo "  missing export: $name" >&2
      missing=1
    else
      val=$(grep "^$name=" "$exports_file" | head -1 | cut -d= -f2-)
      [ -n "$val" ] || { echo "  empty export: $name" >&2; missing=1; }
    fi
  done <<< "$expected_envs"
  [ "$missing" -eq 0 ] || bail "live source did not export every expected env name"
  # Vault BWS_/BYS_ names must never be exported. The loader's own
  # bookkeeping vars (BWS_ACCESS_TOKEN, BWS_TOKEN_FILE, BWS_BIN) are the
  # only legitimate BWS_* exports.
  while IFS= read -r line; do
    var=${line%%=*}
    case "$var" in
      BWS_ACCESS_TOKEN|BWS_TOKEN_FILE|BWS_BIN) continue ;;
    esac
    case "$var" in
      BWS_*|BYS_*) bail "vault $var exported; namespace exclusion failed" ;;
    esac
  done < <(grep -E '^(BWS_|BYS_)' "$exports_file" || true)
  [ "$fail" -eq 0 ] && pass "live env -i: all 58 expected names exported, no BWS_/BYS_ leakage, zero stderr"
else
  echo "note: offline mode only; run with --live for the env -i vault coverage proof"
fi

if [ "$fail" -eq 0 ]; then
  echo "validate-load-keys: all checks passed"
else
  echo "validate-load-keys: FAILED"
fi
exit "$fail"
