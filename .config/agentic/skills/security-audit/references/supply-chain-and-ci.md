# Supply chain, CI, and release

Use when the target resolves dependencies, builds from untrusted contributions, runs CI, signs or promotes builds, loads plugins, or updates deployed software. The question is where trust is handed off between source, dependency, and the artifact a user runs.

## Discipline

- A mutable or vulnerable dependency is not a finding alone. Show who can influence resolution, which build consumes it, and what execution or release boundary follows.
- Follow integrity across every handoff: source, resolved inputs, build worker, artifact identity, test result, signature, promotion, update consumer.
- CI configuration is authorization code. Establish which event triggered a workflow, whose code runs, which secrets and tokens exist, and what it may publish.
- A checksum fetched from the same untrusted place as the artifact proves nothing. Name the trusted root and the failure behavior.

## Classes

- Dependency confusion: resolver settings that pick the wrong public or private namespace, fallback registry, or source URL. Check lockfile and checksum use.
- Unbound build inputs: branches, tags, floating CI actions, container tags, remote includes, or downloaded tools that change without review. Require a lower-trust writer and a path into trusted output.
- Generated source: clients, schemas, vendored archives, or blobs shipped without the review and integrity gate source gets.
- Build-context leakage: secrets, local config, or fixtures entering a package or image because ignore rules exceed the intended inputs.
- Untrusted code in a privileged workflow: pull requests, forks, issue comments, or dependency updates running with secrets, write tokens, or deploy authority. Compare trigger, checkout ref, approval gate, and permissions.
- Workflow expression injection: branch names, commit messages, issue fields, or artifact names reaching shell commands or template expressions.
- Cache and artifact mixing: a low-trust job fills a cache or artifact that a high-trust job restores and runs or releases. Check keys, producer identity, and digest binding.
- Automation overreach: jobs with more permission than the operation needs, where untrusted input selects the target. Missing least privilege alone is hardening.
- Build-to-promotion substitution: tests, review, signing, and publish referring to mutable names instead of the same digest.
- Signing policy gaps: a signature accepted from the wrong workflow, branch, environment, or key role. Verify the consumer checks identity claims, not just validity, and fails closed on expiry or revocation.
- Updaters: payload authenticated but not version, product, platform, channel, or rollback state.
- Plugins and extensions: authority beyond declared scope, publisher identity replacement, install hooks running before authenticity checks. Intended installation of same-user plugins is not a boundary.

## Moves

- Walk backward from a released digest or installed update to every source, input, credential, worker, cache, and authorization decision.
- Compare untrusted and protected workflow events side by side and mark each persisted channel between them.
- Read the revoked key, failed download, missing attestation, rollback, and registry outage paths. The failure policy is part of release integrity.

## Validation

1. Name the lower-trust actor, the controllable source, cache, or metadata, the consuming trusted job or updater, and the unauthorized result.
2. Branch protection, hosted runner, registry, and signing service settings are usually not in source. Mark them `needs_validation` with the exact fact an owner must observe.
3. Never publish or alter a real release. Use a harmless fixture repository and dummy credentials.
