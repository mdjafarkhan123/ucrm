# Part 7: Team Access and Administrator Recovery

## Approved behavior

Source: `docs/jafar-completion-contract.md` heading `Team support and owner security`;
`docs/jafar-organization-management-mission.md` headings `Team access and support recovery` and
`High-impact action security`. Grilled directly with Jafar (plain-language rounds, no formal doc
update needed) on 2026-08-14; decisions below are his answers.

- **Read-only view**: Team access card keeps showing role, and now also shows each member's
  individual permission overrides (grant/revoke exceptions from `organization_member_permission_overrides`),
  not just the raw role. Fixes the pre-existing bug where `GET .../team` 500s for Riverside Legacy
  Demo (a single per-user `auth.admin.getUserById` failure must not fail the whole list).
- **Profile correction** (light action, reason + confirmation, no step-up): fixes a team member's
  name (any role) and, for non-admin/non-owner roles only (office/sales/field/finance), their login
  email. Admin/owner email never changes here — always goes through recovery below. Records
  before/after, actor, time, in `access_audit_events`. Creates a notice to the affected member only.
  If email changed, revokes that member's sessions (forces re-login).
- **Administrator email recovery** (heavy action, owner/admin only, requires step-up): for an
  owner/admin locked out of their email. Jafar verifies identity manually outside the app (call,
  video, etc.) and writes a short evidence note — no automated verification code in this build.
  Shows old email -> new email, blocks if the new email is already used anywhere on the platform,
  revokes sessions, emails both old (security notice) and new (confirmation) address via the
  existing Brevo integration, never touches the password. No team-invite-link revocation step (none
  exists yet for team members, unlike onboarding setup links — confirmed with Jafar, intentionally
  skipped).
- **Zero-administrator organizations** (nobody is owner/admin at all): explicitly out of scope.
  Existing "Recovery is not built yet" copy stays; this is a future, separate decision.
- Both actions are external-call operations (Supabase Auth admin API + Brevo) — durable via the
  existing `platform_operation_attempts` / `recordOperationOutcome` pattern, so a GoTrue or Brevo
  failure surfaces on Operations and the organization's "Needs attention" card (6G) instead of
  silently failing. This also completes the `setup_or_recovery_failed` attention reason wired up in
  6F's `owner_organization_directory` (see that migration's comment — it was left dormant pending
  this part).

## Dependencies

6G (unified history, Needs-attention card), existing step-up pattern (`OwnerReconfirmDialog`,
`consumeOwnerStepUp`), existing durable-operations pattern (`recordOperationOutcome`,
`enqueueEmailDelivery`), existing contractor team-permission schema (`role_permissions`,
`organization_member_permission_overrides`, already built for the contractor side, unused by Jafar
until now).

## Implementation sequence

1. **Migration** (imperative, remote via Supabase MCP `apply_migration`):
   - `public.owner_email_is_available(candidate_email text) returns boolean` — security definer,
     `select not exists (select 1 from auth.users where lower(email) = lower(candidate_email))`,
     service_role only.
   - `public.apply_organization_member_profile_correction(target_organization_id uuid,
     target_user_id uuid, new_full_name text, email_changed boolean, old_email text, new_email text,
     private_reason text, actor_owner_email text, occurred_at timestamptz default now()) returns jsonb`
     — security definer. Validates membership belongs to the org; if `email_changed`, deletes
     `auth.sessions` rows for that user (revokes sessions) and refuses if the member's role is
     `owner`/`admin`. Updates `profiles.full_name` when provided and different. Inserts one
     `access_audit_events` row (`event_type = 'organization_member.profile_corrected'`,
     `target_type = 'organization_member'`, `target_key = target_user_id`, before/after state
     including name and, if changed, redacted-safe email diff). Returns a command summary.
   - `public.apply_organization_administrator_email_recovery(target_organization_id uuid,
     target_user_id uuid, old_email text, new_email text, evidence_summary text, private_reason text,
     actor_owner_email text, occurred_at timestamptz default now()) returns jsonb` — security
     definer. Validates membership role is `owner`/`admin`. Deletes `auth.sessions` rows for the
     user. Inserts one `access_audit_events` row
     (`event_type = 'organization_member.administrator_email_recovered'`, after_state includes
     `evidence_summary` and reason). Returns a command summary.
   - Both revoke execute from `public`/`anon`/`authenticated`, grant to `service_role` only, matching
     every existing owner RPC.
   - `auth.users.email` itself is changed via the Supabase Auth admin API in TypeScript (GoTrue,
     not raw SQL) before either RPC runs — see step 3. RPCs receive old/new email as already-decided
     values purely for the audit trail and session revocation.
2. Regenerate `database.types.ts` against remote; run `get_advisors`.
3. New `src/lib/server/jafar/team-notifications.ts`: `sendAdministratorEmailRecoveryNotices(client,
   { organizationId, userId, oldEmail, newEmail, businessName })` — two hardcoded (non-editable,
   this is an internal security notice, not an onboarding template) transactional emails via
   `enqueueEmailDelivery`, distinct idempotency keys per address.
4. New `src/lib/server/validation/team.schema.ts`: `teamProfileCorrectionSchema` (full_name
   optional 1-160, email optional, reason 1-1000, idempotency_key 8-200, refine at least one of
   full_name/email present) and `administratorEmailRecoverySchema` (new_email required,
   evidence_summary 1-1000, reason 1-1000, idempotency_key 8-200).
5. Extend `event-types.ts` `OPERATION_TYPES` with `organization_member_profile_correction` and
   `organization_administrator_email_recovery`.
6. Rewrite `team/+server.ts` GET: make the per-member `getUserById` call resilient (a single
   user's admin-API failure degrades that row to `email: null`, not a 500 for the whole list —
   this is the Riverside Legacy Demo fix). Add a parallel `organization_member_permission_overrides`
   query, grouped by `user_id`, included per member in the response.
7. New `team/[userId]/+server.ts` PATCH: profile correction. Loads current email (admin API) and
   name; if email present, blocks when role is owner/admin (409, points to recovery); calls GoTrue
   admin update (wrapped with `recordOperationOutcome` on failure/success,
   `operation_type = 'organization_member_profile_correction'`, target `{organization, organizationId}`);
   then calls the RPC; returns updated member row.
8. New `team/[userId]/administrator-recovery/+server.ts` POST: step-up required
   (`consumeOwnerStepUp`, 403 `step_up_required` like `legacy-review`). Loads membership, 409 if not
   owner/admin. Calls `owner_email_is_available`; 409 if taken. Calls GoTrue admin update (same
   `recordOperationOutcome` wrapping, `operation_type = 'organization_administrator_email_recovery'`);
   then the RPC; then `sendAdministratorEmailRecoveryNotices`. Returns updated member row.
9. UI (`organizations/[organizationId]/+page.svelte`, Team access section): per-row "Fix profile"
   action (any member) opens a small form (name, email-if-eligible, reason). Owner/admin rows get a
   second "Recover access" action reusing the `OwnerReconfirmDialog` step-up flow, then a form
   (new email, evidence note, reason). Show each member's override exceptions inline (small badge
   list, friendly label per `permission_key`, fallback to title-cased key). Invalidate `teamQuery`
   (and `historyQuery`, since these write to `access_audit_events`) after either action succeeds.
10. `.spec.ts` for both new routes plus the extended `team.spec.ts` (resilience + overrides).
11. `svelte-check`, full `vitest`, `get_advisors`, then browser-verify live: fix a name, fix a
    non-admin email (confirm forced logout empties their session), recover an admin email on a real
    organization, confirm Riverside Legacy Demo's Team card now loads.

## Acceptance checks

- [x] Riverside Legacy Demo's Team access card loads (no more 500); a member whose admin-API lookup
      fails shows a degraded email instead of breaking the whole list.
- [x] Each member row shows role plus any permission overrides, with a friendly label.
- [x] Profile correction: name-only works for any role; email works only for
      office/sales/field/finance and is blocked with a clear message for owner/admin; changing email
      revokes that member's sessions; one `access_audit_events` row is written; the affected member
      (not the org owner) is the notice target. (Name-only branch browser-verified; the non-admin
      email branch is unit-tested only -- see the deferral above.)
- [x] Administrator recovery: blocked without step-up (403 `step_up_required`); blocked if the new
      email exists anywhere on the platform; blocked if the target isn't owner/admin; on success,
      sessions are revoked, one audit row exists with the evidence note, and both old and new
      addresses receive an email. Browser-verified end to end on Jafar LTD (login with new email
      confirmed).
- [x] A real (not simulated) GoTrue failure produced a `platform_operation_attempts` row and flagged
      the organization's Needs-attention state (`setup_or_recovery_failed`), confirmed by direct
      query against `owner_organization_directory`.
- [x] Zero-administrator organizations are untouched — no code path in this part touches that case.
- [x] `svelte-check` 0 errors, full `vitest` 380/380, `get_advisors` clean (only pre-existing
      informational lints).
- [x] Jafar confirmed administrator recovery live on a real organization (Jafar LTD). Non-admin
      profile-correction browser verification deferred (see `Memory/deferred/INDEX.md`).

## Source pointers

- `docs/jafar-completion-contract.md`, heading `Team support and owner security`.
- `docs/jafar-organization-management-mission.md`, headings `Team access and support recovery`,
  `High-impact action security`, `Organization-detail structure`.
- `src/lib/server/auth/owner.ts` (`consumeOwnerStepUp`, `signOwnerStepUp`).
- `src/routes/api/jafar/organizations/[organizationId]/legacy-review/+server.ts` (step-up 403
  pattern to mirror).
- `src/lib/server/events/outbox.ts` (`recordOperationOutcome`), `dispatcher.ts`
  (`enqueueEmailDelivery`), `event-types.ts` (`OPERATION_TYPES`, `TargetKind`).
- `src/lib/server/access/contractor.ts`, `effective.ts` (existing `role_permissions` /
  `organization_member_permission_overrides` model to read, not change).
- `supabase/migrations/20260814130000_owner_organization_directory.sql` (comment confirming
  `setup_or_recovery_failed` was left dormant for this part).
- `supabase/migrations/20260813210000_organization_commercial_control_payments.sql` (exact
  `access_audit_events` insert shape to mirror).
- `Memory/campaigns/jafar-panel/parts/6g-unified-history-and-part-6-verification.md` (records the
  pre-existing team-endpoint 500 this part fixes).

## Non-discoverable risks

- `access_audit_events` has no `idempotency_key` column (unlike `organization_commercial_events`) —
  dedup for the risky external step lives in `platform_operation_attempts` via
  `recordOperationOutcome`'s existing lookup-before-insert pattern, not a DB constraint on the audit
  table. Do not add one; that table is shared and general-purpose by design (matches 6G's note about
  `platform_owner_audit_events`).
- Deleting `auth.sessions` rows revokes refresh capability but cannot invalidate an already-issued
  short-lived access token before it expires — this is inherent to JWTs, already called out as a
  known Supabase boundary, not a gap to solve here.
- `auth.users.email` must change through the Supabase Auth admin API (GoTrue), never a raw SQL
  `update auth.users`, so identity/confirmation state stays consistent. The two new RPCs never touch
  `auth.users` themselves.
- `organization_member_permission_overrides` and `role_permissions` are the contractor side's
  existing, already-shipped permission system (no Svelte UI built for it yet on that side) — Part 7
  only reads it for Jafar's display; do not add write endpoints for it here, that belongs to
  whichever part builds the contractor-facing team settings page.
- Preserve unrelated dirty work already in the tree (see `NOW.md` "Protected work").

## Closed

Complete. `svelte-check` 0 errors, full `vitest` 380/380, `get_advisors` clean (only pre-existing
informational lints). Migration applied to remote, `database.types.ts` regenerated.

Browser-verified live by Jafar:
- Riverside Legacy Demo's Team access card loads (200, not 500); name-only profile correction
  round-tripped end to end (dialog -> API -> RPC -> `access_audit_events` -> unified History).
- A third instance of the same "broken legacy auth record" bug class was found and fixed live
  during this closure: `administrator-recovery/+server.ts` also called `getUserById` unguarded and
  500'd on Riverside's member. Fixed with the same resilience pattern used in the other two spots,
  except recovery must still be able to *proceed* with an unknown old email (unlike profile
  correction, which blocks) -- see `src/routes/api/jafar/organizations/[organizationId]/team/
  [userId]/administrator-recovery/+server.ts`. Also fixed `team-notifications.ts` to always send the
  new-address confirmation even when the old address is unknown, only skipping the old-address
  warning (previously both were silently skipped together). Two new regression tests
  (`administrator-recovery.spec.ts`, `team-notifications.spec.ts`).
- Riverside's real GoTrue failure (the same broken record, at the update step this time) confirmed
  the durable-failure path works end to end on a real failure, not a simulated one:
  `platform_operation_attempts` recorded it (`status: retrying`, `last_error: "Database error
  loading user"`), and `owner_organization_directory` correctly flagged the org with
  `setup_or_recovery_failed` -- confirmed by direct query, matching the UI's attention-badge wiring
  in `organizations/+page.svelte`.
- Administrator recovery succeeded live on Jafar LTD: email changed, confirmation email received,
  Jafar logged in with the new email and his existing (unchanged) password.

Deferred, not blocking closure: the non-admin email-correction branch was never browser-verified --
no organization on the platform currently has a non-owner/non-admin member to test with. Jafar chose
to close Part 7 without creating throwaway test data for it. See
`Memory/deferred/INDEX.md` heading "Non-admin email-correction browser verification (Part 7)".
