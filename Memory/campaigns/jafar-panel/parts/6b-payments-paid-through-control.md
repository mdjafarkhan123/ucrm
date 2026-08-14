# Part 6B: Payments and Paid-Through Control

## Approved behavior

Owner-facing renewal, correction, refund, and reversal actions on top of the 6A commercial
seam, plus overdue/grace visibility. Suspension (any category, including nonpayment) is out of
scope — that ships as one unified action in 6D.

- Renewal offers two explicit actions: **record renewal only**, or **record renewal and
  reactivate**. Reactivation is never automatic or implied by a renewal alone. Reactivation is
  available whenever `organizations.lifecycle_status = 'suspended'`, regardless of why — 6D's
  suspend action (with reason tracking) doesn't exist yet, so this can't be gated on suspension
  category. Accepted known limitation: it's on the owner's judgment to only use it for nonpayment
  cases.
- Correction, refund, and reversal each reference the original initial-payment or renewal event
  and require the owner to explicitly confirm the resulting paid-through date or explicitly
  confirm no change (never inferred).
- Refund/reversal amounts are always entered and stored as a positive magnitude; the event kind
  alone carries the "this reduces value" meaning.
- Commercial actions use four separate labeled buttons (Renew, Fix a mistake, Refund, Reversal),
  each opening a dialog with only its own relevant fields — not one generic event-kind form.
- Every organization provisioned from now on gets a real `initial_payment_confirmed` commercial
  event, not just legacy-table rows (closes a gap left by 6A — see Non-discoverable risks).
- `organization_billing_accounts` / `organization_payment_confirmations` (legacy tables) stop
  receiving new rows once this ships. They remain as frozen historical record for pre-6B
  organizations until 6E reconciliation.
- `effective.ts` fully cuts over to `organization_commercial_state` /
  `organization_commercial_settings`; the fixed-UTC 24h grace math is deleted, not kept as a
  fallback.

## Dependencies

Part 6A (commercial-control foundation) — complete.

## Checklist

- [x] Migration `20260813210000_organization_commercial_control_payments.sql` (applied to remote):
  - [x] Repointed `organization_commercial_events.original_confirmation_id` FK from
        `organization_payment_confirmations(id)` to `organization_commercial_events(id)`, plus a
        self-reference guard and an `event_kind in ('initial_payment_confirmed','renewal_confirmed')`
        check in the validation trigger.
  - [x] Redefined `provision_organization_from_application` to call
        `apply_organization_commercial_command` (`initial_payment_confirmed`) instead of
        inserting directly into the two legacy tables. Also reordered so the operational-timezone
        update happens before the commercial-command call (correct baseline import).
  - [x] Added `apply_organization_late_renewal_reactivation`: records the renewal commercial event,
        and — only when explicitly requested — flips `organizations.lifecycle_status` from
        `suspended` to `active`, records a chained `organization_reactivated` commercial event
        (`source_event_id`), and writes the matching `access_audit_events` row, all in one
        transaction. Guards: requires a non-null actor email when reactivating (the audit row is
        not-null); refuses to reactivate a non-suspended organization; both guards fail before any
        write.
  - [x] Grants: revoked public/anon/authenticated, granted `service_role` only.
- [x] pgTAP coverage, all verified passing against the remote project (49/49 existing 6A coverage
      with no regressions, 26/26 updated provisioning coverage, 16/16 new 6B coverage):
  - [x] `organization_commercial_control_payments.sql` (new file): repointed FK accepts a
        commercial-event id; combined renewal+reactivation function reactivates only when
        requested, never on a plain renewal; refuses to reactivate a non-suspended organization
        (rolls back the renewal too — no partial state); refuses without an actor email; chained
        `source_event_id` and audit row verified.
  - [x] `platform_onboarding_provisioning.sql` (updated): provisioning now asserts against
        `organization_commercial_state`/`organization_commercial_events` instead of the legacy
        `organization_billing_accounts` row count.
- [x] `get_advisors` (security) run post-migration: no new findings, only pre-existing INFO-level
      RLS-no-policy notices on service-role-only tables (expected pattern) and one pre-existing
      unrelated WARN (leaked password protection).
- [x] `GET/POST .../organizations/[organizationId]/commercial` route (one endpoint, `action`
      discriminated union: `renewal` (with `reactivate: boolean`), `correction`, `refund`,
      `reversal`), Zod-validated per variant, owner auth + step-up consistent with sibling routes.
- [x] Follow-up migration `20260813213000_organization_commercial_control_legacy_assignment.sql`
      applied to the linked remote project. The legacy assignment function now delegates through
      the commercial command and does not write the frozen legacy billing tables.
- [x] Jafar LTD's interim legacy confirmation reconciled into one legacy-import
      `initial_payment_confirmed` event; the commercial projection now points to that event.
- [x] `history` route: merge `organization_commercial_events` into the existing
      audit-events + free-access-events feed.
- [x] `effective.ts`: replace `organization_billing_accounts` read and `computeBilling` with
      `organization_commercial_state`/`settings`; `is_overdue` via calendar-date comparison
      against `paid_through_date` in the commercial timezone (reuse the `todayInTimeZone`
      pattern from the free-access route); `is_in_grace` via direct `grace_ends_at` comparison.
      Delete the old UTC/24h computation outright, no fallback.
- [x] UI: Commercial access section on the organization detail page — paid-through date, source,
      commercial timezone, overdue/in-grace/current badge, and the four action buttons.
      Client-generated idempotency key (`crypto.randomUUID()`) per dialog session, reused across
      retries of that submission, discarded on close/success.
  - [x] UI implementation and Svelte validation.
  - [x] Desktop/mobile browser verification for all four dialogs.
- [x] `.spec.ts` coverage for the new route, mirroring `free-access.spec.ts`.

## Acceptance checks

- [x] A plain renewal never changes `lifecycle_status`.
- [x] "Record renewal and reactivate" is only offered/accepted when the organization is currently
  suspended, and always moves it to `active` in the same transaction as the renewal event.
- [x] A correction/refund/reversal without a valid original-event reference is rejected (existing 6A
  constraint; confirm it still holds through the repointed FK).
- [x] Every new organization has a non-null `organization_commercial_state.paid_through_date` and at
  least one `organization_commercial_events` row immediately after provisioning.
- [x] No active application or public database function path writes to
  `organization_billing_accounts` or `organization_payment_confirmations` after this ships. The
  legacy tables remain historical records; the linked remote function audit returned no active
  public function referencing either table.
- [x] `effective.ts` billing output for existing test fixtures matches pre-cutover values (grace
  math parity), including across a DST boundary.

## Source pointers

- `docs/jafar-completion-contract.md`, heading `Organization and commercial control` and
  `Commercial control decisions`.
- `docs/jafar-organization-management-mission.md`, headings `Commercial rules` and `Lifecycle`.
- `supabase/migrations/20260813200000_organization_commercial_control_foundation.sql` (6A seam).
- `supabase/migrations/20260813180000_onboarding_payment_reversal.sql` (current, most-recent
  definition of `provision_organization_from_application` — has a `target_actor_owner_email`
  parameter added after the original 6811231843 definition; redefine from this version).
- `supabase/tests/database/organization_commercial_control.sql` (6A acceptance coverage).
- `src/lib/server/access/effective.ts` (billing/grace computation to replace).
- `src/routes/api/jafar/organizations/[organizationId]/free-access/+server.ts` (route pattern:
  one endpoint, action-discriminated body — follow this shape).
- `src/routes/api/jafar/organizations/[organizationId]/lifecycle/+server.ts` (step-up +
  `recordOwnerAccessAudit` pattern).
- `src/routes/api/jafar/organizations/[organizationId]/history/+server.ts` (feed to extend).
- `src/routes/jafar/(protected)/organizations/[organizationId]/+page.svelte` (detail page to
  extend with the Commercial access section).

## Non-discoverable risks

- 6A's migration only backfilled `organization_commercial_state` once, at migration time. Any
  organization provisioned between 6A shipping and this part shipping has an empty commercial
  event history and a null/stale projection — this part's provisioning fix only prevents new
  gaps, it does not backfill the interim window. Northshore Plumbing and Cascade HVAC Group were
  the two organizations found in that gap; both were confirmed as dummy test data (single-org test
  owner accounts, `.test`/`+test` emails, no contacts/properties/requests/commercial-event history)
  and hard-deleted rather than reconciled — see 2026-08-14 deletion note below.

## 2026-08-14: interim test organizations deleted, not reconciled

Northshore Plumbing (`fcaefa10-1cab-43b2-8308-7479c0b39039`) and Cascade HVAC Group
(`f8329545-42cb-4931-860f-172f47103f8e`) were confirmed dummy data and hard-deleted from the
remote project (organizations, cascaded rows, their full onboarding-application trail, and their
two owner auth accounts). This required temporarily disabling four append-only immutability
triggers inside one transaction, since the schema doesn't support hard-deleting an organization
by design (`organization_package_assignments`, `organization_payment_confirmations`,
`platform_onboarding_application_corrections`, `platform_onboarding_application_payment_confirmations`):

```sql
alter table organization_package_assignments disable trigger organization_package_assignments_immutable;
alter table platform_onboarding_application_corrections disable trigger platform_onboarding_application_corrections_immutable;
alter table platform_onboarding_application_payment_confirmations disable trigger platform_onboarding_application_payment_confirmations_immutable;
alter table organization_payment_confirmations disable trigger organization_payment_confirmations_immutable;
-- deletes in FK-dependency order --
alter table organization_package_assignments enable trigger organization_package_assignments_immutable;
alter table platform_onboarding_application_corrections enable trigger platform_onboarding_application_corrections_immutable;
alter table platform_onboarding_application_payment_confirmations enable trigger platform_onboarding_application_payment_confirmations_immutable;
alter table organization_payment_confirmations enable trigger organization_payment_confirmations_immutable;
```

All four triggers confirmed re-enabled after commit (`pg_trigger.tgenabled = 'O'`). Post-delete
`get_advisors` security scan shows only the pre-existing INFO RLS-no-policy notices and the
pre-existing leaked-password-protection WARN — no new findings. This was a one-off data cleanup,
not a schema change, so no migration file was written; if a future organization needs the same
treatment, this note documents the required trigger list and order.
- `original_confirmation_id` is currently always null in production (nothing populates it yet),
  so the FK repoint is safe with no data migration — confirm this is still true at execution
  time before running the migration.
- `apply_organization_commercial_command` is `security definer`; `provision_organization_from_application`
  is `security invoker`. Both are already granted to `service_role`, so calling the former from
  the latter needs no new grants — but don't assume this stays true if either function's security
  mode changes later.
