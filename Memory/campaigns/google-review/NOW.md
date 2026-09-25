# Google review — NOW

Goal: build the Google review campaign in `docs/google-review-campaign-owner-brief.md`.
Active part: 2 — Customer feedback page (ROADMAP.md entry 2). Not started.

Next action: plan Part 2 from the brief (research + grilling where behavior is open), get Jafar's approval,
then build. Part 1 settings live in `review_settings` / `src/lib/reviews/settings.ts`.

Known unrelated: `settings-business.spec.ts` expects 8 permission flags; the API already sent 11 (stale test).
`npm run check` needs NODE_OPTIONS=--max-old-space-size=8192; its 3 "union type too complex" errors predate
this campaign. Never raise SQLSTATE 40001 for a stale edit: PostgREST retries it forever; use P0409.
Five older baseline functions still raise 40001 (limit exceptions, member identity cleanup x2, website chat
widget update + token rotation) — reported to Jafar 2026-09-25, not owned here.
