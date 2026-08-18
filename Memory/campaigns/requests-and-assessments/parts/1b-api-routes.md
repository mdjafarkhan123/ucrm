# Part 1b — Request and assessment API routes

Slice: every server route the Requests list, Request detail, and New Request pages will call.
Depends on 1a (applied). Nothing in the UI layer is built here.

## Approved behavior

Six stored request statuses: `new`, `unscheduled`, `assessment_completed`, `completed`, `converted`,
`archived`. `upcoming` / `today` / `overdue` are **derived at read time** and returned as a separate
`schedule_state` field — never written. Derivation, in the organization's timezone from
`organization_settings.timezone`:

- assessment exists, `completed_at` null, `starts_at` set → `today` / `upcoming` / `overdue`
- assessment exists, `completed_at` null, `starts_at` null → `unscheduled`
- otherwise → the stored status

## Routes

| Route | Method | Purpose |
| --- | --- | --- |
| `/api/requests` | `POST` | Already exists. Extended, not replaced: optional inline assessment on create. |
| `/api/requests` | `GET` | Cursor list. Jobber's columns + `schedule_state`. Filters: search, status, cursor, limit. |
| `/api/requests/[id]` | `GET` | Detail: request, client, property, assessment, assignees. |
| `/api/requests/[id]` | `PATCH` | Partial update so each detail block saves itself. |
| `/api/requests/[id]/assessment` | `PUT` | Book, reschedule, unschedule, set instructions and assignees. |
| `/api/requests/[id]/assessment/complete` | `POST` | Complete / reopen. Completing moves the request to `assessment_completed`. |

## Rules this slice must hold

- Cursor pagination only, keyed on `(created_at desc, id desc)`. No `offset`, no `range()`.
- Every write validates with Zod from `src/lib/server/validation/foundation.schema.ts` and returns the
  fixed error shape from `src/lib/server/api/errors.ts`.
- Client and property ownership is re-checked on write, the way the existing `POST` does it.
- No N+1: the list fetches assessments and assignees for the page in one query each and joins in memory.

## Decisions taken this session (flag to Jafar)

- **Auth gate.** No `requests.*` permission keys are seeded yet, so these routes use `requireOrganization`,
  matching the existing `POST /api/requests`. RLS is still the real boundary. Seeding a request permission
  matrix like `20260816110000_client_property_permissions.sql` is a separate decision.
- **Index.** `requests` had no `created_at` index, so the cursor sort had nothing to ride. Added
  `requests_organization_created_idx (organization_id, created_at desc, id desc)`.
- **Overview counts.** 1d's Overview card needs status counts across the whole list, which is not one of
  the four routes in this slice. Not built here — decide before 1d starts.

## Checklist

- [x] Migration: cursor indexes (`20260818140000_request_list_cursor_indexes.sql`, applied)
- [x] `GET /api/requests`
- [x] `GET` + `PATCH /api/requests/[id]`
- [x] `PUT` + `DELETE /api/requests/[id]/assessment`
- [x] `POST /api/requests/[id]/assessment/complete`
- [x] Zod schemas for the assessment writes and the request patch
- [x] `npm run check` clean, prettier clean, 457 unit tests pass
- [x] performance-review run on the migration and on the routes

## Not covered by this slice — read before 1d

- No route specs. The existing request routes had none either; the derived-status rules are unit tested
  in `src/lib/server/requests/status.spec.ts` instead.
- No rate limiting, matching every other authenticated CRUD route in the app.
- Nothing has exercised these routes against real data yet — the tables are empty. The first real check
  happens when 1d wires the list page.

## Completion gate

Every route validates with Zod, returns the fixed error shape, is cursor-paginated where it lists, and
has passed a performance review.

## Source pointers

- `.claude/skills/jobber/jobber-02-requests-leads.md` §1.2, §2.1, §4.1, §4.2 — statuses, schedule model, columns.
- `supabase/migrations/20260818100000_assessment_schema.sql` — the tables this layer writes.
- `src/routes/api/clients/[id]/+server.ts` — detail/patch shape to follow.
