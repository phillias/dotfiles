# Evidence: x-research lockfile regen (chore/x-research-lockfile-regen)

Validated live against npm registry (registry.npmjs.org) and the actual skill runtime (bun 1.3.14), in disposable copies under /tmp.

## 1. Clean install from the new lockfile (npm ci)

Disposable copy of `dot_agents/skills/x-research/` (source of truth: worktree at target commit 1f7eecb):

```
$ npm ci --no-audit --no-fund
npm WARN deprecated @hey-api/client-axios@0.2.12 ...
npm WARN deprecated composio-core@0.5.39 ...
npm WARN deprecated uuid@10.0.0 ...
npm WARN deprecated @composio/mcp@1.0.3-0 ...
added 127 packages in 21s
EXIT: 0
```

npm ci is the strict lockfile consumer: it fails if package-lock.json is out of sync with
package.json. It passed → lockfile internally consistent, fully registry-resolvable, and
matches the untouched package.json (`{"composio-core": "^0.5.39"}`).

## 2. Installed versions match the intended lift

| package | base lockfile | new lockfile | required to clear | status |
|---|---|---|---|---|
| axios | 1.13.5 | **1.20.0** | >=1.18.0 | cleared |
| langsmith | 0.5.0 | **0.10.8** | >=0.6.0 | cleared |
| follow-redirects | 1.15.11 | **1.16.1** | >=1.15.9 | cleared |
| form-data | 4.0.5 | **4.0.6** | >=4.0.6 | cleared |
| @ai-sdk/provider-utils | 4.0.14 | **5.0.53** | >=5.0.53 | cleared |
| uuid | 10.0.0 | 10.0.0 | >=11.1.1 | still vulnerable (intent: semver-locked) |
| tmp | 0.0.33 | 0.0.33 | >=0.2.6 | still vulnerable (intent: semver-locked) |
| composio-core | 0.5.39 | 0.5.39 | — | unchanged direct dep |

Semver-lock confirmed: composio-core@0.5.39 declares `"uuid": "^10.0.0"`, so npm cannot
lift uuid to 11.x/13.x without overrides that force a major jump in a package we do not own.
tmp is transitively pinned by inquirer's range. Both deliberately left, per intent.

## 3. npm audit: live advisory-DB comparison base vs new

`npm audit --json` on both lockfiles (same current advisory DB; exit 1 = vulns found, expected):

- Vulnerable packages NEW only (introduced by this regen): **none**
- Vulnerable packages cleared (in base, gone in new): @ai-sdk/gateway, @ai-sdk/openai,
  @ai-sdk/provider-utils, @langchain/core, @langchain/langgraph, @langchain/langgraph-checkpoint,
  ai, axios (high), follow-redirects, form-data (high), langchain, langsmith (high) — 12 packages
  including all five targeted ones.
- Still flagged in both: uuid (moderate, `<11.1.1`), tmp (high, `<=0.2.5`) — the 4 remaining
  alerts per intent — plus pre-existing inquirer/composio-core advisories unchanged (in base
  lockfile too, not introduced here).

Dedup metric: lockfile has 127 distinct packages / 127 node_modules entries (no duplicates),
net -161 lines in the diff — matches intent.

## 4. Runtime loads and runs with the new dependency set (bun, real CLI)

`/tmp/xr-locktest` copy, `bun x-search.ts`:

```
$ bun x-search.ts watchlist
Watchlist is empty. Add accounts with: watchlist add <username>
EXIT: 0
```

Full module graph (composio-core @ 0.5.39, axios 1.20.0, langsmith, ai SDK, inquirer, ...)
loads and the CLI executes correctly — dependency-graph validity end-to-end.

```
$ bun x-search.ts search "test query"
Error: Composio 410: {"error":"This endpoint is no longer available. Please upgrade to v3 APIs. "}
EXIT: 1
```

Live outbound call through the upgraded axios/hc tree reached Composio's API (server 410).
composio-core version is byte-identical (0.5.39) in base and new lockfiles, so the 410 —
Composio's upstream end-of-life of v2 endpoints — is pre-existing upstream behavior, not a
regression from this change. Real X search requires the `bird` CLI or COMPOSIO_API_KEY /
X credentials, which were out of reach for this test run.

## 5. Hygiene

- Worktree `git status --porcelain` clean after testing (no transient artifacts left behind).
- Disposable /tmp copies (`/tmp/xr-locktest`, `/tmp/xr-locktest-base`) removed after capture.