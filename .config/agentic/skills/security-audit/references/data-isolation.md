# Data isolation and lifecycle

Use when the target stores multi-tenant or access-controlled data, derives search, cache, or analytics copies, issues object links, exports or restores records, migrates schemas, or promises deletion and revocation. Follow one data item through every copy and state change. Endpoint-level access control is covered by the main skill.

## Discipline

- A tenant or owner field on a record is not isolation. Find the query, key, path, or row-level policy that enforces it on each read and write path.
- Trace derived copies. Data that is safe in primary storage can be unsafe in search, cache, analytics, exports, previews, logs, replicas, and backups, which have different ACLs and retention.
- Deletion and revocation are contracts. Check current, historical, cached, indexed, exported, restored, and queued copies.
- A retention or privacy preference is not a vulnerability. Require a stated access boundary or deletion guarantee plus an unauthorized reader or later operation.

## Classes

- Missing tenant enforcement: a read, update, delete, list, count, or bulk query that does not bind the object to the authenticated tenant, or takes identity from the body. Compare direct, nested, background, admin, import, and legacy paths.
- Key collisions: cache keys, object paths, search IDs, temp files, or dedup keys without tenant or environment.
- Policy disagreement: row-level policy, ORM default scopes, raw clients, `unscoped` calls, joins, aggregates, and views applying different predicates.
- Blob and signed link overreach: keys, version IDs, or links valid beyond the issuer's access or after the ACL changes.
- ACL drift in derived copies: an index, cache, embedding, thumbnail, or feed keeping content after the primary record's ACL or lifecycle changed. Filter at retrieval, not only at ingestion.
- Alternate readers: logs, traces, analytics, and diagnostics holding private content or credentials with broader access or longer retention.
- Oracles: counts, ordering, errors, timing, or existence checks that disclose protected state. Require a concrete confidential predicate and an observable difference.
- Export and backup scope: other tenants, inaccessible fields, soft-deleted data, secrets, or history above the requester's access, and authorization to download the final artifact.
- Import and restore authority: bypassing owner, schema, ACL, or uniqueness rules, overwriting existing records, or writing into a tenant the requester cannot write.
- Migration defaults: old records without tenant or ACL fields, ID collisions, and mixed old and new readers during rollout or rollback.
- Backup and replica drift: keys, accounts, regions, or support snapshots with broader scope than primary data.
- Soft-delete bypass: lookups, search, relations, links, jobs, or restore ignoring the lifecycle predicate, and deleted identifiers re-registered before references are gone.
- Stale authorization: membership removal or role downgrade not invalidating sessions, caches, subscriptions, jobs, or materialized data.
- Retention overrun: queued processors, retries, or exports recreating data after deletion completed in primary storage.
- Restore reintroducing invalid state: undelete or recovery bringing back credentials, memberships, or permissions current policy no longer allows.

## Moves

- Pick one protected record and draw write, query, cache, index, event, export, backup, delete, and restore paths. Mark principal and tenant at every edge.
- Compare two dummy tenants through the same service methods, then repeat after an ACL change, deletion, account switch, and restore.
- Start at bypass clients, background jobs, migrations, global uniqueness, and cache keys. They often lack the request-scoped identity interactive endpoints carry.

## Validation

1. Name the lower-trust principal, the protected data, the affected tenant, the alternate copy or operation, and the unauthorized disclosure or change.
2. Cite both the intended policy and the path that omits it, and confirm no other layer enforces the same condition.
3. Use dummy tenants and fixtures. If external storage, replica, CDN, or retention policy decides it, mark `needs_validation` with the owner-observed check.
