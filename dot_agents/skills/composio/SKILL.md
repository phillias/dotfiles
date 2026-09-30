---
name: composio
description: Composio REST API patterns for agents — list connected accounts, execute Composio tools, and proxy direct calls to connected-provider APIs (Google Drive, Gmail, etc.) using Composio's stored OAuth. Use when a local CLI's own OAuth has expired (e.g. gws-axi refresh token dead), when the npm/pip `composio` packages turn out to be placeholders with no CLI, when the captain mentions Composio, or when Google Drive/Gmail access is needed and other lanes are blocked. Includes the download-via-proxy pattern and hard limits (no request-body support, redacted tokens, no local-file upload).
---

# composio — REST API v3.1 patterns

The npm and pip `composio` packages are placeholders (no usable CLI). The
usable surface is the REST API. All calls go to
`https://backend.composio.dev/api/v3.1` with header `x-api-key: $COMPOSIO_API_KEY`
(the key lives in Bitwarden / `~/.agents/keys/default/.composio-key`, exported
as `COMPOSIO_API_KEY` by load-keys.sh).

## Connected accounts

```sh
curl -s -H "x-api-key: $COMPOSIO_API_KEY" \
  https://backend.composio.dev/api/v3.1/connected_accounts
```

Lists every connection: `id`, `user_id`, `status` (`ACTIVE`), `appName`.
Keep the pair (connected_account_id, user_id) — both are required for every
tool execution. If `user_id` is omitted, the API returns error 1811.

## Tool execution

```sh
POST /api/v3.1/tools/execute/{TOOL_SLUG}
{"connected_account_id": "<ca_...>", "user_id": "<user>", "arguments": {...}}
```

- `arguments` = structured params per the tool schema; `text` = natural-language
  args (works well for e.g. `GOOGLEDRIVE_FIND_FOLDER` with
  `"text": "Find the folder named Dads-Writings"`).
- Response: `data` (or `data.data`) carries the tool output.
- Useful Google Drive slugs: `GOOGLEDRIVE_FIND_FOLDER`, `GOOGLEDRIVE_FIND_FILE`,
  `GOOGLEDRIVE_LIST_FILES`, `GOOGLEDRIVE_DOWNLOAD_FILE`,
  `GOOGLEDRIVE_GET_FILE_METADATA`, `GOOGLEDRIVE_CREATE_FILE` (folders),
  `GOOGLEDRIVE_UPLOAD_FROM_URL`.

## Proxy (direct provider API with Composio's OAuth)

```sh
POST /api/v3.1/tools/execute/proxy
{
  "connected_account_id": "<ca_...>", "user_id": "<user>",
  "endpoint": "https://www.googleapis.com/drive/v3/files",
  "method": "GET",
  "parameters": [{"name": "q", "in": "query", "value": "<drive query>", "type": "query"}]
}
```

- `parameters` items: `{name, in, value, type}` with `in` = "query"|"header"
  and **`type` must equal `in`** (type is also "query"/"header", not "string").
- Works for DELETE too (no body needed) — e.g. trashing junk Drive files.

### Download pattern

Add `alt=media` as a query parameter; the response JSON contains
`binary_data.url` — a temporary R2 URL. Fetch that URL directly for the bytes.

## Hard limits (verified live — do not retry these paths)

- **No request-body support**: proxy `parameters` accepts only query/header;
  a "body" entry fails validation, and POSTing to provider APIs without body
  processing creates junk artifacts (e.g. "Untitled" files on Drive). Creating
  folders: use the `GOOGLEDRIVE_CREATE_FILE` tool with
  `mimeType: application/vnd.google-apps.folder` instead.
- **Tokens are redacted**: the connected-account detail response returns the
  access/refresh tokens redacted — you cannot extract the OAuth token for
  direct API use.
- **Local files cannot be uploaded**: upload tools require a Composio-hosted
  `s3key` from a prior Composio download, and there is no public endpoint to
  push local bytes into Composio storage. `GOOGLEDRIVE_UPLOAD_FROM_URL` fetches
  from an HTTPS URL instead.
- **Never route private content through a public tunnel to satisfy
  UPLOAD_FROM_URL.** Private file uploads use a directly authenticated path
  (gws-axi, gh-axi, provider CLIs) or escalate for credential re-auth;
  public-tunnel exposure of private files is a captain-flagged anti-pattern.
