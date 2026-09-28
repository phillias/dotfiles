#!/usr/bin/env bash
# Second REAL live run of d1-registry-refresh.mjs with a watcher capturing:
#  - every curl child cmdline (token-in-argv check, -H @file check)
#  - mkdtemp dir + header file permissions while the run is in flight
#  - exit code, stdout, tmp cleanup
set -u
EVID=/home/phillias/.no-mistakes/evidence/01M3K7XF9GW3PKQGEM9CCVJBBF
SCRIPT=/home/phillias/.no-mistakes/worktrees/79da17cc01eb/01M3K7XF9GW3PKQGEM9CCVJBBF/dot_config/opencode/scripts/executable_d1-registry-refresh.mjs
OUT=$EVID/real-run-2-stdout.txt
ERR=$EVID/real-run-2-stderr.txt
CLOG=$EVID/real-run-2-curl-cmdlines.log
PLOG=$EVID/real-run-2-perms.log
: > "$CLOG"; : > "$PLOG"

started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
node "$SCRIPT" > "$OUT" 2> "$ERR" &
PID=$!
while kill -0 "$PID" 2>/dev/null; do
  for c in $(pgrep -P "$PID" -x curl 2>/dev/null); do
    tr '\0' ' ' < "/proc/$c/cmdline" >> "$CLOG"
    echo >> "$CLOG"
  done
  TMPD=$(ls -d /tmp/d1-registry-refresh-* 2>/dev/null | head -1)
  if [ -n "$TMPD" ] && [ ! -s "$PLOG" ]; then
    stat -c '%a %n' "$TMPD" >> "$PLOG"
    stat -c '%a %n' "$TMPD/cf-auth.txt" "$TMPD/vc-auth.txt" >> "$PLOG"
  fi
  sleep 0.05
done
wait "$PID"; RC=$?
ended=$(date -u +%Y-%m-%dT%H:%M:%SZ)

{
  echo "started=$started ended=$ended exit=$RC"
  echo "--- stdout ---"
  cat "$OUT"
  echo "--- stderr ---"
  cat "$ERR"
  echo "--- curl cmdline samples: $(grep -c . "$CLOG") ---"
  head -3 "$CLOG"
  echo "--- perms ---"
  cat "$PLOG"
  echo "--- tmp leftovers ---"
  ls -d /tmp/d1-registry-refresh-* 2>/dev/null || echo "none"
} > "$EVID/real-run-2-summary.txt"

echo "exit=$RC"
echo "curl samples: $(grep -c curl "$CLOG")"
echo "perms:"; cat "$PLOG" 2>/dev/null
echo "token-in-argv cf=$(grep -cF -- "$CF_AI_GATEWAY_TOKEN" "$CLOG") vc=$(grep -cF -- "$VERCEL_TOKEN" "$CLOG") (expect 0 0)"
echo "leftovers:"; ls -d /tmp/d1-registry-refresh-* 2>/dev/null || echo none