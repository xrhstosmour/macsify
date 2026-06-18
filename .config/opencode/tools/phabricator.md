# Phabricator

When you encounter a `https://phabricator.<sub>.<domain>/T<id>` link, use `curl` to fetch task details and related data via the `Conduit` API.

## Required behavior

- Always use Conduit API calls (`$PHAB/api/...`) first.
- Do not use browser/web scraping for Phabricator task URLs.
- SSO-protected pages usually return a Google sign-in HTML page, not task content.
- If API calls fail, troubleshoot token/auth first, then retry API calls.

## Authentication

1. Look for an environment variable named `$PHABRICATOR_TOKEN` or `$CONDUIT_TOKEN`.
2. Look for a token in `~/.arcrc` (`jq -r '.hosts' ~/.arcrc`).
3. Look for a token in 1Password (`op item get "Phabricator Token" --fields label=credential --reveal`).
4. Ask the user to provide a token.

After finding a token, verify it before task calls:

```bash
curl -s -X POST "$PHAB/api/user.whoami" \
  -d api.token="$TOKEN" | python3 -m json.tool
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
ID="$(python3 - <<'PY'
import re
url = "https://phabricator.skroutz.gr/T241638"
m = re.search(r"/T(\d+)", url)
print(m.group(1) if m else "")
PY
)"

TOKEN="${PHABRICATOR_TOKEN:-${CONDUIT_TOKEN:-}}"

if [ -z "$TOKEN" ] && [ -f "$HOME/.arcrc" ]; then
  TOKEN="$(python3 - <<'PY'
import json, os
path = os.path.expanduser('~/.arcrc')
token = ''
try:
    data = json.load(open(path))
    hosts = data.get('hosts', {})
    for host, info in hosts.items():
        if 'phabricator' in host:
            token = info.get('token', '')
            if token:
                break
    if not token and hosts:
        token = next(iter(hosts.values())).get('token', '')
except Exception:
    pass
print(token)
PY
)"
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
  -d limit=1 | python3 -c "
import json, sys
payload = json.load(sys.stdin)
if payload.get('error_code'):
    print('ERROR:', payload.get('error_code'), payload.get('error_info'))
    raise SystemExit(1)
items = payload.get('result', {}).get('data', [])
if not items:
    print('Task not found')
    raise SystemExit(1)
t = items[0]
f = t.get('fields', {})
print(f'T{t["id"]}: {f.get("name", "")}')
print(f'Status: {f.get("status", {}).get("name", "")} | Priority: {f.get("priority", {}).get("name", "")}')
print()
print((f.get('description', {}) or {}).get('raw', ''))
"
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
  -d limit=1 | python3 -m json.tool
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
  -d limit=1 | python3 -c "
import sys, json
t = json.load(sys.stdin)['result']['data'][0]
f = t['fields']
print(f'T{t[\"id\"]}: {f[\"name\"]}')
print(f'  Status: {f[\"status\"][\"name\"]} | Priority: {f[\"priority\"][\"name\"]}')
print(f'  Created: {f[\"dateCreated\"]} | Modified: {f[\"dateModified\"]}')
print(f'  Owner PHID: {f[\"ownerPHID\"]} | Author PHID: {f[\"authorPHID\"]}')
print()
print(f['description']['raw'][:3000])
"
```

## Task transactions (history, comments)

```bash
PHAB="<base-url>" TOKEN="<token>" ID="<id>"
curl -s -X POST "$PHAB/api/maniphest.gettasktransactions" \
  -d api.token="$TOKEN" \
  -d "ids[0]=$ID" | python3 -m json.tool
```

Transaction types: `status`, `reassign`, `description`, `title`, `priority`, `core:edge`, `core:create`, `core:subscribers`, `core:space`.

## Resolve PHIDs to names

```bash
PHAB="<base-url>" TOKEN="<token>"
curl -s -X POST "$PHAB/api/phid.query" \
  -d api.token="$TOKEN" \
  -d "phids[0]=<phid1>" \
  -d "phids[1]=<phid2>" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for phid, info in data['result'].items():
    print(f'{phid}: {info[\"fullName\"]} ({info[\"typeName\"]})')
"
```

## Search users

```bash
# By username (exact).
curl -s -X POST "$PHAB/api/user.search" \
  -d api.token="$TOKEN" \
  -d "constraints[usernames][0]=<username>" \
  -d limit=5 | python3 -m json.tool

# By display name (fuzzy).
curl -s -X POST "$PHAB/api/user.search" \
  -d api.token="$TOKEN" \
  -d "constraints[query]=<name>" \
  -d limit=5 | python3 -c "
import sys, json
data = json.load(sys.stdin)
for u in data['result']['data']:
    f = u['fields']
    print(f'{f[\"username\"]} — {f[\"realName\"]} (PHID: {u[\"phid\"]})')
"
```

## Search projects

```bash
curl -s -X POST "$PHAB/api/project.search" \
  -d api.token="$TOKEN" \
  -d "constraints[query]=<name>" \
  -d limit=5 | python3 -c "
import sys, json
data = json.load(sys.stdin)
for p in data['result']['data']:
    f = p['fields']
    print(f'{f[\"name\"]} ({f[\"slug\"]}) — PHID: {p[\"phid\"]}')
"
```

## Search tasks

```bash
# By text query.
curl -s -X POST "$PHAB/api/maniphest.search" \
  -d api.token="$TOKEN" \
  -d "constraints[query]=<search terms>" \
  -d limit=10 | python3 -c "
import sys, json
for t in json.load(sys.stdin)['result']['data']:
    f = t['fields']
    print(f'T{t[\"id\"]}: {f[\"name\"]}')
    print(f'  Status: {f[\"status\"][\"name\"]}, Owner PHID: {f[\"ownerPHID\"]}')
    print()
"

# By author PHID.
curl -s -X POST "$PHAB/api/maniphest.search" \
  -d api.token="$TOKEN" \
  -d "constraints[authorPHIDs][0]=<phid>" \
  -d limit=20 | python3 -c "
import sys, json
for t in json.load(sys.stdin)['result']['data']:
    f = t['fields']
    print(f'T{t[\"id\"]}: {f[\"name\"]} — {f[\"status\"][\"name\"]}')
"

# By status (open, inprogress, resolved, etc.)
curl -s -X POST "$PHAB/api/maniphest.search" \
  -d api.token="$TOKEN" \
  -d "constraints[statuses][0]=<status>" \
  -d limit=20 | python3 -c "
import sys, json
for t in json.load(sys.stdin)['result']['data']:
    f = t['fields']
    print(f'T{t[\"id\"]}: {f[\"name\"]} — {f[\"status\"][\"name\"]}')
"
```

## Who am I?

```bash
curl -s -X POST "$PHAB/api/user.whoami" \
  -d api.token="$TOKEN" | python3 -m json.tool
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
AFTER=$(python3 -c "import sys,json; print(json.load(sys.stdin)['result']['cursor']['after'])" < /tmp/page1.json)

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
- Avoid `curl ... | python3 - <<'PY'` when parsing piped JSON, this pattern can consume stdin incorrectly. Prefer `python3 -c` for piped JSON, or save JSON to a file first.
