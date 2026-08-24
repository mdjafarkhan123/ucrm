# Part 3: Team & Access

## Outcome

Contractor Owners and Administrators can invite and manage the right people, apply understandable access,
and offboard safely without weakening tenant isolation or historical truth.

## Authority

- Product behavior: `docs/contractor-settings-blueprint.md` → **Confirmed Part 3 behavior**.
- Domain language: `CONTEXT.md` → organization and team-member terms.
- Existing implementation truth: active migrations, `src/lib/server/access/*`, and `/api/team/*`.
- Part 1 and Part 2 decisions remain protected.

## Dependencies

- Part 1 Settings directory and permission-aware navigation.
- Existing organization membership, entitlement, permission-override, audit, and collaboration foundations.
- Supabase Auth Admin operations remain server-only.
- Availability waits for real Scheduling support; its destination remains absent until then.

## Execution slices

### 3A — Access and data foundation

- Reconcile live permission keys; keep legacy and unenforced keys out of contractor payloads.
- Model Pending, Active, and Deactivated membership plus one protected Owner.
- Add member profile, invitation, lifecycle, and independent revision state.
- Represent No access, Assigned work only, and All work only where the target domain enforces that scope.
- Add dependency-aware permission validation and protected Owner/Administrator invariants.
- Add narrow indexes for tenant/status lists, invitation lookup, audit history, and RLS predicates.
- Implement atomic database commands and direct database tests for every invariant.
- Audit all membership/authorship foreign keys before choosing permanent-removal mechanics.

Completion gate: schema, commands, RLS, grants, indexes, and database tests prove tenant isolation,
single-Owner safety, scoped access, seat concurrency, and historical preservation.

### 3B — Invitation lifecycle

- Invite with explicit role and optional compatible adjustments.
- Count Pending plus Active members against the effective platform seat limit under concurrency.
- Support delivery failure, resend, cancellation, expiry, and acceptance with idempotent commands.
- Reject an email already attached to another contractor organization.
- Changing a pending email cancels the old identity and creates a new invitation.
- Keep Auth secrets and invitation tokens out of browser payloads and logs.
- Resolve the approved seven-day expiry without weakening unrelated OTP or magic-link security.

Completion gate: retries and partial failures cannot duplicate identities, invitations, or seat use; expired,
canceled, replaced, and cross-tenant invitations cannot grant access.

### 3C — Team directory and member details

- Add live Team and Roles & permissions Settings destinations.
- Separate Pending, Active, and Deactivated members with search and status filtering.
- Bound and paginate the list; return only fields needed by the current view.
- Give Member details, Role & access, and later Availability independent Save/Cancel/conflict behavior.
- Use TanStack Query with deliberate stale times and precise invalidation.
- Build desktop first, then verify mobile, keyboard, focus, and screen-reader behavior.

Completion gate: authorized users can find and inspect members across states; unauthorized roles cannot see
or call Team management; navigation renders cached/skeleton state without blocking.

### 3D — Roles and permission controls

- Implement the approved Administrator, Office, Sales, Field, and Finance starting points.
- Group enforced capabilities and expose safe detail rather than raw permission keys.
- Use accessible information popovers with plain examples and dependency explanations.
- Preview role results, retained/removed adjustments, and assignment conflicts before Save.
- Mark individual differences as Adjusted.
- Keep unavailable entitlements visible only when useful, disabled as Not included in your plan.
- Preserve saved adjustments while their entitlement is unavailable; they grant no access meanwhile.

Completion gate: every visible choice changes effective server and database authorization exactly as described;
invalid combinations and self-escalation fail at both API and database boundaries.

### 3E — Offboarding and ownership

- Deactivate with immediate membership denial, session revocation, and one explicit assignment decision.
- Restore only when a seat is available; never restore former assignments.
- Allow Owner-only permanent removal after deactivation and typed-name confirmation.
- Preserve historical attribution while removing future access and legally removable contact details.
- Reinviting a removed email creates a new membership and does not join old history.
- Transfer ownership only to an Active Administrator through confirmed request and acceptance.
- Record access events and send the approved summarized notifications.

Completion gate: offboarding and transfer pass concurrency, partial-failure, session, ownership, assignment,
audit, and historical-attribution tests, plus browser verification of every destructive confirmation.

### 3F — Availability integration

- Activate only after Scheduling owns member availability and assignment conflicts.
- Add weekly patterns and dated exceptions.
- Let authorized schedulers override availability with a warning and recorded actor.
- Keep Business Hours and personal availability separate.

Completion gate: availability affects suggestions and warnings truthfully without becoming a hidden permission
barrier or a dead settings page.

## Cross-cutting safeguards

- Route all writes through validated `/api/*` commands with rate limits and `Cache-Control: no-store`.
- Keep tenant, role, state, entitlement, and permission checks at server and database boundaries.
- Treat Auth calls and Postgres writes as separate failure domains with retryable state and compensation.
- A revoked or deactivated member fails authorization even while an old JWT or cached page remains open.
- Preserve one source of truth for role defaults, permission dependencies, and user-facing explanations.
- Protect existing Clients, Requests, Pipeline, Quotes, collaboration, and Part 1 Settings behavior.

## Verification

- Database: constraints, RLS, grants, indexes, locking, idempotency, revision conflicts, and cross-tenant denial.
- Auth: invite acceptance, expiry, resend/cancel, active-session revocation, and removed-user denial.
- API: Zod validation, field errors, authorization order, rate limits, partial failures, and cache headers.
- Performance: bounded queries, no N+1 Auth/profile lookup, query plans, RLS predicate indexes, and payload size.
- UI: desktop/mobile, mouse/keyboard/touch, popover focus, dirty navigation, conflicts, toasts, and error recovery.

## Non-discoverable risks

- Supabase invite expiry shares the Email OTP expiry setting; do not change it globally without auditing every
  email-link flow.
- Auth-user deletion does not invalidate an already-issued JWT until expiry. Sensitive boundaries need current
  membership/session validation.
- Existing permission history contains singular/plural duplicates and unenforced keys.
- Current boolean overrides cannot represent Assigned versus All without an authorization-model change.
- Auth operations cannot share a Postgres transaction, so an apparently simple invite/remove is a workflow.
