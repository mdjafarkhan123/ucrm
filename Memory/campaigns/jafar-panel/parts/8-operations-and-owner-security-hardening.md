# Part 8: Operations and current-owner security hardening

## Approved outcome

High-impact Platform Owner work is attributable and recoverable while the approved single,
environment-configured owner identity remains in place. Named owner accounts and MFA are excluded.

## Approved behavior

- The configured owner login is rate-limited and records only sanitized security outcomes.
- An owner session is server-revocable and rotates on a fresh login. Revoked sessions fail every
  protected page and `/api/jafar/*` request.
- Password reconfirmation is short-lived and single-use for each high-impact action.
- Owner security and operations records carry a correlation identifier and never contain passwords,
  cookie values, setup links, secrets, or raw provider failures.
- Operations remains a global, recoverable queue: retry is idempotent, acknowledgement retains
  history, and manual resolution requires a non-secret note.

## Current implementation and gap

- Durable operation attempts, immutable owner audit events, rate-limit RPC support, operation
  retry/acknowledge/resolve endpoints, and a signed five-minute step-up cookie already exist.
- `jafar_session` currently contains only a signed email and expiry. It has no server-side session
  identifier or revocation record, so logout or a security response cannot invalidate an already
  issued cookie centrally.

## Implementation checklist

- [x] Add a private, service-role-only owner-session registry with expiry, revocation, rotation,
  correlation, and suitable expiry/revocation indexes; cover its protection and transitions with
  pgTAP. -- `platform_owner_sessions` (immutable except revocation, PK lookup), migration
  `20260815090000_owner_session_registry_and_login_audit.sql`, 20/20 pgTAP passing.
- [x] Add a server-only owner-session seam that issues, validates, rotates, revokes, and clears
  cookies without exposing session identifiers to browser code. -- `src/lib/server/auth/owner.ts`:
  the cookie carries a signed session id only (safeguard: still HMAC-signed, not just a bare id);
  `getOwnerSession` is the sole place a session id is resolved against the registry, and it creates
  its own scoped Supabase client rather than exposing one to callers, so no route can reach its
  normal service-role client before this check resolves.
- [x] Rate-limit and audit login attempts; rotate on successful login and revoke the presented
  session on logout. -- `ownerLoginRateLimitBucketKey` is a keyed HMAC of the caller IP (never the
  raw IP) fed into the existing `check_rate_limit` RPC; `platform_owner_login_attempts` stores only
  outcome + correlation id (no raw IP or attempted email, per the approved privacy boundary);
  `setOwnerSession` revokes any previously presented session (`revoked_reason: 'rotated'`) before
  issuing a new one.
- [x] Make `getOwnerSession` validate the server registry before any privileged client is created.
  -- done; `getOwnerSession`/`requireOwner` are now async and every one of the ~44 owner API routes
  plus the protected layout and login-redirect check now `await` them before touching their own
  `getOwnerSupabaseClient()`.
- [x] Audit operational acknowledgement and resolution transitions without mutating immutable
  history or leaking private diagnostic content. -- acknowledge/resolve already attributed
  correctly; found and fixed a real gap: `dispatchOutboxDelivery` never threaded an actor through to
  `recordOperationOutcome`, so an owner retrying a stuck outbox email from Operations left no audit
  trail of who retried it. It now takes an optional `actorEmail`, passed by the retry route only
  (the original automated send stays unattributed, correctly).
- [x] Add route and server tests for rejection of revoked/expired sessions, rotation, rate limits,
  sanitized audit data, and recoverable Operations behavior. -- new `src/lib/server/auth/owner.spec.ts`
  (revoked/expired/malformed-cookie rejection, fail-closed on registry error, rotation, bucket-key
  hashing) and rewritten `src/routes/api/jafar/session/session.spec.ts` (rate limit, sanitized
  outcome recording); two new `dispatcher.spec.ts` cases for retry attribution.
- [x] Regenerate database types, run focused and full checks, database tests, advisors, and the
  real browser journey. -- types regenerated, `svelte-check` 0 errors, full `vitest` 397/397, 20/20
  pgTAP, advisors clean (same pre-existing informational RLS-no-policy lints as every other
  service-role-only platform table). Browser journey still needs Jafar.

## Non-goals

- Named Platform Owner accounts, MFA, contractor impersonation, provider controls, and organization
  closure are separate approved parts.
- Do not alter contractor Supabase Auth sessions, organization membership, RLS, or existing
  commercial/team behavior.

## Risks and safeguards

- Every owner endpoint must fail closed if its registry lookup fails or is revoked.
- Login failure recording must not reveal whether the configured email exists or store passwords.
- Rotation and logout must not depend on a browser-only cookie clear.
- Operation retries must retain their existing idempotency keys and cannot be generalized into
  arbitrary provider execution.

## Acceptance checks

- A current owner can sign in and access protected pages; a rotated or revoked cookie cannot.
- A rate-limited login returns a generic response and creates only safe observability data.
- A high-impact action consumes exactly one fresh password reconfirmation.
- Operation retry, acknowledgement, and resolution preserve immutable history and actor/correlation
  attribution.
- `svelte-check`, focused Vitest, full Vitest, pgTAP, and Supabase advisors pass; Jafar approves
  the browser journey.

## Sources

- `docs/jafar-completion-contract.md`: delivery, team/security, and operations requirements.
- `docs/jafar-organization-management-mission.md`: operational recovery and high-impact-action
  security rules.
- `src/lib/server/auth/owner.ts`, `src/routes/api/jafar/session/+server.ts`.
- `supabase/migrations/20260812055458_platform_operations_foundation.sql` and
  `supabase/migrations/20260812083608_platform_rate_limiting.sql`.
