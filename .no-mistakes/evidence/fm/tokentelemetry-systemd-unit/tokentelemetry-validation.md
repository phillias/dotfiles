# TokenTelemetry systemd unit + CI pi-config fix — validation evidence

Branch: fm/tokentelemetry-systemd-unit
Base: c4709fdebc505a1790576d82eaa58188e21d19e0
Target: 869da8af3cbe137b7c57cc95527947bcd549b976

## Files changed (git diff base..HEAD)

- `.github/workflows/ci.yml` (+11): comment-aware template stripping in pi-config validator
- `dot_config/systemd/user/tokentelemetry.service` (-12/+20): native systemd unit for fork deployment

## Scenario 1: systemd unit is syntactically valid

```
$ systemd-analyze verify dot_config/systemd/user/tokentelemetry.service
exit: 0
```

## Scenario 2: ExecStart wrapper structure

```
ExecStart=/bin/bash -c 'export ANTHROPIC_API_KEY="$(cat "%h/.agents/keys/default/.anthropic-key")"; export NEXT_PUBLIC_API_BASE=""; exec %h/.local/share/mise/shims/node %h/tokentelemetry/bin/cli.js --port 13000 --api-port 18000 --host 127.0.0.1 --no-open'
```

Components checked: bash -c wrapper YES, ANTHROPIC_API_KEY read-from-file export YES,
NEXT_PUBLIC_API_BASE="" YES, exec mise-shim node YES, cli.js with --port 13000
--api-port 18000 --host 127.0.0.1 --no-open YES.

## Scenario 3: Environment and resource limits

- Environment=TOKENTELEMETRY_DATA_DIR=%h/.tokentelemetry YES
- Environment=TOKENTELEMETRY_HOME=%h/.tokentelemetry YES
- Environment=NODE_ENV=production YES
- Environment=DO_NOT_TRACK=1 YES
- Environment=TT_NO_UPDATE_CHECK=1 YES
- MemoryHigh=1536M YES, MemoryMax=2G YES, CPUQuota=100% YES, CPUWeight=100 YES,
  IOWeight=100 YES, TasksMax=128 YES
- WorkingDirectory=%h/tokentelemetry YES, Restart=on-failure YES, RestartSec=5 YES
- WantedBy=default.target YES, Type=simple YES

## Scenario 4: CI pi-config validator handles template comments

New code (comment-aware + template stubbing) — runs clean:

```
$ python3 - <<'EOF'
... (exact CI script) ...
print('pi config valid')
EOF
pi config valid
exit: 0
```

Regression: old CI code (without comment stripping) on the same files fails:

```
json.decoder.JSONDecodeError: Expecting property name enclosed in double quotes: line 1 column 2 (char 1)
```

This confirms the fix was needed: the .tmpl files contain `{{- /* ... */ -}}`
comments that the old single-pass `{{}}` stub left in place, breaking JSON parse.

## ANSI: no API key value committed

`git grep -l "sk-ant-"` over the repo (non-md): no matches. Unit references the
key only by path (`%h/.agents/keys/default/.anthropic-key`).