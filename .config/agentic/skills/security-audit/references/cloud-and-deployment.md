# Cloud and deployment

Use when the repo defines cloud identity, infrastructure as code, containers, Kubernetes, serverless or edge functions, ingress, object storage, or per-environment configuration. Source often expresses intent rather than live fact, so keep source-confirmed defects apart from what only an owner can observe.

## Discipline

- Do not infer a live exposure from a manifest alone. Establish which environment consumes it, which defaults or overlays change it, and whether the path is active.
- Map each workload identity to the operations and resources it can reach. Broad policy is a finding only when lower-trust input can reach an unauthorized action.
- Ingress, proxies, mesh, metadata services, and admission policy count as controls only when their configuration and attachment are visible.
- A secret reference is not secret disclosure. Require a lower-trust reader, output, log path, or unsafe fallback.

## Classes

- Workload identity overreach: a pod, function, or node identity acting on resources beyond its role, with untrusted input choosing the target.
- Role confusion: role assumption, external IDs, or token exchange accepting claims not bound to the intended account, audience, repository, or namespace.
- Identity from metadata: an app trusting caller-supplied headers, tags, or account IDs as if the cloud control plane set them.
- Unexpected reachability: ingress, listeners, port mappings, or binds exposing admin, debug, metrics, or internal APIs. A repo-controlled public route to a sensitive handler can be confirmed, missing network controls alone are `needs_validation`.
- Proxy and mesh bypass: backends accepting forwarded identity from peers outside the ingress, alternate ports or health paths skipping the mesh, fail-open when the proxy is absent.
- Metadata reachability: untrusted URLs reaching instance metadata, runtime sockets, or internal APIs with workload credentials.
- Host capability exposure: privileged mode, host namespaces, host paths, runtime sockets, or service-account tokens selectable by a lower-trust workload.
- Policy path inconsistency: one deploy route enforcing image, namespace, or privilege policy while a job, upgrade, or restore path does not.
- Label trust: network, admission, or identity policy keyed on labels or namespaces a less-trusted principal can set.
- Precedence drift: dev values, chart defaults, flags, or per-region overlays disabling authentication, transport security, or audit in a deployed environment.
- Secret exposure across workloads: logs, crash reports, process arguments, broad volumes, or build outputs readable by another workload.
- Credential renewal fallback: failed refresh or rotation leaving stale credentials active or the app accepting a weaker identity mode.
- Object and signed URL policy: bucket policy, keys, or signed URLs not binding principal, operation, namespace, audience, or expiry.
- Event-source identity: functions trusting event body fields instead of the provider-signed envelope, topic, account, and replay state.
- Edge vs origin mismatch: an edge runtime assuming secrets, isolation, or tenant policy that differ from the origin, with fallback changing authority or caching.

## Moves

- Render every maintained environment and build a matrix of external port, workload identity, network peers, mounted secrets, and cloud resources.
- Follow a lower-trust request, object, label, or event into cloud policy and name the credential that performs the final operation.
- Diff normal deploy, migration, restore, failover, and emulator paths, and read behavior when mesh, admission, identity, or secret services are down.

## Validation

1. Establish the active source path and effective deployed object, otherwise `needs_validation` with the missing rendered manifest or attachment.
2. Verify provider and orchestrator defaults at the pinned version. Do not assume a public IP, reachable metadata, or absent admission policy.
3. Local checks may render templates, evaluate policy, or run an emulator with dummy identities. Never probe live endpoints or change shared cloud resources.
