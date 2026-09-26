# Google review — NOW

Goal: build the Google review campaign in `docs/google-review-campaign-owner-brief.md`.
Active part: 6 — Live verification. Part 5 closed 2026-09-26.

Part 5 closed this session: the `review.requested` / `review.cancelled` trigger proven end to end in a real
browser (scheduled a request on Raad job #2, cancelled it, both rows landed for client and job and both show
in the panels); the bell alert row opens `/reviews?tab=feedback`; the office role sees the Private feedback
tab and its contents. Two fixes committed: `74af3495` (a Reviews tab click left its panel empty — `page.url`
does not follow `replaceState`, so the open tab now lives in page state) and `088123cd` (the client page had
no history surface at all, so it gained the work records' History panel, reusing `ActivityFeed`).

Next action — Part 6, live verification, needs Jafar present for the parts only he can do:
1. Ask Jafar to delete this campaign's live test data first, or confirm I should (Raad LTD): review requests
   `f251b5a8…` and `572757f9…` (tokens `UCRMTEST5B` + 32×`a` + `1`/`2`) with their private feedback, and
   `814797d9…` (job #2, created and cancelled while testing) with its 4 `activity_events` rows and the bell
   alerts. The two fake complaints are visible on his Reviews page until then.
2. Then Part 6 proper: a real end-to-end ask on a real job to a real inbox, every role login, and the
   performance verification. Raad has no SMS number, so SMS cannot be proven live here.
3. When Part 6 passes, tell the jafar-panel campaign its review-link slice is unblocked.

Open with Jafar, not decided: the brief mentions assigning a private-feedback item to a person; the approved
5B shape had status only, so it was never built.

Facts: Jafar wants the design "best, beautiful, modern, professional, easy to use". `npm run check` needs
NODE_OPTIONS=--max-old-space-size=8192 and reports 3 pre-existing "union type too complex" errors; 75
quote/settings unit tests were already failing. Never raise SQLSTATE 40001 for a stale edit; use P0409.
Supabase CLI is `npx supabase`. Another agent is working in this same folder on Communications email setup —
leave its uncommitted files alone and stage only this campaign's.
