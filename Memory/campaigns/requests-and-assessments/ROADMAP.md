# Requests and Assessments — Roadmap

Goal approved by Jafar 2026-08-18: staff-side request intake, on-site assessment scheduling, and
assessment completion, matching Jobber. Public booking form and real Quote/Job conversion are out.

Part 1 is split into six subparts because completing it in one session would materially reduce quality.
Each subpart is independently verifiable. The parent completion gate for Part 1 is: a staff user can
create a request, find it in the list, open it, book and complete its assessment, and every layer has
passed its own performance review.

| # | Outcome | Status | Depends on | Packet | Completion gate |
| --- | --- | --- | --- | --- | --- |
| 1a | `assessments` table, assignee join table, RLS, indexes, request status constraint reduced to the six stored values | Done 2026-08-18 | — | closed | Tenant-isolation assertions pass against the remote project in a rolled-back transaction; `get_advisors` clean for the new objects |
| 1b | API routes: cursor list, detail, patch request, book/complete assessment | Done 2026-08-18 | 1a | `parts/1b-api-routes.md` | Every route validates with Zod, returns the fixed error shape, and is cursor-paginated; performance review passed |
| 1c | Shared work-object components: header, client+property summary card, facts list, `PrimaryInfoCard` | Done 2026-08-18 | — | closed | Mounted on a demo-data page and reviewed live by Jafar before any real data is wired in |
| 1d | Requests list page | Built and browser-verified 2026-08-18, awaiting Jafar's look | 1b, 1c | `parts/1d-requests-list.md` | Real requests listed with Jobber's columns and the Overview status card; verified in browser |
| 1e | Request detail page | Not started | 1b, 1c | — | Blocks edit in place and save themselves; bar handles notes/tags only; verified in browser |
| 1f | New Request page | Not started | 1b, 1c | — | A request can be created end to end; verified in browser |

Deferred out of this campaign, tracked in `Memory/deferred/INDEX.md`:
`Product & Services` and `Labor` blocks on the request, and the client detail page conversion.

Create each subpart's packet when it starts, not before.
