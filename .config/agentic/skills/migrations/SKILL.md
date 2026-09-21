---
name: migrations
description: Rules for naming and chaining database migration files. Use when creating or reviewing a migration file, or when a migration merge conflict or multi-head state comes up.
---

# Migrations

## When to use

- Creating a new database migration file.
- Reviewing a migration file's timestamp or `down_revision`/parent link.
- A migration chain has diverged into multiple heads, or CI is failing an `upgrade head` check.

## Timestamps

Always use real, generated timestamps with millisecond precision when naming migration files. Never hardcode sequential or placeholder timestamps.

```bash
# Generate a real timestamp with milliseconds (UTC).
date -u +"%Y%m%d%H%M%S%3N"
```

Do not use timestamps that look hand-typed or sequential, like `20260706120000`, `20260706120001`, `20260707120000`. These lack sub-second precision and can collide when migrations are generated in rapid succession. Better use the framework's built-in migration generator if it exists, or generate a timestamp programmatically.

## Chain

Migration chains must stay linear with a single head. Concurrent PRs adding migrations from different ancestors create a multi-head state that blocks `upgrade head` and fails CI.

- **CI check**: Verify a single head in the lint step, no database connection required.
- **Generate from head**: Always run `upgrade head` first so new migrations chain off the current tip.
- **Merge heads immediately**: Resolve divergence via the framework's merge command in a dedicated PR before any new migration is added.
- **Down-revision from script**: Set `down_revision` to the output of `current`, after `upgrade head`, never an intermediate node.
