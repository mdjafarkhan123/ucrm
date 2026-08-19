# Part 1: Request-side Pipeline Foundation

## Approved outcome

Deliver the first usable Sales Pipeline slice: every authorized organization sees each existing or new Request
exactly once as an Opportunity on a protected desktop lifecycle board.

Revised 2026-08-18 to follow Jobber's current Sales Pipeline. Standalone Opportunity creation is removed from
this part and from the product.

## Approved behavior

- Every Request automatically owns exactly one Opportunity. Nothing else creates one.
- Existing Requests receive Opportunities through an idempotent migration backfill.
- Opportunity outcome is `open`, `won`, or `lost`; Part 1 only ever produces open Opportunities.
- The board projects Request and Assessment truth into these protected stages, inside a `Requests` group:
  1. New requests
  2. Assessment unscheduled
  3. Assessment scheduled
  4. Assessment completed
- Draft, Awaiting response, and Changes requested join the same board as a second `Quotes` group in Part 5.
  A converted Request leaves the Request stages; its Quote arrives in Draft as its own card.
- Protected stage movement never writes a second status that can disagree with the Request or Assessment.
- No dragging in Part 1, and cards must not look draggable.
- No money, no sort or filter bar, no lead source, no owner avatar. Each belongs to a later part, and nothing
  shows a placeholder such as `$0.00`.
- Clicking a card opens a thin Opportunity Brief drawer: title, client and property, stage, stage age, and a
  `View request` action. Tasks, notes, AI summary, email, and Quote actions belong to their later parts.
- Stage age comes from `stage_entered_at`: green under one hour, neutral to 24 hours, red after that.
- Desktop web only. Mobile belongs to the separate mobile app and is out of this campaign.
- Custom stages are outside the first release.

## Dependencies

- Completed Clients and Properties foundation.
- Completed staff Request intake, list, detail, assessment scheduling, and assessment completion.
- Existing `sales.pipeline` feature entitlement and effective-access resolver.
- Approved behavior contract: `docs/sales-pipeline-behavior-contract.md`.

## Implementation-plan gate

Before editing code or migrations, present for approval:

- exact Opportunity, history, and relationship table shapes;
- whether protected stage is calculated in SQL, server code, or a security-invoker read model;
- tenant-safe foreign keys and uniqueness constraints;
- indexes for the open board, owner/date filters, RLS predicates, and cascade behavior;
- idempotent backfill mapping for every stored and derived Request state;
- `pipeline.view` / `pipeline.edit` role matrix and package-entitlement enforcement;
- Zod request shapes and `/api/pipeline/*` endpoints;
- TanStack Query key family and targeted invalidation from Request writes;
- board layout, keyboard and screen-reader path, and empty/error/loading states;
- database, unit, Svelte, and browser verification commands.

## Checklist

- [x] Inspect current remote/local schema truth and confirm the project still uses imperative migrations.
- [x] Confirm current Supabase changelog/docs relevant to schema, RLS, and Data API exposure.
- [x] Obtain approval for the exact Part 1 implementation plan.
- [x] Create tenant-safe Opportunity and immutable history foundations with named constraints.
- [x] Add indexes for every foreign key, RLS predicate, board filter, and stable board ordering path.
- [x] Enable RLS, grant only required operations, and test anonymous and cross-tenant denial.
- [x] Seed `pipeline.view` and `pipeline.edit` with the approved role matrix. Feature gating still belongs to the server layer and is not built yet.
- [x] Backfill existing Requests once and make automatic creation safe under retry/concurrency.
- [x] Add Zod-validated application writes through `/api/*`.
- [x] Add the shared Pipeline query-key family and invalidate it after affected Request/Assessment writes.
- [x] Retire standalone Opportunity creation from the API, schemas, and browser client.
- [x] Build the desktop protected board using existing layout/data-display primitives and Tabler icons.
- [x] Add the thin Opportunity Brief drawer and an accessible `Load more` per column.
- [x] Load the client's phone and email into the drawer on open, prefetched on card hover. Fixed 2026-08-19:
      `OpportunityBriefDrawer` now queries `clientDetailKey`/`fetchClient`, and `OpportunityCard` warms that
      key on hover/focus, browser-verified against a client with both a phone and an email on file.
- [~] Navigation item enabled as a plain link; real entitlement/permission gating is deferred — see
      `Memory/deferred/INDEX.md`. The page's own refusal is built and correct.
- [x] Run database, unit, Svelte autofixer, type, and browser checks. `npm run check` 0 errors, Prettier clean,
      `npm run build` clean, no console errors.
- [x] Update the packet and checkpoint at the completion gate.

## Acceptance checks

### Database and security

- Each Request can relate to only one Opportunity, including concurrent retry attempts.
- A relationship cannot cross organization, customer, property, Request, owner, or history boundaries.
- Anonymous users and members of another organization cannot read or mutate Pipeline rows.
- A member without `pipeline.view` cannot read the board; `pipeline.edit` separately protects writes.
- An organization without `sales.pipeline` is rejected server-side even if a route is requested directly.
- Backfill is idempotent and maps archived/converted historical Requests without placing them incorrectly on the
  active board.

### API and cache

- POST/PATCH payloads are Zod-validated before database access and use `{ error, field_errors }` failures.
- Board reads use stable ordering and keyset/cursor behavior if pagination is needed; no unbounded row load.
- Request creation and assessment changes invalidate only affected Request and Pipeline families.
- No application path can insert an Opportunity. Creation happens only through the Request trigger, and a
  retried Request write cannot produce a second card.

### Interface

- Desktop shows the four protected Request stages inside one `Requests` group with its own total.
- A card shows title, client, created date, and a stage-age chip coloured by the freshness rule. Nothing else.
- Cards carry no drag affordance: no grab cursor, no handle, no reorder hint.
- Empty columns and an entirely empty Pipeline explain what will make work appear.
- Loading renders the shell or skeleton first; stale cached data remains visible during background refresh.
- The page scrolls once, vertically. Each column's next page comes from a keyboard-reachable `Load more`.
- Keyboard and screen-reader users can open every card's drawer and reach its full Request.
- Feature-disabled and permission-denied users receive an honest unavailable state rather than leaked counts.

## Meaningful edge cases

- Requests created during the backfill.
- A Request converted or archived while its card is on screen: the card must leave the board on refresh.
- Requests with no Assessment, an unscheduled Assessment, a scheduled Assessment, or a completed Assessment.
- Archived and converted Requests that should remain historical rather than active.
- A deleted or archived customer/property after historical work exists.
- Owner membership deactivation after assignment foundations arrive.
- A card sitting in a stage for months, so the age chip has to read sensibly well past `24h`.
- Two browser tabs creating or updating related work concurrently.
- Organization suspension, commercial grace, feature override, or package change while the board is open.
- Day-boundary stage age in the organization's timezone.

## Source pointers

- `docs/sales-pipeline-behavior-contract.md`
- `docs/research/contractor-crm-sales-pipeline-comparison.md`
- `docs/PRODUCT.md` sections 9–10
- `docs/build-sequence.md`
- `supabase/migrations/20260808054034_initial_crm_foundation.sql`
- `supabase/migrations/20260818050039_assessment_schema.sql`
- `supabase/migrations/20260818133431_sales_pipeline_opportunity_foundation.sql`
- `src/lib/server/access/effective.ts`
- `src/routes/api/requests/`
- `src/lib/requests/api.ts`
- `src/lib/components/layout/AppShell.svelte`

## Non-discoverable risks

- Current Pipeline permissions appear only in archived migrations, so active history must seed them explicitly.
- The three Quote server files are empty placeholders and do not justify Quote schema or behavior.
- The current Request detail offers disabled conversion actions; Part 1 must preserve them until their owning
  campaigns implement real conversions.
- The schema still allows `request_id` to be null, which is how standalone Opportunities were built. That
  nullability is now what Part 5 needs for Quote-backed cards, so it stays; only the write path is removed.
  Nothing in the application may insert a row without a `request_id` until Part 5 defines the Quote case.
- `opportunities.stage` and `stage_entered_at` are owned by triggers. A before-insert/update trigger
  overwrites whatever any caller sends, so never try to set them from the API — send the Request or
  Assessment change instead and the stage follows.
- Pipeline RLS uses `private.permitted_organizations(permission)`, not the app-wide
  `is_organization_member` + `has_permission` pair, because those run once per returned row. Other
  tables were left alone.
- Existing Svelte autofixer output reports unrelated pre-existing issues in `AppShell.svelte` and the Request
  detail page. Do not absorb them unless they block the approved Pipeline change.
