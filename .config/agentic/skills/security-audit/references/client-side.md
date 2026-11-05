# Client side and browser

Use when meaningful trust decisions or untrusted rendering happen in a browser, single-page apps, extensions, webviews, service workers, offline apps, or code that renders attacker-influenceable content, receives cross-window messages, or uses browser storage. Covers sources the server never sees, such as URL fragments, `window.name`, `postMessage`, and cached content. Server-side CSRF, sessions, and auth callbacks are in `web-and-auth.md`, the native side of a webview bridge is in `desktop-mobile-and-local-ipc.md`.

## Discipline

- A candidate needs a controllable source and an executing or disclosing sink. Name both and show attacker-influenced data reaching the sink.
- Impact must reach a victim's session, another origin, or shared persistence. Self-injection and disclosure of the attacker's own data are not findings.
- Framework escaping, same-origin policy, CSP, COOP and CORP, service worker scope, and modern `noopener` defaults are real controls. Verify them before assigning impact.
- Browser storage and caches are shared by origin and may outlive login state. Identify who writes, who reads, and what clears each record.

## Classes

- DOM-based XSS: `location`, `document.referrer`, `window.name`, message data, or storage reaching `innerHTML`, `document.write`, string-evaluating APIs, executable URLs, or framework escape hatches. Framework-escaped interpolation is not a finding.
- DOM clobbering: injected `id` or `name` attributes shadowing a global, form property, or initialization flag later trusted by code. Needs a markup path that keeps the attribute and a security-relevant use.
- Prototype pollution: an attacker-controlled key reaching a recursive write, plus a reachable gadget that changes authorization, execution, navigation, or rendering. Pollution without a gadget is not enough.
- `postMessage` trust: a sensitive handler without an exact origin allowlist and, where frames share an origin, the expected `event.source`, or sensitive data sent to `*`. Substring, prefix, and unanchored regex matching are not origin checks.
- Cross-site WebSocket and credentialed CORS: an upgrade or response honoring ambient cookies from an untrusted origin without an `Origin` check or channel token.
- Service worker takeover: attacker-influenceable content becoming the registered script, an over-broad `Service-Worker-Allowed` scope, or imports without integrity control.
- Service worker cache confusion: personalized responses cached without account, tenant, or authorization state in the key, then served after logout or account switch.
- Storage disclosure and stale authorization: tokens, private responses, or decisions in web storage, IndexedDB, Cache Storage, or extension storage readable by a less-trusted same-origin component or used after revocation. A stored token alone is not a finding.
- Cross-context confusion: `storage` events, `BroadcastChannel`, or shared workers carrying identity or commands between tabs without binding to the current session.
- XS-Leaks: an attacker page telling protected cross-origin state apart through load or error events, frame state, redirects, timing, or cache state. Needs one concrete secret-bearing predicate, generic timing variance is not a finding.
- Clickjacking: a framed state-changing action without effective `frame-ancestors` or equivalent. Missing headers on read-only content are hardening notes.
- Navigation confusion: a client source controlling redirects without a scheme and destination policy, including `javascript:` and `data:`. Reverse tabnabbing applies only where code keeps `window.opener` or lacks implicit `noopener`.

## Moves

- Start from DOM, navigation, worker, message, and storage sinks, trace back to browser-only and server-controlled sources, and record the browser policy that should stop the path.
- Test account switch, logout, worker update, offline fallback, and stale tabs with a local test origin and dummy accounts.
- For XS-Leaks, list only predicates proved by source and local browser behavior, then name the header or rendering choice that removes the oracle.

## Validation

1. Cite the source, sink, browser policy, affected origin or session, and the observable mutation or disclosure.
2. Prove the recursive write and gadget for pollution, the surviving markup and its use for clobbering, and the attacker write that reaches a different account or later authorization state for workers and storage.
3. Confirm CSP, COOP and CORP, cookies, and `SameSite` do not already block it.
4. If the deployed header, extension permission, browser version, or renderer behavior decides it, mark `needs_validation` with that fact.
