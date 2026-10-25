# AI, LLM, and agents

Use when a model takes part in a trust-sensitive decision: chatbots, retrieval, persistent memory, tool-calling agents, MCP servers or clients, prompt assembly from untrusted input, or code that acts on model output. The data flow to follow is untrusted content, then model or memory, then capability, authority, or sink. Transport, access control, and output rendering stay ordinary boundaries, this file covers the delegation layer.

## Discipline

- Prompt injection alone is not a finding. Require a code-level boundary failure: content reaches another principal's context, invokes authority the requester lacks, discloses data they cannot read, or drives a sink they cannot reach directly.
- Model output, memory, tool descriptions, and MCP responses are untrusted input. Point to the code that grants authority, trusts output, writes durable state, or feeds a sink.
- A guardrail prompt is not a boundary. Count only deterministic checks, resource-scoped authorization, isolation, and constrained credentials.
- State the attacker, affected principal, execution identity, resource, action, and observable impact. A user asking for something their own authority allows is not a defect because a model ran it.
- Authorization and action binding are separate. Attacker content that causes an action under the victim's valid authority is a binding failure when the victim never asked for that exact action.

## Classes

- Indirect injection: who can write each retrieved or ingested source, how retrieval scopes it, whose session consumes it, and what capability that session has.
- Context bleed: history, embeddings, retrieval results, or prompt caches keyed too broadly. Tenant filters must be in the query and every cache key.
- Memory poisoning: who can create, update, and delete memory, and whether a low-trust observation becomes a durable instruction for another user or a privileged session.
- Role and provenance confusion: string concatenation, untyped history, or caller-controlled role fields let untrusted text pose as a system message or tool result.
- Tool-argument injection: model-produced arguments reaching SQL, shell, files, URL fetches, or privileged APIs. The schema is input parsing, structured output does not prove authorization or safe paths.
- Confused deputy: the agent runs on a broad service credential and the handler does not re-check the requester on the named resource.
- Approval binding: an approval must bind tool name, full arguments, requester, target, and expiry. Check retries, resumed sessions, and batches for mutated or duplicated side effects.
- Schema and dispatcher disagreement: aliases, extra fields, duplicate keys, or coercions that the handler reads differently from the validator.
- Unbounded action loops: repeated spend, send, or mutation with no per-request budget, cancellation, or idempotency.
- Sub-agent and MCP inheritance: delegated tasks receiving the full session, credentials, or memory instead of least authority.
- MCP identity: routing by server name, tool name, or request ID instead of the authenticated connection. Two servers claiming one tool, and reconnects changing the binding.
- MCP metadata as policy: descriptions and schemas from a peer can guide the model but never grant capability.
- Output rendering: model output reaching HTML, Markdown, URL, or command sinks without that sink's encoding.
- Context extraction: assembled prompts containing credentials or another user's data that user-influenced output can expose.

## Moves

- Draw four maps first: execution identities, capabilities, writable context and memory sources, output destinations.
- Start at side-effecting tools and walk back through dispatcher, schema, confirmation, model context, retrieval, and ingestion. Start at memory reads and trace every writer.
- Compare direct, queued, retry, resume, batch, and delegated paths for the same action. The strongest gate must run after arguments are final and before every side effect.

## Validation

1. Name the crossed boundary and the observable unauthorized or unrequested result.
2. For confused deputy, prove the tool lacks requester-and-resource authorization and the attacker cannot do the same thing normally.
3. For memory or retrieval, cite both the attacker-controlled write and the later cross-principal read or decision.
4. Provider, model, renderer, or external server behavior that is not observable locally means `needs_validation`.
