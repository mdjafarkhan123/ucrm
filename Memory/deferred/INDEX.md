# Deferred Work

Only unresolved work explicitly postponed by the user belongs here.

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

- **Campaign:** `requests-and-assessments` Part 1, deferred by Jafar on 2026-08-18.
- **Reason:** Both blocks are drawn on `Design/Request Details.jpg` and Jafar confirmed they stay — they are
  **not** dropped. Jobber's request carries no line items, so there is no toured behavior to copy, and the
  pricing tables they need do not exist yet. Build them when pricing lands, not before.
- **Reactivation trigger:** The Quotes campaign creates line-item and labor tables, or Jafar asks for
  pricing on the request itself.
- **Prerequisites:** Ask Jafar how a request's line items relate to the quote's — the same rows carried
  forward on conversion, or a separate estimate that the quote copies. Jobber cannot answer this one, so it
  is his call under CLAUDE.md rule 4.
- **Checkpoint:** `Design/Request Details.jpg`, `Design/Request new.jpg` (the same blocks appear on both).

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
