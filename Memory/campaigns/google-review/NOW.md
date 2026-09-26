# Google review — NOW

Goal: build the Google review campaign in `docs/google-review-campaign-owner-brief.md`.
Active part: 4B — automatic ask. Read `parts/04-automation.md` (4B section).

State 2026-09-26: 4B engine (`ea9840c`) and builder (`0cbdf66`) committed; performance checks done.

Next action:
1. Live proof (no-sender case) PASSED 2026-09-26: job #23 closed -> automatic request "Not sent" with reason,
   seen on screen in the job's Request a review panel. Recipe `34803b3e` is still ACTIVE in Raad.
2. GHL sender rule shipped (`c2a1904`); Raad's Office sender now "Manual and automated" (done in UI).
   Job #23 re-close was correctly ignored (one ask per one-off job). Remaining: finish job #14 "Panel upgrade
   quote" (same client, email dev.jafarkhan+part8@gmail.com): add visit, complete, Finish job. Agent was
   blocked from sending a real email, so Jafar clicks it. Then check the request shows sent + email arrives,
   then pause recipe `34803b3e`.
3. Close 4B: reduce the packet to its roadmap entry, pick the next part from ROADMAP.md.

Facts: Raad has no SMS number.
Known unrelated: `npm run check` needs NODE_OPTIONS=--max-old-space-size=8192; 3 "union type too complex"
errors and 75 failing quote/settings unit tests predate this. Never raise SQLSTATE 40001 for a stale edit;
use P0409. Supabase CLI is `npx supabase`.
