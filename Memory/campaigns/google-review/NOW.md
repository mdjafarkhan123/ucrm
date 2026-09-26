# Google review — NOW

Goal: build the Google review campaign in `docs/google-review-campaign-owner-brief.md`.
Active part: 4A — reminder plan for every review request. Read `parts/04-automation.md` (4A section).

Next action — in a fresh session (10-reminder ceiling approved 2026-09-26):
1. Finish the performance design verdict for 4A (performance-review design branch), then load the Postgres
   best-practices skill.
2. Build 4A: migration (per-message token table, per-message rows, due marker + claim), worker drain, settings
   "Request behavior" + timeline UI, cancel-while-pending, stop rules. Then prove it live.

Facts: Raad has no SMS number; manual email uses the default sender with `allows_manual` (automation must use
`allows_automated`). Operational review emails carry no unsubscribe link yet (suppression is honoured).

Known unrelated: `settings-business.spec.ts` expects 8 permission flags (stale). `npm run check` needs
NODE_OPTIONS=--max-old-space-size=8192; 3 "union type too complex" errors predate this. Never raise SQLSTATE
40001 for a stale edit; use P0409. Playwright vs `npm run dev`: wait ~9s first visit.
Part 2 leftover: Jafar to glance at Review settings → "Preview feedback page" while signed in.
