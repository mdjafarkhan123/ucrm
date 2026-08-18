# Requests and Assessments — NOW

## Stage: 1d built and verified in the browser 2026-08-18. Awaiting Jafar's look at the live page.

## Goal (approved 2026-08-18)

Staff-side request intake + on-site assessment scheduling + completion, matching Jobber. Public booking
form and real Quote/Job conversion are explicitly deferred out of Part 1 (Jafar confirmed both).

## Exact next action

Wait for Jafar's verdict on `/requests` (screenshots shown, dev server, real data). Then start 1e, the
Request detail page, on `Design/Request Details.jpg` and the `src/lib/components/work/` pieces.

Two things on the page still want his word — both listed under "Open, needs Jafar" below.

## State of the server — do not redo

The whole API layer for Part 1 is built and type-clean:

- `GET`/`POST /api/requests` — cursor list (`?search`, `?status`, `?cursor`, `?limit`, max 50) and create.
- `GET /api/requests/counts` — the Overview card's numbers, counted on demand.
- `GET`/`PATCH /api/requests/[id]` — detail with client, property, assessment, assignees; partial patch.
- `PUT`/`DELETE /api/requests/[id]/assessment` — book, move, unschedule, reassign, remove.
- `POST /api/requests/[id]/assessment/complete` — complete and reopen.

Every response carries `stored_status` and a derived `status`. Never write the derived one.

## State of the browser side — do not redo

- `src/lib/requests/statuses.ts` — the status list, labels, and the nine-to-five tone map, readable from
  both sides. `src/lib/server/requests/status.ts` re-exports it and owns the derivation rule alone.
- `src/lib/requests/api.ts` — list and counts fetchers plus query keys.
- `src/routes/(app)/requests/+page.svelte` — the list page. Route is warm-listed; sidebar entry live.
- `src/lib/components/work/` — `WorkRecordHeader`, `ClientSummaryCard`, `RecordFactsList`,
  `PrimaryInfoCard`, `StatusOverviewCard`, `types.ts`. Nothing request-specific; 1e/1f consume them.
  Demo page `src/routes/(app)/dev-preview/work-record/+page.svelte` — delete once real pages exist.

## Settled decisions

- `requests.status` stores six values. `upcoming` / `today` / `overdue` come from
  `src/lib/server/requests/status.ts` at read time, in the org's timezone. Same rule for job visits later.
- The timezone rule lives in one file. `organizationDayRange()` hands the counts function two instants;
  SQL only buckets between them. Never write the calendar rule a second time in SQL.
- Zero or one assessment per request; both times null means unscheduled; `completed_at` null means not
  complete; assignees are a join table.
- Counts are read-only and counted on demand, not materialized. Clicking one does not filter.
- Overview rows: New, Unscheduled, Overdue, Assessment complete. "Needs approval" from the blueprint was
  swapped for Unscheduled (Jafar, 2026-08-18) — nothing can reach it until the public booking form exists.
- The three KPI cards are drawn as placeholders saying what they wait for, on the shared `KpiCard`.
- Load more, not numbered pages (Jafar, 2026-08-18). The list API is cursor-only.
- Date filter deferred; Status ships now (Jafar, 2026-08-18).
- New Request and More Actions render disabled with an honest reason until 1f and the booking form.
- The header is a filled grey card, not Jobber's status-tinted stripe — the blueprint wins.

## Open, needs Jafar

- **Filtering by Status is by stored status, so picking "Unscheduled" also returns rows badged
  "Overdue".** Honest but confusing. Filtering by the derived status is possible with the same day
  boundaries the counts route already computes. His call whether that is worth doing now.
- **The third KPI card is named "Assessments booked"** — a proposal, not his word. Jobber only has two.
- **Request permissions.** No `requests.*` permission keys are seeded, so these routes only check
  organization membership. Seeding a role matrix is a separate call.
- **Status filter select truncates "Assessment complete"** — narrow fixed width. Cosmetic.

## Protected work

- Migration `supabase/migrations/20260818160000_request_status_counts.sql` — applied remotely.
- Indexes from `20260818140000_request_list_cursor_indexes.sql` — applied remotely.
- **Eight demo requests and five assessments were inserted into `Jafar LTD`** (org
  `18f0d717-904e-48d8-bd99-9df7e3844cda`), one per display status, so the list has something real to
  show. Delete them once real requests exist — they say so in their description.
- `src/lib/database.types.ts` regenerated; the stale `contacts` table entries are gone.
- `npm run check` clean, 461 unit tests pass.

## Pointers

- `parts/1d-requests-list.md` — the slice that just closed; keep for the decisions it records.
- `parts/1b-api-routes.md` — what the API layer does and what it deliberately leaves out.
- `.claude/skills/jobber/jobber-08-screen-patterns.md` — shared skeleton, edit patterns, parts inventory.
- `.claude/skills/jobber/jobber-02-requests-leads.md` §4.1–§4.2 — the list and detail screens.
- `Design/Requests.jpg`, `Design/Request Details.jpg`, `Design/Request new.jpg` — blueprints.
- Auto-memory: `feedback_work_object_header_shared_across_types`, `feedback_create_pages_share_one_shell`,
  `feedback_titled_blocks_use_section_block`, `feedback_review_before_wiring`,
  `feedback_preview_built_components_live`.
