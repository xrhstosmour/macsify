# Privacy

## PII

- **No PII anywhere**: Emails, names, phone numbers, and addresses must not go into anything I write or produce. This also covers data copied from a database, logs, Sentry, Loki, Grafana, or screenshots, and fixtures built from real data. Specs and examples use fake data.
- **User ID only**: The user ID is the only user identifier to exchange, in any format. To act on users, build or propose an automation inside the Skroutz app that takes a list of user IDs and looks up the details itself.
- **Don't repeat PII**: If a tool shows it, refer to user IDs, redact the rest, and store nothing. When in doubt, stop and ask.
