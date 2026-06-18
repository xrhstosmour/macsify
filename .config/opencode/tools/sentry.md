# Sentry

## Authentication

1. Look for a token in `~/.sentryclirc`.
2. Look for an environment variable named `$SENTRY_AUTH_TOKEN`.
3. Look for a token in 1Password (`op item get "Sentry Token" --fields label=credential --reveal`).
4. Ask the user to provide a token.

## Commands

```bash
# Check if authenticated.
sentry-cli info

# Login.
sentry-cli login --auth-token <token>

# List organization, projects, and issues.
sentry-cli organizations list

# List projects for an organization.
sentry-cli projects list -o <org>

# List unresolved issues for a project, with optional query.
sentry-cli issues list -o <org> -p <proj> --query "<q>" --status unresolved --max-rows 20

# Get details for an issue.
sentry-cli issues list -o <org> -p <proj> -i <id>
```

## Fetch events for an issue

```bash
TOKEN=<token>
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://sentry.io/api/0/organizations/<org>/issues/<issue_id>/events/?limit=10&full=true" \
  | python3 -c "
import sys, json
events = json.load(sys.stdin)
for e in events:
    print('=== EVENT', e.get('id'), e.get('dateCreated'), '===')
    tags = {t['key']: t['value'] for t in e.get('tags', [])}
    print('TAGS:', json.dumps(tags))
    for entry in e.get('entries', []):
        if entry.get('type') == 'exception':
            for v in entry['data'].get('values', []):
                print('EXCEPTION:', v.get('type'), '-', v.get('value'))
                for f in v.get('stacktrace', {}).get('frames', [])[-8:]:
                    print(' ', f.get('filename'), ':', f.get('lineNo'), '-', f.get('function'))
                    if f.get('vars'):
                        print('    vars:', json.dumps(f.get('vars'))[:400])
        elif entry.get('type') == 'request':
            req = entry.get('data', {})
            print('REQUEST URL:', req.get('url'))
            print('REQUEST QUERY:', json.dumps(req.get('query'), indent=2)[:600])
    print()
"
```

## Analyze routes/params across events

```bash
TOKEN=<token>
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://sentry.io/api/0/organizations/<org>/issues/<issue_id>/events/?limit=50&full=true" \
  | python3 -c "
import sys, json
events = json.load(sys.stdin)
print(f'Total events: {len(events)}')
routes = {}
for e in events:
    for entry in e.get('entries', []):
        if entry.get('type') == 'request':
            q = dict(entry['data'].get('query', []))
            if not q:
                continue
            route = ' | '.join(f'{k}={v}' for k,v in sorted(q.items()))
            routes[route] = routes.get(route, 0) + 1
for r, count in sorted(routes.items(), key=lambda x: -x[1]):
    print(f'  {r}: {count} events')
"
```

## Notes

- `sentry-cli events list` doesn't filter by issue, use the REST API.
- `full=true` required for stacktraces and request params.
- URLs are organization-scoped: `/api/0/organizations/<org>/issues/<id>/events/`.
- Token scopes: `event:read`, `org:read`, `project:read`.
