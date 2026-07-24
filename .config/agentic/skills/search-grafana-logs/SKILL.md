---
name: search-grafana-logs
description: Use for Grafana/Loki links, "search Loki", "check Grafana", log queries, or investigating an error/failure that likely shows up in logs.
---

# Search Grafana Logs

## When to use

- User shares a Grafana dashboard/explore link or a Loki reference.
- User says "search Loki", "check Grafana", or asks to search/investigate logs for an error or failure.

Two ways this gets triggered:

1. A link: `https://grafana.<host>/d/<uid>/<slug>?...` or `https://grafana.<host>/explore?...`.
2. Just a problem description, no link at all: "find errors for request X", "why did job Y fail", "search yesterday's logs for `<id>`". Don't ask the user for a link, dashboard name, or LogQL syntax before trying, infer what's needed (see "Starting from a description only" below) and only ask if genuinely stuck.

Either way, query Loki directly with `logcli`, Grafana Labs' own CLI for querying Loki. Don't use `curl`, the Grafana HTTP API, or anything else, `logcli` is the only tool this doc uses.

This is not just a preference, it's usually the only path that works: Grafana's own UI/API commonly sits behind an additional identity proxy (Cloudflare Access, Okta, etc.) that blocks a plain token from getting through, while Loki itself is frequently reachable directly over the same VPN/zero-trust network the user is already on, with no separate credential at all. If Loki genuinely isn't reachable this way, stop and tell the user, don't fall back to scraping the dashboard or calling the Grafana API.

`grafana-cli` only manages plugins and admin resets on a Grafana server, it cannot query dashboards, logs, or metrics, don't reach for it here. Never scrape the dashboard HTML page either, SSO-protected instances return a login page, not data.

## Required behavior

- Check for a project-specific skill or notes file first, something matching `*loki*`/`*logcli*` under `.agents/skills/`, `.claude/skills/`, or similar in the current project. If one exists, reuse its `--addr` and label selector conventions instead of rediscovering them, it encodes real, observed label values for that project.
- If `logcli` redirects to a login/SSO page instead of returning data, that's an identity proxy in front of the host, not a bad token, don't keep retrying the same call, tell the user instead.
- Don't gate on having a link. A search term/ID plus a rough sense of the service or time window is enough to start.

## Starting from a link

Derive the dashboard slug, org ID, time range, and template variable overrides from the link's query string.

```bash
LINK="https://grafana.example.com/d/<uid>/<slug>?orgId=1&from=now-24h&to=now&timezone=browser&var-filter="

UID_AND_REST="${LINK#*/d/}"
SLUG="${UID_AND_REST#*/}"
SLUG="${SLUG%%\?*}"

QUERY="${LINK#*\?}"
ORG_ID=$(echo "$QUERY" | tr '&' '\n' | grep '^orgId=' | cut -d= -f2)
FROM=$(echo "$QUERY" | tr '&' '\n' | grep '^from=' | cut -d= -f2)
TO=$(echo "$QUERY" | tr '&' '\n' | grep '^to=' | cut -d= -f2)
echo "$QUERY" | tr '&' '\n' | grep '^var-'
```

`$SLUG` (e.g. `checkout-service-logs`) is usually a strong hint at the label value to filter on later.

## Starting from a description only, no link

Treat the description as the same inputs a link would have given you, just extract them from language instead of a query string:

- Service/app hint: a name mentioned in the request, the current repo's name, or a project skill file (see "Required behavior" above) → becomes the label-value hint used in "Discover the right label selector" below.
- Search term: any ID, trace ID, exception name, or exact string given → the `|=`/`|~` filter.
- Time window: an explicit time/date if given, otherwise default to a reasonable recent window, `--since=1h`, widen to `24h` if nothing is found, rather than asking first.
- Loki address: resolved the same way as "Find the Loki endpoint" below, a project skill or prior convention in this repo/conversation is the first place to check, not a fresh guess every time.

Only ask the user when none of these can be inferred at all, e.g. there's no project skill, no repo context, and no recognizable service name in the description.

## Find the Loki endpoint

1. If a project skill already names one, use it.
2. Otherwise derive candidates from the Grafana host, internal Loki gateways are often named by swapping the `grafana.` subdomain for something like `loki.`, `loki-gateway.`, or `<env>-loki.`, on the same or a sibling internal domain.
3. Verify a candidate is reachable and is actually Loki, no Grafana token needed for this:

  ```bash
  logcli --addr="$LOKI_ADDR" labels
  ```

  A real label list confirms it, and confirms Loki is reachable independently of whatever sits in front of Grafana's own UI. An error or an SSO redirect means try the next candidate.

4. If no candidate works, ask the user for the address, `logcli` needs a working Loki endpoint to do anything.

## Authentication for Loki

Try unauthenticated first, plenty of internal setups need nothing extra once the network path (VPN/WARP/etc.) is up. If the instance does reject an unauthenticated request, `logcli` supports, roughly in order of likelihood for an internal setup:

1. `$LOKI_BEARER_TOKEN` / `--bearer-token`
2. `$LOKI_USERNAME` + `$LOKI_PASSWORD` / `--username` + `--password` (HTTP basic auth)
3. `$LOKI_ORG_ID` / `--org-id`, for multi-tenant Loki, needed alongside one of the above, not instead of it
4. `--cert`/`--key` (mTLS client certificate), for zero-trust setups that authenticate the machine instead of a token

Look for credentials in an env var first, then 1Password (`op item get "Loki Token" --fields label=credential --reveal`), then ask the user.

## Discover the right label selector

The hint is whatever names the service, either the dashboard `$SLUG`, from a link, or the app/repo name from a description.

```bash
# All label names.
logcli --addr="$LOKI_ADDR" labels

# Values for a label, filtered to the hint.
logcli --addr="$LOKI_ADDR" labels namespace | grep -i "<hint>"
logcli --addr="$LOKI_ADDR" labels container | grep -i "<hint>"

# Confirm a concrete selector resolves to real streams before querying it.
logcli --addr="$LOKI_ADDR" series '{namespace="<value>"}' --since=1h
```

## Query for a string over a time range

```bash
logcli --addr="$LOKI_ADDR" query --since=24h --limit=1000 -q -o raw \
  '{namespace="<value>"} |= "<search string>"'
```

- `--since=24h` matches a `from=now-24h` link param, or a "last day"-type description. For absolute `from`/`to`, use `--from`/`--to` in RFC3339, no timezone suffix plus `--timezone`.
- `|=` for an exact substring match, `|~` for a regex, escape `\` for characters that need to be literal in the pattern.
- No exact string to search for yet, just a described symptom, a failure, a stuck job: start with the label selector alone, or filter on generic symptom keywords (`error`, `exception`, `timeout`, `5\d\d`) with `|~`, then narrow once a concrete ID/message surfaces.
- Drop `-q -o raw`, use the default output mode to get a timestamp and label set alongside each line, needed to summarize when/where matches occurred, not just what they said.
- Increase `--limit` if results look truncated, `logcli` reports the query URL and common labels above the log lines unless `-q` is set.
- `--org-id`, resolve it from the link's `orgId=` param on multi-org/multi-tenant instances.

## Presenting results

Don't just dump raw JSON/log lines. List matches with their timestamp, then summarize: total count, first/last occurrence, distinct label values seen (pod, instance, service), and any notable pattern, single event vs. a burst, one instance vs. spread across many. If matched lines carry personal data, names, emails, phone numbers, addresses, keep the summary focused on the operational facts, status codes, timing, IDs, and only repeat the specific PII fields the user actually needs to resolve their question.

## Notes

- Loki timestamps are nanoseconds since epoch.
- If `logcli` redirects to an SSO/login page, that's an identity proxy in front of the host, ask the user whether the datasource itself is reachable on a different, unproxied hostname, which is usually the point of using `logcli` directly in the first place, don't try the Grafana API or dashboard page instead.
