# Google review — NOW

Goal: build the Google review campaign in `docs/google-review-campaign-owner-brief.md`.
Active part: 5B — built and committed 2026-09-26; a few live checks remain before Part 5 closes, then Part 6.

Done in 5B: Private feedback tab (`src/lib/components/reviews/ReviewFeedbackPanel.svelte`, `src/lib/reviews/feedback.ts`,
`/api/reviews/workspace/feedback`, `PATCH /api/reviews/feedback/[id=uuid]`), bell alert to owners/admins (opens
`/reviews?tab=feedback`), review milestones in client + job history (`ActivityFeed.svelte` icons; histories refresh
after send/cancel). Both migrations applied. Not built by design: assigning an item to a person (approved 5B shape
had status only; the brief's "assign" is open — ask Jafar if he wants it).

Next action (small, do first, in a real browser — script pattern: log in on localhost:5173, wait 2.5 s for the
login form, never wait for networkidle):
1. Prove the history trigger: create a request that is scheduled days ahead (POST `/api/reviews/requests` as owner
   returned no new row last time — check the response body; use the UI "Request a review" on Raad job #1 / client
   Riverbend Family Diner if the API body is wrong), then click "Cancel request" on `/reviews`, and confirm
   `review.requested` and `review.cancelled` show in the client's Activity and the job's history.
2. Click-test the bell alert row (should open the Private feedback tab); check office-role login sees the tab.
Then close Part 5 in the roadmap and start Part 6 (live verification).

Left over on the live database (Raad LTD, test data I made): two test review requests `f251b5a8…` and
`572757f9…` (tokens `UCRMTEST5B` + 32×`a` + `1`/`2`) with private feedback (one now "Contacting customer"), and
4 bell alerts. Delete them when Part 5 closes.

Facts: Raad has no SMS number. Jafar wants the design "best, beautiful, modern, professional, easy to use".
Known unrelated: `npm run check` needs NODE_OPTIONS=--max-old-space-size=8192; 3 "union type too complex"
errors and 75 failing quote/settings unit tests predate this (a route `resolve()` helper needs an explicit
`string | null` return type to avoid a 4th). Never raise SQLSTATE 40001 for a stale edit; use P0409.
Supabase CLI is `npx supabase`. Uncommitted `AGENTS.md`, `CLAUDE.md`, communications page files are another task's.
