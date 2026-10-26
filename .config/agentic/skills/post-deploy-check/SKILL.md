---
name: post-deploy-check
description: >
  Read-only post-deploy diagnostic for any repository. Use for "/post-deploy-check", "check if PR X caused any issues", "check PR post deploy", or when given a PR, branch, commit, timestamp or "since this morning's deploy" and asked whether anything looks out of the ordinary. Discovers the tools the project uses, finds the live release, checks the error tracker, logs, metrics and CI/CD runs against the change, reports, and suggests follow-ups. Accepts extra context ("this may affect payments") to focus the checks. Can repeat itself on a cron until an end time.
---

# Post-deploy check

Read-only. You change nothing in production, the error tracker, the metrics store, CI/CD or GitHub.

## Input

- Target: a PR number or URL, a branch, a commit, a timestamp, or a description such as "since this morning's deploy". `my PRs today` is a target of its own, step 1b, not a time window.
- Asking the user: use the question tool when the agent has one, `AskUserQuestion` in Claude Code, otherwise ask in plain chat with short numbered options and wait for the answer.
- No target: ask whether to check the PRs the user merged today in this repository, or to give a PR, branch or commit. Skip the question for a scheduled run.
- Context, optional free text: what the user thinks may be affected. It tells you where to look first, never a reason to skip the general checks. Repeat it back in one line at the start of the report.
- Flags: which feature flags the change uses and whether they are on. If the user does not say, read them from the PR or the diff and state your assumption.
- Time zone: the local one from `date +%z`. Error trackers and log stores often answer in UTC, keep the zones apart and state the zone in the report.

## Rules that never bend

- No personal data in the output, from a database, logs, the error tracker or screenshots. Refer to user IDs and record IDs only, and print only the tag or field you need, never a whole event or raw JSON.
- No secrets or tokens in the output. Never open `.env` files, key files, credential stores or shell history during discovery, a file name is enough evidence. Never print environment variables or request headers.
- Use only the tools the project already uses and the session already has, authenticated as the user. Do not install anything, do not create tokens, do not send project data to any service the project does not already use.
- Run single-purpose, readable commands. No network scanning, tunnels or encoded one-liners. If a command is blocked or flagged, stop and tell the user.
- Data stores: read-only aggregates only, a bounded time range, counts only, no row-level output, no writes.
- No fixes, flag changes, restarts, rollbacks, and no CI/CD action such as re-run, cancel or approve. Recommend them, do not run them.
- Do not blame the change without evidence. An issue is suspect only when its code path matches the diff and it started after the deploy.
- A tool you could not reach is "not checked", never "clean". An empty result needs a control query first, see step 4.

## Steps

### 0. Discover the tools

Scan the repository read-only, about 10 calls, and write one list of tool and evidence. Do not assume a tool because it is common.

- Project instructions first, they name the tools and runbooks: `AGENTS.md`, `CLAUDE.md`, `.agents/`, `.github/copilot*`, `README`, `docs/`. If a project skill already covers a check, use it instead of the generic steps below.
- Deploy and CI/CD: `.github/workflows/*`, `.gitlab-ci.yml`, `Jenkinsfile`, `.circleci/`, `fly.toml`, `vercel.json`, `netlify.toml`, `Procfile`, `Dockerfile`, Helm or Kubernetes manifests, `fastlane/`, `codemagic.yaml`. Note which workflows deploy, release, or gate merges.
- Error tracking: `sentry`, `bugsnag`, `rollbar`, `honeybadger`, `crashlytics` in manifests, lockfiles, config and initializers. Note the project name and whether events carry a `release` tag.
- Logs and metrics: Loki, Grafana, Datadog, New Relic, Elasticsearch or Kibana, CloudWatch, Prometheus.
- Product metric: an orders, signups or requests per hour figure the project documents.
- What this session can reach: the `gh` or `glab` CLI, the error tracker CLI or MCP server, other MCP servers, and the installed skills that already cover a tool, such as `read-github-pr`, `read-sentry-issue` and `search-grafana-logs`. Use those skills instead of rebuilding their commands.

A tool found in the repository but not reachable from the session goes under "Not checked", with the query or link for the user to run.

When the scan finds no error tracker, no logs or metrics tool and no deploy workflow, or only some of them, ask which tools to monitor and how to reach them, for example the error tracker and its project name, the log store and a selector, the deploy pipeline, a metric and its query. Skip the question for a scheduled run, reuse the answers from the previous run. Treat the answers as the tool list for the rest of the run, and say in the report that they came from the user, not from the repository.

### 1. Pin the window and the release

- PR: read it with `read-github-pr`, or `gh pr view <n> --json title,body,mergedAt,mergeCommit,files`. Read the body and the files. Note what the flags guard and what runs with the flags off.
- Branch: `gh pr list --head <branch> --state merged`, then continue as for a PR.
- Timestamp or description: that is the start of the window.
- Find the live release. Use what step 0 found, in this order: the `release` tag the error tracker puts on events, a version or sha the deploy workflow's last successful run published, a version endpoint the project documents. During a rolling deploy one fresh event can come from an old instance, so take the most frequent value over the last few minutes, not the latest one.
- Confirm the live release contains the change. Same repository: `git fetch origin`, then `git merge-base --is-ancestor <merge sha> <release sha>`. Another repository: `gh api repos/<owner>/<repo>/compare/<merge sha>...<release sha> --jq .status`, where `ahead` or `identical` means live and `behind` or `diverged` means not. If the change is not live, say "merged, not live yet" and stop for that PR.
- A release value that is not a git sha, or no release signal at all: report "deploy not verifiable", never "clean". Fall back to the window by time and say so.

### 1b. My PRs today

- List the PRs the user authored that merged today, in the local zone, in the current repository. Pass the start of the local day with its offset, a bare date is read as UTC and drops the first hours: `gh search prs --author @me --merged --merged-at ">=<today>T00:00:00<offset>" --repo <owner>/<repo> --json number,title,closedAt,url --limit 100`. Widen to `--owner <owner>` only when the user asks for other repositories, then group by repository and run steps 1 to 5 once per repository with its own tools and live release.
- Start the window at the earliest merge of the day. Report each PR as live or "merged, not live yet", and skip the tracker checks for those not live.
- No PRs: say so and stop.

### 2. Recent deploys and CI/CD health

Use the deploy, release and merge gating workflows from step 0.

- Runs in the window: `gh run list --workflow <file> --created ">=<window start ISO>" --limit 100 --json databaseId,status,conclusion,displayTitle,createdAt,url`. `--created` filters on the server, so a busy day does not push runs out of the list.
- PRs deployed in the window: `git log --first-parent --merges --format='%h %s' <old release>..<new release>`, or the compare API for another repository.
- A failed deploy or release run is a finding for the change it deployed. A failed run on a PR branch only means that PR did not land. Two or more different PRs failing in a row point at the default branch or the pipeline, not one PR. `cancelled` is not a failure, runs behind a failed one are often cancelled. `in_progress` is pending.
- For a failed run name the failed job and step: `gh run view <id> --json jobs --jq '.jobs[] | select(.conclusion == "failure") | {name, url}'`. Read `--log-failed` only to tell a flaky step from a real one, never paste it.
- Open CI/CD issues created in the window, titles and numbers only: `gh issue list --state open --search "created:>=<date> ci OR cd OR deploy OR pipeline OR build OR flaky in:title,body" --json number,title,url`.
- No CI/CD configuration found: list it under "Not checked".

### 3. Error tracker

- New issues since the deploy, per project, most frequent first. Use relative windows such as `firstSeen:-3h`, an absolute date is often rejected. The window is the real time since the deploy rounded up, or events from before it are silently dropped.
- Never rely on a saved view, it is personal and may not exist for the user running this. Give the link to a search with the same query in the report.
- Search the signals the diff adds: every new log message, reported message and validation error string. Search the static part, without interpolated values, one search per message.
- Keyword search across all projects for the feature, using the domain words from the diff and from the user's context.
- Issues on the live release: add the release filter to the query.
- Verify before reporting. A list returns issues with activity in the window, not only new ones. For each suspect read its first seen, count and last seen, and the release value of its events in the window. Print only the release value, other tags can carry user data. An issue that only hit older releases, or stopped before the deploy, is not from this change. Run the ancestor check from step 1 for each release the events show.
- Old, recurring issues such as long-standing N+1 or timeout noise are background. Compare the true first seen date.
- Error tracker with no CLI or MCP in the session: give the user the search link and list it under "Not checked".

### 4. Logs and metrics

Only for the tools step 0 found and the session can reach.

- Ask for counts, such as `count_over_time` or a facet count, never print log lines.
- Before trusting an empty result, run a control query on the same selector and window without the line filter. If the control is empty too, the selector or window is wrong, so report the check as inconclusive, not clean.
- Compare error rate, latency and saturation before and after the deploy for the changed service, over equal windows.
- Follow one request or trace ID from a tracker event into the logs when a suspect needs more evidence.

### 5. Product metric

Only when the user names one or the project documents one, such as orders, signups or requests per hour.

- Read the schema or the project's documentation first. Never guess table or column names, and never put a figure that identifies a person in the output.
- Run it through a connector, MCP or CLI the session has, bounded range, counts only. If there is none, give the query to the user and report the metric as not checked.
- Compare per hour, today against the same weekday one and two weeks earlier. The deploy hour and the current hour are partial, pro-rate them. If a daylight saving change falls between today and a baseline, shift that baseline by one hour or drop it.
- Look for a step change at the deploy time, not a constant gap. A gap that was there before the deploy is not from the change.
- A filter on an unindexed column can time out on a live database. Check the schema for an index first. After one timeout stop, do not retry, report it as not run.
- Warehouse or batch data refreshes later, so it has nothing for today. Use it only the next day.

### 6. Use the context

Turn the user's context and the diff into extra checks. Adapt as needed, and state which hints you used and which you could not check.

| Hint | Also check |
| --- | --- |
| Auth, sessions | Login, token and permission errors, a drop in successful sign-ins |
| Checkout, payments | Payment provider errors, the success rate of the payment step, orders per hour |
| Search, listing | Search engine errors and latency, empty result rate |
| Background jobs, queues, cron | Job failures and retries, queue depth and lag, consumer errors, missed schedules |
| Mobile app, public API | Errors by app version, API error rate by endpoint, version gates |
| Migrations, data model | Long locks, slow queries, errors from code that reads the changed columns |
| Frontend | Browser error tracker project, bundle or asset load errors, client-side error rate |
| Infrastructure, config | Restarts, out-of-memory kills, readiness failures, startup errors |

### 7. Judge

- Flags off: the new paths are not exercised, so only the always-on changes can fail. List them from the diff and check those first.
- Flags on: also check the feature's own path.
- Compare with the stated impact of the change. If it says "no impact on X", a change for X in errors or metrics is a finding.

## Report

Answer first, plain words, no personal data.

1. Verdict: one line, "nothing unusual" or "issue found".
2. Context: what the user asked to focus on, one line.
3. Tools: the list from step 0, reachable or not, one line.
4. Window: merge time, release, checked until when, with the zone.
5. CI/CD: failed deploy, release or gate runs in the window with the job name, or "green", and how many are pending. Open CI/CD issues by number.
6. Error tracker: new issues related to the change, with ID and why. For each related or suspect issue give first seen, events per release, and the event count in a window as long as the time since the deploy, just before against just after the deploy. One line on the unrelated ones.
7. Logs and metrics: what was compared and the result, or inconclusive.
8. Product metric: a small table for the hours around the deploy with the percentage against both baselines, partial hours marked.
9. Not checked: tools without access, short window, paths not exercised with the flags off.
10. Follow-up: from the tools found in step 0, one line each with the exact query or link when you can build one. Offer to run the ones you can.

For "my PRs today", open with a table of PR, repository, merged at local time, live yes or no, and verdict, then one block per repository with items 4 to 10. The top verdict is "issue found" when any PR has one.

If you find something: give the link, first event time, release, user count, and whether it is tied to the change. Do not fix it, tell the owner.

## Scheduling re-runs

On a busy day one check is not enough. At the end of a manual run, offer to repeat it on a cron until an end time, default 18:00 local, so each merge is checked as it deploys.

- Needs a scheduler. Claude Code has `CronCreate`, `CronList` and `CronDelete`. An agent without one skips the offer and says the check can be re-run by hand or from the user's own scheduler.
- Ask: every 30 minutes, every hour, or no schedule. Skip the question for a scheduled run, when `CronList` already shows a job for this target, or when the end time is less than 30 minutes away. Leave out "every hour" when its last slot has passed.
- Create it with `CronCreate`, `recurring: true`, in local time and at off-minutes. Pin the day and month so it stops by itself at the end time. Hourly: `7 <current hour>-<end hour minus 1> <day> <month> *`. Every 30 minutes: `7,37 <current hour>-<end hour minus 1> <day> <month> *`.
- The cron prompt is `/post-deploy-check <target> scheduled run`, plus the user's context. The target can be the default branch, each run then covers every PR merged since the previous run. For "my PRs today" each run lists the PRs again, checks the new ones, and looks for new issues on the ones already checked.
- Tell the user that jobs are session-only, fire only while the session is idle, so the session must stay open, and that `CronDelete` cancels the job.
- Scheduling is the only action beyond reading, and it changes nothing in production, the tracker, CI/CD or GitHub.

### Scheduled runs

- The window starts at the previous run, not at the merge. Keep from the previous report the live release, the PRs already checked and the issue IDs already judged unrelated, and do not report those again.
- Find the live release as in step 1. A new one means a new deploy, so list the PRs in it as in step 2 and check each against the diff, the tracker and CI/CD.
- Report only what changed. With nothing new, one line: "nothing new since HH:MM", with the live release, the pending runs and the metric trend. Give the full report only when something is found.
- Add the metric table only when an hour deviates 10% or more from both baselines, or shows a step at a deploy time, after pro-rating.
- The last run of the day ends with one line on the whole day: deploys checked, issues found, CI/CD failures.

## Command reference

Starting points when the tool was found in step 0. Replace the placeholders from the project's own config, never from memory. Every command is read-only. If a flag is rejected, check the tool's `--help` before trying another form.

Release and liveness:

- Same repository: `git fetch origin`, then `git merge-base --is-ancestor <merge sha> <release sha>`, exit code 0 means live.
- Another repository: `gh api repos/<owner>/<repo>/compare/<merge sha>...<release sha> --jq .status`.
- Release tag of recent events, most frequent first, `<tracker command listing events with only the release field> | sort | uniq -c | sort -rn | head -3`. Select the release field only, never whole events.

GitHub Actions:

- Runs: `gh run list --workflow <file> --created ">=<ISO time>" --limit 100 --json databaseId,status,conclusion,displayTitle,createdAt,url`.
- Failed job and step: `gh run view <id> --json jobs --jq '.jobs[] | select(.conclusion == "failure") | {name, url}'`.
- Another CI system: use its own CLI or API with a read-only call, or give the user the link.

Sentry, CLI or MCP:

- New issues: query `is:unresolved firstSeen:-<N>h`, sort by frequency, small limit, fields limited to ID, title, culprit, count, user count and first seen.
- One suspect: first seen, last seen and count, then the release value of its events in the window.
- Release filter: `release:<sha>`. Relative dates only.
- MCP search can reject `OR` and `AND`, so run one keyword per search.
- Other trackers: the same questions, new issues since the deploy, and events per release.

Loki or Grafana, through `search-grafana-logs` when installed:

- Selector from the project's own docs or dashboards, with the environment label set to production.
- Counts: `sum(count_over_time(<selector> |= "<static message part>" [<window>]))`.
- Control: the same query without the `|=` filter. An empty control means the selector or window is wrong.

Datadog, New Relic and similar:

- Error rate and latency of the changed service or job over equal windows before and after the deploy, through the tool's CLI, MCP or a dashboard link.

Product metric:

- Template: `SELECT <hour of timestamp>, COUNT(*) FROM <table> WHERE <completed flag> AND <timestamp> >= '<day start>' AND <timestamp> < '<next day start>' GROUP BY 1`, one query per day compared. Table, columns and filters come from the schema or project docs, run on a read-only connection or replica, never a primary with write access.
