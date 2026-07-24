---
name: read-sentry-issue
description: Use when a Sentry issue/event link appears, or when working with Sentry error tracking, authenticating, listing organizations/projects/issues, or fetching event/stacktrace details for an issue.
---

# Read Sentry Issue

## When to use

- User shares a Sentry issue/event link `https://sentry.io/organizations/<org>/issues/<id>/` or `<org>.sentry.io/issues/<id>/`.
- User mentions Sentry or error tracking by name.
- Investigating an exception, stack trace, or production error that might be tracked in Sentry.

## Authentication

1. Look for a token in `~/.sentryclirc`.
2. Look for an environment variable named `$SENTRY_AUTH_TOKEN`.
3. Look for a token in 1Password via `op item get "Sentry Token" --fields label=credential --reveal`.
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
  | jq -r '
.[] |
"=== EVENT \(.id) \(.dateCreated) ===",
"TAGS: \(.tags | map("\(.key)=\(.value)") | join(", "))",
(.entries[] |
  if .type == "exception" then
    (.data.values[] |
      "EXCEPTION: \(.type // "?") - \(.value // "?")",
      (.stacktrace.frames[-8:][] |
        "  \(.filename // "?"):\(.lineNo // "?") - \(.function // "?")"
      )
    )
  elif .type == "request" then
    "REQUEST URL: \(.data.url // "?")",
    (.data.query // [] | map("  \(.[0]) = \(.[1])") | .[])
  else empty
  end
),
""
'
```

## Analyze routes/params across events

```bash
TOKEN=<token>
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://sentry.io/api/0/organizations/<org>/issues/<issue_id>/events/?limit=50&full=true" \
  | jq -r '
def route: .entries[] | select(.type == "request") | .data.query // [] | map("\(.[0])=\(.[1])") | join(" | ");
[.[] | select(.entries | any(.type == "request")) | route] |
group_by(.) | map({route: .[0], count: length}) | sort_by(-.count)[] |
"  \(.route): \(.count) events"
'
```

## Notes

- `sentry-cli events list` doesn't filter by issue, use the REST API.
- `full=true` required for stacktraces and request params.
- URLs are organization-scoped: `/api/0/organizations/<org>/issues/<id>/events/`.
- Token scopes: `event:read`, `org:read`, `project:read`.
