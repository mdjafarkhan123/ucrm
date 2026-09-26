# Google review — NOW

Goal: build the Google review campaign in `docs/google-review-campaign-owner-brief.md`.
Active part: 5B — live checks done 2026-09-26. One gap blocks closing Part 5; it needs Jafar's answer.

Verified live (Raad LTD, real browser): scheduling a request on job #2 then cancelling it writes
`review.requested` and `review.cancelled` to `activity_events` for both client and job, and both show in the
job's History panel. The bell alert row opens `/reviews?tab=feedback`. The office role sees the tab and its
contents. Fixed and committed `74af3495`: a Reviews tab click left the panel empty because `page.url` does not
follow `replaceState`; the open tab now lives in page state.

BLOCKER — ask Jafar before closing Part 5: the brief's "same request activity appears in the client history" has
nowhere to appear. `src/routes/(app)/clients/[id=uuid]/+page.svelte` renders no activity feed (tabs are Details
and Communication; `ActivityFeed.svelte` is used only on the quote and request pages), so the `entity_type =
'client'` rows are invisible. Options put to him: add a client History rail card or tab mirroring the job one, or
leave the rows until the Clients area grows its own history. Then close Part 5 and start Part 6.

Also raised, not acted on, all outside this campaign: the same stale-`page.url` tab pattern in
`clients/[id=uuid]`, `marketing`, `marketing/campaigns/[id]`, `jafar/*` and two components; the client page's
"Work overview" and "Client schedule" are hardcoded placeholders; the office role cannot load client
communication history; the insert summary says "sent" even when the request is only scheduled.

Live test data to delete when Part 5 closes (Raad LTD): requests `f251b5a8…` and `572757f9…` (tokens
`UCRMTEST5B` + 32×`a` + `1`/`2`, with private feedback); `814797d9…` (job #2, created and cancelled this
session) plus its 4 `activity_events` rows; and the bell alerts.

Facts: Raad has no SMS number. Jafar wants the design "best, beautiful, modern, professional, easy to use".
Known unrelated: `npm run check` needs NODE_OPTIONS=--max-old-space-size=8192; 3 "union type too complex" errors
and 75 failing quote/settings unit tests predate this. Never raise SQLSTATE 40001 for a stale edit; use P0409.
Supabase CLI is `npx supabase`. Another agent owns the uncommitted AGENTS.md/CLAUDE.md/communications files.
