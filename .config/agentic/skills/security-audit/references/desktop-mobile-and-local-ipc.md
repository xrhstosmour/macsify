# Desktop, mobile, and local IPC

Use when the target is a desktop or mobile app, privileged helper, updater, local daemon, webview host, deep link handler, native messaging host, or local IPC client or server. State the attacker's starting capability, a downloaded document, remote web content, another local app, another OS user, or a sandboxed process, never treat all local users as equivalent. Browser side webview behavior is in `client-side.md`, update authenticity is in `supply-chain-and-ci.md`.

## Discipline

- Self-harm within the same account and authority is not a boundary violation.
- Paths, process names, bundle IDs, and claimed sender fields are not peer authentication. Use OS peer credentials, code identity, capability handles, or protected channel state.
- The bridge or helper must authorize each operation and the final resource after parsing. A trusted UI or broker does not make attacker-influenceable arguments trusted.
- OS sandbox, signing, entitlements, permissions, keychain ACLs, and exported component policy are real controls when pinned and visible.

## Classes

- Deep link ambiguity: another app or page invoking a route that mutates state, imports data, completes authentication, or selects an account without a current session and one-time callback binding. Check normalization, duplicate query fields, scheme and host matching, and replayed links.
- Handoff confusion: OAuth, SSO, magic link, invite, pairing, or payment callbacks returning to the wrong app, profile, tenant, or pending transaction.
- File open and intent authority: an associated file, share intent, drag and drop item, clipboard record, or notification action triggering a privileged operation without checking content type, user intent, and the final target.
- Navigation to bridge confusion: remote or attacker frames reaching a JavaScript to native bridge meant for packaged content. Validate origin at call time and after every navigation, redirect, subframe, popup, and error page, not only at first load.
- Over-broad bridge: web content choosing arbitrary files, commands, IPC methods, or credentials through a generic bridge. Check method allowlists, normalized arguments, confirmation, and return value disclosure.
- Webview file and universal access: remote content reading app local files or internal origins through file access, universal access, mixed content, debug interfaces, or custom protocol handlers. A loose setting without reachable protected content is hardening.
- IPC peer authentication: sockets, pipes, XPC, Binder, D-Bus, native messaging, or loopback listeners accepting a lower-trust peer without OS credentials or code identity.
- Claimed principal versus channel identity: the channel belongs to one app or user while request fields select another user, tenant, or capability.
- Exported component overreach: an externally invokable service, activity, receiver, or provider doing something meant for the app itself. Read the final merged manifest, intent filters, permission level, and path grants.
- IPC lifecycle: predictable request IDs, reused handles, inherited descriptors, world-writable socket paths, or restart behavior letting one peer answer or reuse another's operation.
- Privileged helper as confused deputy: a low-privilege caller selecting a privileged command, file, service, or setting without per-operation authorization. Check polkit, UAC, sudo, and XPC rules and that the helper validates normalized arguments itself.
- Install, update, and repair trust: a privileged installer reading manifests, scripts, symlinks, or repair state writable by a lower-trust actor after authorization.
- Local file race: check then use on a path followed through replacement, symlink, mount, or normalization change in a privileged read or write.
- Local secret boundary: a keychain item, token file, backup, log, clipboard, or notification preview readable by another app, profile, or user with less authority. Plaintext readable only by the same intended account is not automatically a vulnerability.
- Lifecycle leakage: cached data, background tasks, widgets, notifications, local databases, or biometric approvals surviving logout, account change, backup restore, or profile switch.
- Pending action confusion: a notification, widget, shortcut, or deferred operation authorizing a different action than displayed, running after expiry, or using another profile's pending state.

## Moves

- List every process, component, local endpoint, URI scheme, file association, webview origin, and helper with its OS identity, privilege, caller, and callable operation.
- Read the final packaging inputs, merged manifest, entitlements, installer rules, protocol handlers, and ACL creation. Source declarations can be overwritten downstream.
- Validate with dummy profiles and non-sensitive fixtures on an isolated machine or emulator.

## Validation

1. Name the attacker's starting capability, the principal crossed, the entry channel, the accepted argument or state, and the unauthorized operation or disclosure.
2. Cite the navigation and origin control and the native sink for bridges, peer authentication and per-resource authorization for IPC, and the final normalized destination for helpers.
3. If signing, manifest merge, OS version, device policy, or installer ACL decides it and is not observable, mark `needs_validation` with that fact.
4. Stop after proving the boundary result, no persistence or wider system change.
