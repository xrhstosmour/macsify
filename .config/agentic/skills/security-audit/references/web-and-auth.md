# Web protocol and authentication

Use when the target speaks HTTP at a parsing, caching, session, or identity boundary: web apps, APIs, proxies, gateways, and anything with sessions, JWT, OAuth, OIDC, SAML, MFA, passkeys, API keys, or mTLS. Access control asks whether a principal may do an operation, this file asks whether the HTTP or identity layer can confuse which principal, request, or token the operation belongs to.

## Discipline

- Framing and cache findings need two interpretations of the same request or key. Name both components and the exact value each sees.
- For every credential, find the verification and every binding its role needs: issuer, audience, origin, client, session, principal, resource, expiry, one-time state.
- Host, `Forwarded`, `X-Forwarded-*`, `Origin`, `Referer`, redirect targets, callback state, and request-derived URLs are trust decisions. Trace each to the identity or response it changes.
- A missing header, cookie flag, MFA prompt, or rate limit is not a finding alone. Require an accepted invalid request, cross-principal impact, assurance downgrade, or credential disclosure.

## Classes

- Request framing: two `Content-Length` values, `Transfer-Encoding`, HTTP/2 downgrade, header normalization. Which bytes does each side assign to the next request.
- Cache poisoning and deception: a request value changes the response but is missing from the cache key, or a private dynamic path is cached as a static asset.
- Host and forwarded-header trust: untrusted metadata picks absolute URLs, tenant routing, reset links, or the client address used by authorization.
- Response-header injection: untrusted data in `Location`, `Set-Cookie`, or CSP. Check the framework rejects control characters first.
- CSRF: every cookie-authenticated mutation, including JSON-like, multipart, method-override, and legacy routes. Bearer-token routes do not qualify.
- Session lifecycle: no rotation on login, MFA, impersonation, or privilege change, and sessions or refresh tokens that survive logout, password change, or disable.
- Cookie scope: over-broad `Domain` or `Path`, or sibling cookies selected differently by two components.
- JWT: server-pinned algorithm and key source, then `exp`, `nbf`, `aud`, `iss`. `kid`, `jku`, and `x5u` are untrusted selectors. A token signed by a trusted issuer for another service is invalid.
- OAuth and OIDC: session-bound `state`, PKCE, ID-token `iss`, `aud`, `nonce`, and the selected provider in multi-provider flows. Compare initial, retry, deep-link, and account-link callbacks.
- SAML: the signed element must be the element used as identity. Check unsigned fallbacks, parser safety, and replay state.
- MFA and step-up: enrollment, replacement, disablement, and recovery codes need fresh prior assurance. A challenge must bind to the session, action, and expiry, and every alternate route must check it.
- Passkeys: bind challenge, RP ID, origin, credential, and user handle to the initiating session.
- Account linking and recovery: new identity needs a current session, proof of ownership, and callback state bound to the initiating account. Reset tokens need randomness, user binding, expiry, one-time use, and invalidation of earlier tokens and sessions.
- API keys: scope and resource binding enforced server-side, publishable vs secret key confusion, keys in bundles, URLs, logs, or redirects.
- mTLS: identity headers trusted from any peer, subject text mapped to an account loosely, and fail-open fallback when a certificate expires or renewal fails.

## Moves

- Walk issue, store, transmit, consume, refresh, revoke for every credential and challenge, including error, retry, migration, and legacy paths.
- List every door to the same identity and every route to the same operation. The effective policy is the weakest parallel path.
- For recovery and linking, draw the account graph before and after. Each edge names the current principal, proof of the new identity, assurance, and revocation effect.

## Validation

1. Proxies, edge cache keys, identity provider policy, browser cookie behavior, and deployed auth modes are often outside the repo. Mark them `needs_validation` with the exact fact, never assert missing infrastructure.
2. Cite the verification line and the missing binding, and show the server accepts the invalid transition.
3. Verify framework defaults at the pinned version before reporting. Unknown version or configuration means `needs_validation`.
