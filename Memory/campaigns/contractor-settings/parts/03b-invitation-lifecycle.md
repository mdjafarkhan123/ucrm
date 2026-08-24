# Part 3B: Invitation lifecycle

This slice owns invitation orchestration over 3A's database primitives. It does not own the Team directory
UI (3C), general role editing (3D), or member offboarding (3E).

## Outcome

An Owner or Administrator can invite an eligible person by email with an explicit role and compatible
permission adjustments. The person receives one UCRM-controlled seven-day link, establishes a password,
and becomes Active exactly once. Delivery failures stay visible and retryable. Crashes, retries, expiry,
cancellation, replacement, and concurrent requests cannot duplicate an Auth identity or consume two seats.

## Locked orchestration

### Invite

1. Authenticate an Active contractor and require `team.manage`; database commands remain the final authority
   over who may invite which role.
2. Validate and normalize the email, explicit role, and compatible adjustments. No role is preselected.
3. Reserve the seat with `begin_team_invitation`. The existing organization advisory lock serializes seat
   checks; no aggregate or materialized view is needed for this write path.
4. Stamp `mark_team_invitation_auth_attempt_started` immediately before `auth.admin.createUser`.
5. Create a confirmed Auth identity without a usable chosen password. Its server-owned `app_metadata` names
   the invitation id as the identity receipt; it is not used for authorization.
6. Attach the identity, hashed 32-byte token, seven-day expiry, pending membership, and compatible
   adjustments atomically. Pending membership grants no application access.
7. Send the transactional email with the raw token only in the link, then record success or the safe
   delivery error. A failed send returns Delivery failed but keeps the pending seat so resend/cancel works.

Every raw token and password exists only in request memory or the outbound email call. Neither is stored,
logged, returned to an authenticated manager, or written to an audit event.

### Accept

1. Public GET validates the token hash and returns only usability plus a masked email hint.
2. Public POST is Zod-validated and IP-rate-limited. `claim_team_invitation` atomically binds token, email,
   expiry, and a 15-minute lease.
3. Read the Auth user. If `app_metadata.invitation_password_set_for` already equals this invitation id,
   skip the token and password operations and call finalize only.
4. Otherwise call `updateUserById` once with the password and a merged `app_metadata` receipt
   `invitation_password_set_for = invitation_id`. A live disposable-user test must prove that this remote
   Auth version writes both fields atomically before this path ships.
5. Record the password receipt in Postgres, then call the idempotent finalizer. Finalization activates the
   membership and settles the invitation in one transaction.

After any uncertain Auth outcome, a retry never submits the token or password again. It reads the Auth
receipt and finalizes only when the receipt matches. A mismatched or absent receipt goes to reconciliation.

### Resend, cancel, expiry, and email replacement

- Resend is allowed only from `invited`, rotates the token before delivery, resets the seven-day expiry, and
  invalidates every older link even when the new email delivery fails.
- Cancel refuses an open acceptance lease. Otherwise it settles the invitation, removes only its pending
  membership, and queues its invitation-owned Auth identity for cleanup.
- Expiry is a bounded worker action. It expires untouched invitations, preserves an open acceptance lease,
  and reconciles a completed Auth receipt before deciding cleanup.
- Changing a pending email is cancel-old then create-new. It never mutates an Auth email or reuses the old
  invitation identity. If new creation fails, the old invitation remains cancelled and the manager retries.
- An email already present in Auth or reserved by another non-terminal invitation is refused before send.
  A global partial uniqueness guard closes concurrent cross-organization reservations; Auth uniqueness is
  the second boundary.

### Reconciliation and orphan cleanup

- One protected worker processes bounded batches with `FOR UPDATE SKIP LOCKED`; repeated runs are safe.
- A stale reservation with `auth_attempt_started_at is null` may be abandoned immediately, exactly as 3A
  requires.
- A marked Auth attempt is never released blindly. The worker performs an exact server-only Auth identity
  lookup and accepts only an identity whose invitation receipt matches the row.
- Matching identity plus password receipt: record/finalize. Matching identity without password receipt:
  prepare cleanup under the worker lease, which withdraws the link and removes only the pending membership
  while keeping the reservation, email, and seat held; then delete the invitation-owned Auth account and
  settle only after confirmed deletion. No match: settle the reservation. Any uncertain delete keeps
  `identity_cleanup_state = required`, the email claimed, and the seat held for retry.
- Cleanup never deletes an accepted identity or an identity whose receipt belongs to another invitation.

## HTTP surface

- `POST /api/team/invitations` — invite and attempt email delivery.
- `POST /api/team/invitations/[invitationId]/resend` — rotate first, then deliver.
- `POST /api/team/invitations/[invitationId]/cancel` — cancel pending invitation.
- `POST /api/team/invitations/[invitationId]/replace-email` — cancel old, then create a fresh invitation.
- `GET /api/team/invitations/accept?token=...` — public safe link check.
- `POST /api/team/invitations/accept` — public password acceptance.
- One protected scheduled worker entry point for expiry and reconciliation; it is not callable with a user
  session and never trusts browser input.

All writes use `/api/*`, Zod, deliberate rate limits, and `Cache-Control: no-store`. Errors expose stable,
plain outcomes (`seat_limit`, `email_in_use`, `invalid_or_expired`, `acceptance_in_progress`,
`delivery_failed`) without leaking whether an arbitrary email has a UCRM login.

## Database changes before orchestration

- Add the smallest persisted representation needed for invitation permission adjustments and make identity
  attachment copy them to the pending member atomically.
- Add a global partial uniqueness guard for normalized email across non-terminal invitations.
- Add exact service-role-only reconciliation commands/lookups; do not expose `auth.users` or secrets.
- Add bounded worker claim/settlement support and indexes matching its state/cleanup/age predicates.
- Preserve the existing organization/state/created index for the future 3C cursor list. No offset pagination.
- Extend the grant matrix for every new or replaced function.

## Ordered implementation

1. ~~Database delta and pgTAP: adjustments, global email race, reconciliation claims, cleanup settlements,
   grants, and query plans. Applied through Supabase MCP and written locally.~~ Closed 2026-09-02.
2. ~~Performance-review the database layer before moving on.~~ Closed 2026-09-02: the 10,000-row worker
   queue used the intended index, selected 25 rows in 0.075 ms, and completed in 5.47 ms.
3. ~~Server invitation module: token handling, Auth receipts, transactional email, and error mapping.~~
   Closed: the server-only create sequence reserves, marks the Auth boundary, creates a receipt-owned
   confirmed identity without a password, attaches only the token hash, delivers through Brevo, records a
   safe delivery outcome, and maps provider/database failures to stable outcomes. Ten focused Vitest checks
   cover ordering, secrets, and partial failures.
4. ~~Auth contract test against a disposable live user, with guaranteed cleanup.~~ Closed 2026-08-22:
   one `updateUserById` call wrote the password and merged invitation receipt metadata, password sign-in
   succeeded, and deletion of the disposable identity was confirmed.
5. API routes and Vitest coverage for authorization, Zod, rate limits, headers, partial failures, and retries.
   Create, resend, cancel, replace-email, public inspection/acceptance, and the protected worker implementation
   are closed. Worker deployment activation is the exact next action: configure the matching app/Vault secret
   and live route URL, then verify one authorized scheduled pass.
6. ~~Performance-review the API/Auth layer.~~ Closed: maintenance is capped at 25 rows per queue, Auth work is
   capped at five concurrent calls, every response is `no-store`, and the 10,000-row reservation/expiry plans
   used their partial indexes in 2.142 ms/0.070 ms.
7. Public acceptance page using the existing setup-password visual pattern; load design and Svelte gates
   before touching it. Contractor Team UI remains 3C.
8. Browser-verify invite, failed delivery, resend, wrong email, expiry, acceptance, retry, and cancellation.

## Acceptance checks

- Concurrent final-seat invitations produce one reservation and one clear refusal.
- Concurrent cross-organization invites for one normalized email produce one identity at most.
- Every crash boundary before/after reserve, Auth create, attach, token rotation, delivery, password receipt,
  and finalize has a tested retry or worker outcome.
- Wrong email does not consume the link; old, expired, cancelled, replaced, and cross-tenant links never
  activate membership.
- A delivery failure remains Pending, consumes one seat, shows Delivery failed, and can resend or cancel.
- Pending users read no tenant data; only successful finalization changes them to Active.
- No Auth secret, raw token, password, or unrestricted Auth error enters logs, payloads, or audit history.
- Database, Auth, API, performance, and browser gates pass before 3B closes.

## Required sources

- `parts/03-team-and-access.md` §3B and `parts/03a-access-and-data-foundation.md`.
- `docs/contractor-settings-blueprint.md` Confirmed Part 3 behavior.
- Supabase Admin Auth documentation for `createUser`, `getUserById`, `updateUserById`, and `deleteUser`.
- Existing `/setup-password` and `issueSetupLink` code are patterns, not reusable lifecycle authority.
