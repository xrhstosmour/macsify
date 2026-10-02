# Privacy

## PII

- **No PII anywhere**: Emails, names, phone numbers, and addresses, for customers, employees, or anyone else, must not go into any file, Google Doc/Sheet/Drive, Slack, Phabricator, PR/issue/commit text, memory, skill, artifact, report, backup, or routine output. This also covers data copied from a database, logs, Sentry, Loki, Grafana, or screenshots, and fixtures built from real data. Specs and examples use fake data. Exception: a teammate's own name/email in a structured attribution field they've consented to, `Co-authored-by` trailers, commit authorship, PR reviewer/assignee handles, is the mechanism working as intended, not a leak.
- **User ID only**: The user ID is the only identifier to exchange for a customer, in any format. To act on a customer, build or propose an automation inside the Skroutz app that takes a list of user IDs and looks up the details itself.
- **Don't repeat PII**: If a tool shows it, refer to IDs, redact the rest, and store nothing. When in doubt, stop and ask.
