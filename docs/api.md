# Readout HTTP API v1

This is the contract between the `readout` CLI and a readout server. Breaking changes need
`/api/v2`. Additive response fields are allowed; clients must ignore fields they do not know.

## Conventions

- Base URL: the server origin, for example `https://readout.hillig.dev`. All endpoints live under
  `/api/v1`.
- Every request carries `Authorization: Bearer <api key>` and, from the CLI,
  `X-Readout-Client: cli/<semver>` (for example `cli/0.1.0`). A missing client header is allowed.
- Request and response bodies are JSON unless stated otherwise. Publishing uses `multipart/form-data`.
- Timestamps are ISO 8601 UTC strings (`2026-11-13T09:30:00.000Z`).
- Errors use one shape for every non-2xx response:

  ```json
  { "error": { "code": "<slug>", "message": "<human text>" } }
  ```

## Limits

| Limit | Value |
|---|---|
| Files per page | 200 |
| Bytes per file | 26214400 (25 MiB) |
| Bytes per page | 52428800 (50 MiB) |
| Default TTL | 2592000 s (30 days) |
| Minimum TTL | 60 s |
| Maximum TTL | 31536000 s (365 days) |

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/v1/me` | Check the token, return the account |
| `POST` | `/api/v1/pages` | Publish a file or a folder |
| `GET` | `/api/v1/pages` | List the caller's pages, newest first |
| `DELETE` | `/api/v1/pages/:id` | Delete one of the caller's pages |

### `GET /api/v1/me`

Response `200`:

```json
{ "email": "user@example.com", "name": "User" }
```

Errors: `unauthorized` 401, `client_outdated` 426, `rate_limited` 429.

### `POST /api/v1/pages`

Request: `multipart/form-data` with these parts.

- `manifest`: a JSON part (`Content-Type: application/json`).

  ```json
  {
    "title": "optional",
    "entry": "optional relative path",
    "name": "optional stable key",
    "ttl": 2592000,
    "keep": false,
    "files": [
      { "field": "f0", "path": "index.html" },
      { "field": "f1", "path": "assets/mermaid.min.js" }
    ]
  }
  ```

  | Field | Type | Rule |
  |---|---|---|
  | `title` | string, optional | Page title. Default: the entry's `<title>`, else its first `# ` heading, else the entry filename. |
  | `entry` | string, optional | Relative path of the file to open. Must equal one of the `files[].path` values. |
  | `name` | string, optional | Stable per-owner key. See "Name upsert". |
  | `ttl` | integer, optional | Seconds, 60 to 31536000. Default 2592000. Invalid with `keep: true`. |
  | `keep` | boolean, optional | `true` means the page never expires. |
  | `files` | array, required | One element per file part. Not empty. |

- One binary part per file. Each part is named by its manifest `field` (`f0`, `f1`, ...).

Relative paths travel only in the manifest. A server must not read paths from multipart filenames,
because multipart parsers may strip directory parts. A client must not rely on them either.

**Path rules.** A path is relative and uses `/` separators. It has no empty segment, no `.` or
`..` segment, no leading `/`, no backslash and no control character. Each segment uses only
`A-Z a-z 0-9 . _ @ + -` and space. A path has at most 8 segments and at most 255 bytes. Paths are
unique within a page.

**Entry selection.** If `entry` is given it must be one of the paths. Otherwise the server picks:
the only file; else `index.html`; else the only `.html` file; else `index.md`, then `README.md`;
else the only `.md` file; else the request fails with `entry_required`.

**Content types.** The server sets each file's content type from its extension. Content types sent
by the client are ignored.

**Name upsert.** If `name` matches an existing page of the same owner, the server stores the new
files as a new version, switches the page to it, resets the expiry and deletes the old version's
files. The page `id` and its URL stay the same, and the response has `replaced: true`.

**Atomicity.** The server writes all files first and the page record last. If any step fails it
removes what it wrote (best effort) and returns `internal`.

Response `201`:

```json
{
  "id": "Zq3k9T0vWl8xYb2A",
  "url": "https://readout.hillig.dev/p/Zq3k9T0vWl8xYb2A",
  "title": "Report",
  "expiresAt": "2026-11-13T09:30:00.000Z",
  "files": 3,
  "bytes": 812345,
  "replaced": false
}
```

`expiresAt` is `null` when the page is kept. `url` is the page address for a signed-in reader.

Errors: `unauthorized` 401, `client_outdated` 426, `invalid_manifest` 400, `invalid_path` 400,
`duplicate_path` 400, `missing_file` 400, `entry_required` 400, `entry_not_found` 400,
`invalid_ttl` 400, `too_many_files` 413, `file_too_large` 413, `payload_too_large` 413,
`rate_limited` 429, `internal` 500.

### `GET /api/v1/pages`

Lists the caller's pages, newest first. Never includes another user's pages.

Response `200`:

```json
{
  "pages": [
    {
      "id": "Zq3k9T0vWl8xYb2A",
      "url": "https://readout.hillig.dev/p/Zq3k9T0vWl8xYb2A",
      "title": "Report",
      "name": null,
      "entry": "index.html",
      "files": 3,
      "bytes": 812345,
      "createdAt": "2026-10-14T09:30:00.000Z",
      "updatedAt": "2026-10-14T09:30:00.000Z",
      "expiresAt": "2026-11-13T09:30:00.000Z"
    }
  ]
}
```

`name` and `expiresAt` are `null` when unset or kept.

Errors: `unauthorized` 401, `client_outdated` 426, `rate_limited` 429.

### `DELETE /api/v1/pages/:id`

Deletes one of the caller's pages and its files. Response `204` with no body. A page that does not
exist, or belongs to another user, returns `not_found` 404.

Errors: `unauthorized` 401, `client_outdated` 426, `not_found` 404, `rate_limited` 429,
`internal` 500.

## Error codes

| Code | Status | Meaning |
|---|---|---|
| `unauthorized` | 401 | Missing, unknown, expired or revoked API key |
| `client_outdated` | 426 | `X-Readout-Client` is below the server's minimum; the message says how to upgrade |
| `invalid_manifest` | 400 | The manifest part is missing, is not valid JSON, or has wrong field types |
| `invalid_path` | 400 | A path breaks the path rules; the message names the path |
| `duplicate_path` | 400 | Two files share a path |
| `missing_file` | 400 | A manifest entry has no matching file part |
| `entry_required` | 400 | No `entry` was given and none could be chosen |
| `entry_not_found` | 400 | `entry` is not one of the paths |
| `invalid_ttl` | 400 | `ttl` is out of range, or given together with `keep: true` |
| `length_required` | 411 | The request has no `Content-Length`; chunked uploads are not accepted |
| `too_many_files` | 413 | More than 200 files |
| `file_too_large` | 413 | A file is over 25 MiB |
| `payload_too_large` | 413 | The page is over 50 MiB in total |
| `rate_limited` | 429 | Too many requests for this key |
| `not_found` | 404 | No such page for this caller |
| `internal` | 500 | Server failure; retry later |

## Viewing (reference)

The `url` of a page opens `GET /p/:id` in a browser. It requires a signed-in session of the owner,
then redirects to a time-limited capability URL of the form

```
/c/<id>/<exp>.<sig>/<path>
```

`exp` is a Unix time in seconds, 12 hours ahead. `sig` is the first 32 characters of
`base64url(HMAC-SHA256(secret, "v1:" + id + ":" + exp))`. Content under `/c/` is served in a
sandbox without cookies. Clients do not call these routes.
