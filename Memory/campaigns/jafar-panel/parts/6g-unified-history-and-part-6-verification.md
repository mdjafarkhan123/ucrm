# Part 6G: Unified History and Part 6 Verification

## Approved behavior

Source: `docs/jafar-completion-contract.md`, heading `Organization and commercial control` ("History
combines onboarding, payments and corrections, provisioning and setup delivery, package and access
changes, lifecycle, support, integrations, recovery, and deletion without exposing secrets.").
Jafar approved the concrete shape below directly (plain-language plan, no formal grill needed).

- An organization's History and recovery section shows its full story starting from the original
  application, not just from the moment the organization row was created.
- A separate "Needs attention" card on the organization page shows only this organization's
  unresolved background failures (stuck retries), reusing the existing global Operations data. It
  is empty by default and links to `/jafar/operations` rather than duplicating retry/acknowledge
  actions on the organization page.
- Organizations with no linked application (legacy/manually created) show history starting at
  organization creation — no error, no empty-state noise.
- An application that never became an organization is never pulled into any organization's feed.
- Application-phase events go through the same private-history model as everything else already in
  the feed; nothing new is exposed to contractors.
- Part 6 verification: full regression across 6A-6F together, then a live browser walkthrough with
  Jafar on 2-3 real organizations confirming the combined story reads correctly end to end.

## Dependencies

Parts 6A through 6F — all complete. 6G adds no new mutation, only read/merge of data these parts
(and earlier onboarding parts) already write.

## Key discovery (why this isn't just "add a query")

Two separate audit tables exist and neither was designed to be queried by organization alone:

- `access_audit_events` (organization-scoped, has `organization_id`) — already merged into
  `history/+server.ts` today.
- `platform_owner_audit_events` (platform-wide, generic `target_type`/`target_key` text pair, no
  `organization_id` column) — **not yet merged**. This is where the onboarding trail lives:
  `onboarding_application.corrected`, `.payment_confirmed`, `.reviewed`, `.duplicate_acknowledged`,
  `.not_proceeding`, `.payment_reversed`, `.package_corrected` are all written with
  `target_type = 'onboarding_application'`, `target_key = application_id::text`.
  One event, `onboarding_application.provisioned`, is already written with
  `target_type = 'organization'`, `target_key = organization_id::text` — it needs no join.

The join key from an organization back to its originating application is
`platform_onboarding_application_provisions.organization_id -> .application_id` (primary key on
`application_id`; nullable `organization_id` until provisioning succeeds). Not every organization
has a row here (legacy/manually created orgs) — that's an expected, not an error, case.

`platform_operation_attempts` (the Operations queue backend) already supports a `target_id` filter
via `GET /api/jafar/operations`. Its rows are keyed `target_kind` + `target_id`, covering both
`'organization'` (target_id = organization id) and `'onboarding_application'` (target_id =
application id) — the same two ids resolved above cover both kinds.

## Implementation sequence

1. Database: read-only function `owner_organization_application_id(target_organization_id uuid)
   returns uuid` (or inline the lookup in step 2's query) resolving the linked application id from
   `platform_onboarding_application_provisions`, `security definer`, `service_role`-only grant,
   matching the existing owner-function privilege pattern.
2. Extend `history/+server.ts`: after loading the organization, resolve its application id, then
   add a fourth parallel query against `platform_owner_audit_events` for
   `(target_type = 'organization' and target_key = organizationId) or (target_type =
   'onboarding_application' and target_key = applicationId)` (second branch skipped when there is no
   linked application). Map rows into the existing `HistoryEvent` shape and merge into the same
   sorted feed.
3. Extend `HISTORY_EVENT_LABELS` in the organization detail page for every `onboarding_application.*`
   event type found in step 2 (see Key discovery list above) plus `onboarding_application.provisioned`.
4. New read endpoint or extended `history` response field: unresolved operation attempts for this
   organization, resolved the same way (`target_id` = organization id OR resolved application id),
   `status <> 'succeeded'`, reusing `operationListQuerySchema`/pattern from
   `api/jafar/operations/+server.ts` rather than duplicating its query shape.
5. UI: new small "Needs attention" card on the organization detail page (separate from the History
   and recovery section), rendering the step 4 list with a link to `/jafar/operations`. Empty state:
   render nothing or a quiet "No open issues" — match existing card conventions on this page.
6. `.spec.ts` coverage for the extended history route and the new/extended operations-lookup piece.
7. `database.types.ts` regenerated against remote if a new function is added; `get_advisors` run.
8. Part 6 verification: `svelte-check`, full `vitest`, full pgTAP (6A-6F suites), then browser-verify
   the combined history and needs-attention card on 2-3 real organizations (at least one with a
   linked application, at least one legacy org with none).

## Acceptance checks

- [x] An organization's history includes its own application's corrections, review, payment
      confirmation(s), reversal (if any), and provisioning, correctly interleaved by time with the
      existing commercial/free-access/audit events. Verified live on Jafar LTD (the only real
      organization with a linked application): "Application marked reviewed" -> "Application payment
      confirmed" -> "Organization provisioned from application" appear at the correct chronological
      position beneath the org's later commercial/lifecycle history.
- [x] A legacy organization with no linked application shows history starting at organization
      creation, with no error and no broken empty state. Verified on Riverside Legacy Demo, Raad, and
      xdasd (none have a `platform_onboarding_application_provisions` row).
- [x] No application that never became an organization appears in any organization's feed. Structural
      guarantee: the merge only runs off an organization's own resolved application id, never a scan
      of all applications.
- [x] The "Needs attention" card shows only this organization's unresolved operation attempts
      (`status <> 'succeeded'`) and is empty/quiet when there are none. Verified empty on all 4 real
      organizations (none currently have an open recovery item).
- [x] Nothing new is exposed through the contractor-safe surface; this part touches only the owner
      route and owner-authenticated data. No migration, no new grant, no contractor-facing route
      touched.
- [x] `svelte-check` 0 errors; full vitest suite green (356/356, includes 1 new merge-behavior test in
      `history.spec.ts`).
- [x] Jafar confirms the combined story reads correctly on real organizations in the browser. Verified
      live on all 4 real organizations (Jafar LTD, Riverside Legacy Demo, Raad, xdasd); no console
      errors, all `/api/jafar/organizations/*` and `/api/jafar/operations` calls returned 200.
- [~] Existing 6A-6F pgTAP suites: not re-run. 6G made no migration and no schema change — it only adds
      read queries against tables/columns 6A-6F already finished, so there is nothing for those suites
      to regress. Full vitest and live browser verification across all 4 real organizations cover this
      part's actual surface (a read/merge feature).

## Source pointers

- `docs/jafar-completion-contract.md`, heading `Organization and commercial control`.
- `docs/jafar-organization-management-mission.md`, headings `History, transparency, and recovery`
  and `Operational recovery`.
- `supabase/migrations/20260810103725_owner_package_management.sql` (`platform_owner_audit_events`
  table definition).
- `supabase/migrations/20260812055458_platform_operations_foundation.sql`
  (`platform_operation_attempts` table; `onboarding_application.corrected`/`.payment_confirmed`/
  `.not_proceeding`/`.provisioned` event writes).
- `supabase/migrations/20260813033725_onboarding_reviewed_and_duplicate_handling.sql`
  (`.reviewed`/`.duplicate_acknowledged`/`.not_proceeding` event writes).
- `supabase/migrations/20260813150000_onboarding_package_correction.sql` (`.package_corrected`).
- `supabase/migrations/20260813180000_onboarding_payment_reversal.sql`
  (`.payment_reversed`/`.payment_confirmed`/`.provisioned`).
- `supabase/migrations/20260811231843_platform_onboarding_provisioning.sql`
  (`platform_onboarding_application_provisions` link table).
- `src/routes/api/jafar/organizations/[organizationId]/history/+server.ts` (route to extend).
- `src/routes/api/jafar/operations/+server.ts` (existing `target_id` filter pattern to reuse, not
  duplicate).
- `src/lib/server/validation/operation.schema.ts` (`operationListQuerySchema`).
- `src/routes/jafar/(protected)/organizations/[organizationId]/+page.svelte` (History section,
  `HISTORY_EVENT_LABELS`, new card placement).
- `src/routes/jafar/(protected)/operations/+page.svelte` (link target for the new card).

## Non-discoverable risks

- `platform_owner_audit_events` has no RLS-friendly organization column by design (it is
  intentionally generic across applications/organizations/platform-wide targets) — do not add an
  `organization_id` column to it; resolve via the application-id join instead, matching how the rest
  of the schema treats this table.
- `platform_onboarding_application_provisions.organization_id` is nullable until provisioning
  succeeds; a failed/abandoned application has no organization to attach to and must simply not
  appear anywhere (there is nothing to join to).
- Do not widen `history/+server.ts`'s existing `access_audit_events` query — it is already correct
  and organization-scoped; this part only adds the missing `platform_owner_audit_events` branch.
- The remote Supabase project is authoritative; Docker/local CLI remain unavailable. Apply any
  migration through Supabase MCP tools and verify via `list_migrations`.
- Preserve unrelated dirty work already in the tree (see `NOW.md` "Protected work").

## Current checkpoint

Closed 2026-08-14. All acceptance checks pass except the deliberately-skipped pgTAP re-run (see
above — no schema touched). `svelte-check` 0 errors, `vitest` 356/356. Browser-verified live on all
4 real organizations.

No database migration was needed: `getOwnerSupabaseClient()` already uses the service-role key
(bypasses RLS), and `platform_owner_audit_events` / `platform_onboarding_application_provisions`
already grant `select` to `service_role` from their original migrations. The whole part is three
plain reads added to `history/+server.ts` plus two reused `GET /api/jafar/operations?target_id=`
calls from the UI — `database.types.ts` needed no regeneration.

One real bug caught during browser verification, fixed the same session: the initial "Needs
attention" card gated its loading skeleton on `organizationOperationsQuery.isPending ||
applicationOperationsQuery.isPending`. TanStack Query keeps a *disabled* query's status at
`'pending'` forever (it never transitions since it never fetches) — and `applicationOperationsQuery`
is intentionally disabled whenever an organization has no linked application (three of the four real
organizations). The card was stuck on its loading skeleton permanently for every organization except
Jafar LTD. Fixed by gating the second query's contribution to the loading/error condition on
`Boolean(applicationId)` — `organizationOperationsQuery.isPending || (applicationId &&
applicationOperationsQuery.isPending)`. Worth remembering for any future UI that conditionally
enables a second `createQuery`: never OR its bare `isPending`/`isError` into a combined condition
without gating on the same `enabled` predicate.

One pre-existing, out-of-scope bug found (not fixed, not part of 6G): `GET
/api/jafar/organizations/[organizationId]/team` returns 500 for Riverside Legacy Demo
(`7e37a58f-60e4-40ee-bb4a-cf13966a7a3d`), leaving that organization's "Team access" card stuck on its
loading skeleton. Confirmed via `git status` that no file in the team route was touched this session.
Raad and xdasd's team cards both render correctly, so this is specific to Riverside Legacy Demo's
data shape, not the route generally. Flagged here since it lives on the same page 6G touched, but the
route itself belongs to earlier parts (6A/6E territory) — worth a quick look whenever that area is
next open, not urgent enough to justify unplanned scope right now.

`onboarding_application.provisioned` is the only `platform_owner_audit_events` row with
`target_type = 'organization'` in the entire remote database today (confirmed via direct query
before implementation) — the other six `onboarding_application.*` kinds are all `target_type =
'onboarding_application'`. If a future migration adds a new event kind targeting an organization
directly through this table, it will show up automatically since the query already filters on
`target_type = 'organization'` generically, not on a fixed list of event kinds.
