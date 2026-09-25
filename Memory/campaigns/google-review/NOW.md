# Google review — NOW

Goal: build the Google review campaign in `docs/google-review-campaign-owner-brief.md`.
Active part: 3 — Manual "Request a review" (ROADMAP.md entry 3). Not started.

Next action: plan Part 3 from the brief (research + grilling where behavior is open), get Jafar's approval,
then build. Part 3 creates `review_requests` rows (token from `createReviewRequestToken`, link from
`reviewRequestUrl` in `src/lib/server/reviews/requests.ts`) and adds the sending columns (channel, contact,
schedule, delivery state). The customer page `/v/[token]` already records opened / continued to Google /
feedback submitted on that row.

Open from Part 2: Jafar to glance at Review settings → "Preview feedback page" while signed in (not
browser-checked by the agent; same component as the verified public page).

Known unrelated: `settings-business.spec.ts` expects 8 permission flags; the API already sent 11 (stale test).
`npm run check` needs NODE_OPTIONS=--max-old-space-size=8192; its 3 "union type too complex" errors predate
this campaign. Never raise SQLSTATE 40001 for a stale edit: PostgREST retries it forever; use P0409.
Playwright against `npm run dev`: the page loads twice on first visit; wait ~9s before clicking.
