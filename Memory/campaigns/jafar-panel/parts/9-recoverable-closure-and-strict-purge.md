# Part 9: Recoverable Closure and Strict Purge

## Approved behavior

- Closure starts a recoverable 30-day countdown and immediately blocks contractor access and new
  outbound work. Starting requires an impact preview, private reason, typed organization name,
  explicit confirmation, and password step-up (same pattern as suspend).
- During the window, only Jafar may restore, after a safe evidence note and step-up. Restoring
  returns the organization to its prior lifecycle status (`active` or `suspended` -- captured at
  closure start, since suspension state must not be silently lost).
- Contractor-safe notices send automatically at closure start, 14 days remaining, 3 days remaining,
  and completion. Each is editable (reuses the existing template draft/publish system) but sends
  exactly once per closure, even if the daily job runs more than once on the due day.
- Settings > Cleanup lists every organization from the start of its closure window with remaining
  recovery time. Jafar may permanently delete one early from that queue only: explicit irreversible
  confirmation, typed organization name, password step-up. This bypasses the remaining recovery
  period and cannot be restored. This screen does not exist yet and is new in this part.
- At day 30 (or on early manual delete), permanently delete all live organization CRM data, Auth
  users, files, queued work, and connected provider resources. No organization or CRM record
  remains. Provider resources (Twilio/Brevo/R2/Stripe) are not built yet in this codebase, so that
  purge step records `not_applicable` rather than faking a mutation -- same dependency-linked
  convention already used for Part 10.
- Retain only a non-personal technical deletion receipt: random operation ID, timestamps, and
  per-component success/failure. No organization name, personal detail, or CRM content.
- Deletion is resumable and idempotent. Partial failure blocks completion, creates an urgent
  Operations alert, and exposes safe retry -- same `platform_operation_attempts` /
  `recordOperationOutcome` pattern already used for provisioning and setup-email delivery.
- The 14-day/3-day reminders and the day-30 purge trigger run on a real daily `pg_cron` job (new
  extension for this project -- confirmed with Jafar in-session), not on-demand page-load checks.

## Dependencies

Part 6G (unified history), Part 8 (step-up/session hardening) -- both complete. Builds on the
`organization_commercial_events` / `organization_safe_events` shared stream from 6A, the
`platform_outbox_deliveries` / `recordOperationOutcome` durable-delivery seam from Part 2/4, and the
message-template draft/publish system from Part 4.

## Implementation sequence

1. **Schema audit before writing the purge RPC.** Confirmed during planning: most
   organization-scoped tables cascade-delete when `organizations` is deleted, but three do not --
   `organization_package_assignments`, `organization_free_access_events`, and
   `platform_onboarding_application_provisions` (nullable `organization_id`). Re-verify this list is
   complete (grep every `references public.organizations(id)` across migrations) before relying on
   cascade for anything.
2. Migration: `organizations.lifecycle_status` check gains `pending_closure`, `closed`.
   `organization_commercial_events.event_kind` gains `organization_closure_started`,
   `organization_closure_restored`, `organization_closure_completed`. `organization_safe_events`
   gains matching safe kinds. `actor_kind` on commercial events gains `platform_system` for the
   cron-triggered completion event (the audit trail must not claim a human acted).
3. Migration: `organization_closure_records` (one open row per org: reason, `prior_lifecycle_status`,
   `started_at`, `deadline_at`, status `pending_closure`/`restored`/`purged`, restoration evidence,
   idempotency key) and `organization_closure_notices` (unique per closure record + notice kind, so
   the daily job is idempotent).
4. Migration: standalone `organization_deletion_receipts` table -- no FK to `organizations`, no
   name, no personal data. Operation ID, `initiated_at`, `completed_at`, `trigger`
   (`scheduled`/`early_manual`), `component_results jsonb`, `status`.
5. Migration: `apply_organization_closure_start` and `apply_organization_closure_restore` RPCs,
   mirroring the 6D/6E pattern exactly -- per-org row lock, idempotency dedup, atomic owner+safe
   event writes.
6. Migration: `apply_organization_purge` RPC. Explicit deletion order handling the three non-cascade
   tables from step 1 (delete or null them before deleting the `organizations` row), writes the
   `organization_deletion_receipts` row, and is safely re-runnable if it fails partway (check receipt
   status before re-doing completed components). Auth user deletion happens via the service-role
   Auth admin API as an explicit step in the same operation, tracked through
   `platform_operation_attempts` like existing provisioning/setup-email work, so a partial failure
   surfaces in Operations with idempotent retry.
7. Migration: `pg_cron` job, once daily -- finds due 14-day/3-day/completion notices via
   `organization_closure_notices` and enqueues them through the existing outbox; finds closure
   records past `deadline_at` and calls `apply_organization_purge`.
8. pgTAP: idempotency and concurrent serialization on both closure RPCs; restore-then-reclose;
   purge correctness against the three non-cascade tables; receipt contains zero identifying fields;
   notices send exactly once even if the cron function runs twice on the same day.
9. New `owner.schema.ts` schemas (closure start/restore, mirroring `organizationLifecycleSchema`);
   new API routes under `organizations/[organizationId]/closure/` (start, restore) and a new
   `settings/cleanup/` route (list + early-delete); extend `event-types.ts` `OPERATION_TYPES` with
   the purge operation type. Route-level vitest for each.
10. UI: Overview section gets "Close organization" (impact preview, typed name, reason, step-up) and,
    while `pending_closure`, "Restore". New `Settings > Cleanup` page listing closing organizations
    with remaining time and early-delete action.
11. Four new `platform_message_templates.template_key` entries (closure start / 14-day / 3-day /
    completion notices) through the existing template system -- no new template infrastructure.
12. Regenerate `database.types.ts`, run `get_advisors`, full `svelte-check` + `vitest` + pgTAP sweep,
    then browser-verify with Jafar on a disposable test organization: closure start -> restore, and
    closure start -> early delete. Day-30 automatic execution cannot be watched live in one sitting --
    verify by manually backdating a test closure record's `deadline_at` and confirming the cron
    function purges it correctly, rather than waiting 30 real days.

## Acceptance checks

- [ ] Closure start requires reason, typed name, confirmation, and step-up; blocks contractor access
      immediately; is idempotent per idempotency key.
- [ ] Restore requires evidence note and step-up; returns the organization to its exact prior
      lifecycle status (active or suspended); only possible before purge completes.
- [ ] Start/14-day/3-day/completion notices each send exactly once per closure, even under a
      double-run of the daily job.
- [ ] Settings > Cleanup lists every closing organization with correct remaining time; early delete
      requires typed name and step-up and is irreversible.
- [ ] Purge removes all rows across every organization-scoped table (including the three non-cascade
      tables) and the Auth user(s); is safely re-runnable after a simulated partial failure without
      duplicating work or corrupting the receipt.
- [ ] The deletion receipt contains no organization name, slug, personal data, or CRM content --
      only operation ID, timestamps, and component outcomes.
- [ ] Provider-resource purge step records `not_applicable` honestly rather than a fake success.
- [ ] Concurrent closure/restore/purge commands for one organization serialize safely (per-org row
      lock, no lost update).
- [ ] RLS, grants, and independent owner authorization prevent contractor or anonymous access to any
      new table, function, or route.
- [ ] Existing 6A-6G/7/8 pgTAP and route suites remain green.

## Source pointers

- `docs/jafar-completion-contract.md`, heading `Organization closure`.
- `docs/jafar-organization-management-mission.md`, headings `Lifecycle` -> `Later closure`,
  `History, transparency, and recovery` -> `Retention`, `Operational recovery`.
- `supabase/migrations/20260813200000_organization_commercial_control_foundation.sql` (event/safe
  stream to extend).
- `supabase/migrations/20260814034522_organization_free_access_scheduling_and_lifecycle_control.sql`
  (`apply_organization_lifecycle_change` -- RPC pattern to mirror).
- `supabase/migrations/20260810054722_organization_versioned_package_assignments.sql`,
  `20260810064732_organization_free_access_history.sql`,
  `20260811231843_platform_onboarding_provisioning.sql` (the three confirmed non-cascade
  `organization_id` foreign keys).
- `src/lib/server/events/dispatcher.ts`, `src/lib/server/events/outbox.ts` (durable email +
  `recordOperationOutcome` pattern to reuse for notices and purge attempts).
- `src/lib/server/events/event-types.ts` (`OPERATION_TYPES`, `TargetKind`).
- `src/lib/server/validation/owner.schema.ts` (`organizationLifecycleSchema` pattern to mirror).
- `src/routes/api/jafar/organizations/[organizationId]/lifecycle/+server.ts` (step-up pattern).
- `src/routes/jafar/(protected)/settings/+page.svelte` (no Cleanup section exists yet -- new).
- `src/lib/server/access/effective.ts` (`lifecycle_status` already gates contractor access; confirm
  `pending_closure`/`closed` are treated as not-active without a separate code change).

## Non-discoverable risks

- Three `organization_id` foreign keys are NOT `on delete cascade`
  (`organization_package_assignments`, `organization_free_access_events`,
  `platform_onboarding_application_provisions`). A purge RPC that just does
  `delete from organizations where id = ...` will fail on the first two and silently leave the third
  dangling. Must handle explicitly.
- **[Resolved in step 6, but the risk itself was bigger than this packet originally described --
  keeping this note for whoever writes the pgTAP suite or touches these tables again.]** FK cascade
  direction is not the only thing that can block a purge. Five organization-scoped tables carry an
  unconditional "history is append-only" `BEFORE UPDATE OR DELETE` trigger:
  `organization_package_assignments`, `organization_free_access_events` (the two non-cascade ones
  above), plus `organization_payment_confirmations`, `organization_commercial_events`,
  `organization_safe_events` (all three of which DO cascade from `organizations` by FK, but the
  trigger still fires during the cascade-triggered delete and blocks it just the same). Before
  trusting "it cascades" as sufficient for any future purge-adjacent table, grep
  `before (update or delete|delete) on public.organization_` across all migrations -- FK cascade
  direction and trigger-level mutation protection are two independent things that both have to allow
  the delete.
- `organization_safe_events.commercial_event_id` uniquely references
  `organization_commercial_events(id)` with default RESTRICT, but both tables cascade from
  `organizations`. This resolves correctly only because Postgres checks FK constraints after all
  cascaded deletes from one statement complete -- do not split the purge into separate statements
  that could observe an intermediate state.
- `platform_outbox_deliveries`/`recordOperationOutcome` calls always need a real client -- the
  `pg_cron` job runs as `postgres`/`service_role` inside the database with no HTTP context, so
  sending the timed notices needs the RPC to either call `net.http_post` to an internal endpoint or
  do the outbox insert directly in SQL and have a separate lightweight process actually send it (the
  existing `dispatchOutboxDelivery` is a TypeScript function, not SQL) -- decide the exact
  cron-to-send bridge during step 7, it is not yet solved by any existing pattern in this codebase.
- Remote Supabase MCP tools and `npx supabase gen types` are the only available path (no local
  Docker/CLI). `mcp__supabase__execute_sql` only surfaces the last statement's result.
- Preserve all unrelated dirty work already in the tree (per `NOW.md` Protected work).

## Current checkpoint

Steps 1-6 done and verified; step 7 (pg_cron job) not started.

- Migrations applied (remote, in order): `organization_closure_schema_foundation` (lifecycle_status +
  event_kind + safe_kind + actor_kind='system' + reason_check), `organization_closure_and_deletion_tables`
  (`organization_deletion_receipts`, `organization_closure_records`, `organization_closure_notices`,
  RLS/grants), `organization_closure_start_and_restore` (both RPCs), a same-session corrective
  migration `fix_closure_restore_field_ambiguity`, `organization_purge` (the purge RPC + bypass on the
  two originally-known non-cascade tables), and a same-session corrective migration
  `fix_organization_purge_missing_immutable_bypasses` (see below).
- Real bug caught by an in-session smoke test before it ever reached pgTAP: the restore RPC's
  `UPDATE ... SET restoration_evidence_note = trim(restoration_evidence_note)` was ambiguous between
  the PL/pgSQL parameter and the identically-named table column (same class of bug as 6D's
  `fix_free_access_change_record_field_access`). Fixed by qualifying with the function name.
- Verified via rollback-wrapped `execute_sql` runs (not persisted): full closure-start -> restore
  round trip on a real demo organization, plus a dedicated fixture-based pass covering privileges,
  idempotency (both directions), 30-day window math, prior-status capture for both `active` and
  `suspended` starting states, and contractor-safe payload redaction. All passed.
- **A second, bigger real bug caught by this session's smoke test on `apply_organization_purge`,
  before it ever reached pgTAP: the "three non-cascade FKs" framing in this packet's original risk
  audit was incomplete.** Three MORE organization-scoped tables that DO cascade from `organizations`
  by FK still carry an unconditional "history is append-only" `BEFORE UPDATE OR DELETE` trigger that
  blocks the cascade outright: `organization_payment_confirmations`, `organization_commercial_events`,
  `organization_safe_events`. A plain `delete from organizations` failed immediately on the first of
  these hit during cascade resolution (`organization_commercial_events`). Re-grepped every
  `before (update or delete|delete) on public.organization_` trigger across all migrations to confirm
  the full set is now exactly five (the two originally known plus these three) -- see
  `fix_organization_purge_missing_immutable_bypasses`. Jafar approved the fix approach up front
  (narrow transaction-local bypass flag, checked via `AskUserQuestion`, over disabling triggers
  table-wide) before any trigger was touched, per CLAUDE.md rule 13.
- **Fix, applied as its own migration (do not merge into `organization_purge` -- keep the audit trail
  of the correction):** all five trigger functions
  (`private.prevent_organization_package_assignment_mutation`,
  `private.prevent_organization_free_access_event_mutation`,
  `private.prevent_organization_payment_confirmation_mutation`,
  `private.prevent_organization_commercial_event_mutation`,
  `private.prevent_organization_safe_event_mutation`) now allow `DELETE` only when
  `current_setting('app.organization_purge_in_progress', true) = 'true'` -- a transaction-local flag
  (`set_config(..., true)`) that `apply_organization_purge` sets immediately before its destructive
  statements and that resets automatically at the end of that transaction (each `client.rpc(...)` call
  from the TS layer is its own implicit transaction, so the bypass never leaks to any other request).
  `UPDATE` stays unconditionally blocked for every caller, forever, including the purge RPC itself --
  only `apply_organization_purge` can ever remove rows from these five tables, and only by deleting
  the whole organization.
- `apply_organization_purge(target_organization_id, purge_trigger_kind, actor_owner_email default null)`
  is fully atomic (one PL/pgSQL transaction: locks `organizations` + the open `organization_closure_records`
  row, gathers `organization_members.user_id`s for the caller to delete from Auth afterward, bypass-deletes
  the two non-cascade tables, nulls `platform_onboarding_application_provisions.organization_id`, does one
  `delete from organizations` that cascades everything else including the five bypass-patched tables and
  `organization_closure_records`/`organization_closure_notices` themselves, then inserts the
  `organization_deletion_receipts` row with `component_results.auth_users = 'pending'` for the TS layer
  (step 9) to complete after it deletes the Auth users). A failed call rolls back completely and is
  safely retried by calling it again unchanged -- there is no internal partial state. If the organization
  row is already gone (already purged, or a bare retry of the Auth-deletion leg), it returns
  `{applied: false, reason: 'already_purged'}` instead of raising, since a receipt cannot be looked up
  again from an organization id by design (no identifying FK on that table). Grants/revokes mirror the
  6D/6E RPC pattern (`service_role` only).
- Deliberately **not** written by this RPC: no `organization_commercial_events`/`organization_safe_events`
  row for `organization_closure_completed`/`closure_completed`, even though the schema foundation
  migration added those enum values. Both tables cascade-delete in the same transaction as any insert
  into them here, so writing one would be immediately destroyed and provide zero durable value. If step 7
  (the cron job) wants a fleeting pre-purge audit trace of "closure completing" visible to other code for
  the moments before purge actually runs, that is a separate, earlier, already-committed transaction --
  step 7's decision, not step 6's.
- Verified via one rollback-wrapped `execute_sql` smoke test (fixtures + real RPC calls, not persisted --
  confirmed no rows survived after `rollback`): 21/21 checks passed, covering immutability still blocking
  DELETE/UPDATE before any purge runs, purge rejected with no open closure window, `early_manual` rejected
  without an actor email, full cascade deletion (package assignments, free access history, members,
  closure records, commercial events, safe events, payment confirmations), the onboarding-provisions row
  surviving with its `organization_id` nulled (not deleted), the receipt existing/completed/shaped
  correctly with no organization-identifying column, and a repeat call after success being a harmless
  idempotent no-op.
- No pgTAP file written yet for `apply_organization_purge` (the 6D-style checked-in `.sql` suite this
  packet's convention calls for) -- still owed, plus a rerun confirmation of the still-unexecuted
  `organization_closure_start_and_restore.sql` suite from steps 1-5 (see prior entry below on the
  `execute_sql` / pgTAP `plan()`/`finish()` limitation -- unchanged this session, same tool limitation
  applies to any new suite written the same way).
- Nothing yet built: pg_cron job (step 7), API routes/schemas (step 9), UI (step 10), message templates
  (step 11), or the final regression sweep (step 12).
- `svelte-check` 0 errors (2 pre-existing unrelated CSS warnings), full `vitest` 397/397, advisors clean
  (only the same pre-existing informational RLS-no-policy lints). `database.types.ts` regenerated via
  `mcp__supabase__generate_typescript_types` + `prettier --write` (the MCP tool's raw output is a JSON
  wrapper `{"types": "..."}`, not raw TypeScript -- parse and extract `.types` before writing the file,
  or Prettier will fail on the wrapper).

## Exact next action

Steps 1-11 are fully done, including step 8's pgTAP (see "Step 8 and 12 summary" below). Only the
live browser verification leg of step 12 remains -- Jafar chose to do that himself (asked via
`AskUserQuestion`: closure start -> restore, and closure start -> early delete via Settings >
Cleanup, on a disposable test organization; day-30 automatic purge was already verified for real in
step 7 by backdating a test closure record, so that does not need repeating). Once Jafar confirms
the UI paths work, Part 9 is complete -- close this part in `ROADMAP.md` and pick the next
dependency-ready part.

## Step 8 and 12 summary (this session)

Wrote and verified the still-owed step-8 pgTAP suites, both checked in under
`supabase/tests/database/`:

- `organization_closure_start_and_restore.sql` (already existed from an earlier session, never
  actually executed until now) -- 27/27 assertions pass.
- `organization_purge.sql` (new this session) -- 30 assertions covering privileges; rejection of an
  invalid trigger kind, a missing actor email on `early_manual`, and a purge with no open closure
  window; the five immutable-history tables still blocking direct UPDATE/DELETE outside a purge;
  full-cascade purge of every organization-scoped table (package assignments, free access history,
  payment confirmations, commercial events, safe events, memberships); the onboarding-provisions row
  surviving with `organization_id` nulled; the deletion receipt's shape (exactly six component keys,
  `auth_users: 'pending'`, `provider_resources: 'not_applicable'`, nothing organization-identifying);
  idempotent no-op retry after success; and a second `early_manual` purge on an organization with no
  onboarding provision correctly recording `onboarding_provision_unlinked: 'not_applicable'`.

**Two real bugs this suite caught before it ever ran clean, worth remembering for whoever writes the
next pgTAP suite against a shared remote database (no local Docker/CLI in this environment):**
1. `organization_free_access_events` fixture inserts need a `starts_at` column -- added in
   `20260814034522_organization_free_access_scheduling_and_lifecycle_control.sql`, after the table's
   original definition. Grepping only the `create table` statement misses columns added later by
   `alter table`; check the full migration history for a table before writing fixtures against it.
2. **`organization_deletion_receipts` has no organization-identifying FK by design (that's the whole
   point of the table), which means it is not scoped to one test run.** This is a live shared
   database, not a disposable local one -- real, intentionally-kept receipt rows already exist from
   step 7's live browser verification. A first draft of this suite asserted against
   `organization_deletion_receipts limit 1` / bare `count(*)`, which silently read an unrelated real
   receipt instead of the test's own row and produced misleading failures (e.g. `auth_users:
   'succeeded'` instead of the expected `'pending'`, because that real receipt actually had finished
   Auth cleanup). Fixed by capturing each purge call's full JSON result via `set_config` and scoping
   every later receipt assertion to `where operation_id = (that captured operation_id)`. Any future
   test against a table that is deliberately not organization-scoped needs the same care.

Verification method used for both suites (the same `execute_sql` / pgTAP `plan()`/`finish()`
limitation noted throughout this part still applies -- only the last statement's result is visible):
built a throwaway aggregated copy of each `.sql` file (`insert into` a temp results table after every
`is()`/`ok()`/`throws_ok()` call instead of relying on each one being the visible "last statement",
then `string_agg(...)` all lines as the true final statement), ran that copy directly via
`mcp__supabase__execute_sql` inside the file's own `begin; ... rollback;`, confirmed the full
line-by-line TAP report, then discarded the throwaway copy -- the checked-in `.sql` files themselves
were never modified for this trick.

Final regression sweep after both suites passed: `svelte-check` 0 errors (2 pre-existing unrelated
CSS warnings), full `vitest` 438/438, `get_advisors` re-checked (same pre-existing set, nothing new).

## Step 10 and 11 summary (this session)

Step 10 (UI): new `src/lib/components/jafar/ClosureActions.svelte` (mirrors `LifecycleActions.svelte`
-- "Close organization" dialog with impact-preview copy, private reason, typed-name confirmation,
step-up via `OwnerReconfirmDialog`; "Restore organization" dialog with evidence note + step-up;
countdown badge when `pending_closure`). Wired into the organization detail page's lifecycle card
(`organizations/[organizationId]/+page.svelte`) alongside `LifecycleActions` (suspend/reactivate
hidden while `pending_closure`/`closed`); header badge, lifecycle card, and "Next safe action" card
all extended to label/describe `pending_closure` ("Closing") and `closed` ("Closed") instead of
falling through to a raw or wrong status string. New `settings/cleanup/+page.svelte` page (queue
table, remaining-time badge, early-delete dialog with typed name + step-up), linked from a new
"Organization cleanup" section on the main Settings page.

Two small extensions beyond the packet's original step 9/10 wording, both needed for the UI to be
correct rather than scope creep: (1) `GET organizations/[organizationId]/commercial` now also
selects the org's open `organization_closure_records` row (`closure: {...} | null`) since that route
was already the lifecycle-adjacent query the detail page fetches -- avoided adding a new route just
for a deadline countdown; extended `commercial.spec.ts` accordingly (now 6 tests). (2) Fixed a latent
bug in `organizations/+page.svelte` (the directory list): its local `LifecycleStatus` type and
`lifecycleLabel`/`lifecycleTone` functions predated closure and had no case for `pending_closure`/
`closed`, so any closing org would have silently mislabeled as "Suspended" in the directory --
extended both functions.

Step 11 (message templates): `TEMPLATE_KEYS` and `TEMPLATE_PLACEHOLDERS` in
`message-templates.ts` gained the four closure keys (`organization_closure_started`,
`organization_closure_fourteen_day_reminder`, `organization_closure_three_day_reminder`,
`organization_closure_completed`); `closure_deadline_at` marked required on the two reminders
(matches what `organization-closure-cron.ts` actually merges), `business_name` optional on all four
(matches every other template's convention). Also updated the message-templates *UI* page's own
locally-duplicated `TemplateKey`/`TEMPLATE_LABELS`/`TEMPLATE_HAS_SUBJECT` (all four are subject-bearing
emails) -- easy to miss since that page keeps its own copy of the key list rather than importing it.

New migration `20260815133000_organization_closure_message_templates.sql`: widened the
`platform_message_templates_template_key_check` constraint to allow the four new keys, and --
unlike leaving them as empty drafts for Jafar to author -- seeded and **published** real starter
copy immediately (matching exactly how the original 4 templates were seeded on day one), since these
are contractor-facing emails for a feature that already works end-to-end and the cron's graceful
"template not published" skip was only ever meant as a transitional guard, not the intended steady
state. Applied directly via `mcp__supabase__apply_migration` and verified all 8 templates are
`published_version >= 1` with a subject.

`database.types.ts` regenerated and reformatted. `get_advisors` re-checked (same pre-existing
informational/warn set, nothing new). `svelte-check` 0 errors (same 2 pre-existing unrelated CSS
warnings), full `vitest` 438/438 (437 prior + 1 new closure-record case in `commercial.spec.ts`). No
UI-level automated tests exist in this codebase for `.svelte` files (verified by browser only, per
existing convention) -- the new components were checked with `mcp__svelte__svelte-autofixer`
(0 real issues; the one flagged "href without resolve()" on a template-literal link matches an
already-accepted pattern elsewhere in the same file) but not yet exercised in a live browser.

## Step 9 summary (this session)

`owner.schema.ts` gained three schemas: `organizationClosureStartSchema` (`reason`,
`typed_organization_name`, `idempotency_key`), `organizationClosureRestoreSchema`
(`restoration_evidence_note`, `idempotency_key` -- no typed name, per the approved behavior:
restore needs only evidence + step-up), `organizationEarlyPurgeSchema` (`organization_id`,
`typed_organization_name` -- no idempotency key, since `apply_organization_purge` takes none and
is naturally idempotent via its `already_purged` branch).

Three new routes, all mirroring the 6D/6E step-up/idempotency-key pattern:
- `POST organizations/[organizationId]/closure/start` -- fetches the organization first, rejects
  if `typed_organization_name` does not exactly match the real name (server-side check, not just
  client UX -- defense in depth for an irreversible-adjacent action), calls
  `apply_organization_closure_start`, and -- only when the RPC actually applied (not on an
  idempotent replay, which returns no `closure_record_id`) -- sends the `closure_started` notice
  synchronously via the newly-exported `sendClosureNotice` from `organization-closure-cron.ts`
  (best-effort, `.catch`-logged, same as the cron module treats every notice send).
- `POST organizations/[organizationId]/closure/restore` -- calls
  `apply_organization_closure_restore`, no typed-name check, no notice (restore was never one of
  the four approved notice kinds).
- `GET/POST settings/cleanup/+server.ts` (new, no dynamic segment -- one queue screen per the
  approved behavior) -- `GET` lists open `organization_closure_records` (`status = pending_closure`)
  ordered by nearest `deadline_at`, embedding `organizations(name, slug)` via the existing FK.
  `POST` does the early irreversible delete: typed-name check against the real organization name,
  step-up, then `apply_organization_purge` with `purge_trigger_kind: 'early_manual'`; returns 409
  if the RPC reports `already_purged`.

`organization-closure-cron.ts` changes to support the above: `NoticeKind` gained
`'closure_started'` (with its `organization_closure_started` template key, already anticipated in
the module's own top comment); `sendClosureNotice` and its `NoticeOutcome` type are now exported
instead of module-private. No behavior change to the daily sweep itself -- `closure_started` is
still never found "due" by it, exactly as before.

25 new route-level vitest tests across `closure-start.spec.ts`, `closure-restore.spec.ts`,
`cleanup.spec.ts` (session/validation/step-up boundaries, typed-name mismatch rejection, RPC
argument shape, notice-sent-only-on-first-apply, 409 conflict mapping). `svelte-check` 0 errors
(same 2 pre-existing unrelated CSS warnings), full `vitest` 437/437 (412 prior + 25 new). No
migration, no RLS change, no schema change this step.

## Step 7 summary (this session)

The daily `pg_cron` job is real, scheduled, and verified end-to-end against the live dev tunnel --
not just unit-tested. What shipped:

- **The cron-to-outbox bridge** (the open question from the prior session): `pg_cron` -> `pg_net`
  (`net.http_post`, fire-and-forget) -> a new secret-authorized internal route
  `POST /api/jafar/internal/closure-cron` -> `runOrganizationClosureCron` (plain TypeScript, full
  Auth-admin and outbox access). The target URL and the bearer secret both live in **Supabase
  Vault** (`closure_cron_target_url`, `closure_cron_secret`), read fresh by the schedule's command
  text on every firing -- migrations only create placeholder secret values (never real ones -- real
  values are set once directly against the live database, exactly like `.env` vs `.env.example`).
  Moving off the dev tunnel to a real deployment later is a one-value Vault update, no migration.
- New required env var `CLOSURE_CRON_SECRET` (added to `.env`, `.env.example`, `src/lib/server/env.ts`).
  Jafar: when you set up the Docker deployment, generate a new value for this and update the
  `closure_cron_secret` Vault secret to match -- don't reuse the dev one.
- `src/lib/server/jafar/organization-closure-cron.ts`: two independent passes. Pass 1 walks open
  `organization_closure_records` (`pending_closure`), sends the 14-day/3-day reminders when due
  (claimed via `organization_closure_notices`' unique index -- the actual race guard, not a
  pre-check -- so a genuine double-run of the job still can't double-send), and purges anything past
  `deadline_at`. Pass 2 walks `organization_deletion_receipts` with a non-null
  `pending_auth_user_ids` -- the durable anchor for finishing Auth-user deletion after a purge whose
  organization (and closure record) is already gone, so a crash between the SQL purge and the Auth
  cleanup is still resumable on the next run. "Not found" on `deleteUser` counts as success (already
  gone either way). Failures record through `platform_operation_attempts`
  (`operationType: 'organization_purge'`, added to `OPERATION_TYPES`) and `raiseOwnerAlert`
  (`organization_purge_failed`, added to `EMAIL_ALERT_KINDS`) -- same pattern as provisioning.
- Migration `organization_purge_pending_auth_users`: added `organization_deletion_receipts
  .pending_auth_user_ids uuid[]` (nulled once Auth cleanup succeeds -- transient operational
  anchor, not part of the receipt's permanent non-personal steady state, same justification as the
  existing `platform_onboarding_application_provisions.administrator_user_id` pattern) and updated
  `apply_organization_purge` to populate it from the same `member_user_ids` it already returns.
- The `closure_started` notice is deliberately **not** sent by this cron module -- it isn't
  date-driven, so it belongs in step 8's closure-start route, sent synchronously the moment closure
  begins. Only `fourteen_day_reminder` / `three_day_reminder` / `closure_completed` are ever found
  "due" by the daily sweep.
- Notice sending gracefully **skips and does not claim** (so a later run retries once the template
  exists) when: the notice was already claimed, no resolvable owner-member email exists, or --
  expected right now, since step 10's templates don't exist yet -- the template key isn't published.
  Verified live: triggered the sweep against a real backdated-window test org with no template
  published; got `noticesSkipped:1`, zero `organization_closure_notices` rows written, no crash.
- **Verified for real, not just mocked**: created a disposable Auth user + organization + closure
  window via the real `apply_organization_closure_start` RPC, backdated `deadline_at`, ran
  `net.http_post` directly (the exact call `pg_cron` makes) and confirmed `net._http_response` shows
  `200` with the real summary. Confirmed after: organization/closure-record/members rows gone, the
  Auth user actually deleted (`auth.admin.getUserById` -> not found), and the receipt shaped exactly
  as expected (`status: completed`, all components `succeeded`/`not_applicable`,
  `pending_auth_user_ids: null`). Separately verified the Pass-2 resume path for real: ran
  `apply_organization_purge` directly (leaving Auth cleanup undone), then called the route again --
  `authCleanupsCompleted:1`, and the leftover Auth user was actually deleted on that second call.
  All test rows/users cleaned up afterward; the two resulting `organization_deletion_receipts` rows
  are legitimate (anonymous, no organization-identifying field) and were intentionally left in place.
- `svelte-check` 0 errors (2 pre-existing unrelated CSS warnings), `vitest` 412/412 (15 new tests:
  10 for the cron module, 5 for the route's secret-auth boundary), advisors re-checked.
- **New advisory item, accepted as-is, not fixable**: `pg_net` installed its extension-control entry
  into `public` (the security linter's `extension_in_public` WARN). `ALTER EXTENSION pg_net SET
  SCHEMA` errors -- pg_net does not support relocation. Its actual functions (`net.http_post` etc.)
  already live in their own dedicated `net` schema regardless, so this is a namespace-hygiene note
  on the extension's own bookkeeping record, not an exploitable object; nothing to do here.
  `pg_cron` landed in `pg_catalog` (its normal Supabase default) and does not trigger this lint.
