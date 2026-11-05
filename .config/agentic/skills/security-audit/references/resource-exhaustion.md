# Resource exhaustion and availability

Use when untrusted requests, messages, files, tenant state, or agent work can consume CPU, memory, disk, connections, worker slots, paid APIs, or queue capacity, or can crash or deadlock a shared service. This separates a source-reviewable availability vulnerability from a performance issue. Broker delivery logic is in `protocols-rpc-and-messaging.md`.

## Discipline

- Needs an input to cost path, a missing effective bound, and impact on another user, a shared service, or operator-owned spend. Self-limiting work in the requester's own process is not a service vulnerability.
- A missing rate limit is not enough. Check body, message, and file caps, concurrency, queues, deadlines, database constraints, upstream gateways, and per-tenant quotas first.
- Never stress, saturate, or load test a live or shared service. Use asymptotic analysis, small boundary fixtures, mocked paid calls, strict local limits, and deterministic cancellation tests.
- State attacker cost, service work, persistence, scope, and recovery. One bounded input with a superlinear or persistent shared effect differs from sustained volume.

## Classes

- Superlinear work: catastrophic regex backtracking, nested parsing, recursive validation, graph traversal, template expansion, or adversarial sort and hash behavior. Derive the accepted depth and complexity, then show a bounded growth curve locally.
- Decompression and representation amplification: compressed, sparse, nested, or aliased input expanding far beyond the checked size. Verify limits after every expansion and across parser stages.
- Query amplification: a small request causing broad scans, pathological joins, fan-out, unbounded sort, or many downstream calls because depth, filters, pagination, or expansion fields are not bounded.
- Unbounded buffering and cardinality: bodies, streams, uploads, sessions, unique cache keys, metric labels, subscriptions, or pending jobs without per-item and aggregate limits, and no cleanup on disconnect, timeout, or cancellation.
- Handle and temporary resource leaks: malformed or canceled work retaining sockets, files, cursors, timers, subprocesses, or temporary files, repeatable through bounded local iterations and hitting a shared pool.
- Detached work after cancellation: a timeout, disconnect, or failed authorization returning control while database, model, or worker work keeps running.
- Pre-authentication imbalance: expensive parsing, cryptography, decompression, or external requests before authentication and the earliest size gate.
- Quota accounting gaps: accounting keyed on an attacker-influenceable IP, route, tenant, or task ID, with overflow, distributed races, or reset on reconnect or account switch.
- Starvation: low priority or attacker jobs holding shared locks, workers, pools, or event loop turns, or bypassing queue fairness.
- Reachable fatal error or deadlock: untrusted input reaching `panic`, abort, a fatal assertion, process exit, a lock cycle, or an infinite loop in a shared process. Check supervisor scope, an isolated worker restart lowers impact but not the defect.
- Retry storms: timeouts or partial failures causing synchronized or unbounded retries without jitter, ceilings, or circuit breaking.
- Poison records: one malformed message or record failing repeatedly at the front of a shared queue, partition, startup scan, or recovery loop.
- Unsafe recovery: a restart, restore, or fallback rebuilding unbounded state, ignoring quotas, or restoring the input that repeats the failure.

## Moves

- Build an input to resource table: earliest accepted size, work before authentication, downstream fan-out, persistence, shared pool, limit and cleanup owner, recovery.
- Compare aggregate limits with per-object limits. Many valid tiny items can pass a per-message cap and still exhaust tenant-wide or process-wide state.
- Validate only in an isolated fixture with strict CPU, memory, and time limits. Mock external and paid calls and stop once the missing bound is observable.

## Validation

1. Name the untrusted input, requester work, amplification or retained resource, shared blast radius, and recovery. A missing limit without concrete shared impact is hardening.
2. Confirm no visible upstream, parser, queue, tenant, or framework bound stops the path.
3. If upstream caps, topology, autoscaling, paid quota, or recovery behavior outside the repository decides it, mark `needs_validation` with that fact.
