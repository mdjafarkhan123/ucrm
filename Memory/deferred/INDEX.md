# Deferred Work

Only unresolved work explicitly postponed by the user belongs here.

## Opportunity Brief activity timeline

- **Campaign:** `sales-pipeline` Part 3, deferred by Jafar 2026-08-19.
- **Reason:** Jobber's current Opportunity Brief has Tasks and Notes but no embedded activity timeline. UCRM's
  existing `activity_events` omit important Request, Assessment, Opportunity-detail, Task, and Note mutations,
  so rendering them as full Opportunity history would be misleading.
- **Reactivation trigger:** Jafar asks for history inside the Brief, or the shared activity domain gains a
  complete event vocabulary for Request/Quote commercial work.
- **Prerequisites:** Define the event catalog, retention, pagination, permission/value-redaction rules, and
  whether the view merges Client history or only the backing Request/Quote.
- **Checkpoint:** `docs/sales-pipeline-behavior-contract.md`, `src/lib/components/collaboration/ActivityFeed.svelte`,
  `public.activity_events`, and `public.opportunity_stage_events`.

## Task Schedule integration and advanced Tasks

- **Campaign:** `sales-pipeline` Part 3; implementation belongs to the future Schedule domain.
- **Reason:** Part 3 needs lightweight follow-up Tasks, but no Schedule route or unified scheduled-items feed
  exists. Building repeating/timed scheduling, reminders, notifications, or a placeholder calendar now would
  create the wrong ownership boundary.
- **Reactivation trigger:** The Schedule campaign begins or Jafar explicitly asks to schedule Tasks.
- **Prerequisites:** Part 3A's reusable Task foundation exists; Schedule defines how Tasks, Visits,
  Assessments, Events, and reminders share one feed without pretending they are the same object.
- **Checkpoint:** `Memory/campaigns/sales-pipeline/parts/03-opportunity-brief-tasks-notes.md` and
  `docs/PRODUCT.md` §14.

## Database test files under `supabase test db`

- **Campaign:** `clients-properties` (applies to every campaign that adds database tests)
- **Reason:** Development runs against the remote Supabase project with no Docker and no local stack, so
  the pgTAP runner cannot execute. Assertions are verified against the remote project instead, inside one
  transaction that is rolled back.
- **Reactivation trigger:** The app is containerized with local Supabase, or Docker becomes available.
- **Prerequisites:** `npx supabase start`, then `npx supabase test db`. Expect the runner to surface plan
  counts and ordering problems that single-transaction verification cannot.
- **Checkpoint:** `supabase/tests/database/tenant_isolation.sql` (plan 75 as of 2026-08-17). Note: this file
  has never actually been executed by the pgTAP runner, so its plan count and statement ordering are
  unproven — expect the first real run to surface problems that per-assertion verification cannot.
- `supabase/tests/database/client_create_edit.sql` (plan 21) is different: on 2026-08-17 its whole body was
  executed against the remote project in one rolled-back transaction, as the real `authenticated` role, and
  all 21 assertions passed. Its plan count and ordering are proven; only the CLI runner itself is untried.

## `/get-started` page weight

- **Campaign:** `jafar-panel` (the signup route feeding Prospects). Found during `clients-properties`.
- **Reason:** Jafar deferred the work on 2026-08-17, right after it was found. Nothing depends on it yet.
- **What is wrong:** `/get-started` builds to an 8.2 MB client chunk — by far the heaviest page in the app,
  and it is the public signup entry point, hit by people on phones and poor connections. The weight comes
  from `src/lib/components/ui/LocationPicker.svelte` importing `country-state-city`, which ships every
  country, state, and city on earth into the browser bundle. `TimezonePicker` on the same page is fine.
- **Reactivation trigger:** Jafar asks to optimize signup, real signups are reported as slow, or any other
  page starts using `LocationPicker` and inherits the same weight.
- **Prerequisites:** Decide with Jafar how city lookup should work first, because that is a product call,
  not just a build one. Options to put to him: search cities through a server route so nothing ships to the
  browser; ship only the countries the product sells in; or drop the picker to plain typed fields. Then
  re-run `npm run build` and check the chunk under
  `.svelte-kit/output/client/_app/immutable/nodes/` to confirm the drop.
- **Checkpoint:** `src/lib/components/ui/LocationPicker.svelte` and `src/routes/get-started/+page.svelte`.

## `Last communication` rail card on the client page

- **Campaign:** `clients-properties`, but the work belongs to `communications`.
- **Reason:** Jafar deferred it on 2026-08-17 when the client Details/Communication tabs were built. There
  are no messages to summarise yet, so the card would only ever be empty.
- **What it is:** Jobber's client detail rail carries a `Last communication` card under Tags — date and
  time, the subject, a `Read more...` link, and a chevron opening the full history. Toured live and written
  up in `.claude/skills/jobber/jobber-01-clients-properties.md` §2.4. We have no equivalent.
- **Reactivation trigger:** The Communications campaign lands a real message history on the client's
  Communication tab.
- **Prerequisites:** The shared Conversations model exists and the Communication tab lists real messages.
- **Checkpoint:** `src/routes/(app)/clients/[id]/+page.svelte`, the `rail()` snippet.

## Property deletion guarded once work references a property

- **Campaign:** `clients-properties` Part 7, deferred out of scope on 2026-08-17.
- **Reason:** There are no requests, quotes, jobs or invoices yet, so there is nothing to guard against.
  Removing a property today can only orphan attachments and notes, which already cascade correctly.
- **What is missing:** `public.delete_property` removes a property with no check for work that points at it,
  and `propertySchema` in `src/lib/server/validation/foundation.schema.ts` has no spec file — starting the
  validation-spec pattern is Jafar's call, not the agent's.
- **Reactivation trigger:** The first work object that references `properties.id` ships (Requests is next).
- **Prerequisites:** A work table with a property foreign key exists. Decide with Jafar what a blocked delete
  says to the user and whether the property becomes read-only instead.
- **Checkpoint:** `public.delete_property`, `src/lib/server/validation/foundation.schema.ts`.

## Historical address safety and property transfer between clients

- **Campaign:** `clients-properties` Part 7, deferred out of scope on 2026-08-17.
- **Reason:** Editing a property address today silently rewrites history everywhere it is shown. That only
  matters once a past quote, job or invoice carries an address that must stay as it was on that day.
- **What is missing:** No address snapshot onto work records, and no way to move a property from one client
  to another with its history intact.
- **Reactivation trigger:** The first work object stores or prints a property address.
- **Prerequisites:** Agree with Jafar whether work snapshots the address at creation or at completion.
- **Checkpoint:** `docs/client-property-behavior-contract.md`, `20260817150000_property_add_and_remove.sql`.

## Billing address shape on the client

- **Campaign:** `clients-properties` Part 7, deferred out of scope on 2026-08-17.
- **Reason:** Jafar rejected a billing address on the client page during Part 6 — it has no meaning until
  something is billed. Do not reintroduce it before then.
- **Reactivation trigger:** The Invoicing campaign needs an address to bill to.
- **Prerequisites:** Invoicing decides whether billing address is its own field or a chosen property.
- **Checkpoint:** `docs/client-property-behavior-contract.md`.

## Client duplicate detection, merge, archive, restore, and audit history

- **Campaign:** `clients-properties` Part 8, deferred out of scope on 2026-08-17.
- **Reason:** Buildable today, but worth far more once clients carry real work — merge and archive are mostly
  about what happens to the work attached to a client, and there is none yet.
- **What exists now:** Create-time duplicate warnings only, using unindexable `ilike '%term%'`, bounded per
  organization and capped at 5 rows. Fine at this size; real fuzzy matching needs `pg_trgm` and Jafar's
  approval. There is no merge, no archive, no restore, and no audit history.
- **Reactivation trigger:** Clients carry requests, quotes, jobs or invoices, or Jafar reports real duplicates
  in live data.
- **Prerequisites:** A transactional merge must move every child row without history loss or tenant crossing.
- **Checkpoint:** `src/routes/api/clients/`, `docs/client-property-behavior-contract.md`.

## `EntityType` covers only clients and properties

- **Campaign:** `clients-properties` Part 7, deferred out of scope on 2026-08-17.
- **Reason:** Nothing else exists to attach notes, tags or files to yet.
- **What is missing:** `EntityType` in `src/lib/collaboration/api.ts` lists `client` and `property` only.
  Requests, quotes, jobs and invoices each need it extended plus a matching database check constraint before
  their pages can attach anything.
- **Reactivation trigger:** The first non-client, non-property page needs notes, tags or attachments.
- **Prerequisites:** Extend the union and the database check in the same migration, or attachments will fail
  at write time with a constraint error.
- **Checkpoint:** `src/lib/collaboration/api.ts`.

## Six unindexed foreign keys from the collaboration tables

- **Campaign:** `clients-properties` Part 3, deferred by explicit decision, restated on 2026-08-17.
- **Reason:** Row counts are tiny, so the planner scans them fine today.
- **What is missing:** Six Part 3 foreign keys have no covering index; `attachments.note_id` matters most
  because deleting a note has to find its attachments.
- **Reactivation trigger:** Any collaboration table passes a few thousand rows, or note deletion gets slow.
- **Prerequisites:** Confirm the missing indexes against `get_advisors` before writing the migration.
- **Checkpoint:** `20260816090000_client_property_data_model.sql`.
- `tasks.created_by` and `tasks.completed_by` (added 2026-08-19) take the same accepted trade-off: both point
  at `auth.users` and only matter when an account is deleted. `tasks.assignee_user_id`, which the product
  actually queries by, is indexed.

## Client photos are one request each

- **Campaign:** `clients-properties`, accepted limit rather than a defect.
- **Reason:** Attachment photos are private, so each one is fetched through our own server rather than
  straight from storage. A first view of N photos is N round trips, each cached privately for a day.
- **Reactivation trigger:** A client carries dozens of photos, or a client page feels slow to open.
- **Prerequisites:** Decide with Jafar between signed storage URLs handed to the browser in one batch, or a
  sprite/manifest response. Both change how private files are served, so it is his call.
- **Checkpoint:** `src/lib/components/collaboration/AttachmentsCard.svelte` and the attachment API route.

## Prospect detail page

- **Campaign:** `operations-prospects-ux`
- **Reason:** The user paused the Prospect work after the reusable dialog and Operations conversion were completed.
- **Reactivation trigger:** The user explicitly asks to resume the Prospect detail page.
- **Prerequisites:** Reinspect the current Prospect list, APIs, mutations, and organization-detail route before implementation because old line references are stale.
- **Checkpoint:** `Memory/campaigns/operations-prospects-ux/NOW.md`
- **Part packet:** `Memory/campaigns/operations-prospects-ux/parts/03-prospect-detail-page.md`

## Non-admin email-correction browser verification (Part 7)

- **Campaign:** `jafar-panel`
- **Reason:** No organization on the platform currently has a non-owner/non-admin (office/sales/
  field/finance) member -- every seeded org has exactly one member, the owner. The "Fix profile"
  email-change branch for non-admin roles is covered by an automated test
  (`profile-correction.spec.ts`) and code review, but has never been exercised live in the browser.
  Jafar explicitly chose to close Part 7 without this check rather than create throwaway test data.
- **Reactivation trigger:** A real organization gets a non-owner/non-admin member (through normal
  product use, or a deliberate throwaway test member), and Jafar or the agent wants to confirm the
  email field renders and the email-change PATCH round-trips live.
- **Prerequisites:** None beyond a qualifying member existing.
- **Checkpoint:** `Memory/campaigns/jafar-panel/parts/7-team-access-and-administrator-recovery.md`
  (closed packet, kept for this deferral's context).

## `Product & Services` and `Labor` blocks on the Request detail page

- **Campaign:** `requests-and-assessments` (closed 2026-08-18), deferred by Jafar on 2026-08-18.
- **Reason:** Both blocks are drawn on `Design/Request Details.jpg` and Jafar confirmed they stay — they are
  **not** dropped. Jobber's request carries no line items, so there is no toured behavior to copy, and the
  pricing tables they need do not exist yet. Build them when pricing lands, not before.
- **Reactivation trigger:** The Quotes campaign creates line-item and labor tables, or Jafar asks for
  pricing on the request itself.
- **Prerequisites:** Ask Jafar how a request's line items relate to the quote's — the same rows carried
  forward on conversion, or a separate estimate that the quote copies. Jobber cannot answer this one, so it
  is his call under CLAUDE.md rule 4.
- **Checkpoint:** `Design/Request Details.jpg`, `Design/Request new.jpg` (the same blocks appear on both).

## Request list search doesn't match client name

- **Campaign:** `requests-and-assessments` (closed 2026-08-18).
- **Reason:** Jafar didn't decide during the browser pass whether to add it; not blocking real use.
- **What is wrong:** The list search only queries `title` and `service_type`
  (`src/routes/api/requests/+server.ts`). Searching "Priya" finds nothing even though she has requests;
  searching her request's title does. Jobber's request search matches client name too.
- **Reactivation trigger:** Jafar reports the search missing a client he expected to find, or asks for it.
- **Prerequisites:** Join to `clients.display_name` (and `company_name`) in the existing `.or()` filter;
  check the query plan once request volume is non-trivial.
- **Checkpoint:** `src/routes/api/requests/+server.ts`.

## Request Status filter matches the stored status, not the displayed one

- **Campaign:** `requests-and-assessments` (closed 2026-08-18).
- **Reason:** Confirmed in the browser pass — honest but confusing, not decided whether worth fixing yet.
- **What is wrong:** Picking "Unscheduled" in the Status filter also returns rows badged "Overdue"/"Today"
  in the table, because the filter runs against `requests.status` (six stored values) while the badge shown
  is the derived nine-value status. Filtering by the derived status is possible with the same day-boundary
  logic `GET /api/requests/counts` already computes.
- **Reactivation trigger:** Jafar reports the filter behaving unexpectedly, or asks for it to match the
  badge.
- **Prerequisites:** Decide whether to filter by computed status server-side (extra per-row date math) or
  keep the stored-status filter and relabel it so it reads honestly.
- **Checkpoint:** `src/routes/api/requests/+server.ts`, `src/lib/server/requests/status.ts`.

## Third KPI card on the Requests list has no real data source

- **Campaign:** `requests-and-assessments` (closed 2026-08-18).
- **Reason:** Never Jafar's word — a placeholder proposal added while building the list page, now stale.
- **What is wrong:** The card is named "Assessments booked" with a note that no longer matches anything
  real. Jobber's own Requests list only has two KPI cards (New requests, Conversion rate).
- **Reactivation trigger:** Jafar decides what the third card should say, or asks to drop it to match
  Jobber's two.
- **Prerequisites:** None — a naming/scope call only.
- **Checkpoint:** `src/routes/(app)/requests/+page.svelte`.

## No `requests.*` permission keys seeded

- **Campaign:** `requests-and-assessments` (closed 2026-08-18).
- **Reason:** Every request route and every request note currently only checks organization membership.
  Seeding a real role matrix is a separate, cross-cutting call, not specific to Requests.
- **What is missing:** `requests.view` / `requests.create` / etc. equivalent to the `customers.*` keys
  clients already use (`requireClientPermission`).
- **Reactivation trigger:** Jafar asks for role-gated request access, or a second campaign needs the same
  pattern and it's worth doing once for both.
- **Prerequisites:** Decide the role matrix shape with Jafar first — this affects every future work object,
  not just requests.
- **Checkpoint:** `src/lib/server/access/`, `src/routes/api/requests/`.

## Client detail page still uses the superseded staging-dialog edit shape

- **Campaign:** `clients-properties` (closed), reopened as a debt by Jafar's 2026-08-18 rule change.
- **Reason:** Client detail was built to the 2026-08-17 rule where a block's pencil opened a dialog that
  staged into `DetailEditBar`, and `/clients/[id]/edit` was deleted. On 2026-08-18 Jafar adopted all three
  of Jobber's edit patterns instead. He chose to convert clients as we next touch that page rather than
  stopping Requests to do it.
- **Reactivation trigger:** Any work that opens `src/routes/(app)/clients/[id]/+page.svelte`.
- **Prerequisites:** Blocks edit in place with their own scrolling Cancel/Save that writes immediately; the
  bar keeps only tags, notes, pins and staged deletes; restore the full edit page reached from the client
  card's `...` menu in a new tab. See `.claude/skills/jobber/jobber-08-screen-patterns.md` § How WE compare.
- **Checkpoint:** `src/routes/(app)/clients/[id]/+page.svelte`,
  `src/lib/components/clients/ClientDetailsDialog.svelte`.

## App-wide RLS helpers run once per returned row

- **Campaign:** found during `sales-pipeline` Part 1 on 2026-08-18; the fix belongs to whichever campaign
  next touches those tables.
- **Reason:** Fixing it properly means rewriting the policies on clients, properties, client contacts,
  contact methods, communication preferences, requests, assessments, and assessment assignees — all outside
  Part 1's scope. Pipeline was fixed in place because it was the layer being built.
- **What is wrong:** Policies written as `private.is_organization_member(organization_id)` and
  `private.has_permission(organization_id, '...')` reference a column, so Postgres calls them once for every
  row the query returns instead of once for the query. Measured on 50,000 rows: a 50-row page cost 11 ms and
  766 buffers with the per-row helpers, against 2.8 ms and 392 buffers for a 200-row page after the fix —
  and the old cost keeps climbing with page size while the new one stays flat.
- **The fix that worked:** `private.permitted_organizations(permission)` returns a set of organization ids
  and reads no column, so `organization_id in (select private.permitted_organizations('x'))` becomes one
  hashed subplan per query. It already exists and is granted to `authenticated`, so adopting it elsewhere is
  policy rewrites only, no new helper.
- **Reactivation trigger:** Any list page over a table using the per-row helpers gets slow, a tenant passes
  a few thousand rows in `clients` or `requests`, or a campaign is already rewriting those policies.
- **Prerequisites:** `private.can_view_client` mixes membership, permission, and the assigned-work seam, so
  clients and properties need that seam preserved rather than replaced — check it before converting them.
  Re-verify cross-tenant and permission-denied reads on every table converted.
- **Checkpoint:** `supabase/migrations/20260818133726_pipeline_rls_permission_lookup_once_per_query.sql`,
  `supabase/migrations/20260816110139_client_property_permissions.sql`.

## Every entitlement-gated route re-reads the whole access model

- **Campaign:** found during `sales-pipeline` Part 1 on 2026-08-18; the fix belongs to the access layer, so
  whichever campaign next touches `src/lib/server/access/effective.ts` should own it.
- **Reason:** The pipeline routes need entitlement checked server-side, and the only resolver available is
  the same one clients, properties and tags already use. Rewriting it is cross-cutting work that would
  touch every gated route and the Jafar panel's write paths, so Part 1 uses it as is.
- **What is wrong:** `resolveOrganizationAccess` runs roughly twelve queries in four sequential waves on
  **every** gated request — packages, features, package features, package limits, feature overrides, limit
  overrides, commercial state, settings, free access, membership, role permissions, member overrides. The
  first four are global reference tables identical for every user in the product.
- **Measured 2026-08-18** against remote Supabase from local dev, median of five: `/api/pipeline/summary`
  623 ms and `/api/clients` 783 ms, both gated, against `/api/requests` 304 ms and `/api/requests/counts`
  219 ms, which only check membership. The gap is the resolver, not the queries the routes actually make —
  the pipeline board's own database work measures 2.7 ms.
- **Reactivation trigger:** A gated page feels slow, or the app moves to the VPS phase where connection
  count matters, or any campaign is already editing the access resolver.
- **Prerequisites:** Decide with Jafar how stale entitlement may be. Likely shape: cache the global
  reference tables in process with a TTL, keep the per-organization and per-member parts live, and flush on
  the Jafar-panel writes that change packages, overrides, or roles. Never cache per-user data across users.
- **Checkpoint:** `src/lib/server/access/effective.ts`, `src/lib/server/access/permission.ts`.

## The Pipeline nav item is not gated on entitlement or permission

- **Campaign:** `sales-pipeline` Part 1, 2026-08-18. Belongs to whichever campaign next gives the app shell
  a real access context.
- **Reason:** Part 1's checklist asked for the nav item to appear only for members with the
  `sales.pipeline` entitlement and `pipeline.view`. The shell has no access context to decide that with:
  `src/routes/(app)/+layout.server.ts` loads membership only, and the nav in `AppShell.svelte` is a static
  array. The one available answer is `resolveOrganizationAccess`, which costs ~400 ms — and putting it in
  the layout load would charge that to **every** page in the app, not just the gated ones.
- **What ships instead:** the nav item is a normal link, and `/pipeline` itself renders the honest
  unavailable state. A refused member sees "Pipeline is not part of your plan" or "You do not have access
  to the pipeline" — different words for the two 403 reasons — and no counts or records leak either way.
  The refusal is real; only the nav item is unconditioned.
- **Reactivation trigger:** the access resolver gets its cache (see the entry above), or any campaign adds
  a per-feature access context to the app shell. Do it once, for every gated area, not for Pipeline alone.
- **Prerequisites:** the resolver caching decision has to land first, or this trades a correct nav item for
  400 ms on every page load.
- **Checkpoint:** `src/lib/components/layout/AppShell.svelte`, `src/routes/(app)/+layout.server.ts`,
  `src/routes/(app)/pipeline/+page.svelte`.

## Authenticated reads and Pipeline writes are not rate limited

- **Campaign:** found during `sales-pipeline` Part 2 item 3 on 2026-08-19. The fix belongs to whichever
  campaign next touches the API layer as a whole.
- **Reason:** `checkRateLimit` exists (`src/lib/server/security/rate-limit.ts`) but is only used on
  unauthenticated or sensitive routes — get-started, setup-password, the Jafar session. No authenticated
  list read in the app is limited: not Clients, not Requests, and not the Pipeline board. Adding it to the
  board alone would be inconsistent and would put an extra database round trip on every column page.
- **What is at risk:** one logged-in client looping a column page can hold pooled connections across every
  tenant. The board is capped at 50 rows a page and is keyset-paged, so a single request is cheap; the
  exposure is request volume, not request cost.
- **Also uncovered (2026-08-19):** the Pipeline write routes — owner, value, the two dates, and the Part 3A
  Task routes — carry no limit either. Each is one function call, and the Task limits cap what can be
  created, but a loop still spends connections. Same decision, same place to make it.
- **Reactivation trigger:** the app moves to the VPS phase, connection saturation is seen in the Supabase
  dashboard, or any campaign is already reworking the shared API guards.
- **Prerequisites:** decide with Jafar what a limited read says to the user, and pick a bucket key —
  organization plus route reads right for a shared board, per user for personal lists. Do it once for every
  list read, not per route.
- **Checkpoint:** `src/lib/server/security/rate-limit.ts`, `src/lib/server/access/permission.ts`.
