# Phabricator

When you encounter a `https://phabricator.<sub>.<domain>/T<id>` link, use `curl` to fetch task details and related data via the `Conduit` API.

## Required behavior

- Always use Conduit API calls (`$PHAB/api/...`) first.
- Do not use browser/web scraping for Phabricator task URLs.
- SSO-protected pages usually return a Google sign-in HTML page, not task content.
- If API calls fail, troubleshoot token/auth first, then retry API calls.

## Authentication

1. Look for an environment variable named `$PHABRICATOR_TOKEN` or `$CONDUIT_TOKEN`.
2. Look for a token in `~/.arcrc`:

   ```bash
   jq -r '.hosts | to_entries[] | select(.key | test("phabricator")) | .value.token // empty' ~/.arcrc
   ```

3. Look for a token in 1Password (`op item get "Phabricator Token" --fields label=credential --reveal`).
4. Ask the user to provide a token.

After finding a token, verify it before task calls:

```bash
curl -s -X POST "$PHAB/api/user.whoami" \
  -d api.token="$TOKEN" | jq .
```

If `error_code` is not null, token/auth is invalid and must be fixed first.

## Base URL

Derive the Phabricator base URL from the link you see:

`https://phabricator.example.com/T67890` → `PHAB="https://phabricator.example.com"`

The API base is `$PHAB/api/`.

## Quick reliable flow (copy/paste)

Use this when starting from a task link and you need a robust path that avoids SSO HTML pages.

```bash
PHAB_LINK="https://phabricator.skroutz.gr/T241638"
PHAB="${PHAB_LINK%%/T*}"
ID="${PHAB_LINK#${PHAB}/T}"
ID="${ID%%/}"

TOKEN="${PHABRICATOR_TOKEN:-${CONDUIT_TOKEN:-}}"

if [ -z "$TOKEN" ] && [ -f "$HOME/.arcrc" ]; then
  TOKEN="$(jq -r '.hosts | to_entries[] | select(.key | test("phabricator")) | .value.token // empty' ~/.arcrc)"
fi

if [ -z "$TOKEN" ] && command -v op >/dev/null 2>&1; then
  TOKEN="$(op item get "Phabricator Token" --fields label=credential --reveal 2>/dev/null || true)"
fi

[ -n "$TOKEN" ] || { echo "No Phabricator token found"; exit 1; }

curl -s -X POST "$PHAB/api/maniphest.search" \
  -d api.token="$TOKEN" \
  -d "constraints[ids][0]=$ID" \
  -d "attachments[projects]=1" \
  -d "attachments[subscribers]=1" \
  -d limit=1 | jq -r '
if .error_code then
  "ERROR: \(.error_code) \(.error_info // "")" | halt_error(1)
elif (.result.data | length) == 0 then
  "Task not found" | halt_error(1)
else
  .result.data[0] |
  "T\(.id): \(.fields.name // "")",
  "Status: \(.fields.status.name // "") | Priority: \(.fields.priority.name // "")",
  "",
  (.fields.description.raw // "")
end
'
```

## Fetch a task by ID (T\<id\>)

Extract the numeric ID from the link (e.g. `T242861` to `242861`).

```bash
PHAB="<base-url-from-link>"
TOKEN="<token>"
curl -s -X POST "$PHAB/api/maniphest.search" \
  -d api.token="$TOKEN" \
  -d "constraints[ids][0]=<id>" \
  -d "attachments[projects]=1" \
  -d "attachments[subscribers]=1" \
  -d limit=1 | jq .
```

Response fields of interest:

- `result.data[0].fields.name` — title
- `result.data[0].fields.description.raw` — description body
- `result.data[0].fields.ownerPHID` — assignee PHID (null = unassigned)
- `result.data[0].fields.authorPHID` — author PHID
- `result.data[0].fields.status.{value,name,color}` — status
- `result.data[0].fields.priority.name` — priority
- `result.data[0].fields.dateCreated` / `dateModified` — epoch timestamps
- `result.data[0].fields.dateClosed` — epoch timestamp, null if open
- `result.data[0].fields.closerPHID` — who resolved it
- `result.data[0].attachments.projects.projectPHIDs` — associated project PHIDs

## Compact task summary

```bash
PHAB="<base-url>" TOKEN="<token>" ID="<id>"
curl -s -X POST "$PHAB/api/maniphest.search" \
  -d api.token="$TOKEN" \
  -d "constraints[ids][0]=$ID" \
  -d limit=1 | jq -r '
.result.data[0] |
"T\(.id): \(.fields.name // "")",
"  Status: \(.fields.status.name // "") | Priority: \(.fields.priority.name // "")",
"  Created: \(.fields.dateCreated // "") | Modified: \(.fields.dateModified // "")",
"",
(.fields.description.raw // "")[:3000]
'
```

## Task transactions (history, comments)

```bash
PHAB="<base-url>" TOKEN="<token>" ID="<id>"
curl -s -X POST "$PHAB/api/maniphest.gettasktransactions" \
  -d api.token="$TOKEN" \
  -d "ids[0]=$ID" | jq .
```

Transaction types: `status`, `reassign`, `description`, `title`, `priority`, `core:edge`, `core:create`, `core:subscribers`, `core:space`.

## Resolve PHIDs to names

```bash
PHAB="<base-url>" TOKEN="<token>"
curl -s -X POST "$PHAB/api/phid.query" \
  -d api.token="$TOKEN" \
  -d "phids[0]=<phid1>" \
  -d "phids[1]=<phid2>" | jq -r '
.result | to_entries[] | "\(.key): \(.value.fullName) (\(.value.typeName))"
'
```

## Search users

```bash
# By username (exact).
curl -s -X POST "$PHAB/api/user.search" \
  -d api.token="$TOKEN" \
  -d "constraints[usernames][0]=<username>" \
  -d limit=5 | jq .

# By display name (fuzzy).
curl -s -X POST "$PHAB/api/user.search" \
  -d api.token="$TOKEN" \
  -d "constraints[query]=<name>" \
  -d limit=5 | jq -r '
.result.data[] | "\(.fields.username // "-") — \(.fields.realName // "-") (PHID: \(.phid))"
'
```

## Search projects

```bash
curl -s -X POST "$PHAB/api/project.search" \
  -d api.token="$TOKEN" \
  -d "constraints[query]=<name>" \
  -d limit=5 | jq -r '
.result.data[] | "\(.fields.name // "-") (\(.fields.slug // "-")) — PHID: \(.phid)"
'
```

## Search tasks

```bash
# By text query.
curl -s -X POST "$PHAB/api/maniphest.search" \
  -d api.token="$TOKEN" \
  -d "constraints[query]=<search terms>" \
  -d limit=10 | jq -r '
.result.data[] | "T\(.id): \(.fields.name // "")",
"  Status: \(.fields.status.name // ""), Owner PHID: \(.fields.ownerPHID // "null")",
""
'

# By author PHID.
curl -s -X POST "$PHAB/api/maniphest.search" \
  -d api.token="$TOKEN" \
  -d "constraints[authorPHIDs][0]=<phid>" \
  -d limit=20 | jq -r '
.result.data[] | "T\(.id): \(.fields.name // "") — \(.fields.status.name // "")"
'

# By status (open, inprogress, resolved, etc.)
curl -s -X POST "$PHAB/api/maniphest.search" \
  -d api.token="$TOKEN" \
  -d "constraints[statuses][0]=<status>" \
  -d limit=20 | jq -r '
.result.data[] | "T\(.id): \(.fields.name // "") — \(.fields.status.name // "")"
'
```

## Who am I?

```bash
curl -s -X POST "$PHAB/api/user.whoami" \
  -d api.token="$TOKEN" | jq .
```

## Task URL format

- Task links: `https://phabricator.<sub>.<domain>/T<id>`
- User links: `https://phabricator.<sub>.<domain>/p/<username>/`
- Project links: `https://phabricator.<sub>.<domain>/tag/<slug>/`
- API takes numeric IDs (e.g. `242861`), not `T242861`.

## Pagination

```bash
# Page 1 — save cursor.
curl -s -X POST "$PHAB/api/maniphest.search" \
  -d api.token="$TOKEN" \
  -d "constraints[statuses][0]=resolved" \
  -d limit=100 > /tmp/page1.json
AFTER=$(jq -r '.result.cursor.after // ""' /tmp/page1.json)

# Page 2.
curl -s -X POST "$PHAB/api/maniphest.search" \
  -d api.token="$TOKEN" \
  -d "constraints[statuses][0]=resolved" \
  -d limit=100 \
  -d "after=$AFTER" > /tmp/page2.json
```

## Notes

- All API requests are `POST` with form-encoded data. Pass the token as `api.token=<token>`.
- Timestamps are Unix epoch (seconds). Convert to ISO 8601 with `date -u -r <epoch> "+%Y-%m-%dT%H:%M:%SZ"`.
- PHIDs are opaque internal identifiers, use `phid.query` to resolve them.
- If you cannot find a token, ask the user for one or to set `$PHABRICATOR_TOKEN`.
- If you see Google sign-in HTML, you are not using Conduit API correctly, or token is missing/invalid.
