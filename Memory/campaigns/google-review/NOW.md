# Google review — NOW

Goal: build the Google review campaign in `docs/google-review-campaign-owner-brief.md`.
Active part: 5B — Private feedback tab + recovery + owner alerts (5A built and committed 2026-09-26).

State 2026-09-26: Parts 1–4 done. 5A built and verified in a real browser as owner, office and sales (Playwright
script pattern: log in on localhost:5173, wait 2.5 s for the login form to hydrate, never wait for networkidle).
5A files: `src/routes/(app)/reviews/+page.svelte`, `src/lib/reviews/workspace.ts`, `src/routes/api/reviews/workspace/`,
two migrations `20260926190000/190100` (both applied), menu in `AppShell.svelte` + `(app)/+layout.svelte`.

Left over from 5A (small, do first): click-test "Cancel request" on the page; check dark mode and a field-member
login (should have no Reviews item); show request activity in client + job history (today only the request panel);
a back link from `/reviews/settings` to `/reviews`.

Next action — 5B: add the Private feedback tab (`Tabs`, URL `?tab=`, hidden unless `reviews.feedback`): list of
`review_feedback` with customer answers, rating, client link, contact shortcut; move an item through New →
Contacting customer → Resolved → Closed (`PATCH /api/reviews/feedback/[id]`, Zod, `reviews.feedback`); bell alert
to owners/admins only via `team_notifications` when feedback is submitted (see `src/lib/server/team/inquiry-alerts.ts`
and `src/lib/team/notifications.ts` for the pattern); new-feedback count already returned by `review_request_counts`.
Load skills: design, svelte, supabase-postgres-best-practices, performance-review. Product: brief §Private-feedback
recovery. Present nothing new to Jafar unless a decision arises; the 5B shape is already approved.

Facts: Raad has no SMS number. Jafar wants the design "best, beautiful, modern, professional, easy to use".
Known unrelated: `npm run check` needs NODE_OPTIONS=--max-old-space-size=8192; 3 "union type too complex"
errors and 75 failing quote/settings unit tests predate this (a route `resolve()` helper needs an explicit
`string | null` return type to avoid a 4th). Never raise SQLSTATE 40001 for a stale edit; use P0409.
Supabase CLI is `npx supabase`.
