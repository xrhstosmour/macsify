# Protocols, RPC, and messaging

Use when the target uses gRPC, GraphQL transports, Thrift, Protobuf, custom protocols, streaming RPC, webhooks, brokers, queues, pub/sub, or event buses. Covers peer identity, message interpretation, routing, replay, ordering, and delivery semantics. HTTP framing is in `web-and-auth.md`, availability impact is in `resource-exhaustion.md`. Split large systems by producer and consumer pair, and by synchronous, streaming, and asynchronous path.

## Discipline

- Internal is not authentication. Name the peer identity at every hop and show how it becomes the application principal used for authorization.
- Schema validation proves shape, not provenance, resource authority, ordering, or safe values. Follow decoded fields to policy and side effects.
- Broker guarantees and application guarantees differ. Write down retry, ordering, acknowledgement, deduplication, and transaction behavior before judging a state change.
- Parser disagreement needs two concrete consumers, schema versions, or wire forms and one security-relevant divergent value.

## Classes

- Boundary and canonicalization disagreement: components disagreeing on length, compression, duplicate or unknown fields, encoding, numeric width, or envelope and body precedence. Name the principal, resource, or operation that differs after decoding.
- Union, enum, and default confusion: unknown variants, missing discriminators, zero values, or default privileges reaching code that assumes a validated case, and how old consumers read new fields.
- Envelope and payload identity mismatch: authorization using routing metadata while the handler acts on a conflicting tenant, subject, or sender in the body.
- Interceptor and method path inconsistency: authn or authz applied to unary methods but not streams, reflection, health, gateway transcoded paths, or compatibility services.
- Peer identity to principal confusion: mTLS, workload identity, or broker credentials authenticate a channel while a caller field selects the user or tenant.
- Per-item and streaming authorization: a stream, subscription, or batch authorized once while later items name other resources or continue after revocation.
- Reply correlation confusion: predictable, reused, or cross-tenant correlation IDs letting a response, webhook, or cancellation satisfy another caller's operation.
- Topic and subscription scope: a publisher or subscriber reaching another tenant's topic, wildcard, consumer group, reply queue, or dead letter route. Tenant text inside a payload is not isolation.
- Dead letter and diagnostic disclosure: failed messages with secrets or cross tenant payloads readable through error topics, traces, or operator views.
- Untrusted producer as control plane: a message body declaring itself an admin event, provider callback, or migration instruction without an authenticated producer and source, account, and audience binding.
- Duplicate delivery: retries repeating a side effect because deduplication is absent, runs after the mutation, or collides across tenants.
- Stale and out of order messages: older state, revoked membership, or canceled work arriving after newer state and overwriting it. Check sequence checks, tombstones, and replay workflows.
- Acknowledgement and commit ordering: acknowledging before a durable commit loses work, committing before an unreliable acknowledgement duplicates it.
- Partial multi-consumer transitions: several consumers implementing one authorization or business transition where retries and partial failure commit only a subset.

## Moves

- Draw producer, transport, gateway, consumer, and storage for each message family, with the authenticated peer, authoritative tenant and resource fields, validation, and side effect at each hop.
- Feed one small fixture to every schema version and language binding. Test duplicate, missing, unknown, boundary, replayed, and reordered messages without producing load.
- Compare normal, retry, dead letter, replay, migration, reflection, stream, and gateway routes. Policy must survive transport changes.

## Validation

1. Name the realistic producer or peer, the accepted message, the channel identity, the affected resource, and the unauthorized mutation or disclosure.
2. For disagreement, cite both parsers and the divergent decoded value, a safe rejection by either side blocks confirmation.
3. For replay and order, establish the real delivery guarantee and reproduce the invariant failure on a bounded local or in-memory transport.
4. If a broker ACL, mesh identity, topic attachment, or compatibility behavior outside the repository decides it, mark `needs_validation` with that fact.
