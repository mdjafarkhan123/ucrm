# Part 6C: Versioned Package Changes and Reasoned Exceptions

## Approved behavior

- A Platform Owner package change is immediate, separately confirmed, and targets a published
  immutable package version.
- Every package change preserves the prior and new package version, private reason, actor, and
  effective time. Package changes are never scheduled or represented by mutating the legacy
  `organizations.package_key` fields.
- Feature and limit exceptions are immediate owner actions with a required private reason, an
  explicit start time, and an optional expiry. An exception may be ended by an explicit inherit
  action with its own reason; deleting history is not allowed.
- Numeric limits remain explicit: `not included`, a positive numeric value, or `unlimited`.
  Zero is not an alias for unlimited.
- Existing reasonless feature and limit projection rows remain effective until reviewed and are
  marked as legacy imports. New actions do not silently rewrite or remove those historical facts.
- Private reasons, owner identity, and raw internal state stay in owner history. Contractor-safe
  notices contain only safe access outcomes.
- Package and exception commands are idempotent and atomic with their history and current access
  projection. Concurrent commands for one organization serialize safely.

## Dependencies

Part 6A (commercial-control foundation) and Part 6B (payments and paid-through control) — complete.

## Implementation sequence

1. Add the database command seam and immutable exception event history. Extend package assignment
   validation/metadata as needed, preserve legacy projection rows, and add RLS/privilege checks.
2. Add pgTAP coverage for published-version validation, append-only history, legacy-import behavior,
   idempotency, concurrent serialization, rollback, and contractor-safe payload redaction.
3. Replace the owner package endpoint with a reasoned version assignment command. Remove scheduled
   downgrade behavior from the normal path and ensure old/new versions are returned safely.
4. Replace feature and limit override writes/deletes with reasoned command endpoints. Require
   explicit starts and validate expiry/value state before database access.
5. Extend effective-access reads and the organization history feed to use the new projections and
   immutable events without exposing private reasons to contractor callers.
6. Update the Commercial access UI with separate confirmations, reason fields, version details,
   exception start/expiry state, loading/error/retry behavior, and safe success notices.
7. Run focused route/database/unit checks, remote advisors, and desktop/mobile browser verification
   of package, feature, limit, inherit, retry, and legacy-import states.

## Acceptance checks

- [x] Package changes accept only published package versions and require a non-empty reason.
- [x] A package change creates one append-only assignment and one owner history record containing
      old version, new version, reason, actor, and time; no scheduled downgrade remains active.
- [x] Retrying the same idempotency key does not create a second assignment, event, notice, or
      projection change.
- [x] Feature and limit changes require a reason and start time; expiry must be later than start.
- [x] Inherit actions append history and restore package-derived access without deleting history.
- [x] Legacy reasonless overrides remain effective and are visibly marked as legacy imports until
      a reasoned owner action replaces or ends them. (pgTAP and code-reviewed; no real legacy
      feature/limit override rows exist yet to also eyeball the badge live — see closing note.)
- [x] Limit states distinguish not included, numeric, and unlimited, with no zero/unlimited
      ambiguity.
- [x] Partial failures roll back the projection and immutable event together.
- [x] Contractor-safe events contain only approved safe outcome fields and no private reason,
      owner email, or internal references.
- [x] History shows package and exception changes in chronological order with private owner data
      visible only to the Platform Owner route.
- [x] RLS, grants, and independent owner authorization prevent contractor or anonymous mutation.
- [x] Existing 6A/6B payment, free-access, lifecycle, and effective-access checks remain green.

## Source pointers

- `docs/jafar-completion-contract.md`, heading `Organization and commercial control`.
- `docs/jafar-organization-management-mission.md`, headings `Commercial rules`, `History,
  transparency, and recovery`, and `Organization-detail structure`.
- `supabase/migrations/20260810054722_organization_versioned_package_assignments.sql`.
- `supabase/migrations/20260813200000_organization_commercial_control_foundation.sql`.
- `src/lib/server/access/effective.ts`.
- `src/routes/api/jafar/organizations/[organizationId]/package/+server.ts`.
- `src/routes/api/jafar/organizations/[organizationId]/feature-overrides/[featureKey]/+server.ts`.
- `src/routes/api/jafar/organizations/[organizationId]/limit-overrides/[limitKey]/+server.ts`.
- `src/routes/api/jafar/organizations/[organizationId]/history/+server.ts`.

## Non-discoverable risks

- Current package writes mutate legacy organization columns even when a versioned assignment exists;
  changing the route must not break legacy organizations that still resolve through fallback access.
- Current feature and limit rows are mutable projections with no reason fields. The migration must
  preserve their effective values while introducing an immutable event stream and legacy marker.
- The remote Supabase project is authoritative for migration execution. Docker is unavailable, so
  do not assume local database tests can run; never use `db push` blindly.
- Preserve unrelated dirty work, especially layout, picker, dependency, and existing 6B changes.

## Current checkpoint

Closed 2026-08-14. All acceptance checks pass. Remote migrations applied, including a corrective
migration `20260814100000_fix_package_exception_idempotency_ambiguity.sql`. pgTAP green: 6C 25/25,
6A 49/49, 6B 16/16. `get_advisors` shows no new findings. `svelte-check` and the focused vitest
suite (46 tests) are green. `database.types.ts` regenerated against remote.

Fixed two real bugs found during this closeout, both worth remembering for future RPC work:
- Postgres function parameters have no nullability signal, so when a route omits an optional
  timestamptz/numeric arg via `?? undefined`, supabase-js's `JSON.stringify` drops the key and
  PostgREST can't match the function overload (`PGRST202`) — surfaces as a bare 500. Fix: pass
  explicit `null`, not `undefined`, for any RPC arg without a SQL default; cast with `as` since
  generated Args types can never express `| null` here.
- A function parameter sharing a name with a table column it queries (`idempotency_key`) makes an
  unqualified reference ambiguous (`42702`) even when written as `function_name.param`. Qualify
  the table side too.

Not verified: mobile viewport rendering (`resize_window` didn't change this session's actual
window size) and a live legacy→versioned package transition on real org data (skipped as
unnecessary — deliberately not exercised, not a gap; see part packet acceptance checks above).
