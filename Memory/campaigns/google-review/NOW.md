# Google review — NOW

Goal: build the Google review campaign in `docs/google-review-campaign-owner-brief.md`.
Active part: 4B — automatic ask. Read `parts/04-automation.md` (4B section).

State 2026-09-26: 4B engine (`ea9840c`) and builder (`0cbdf66`) committed; performance checks done.

Next action:
1. Live proof (no-sender case) PASSED 2026-09-26: job #23 closed -> automatic request "Not sent" with reason,
   seen on screen in the job's Request a review panel. Recipe `34803b3e` is still ACTIVE in Raad.
2. Jafar approved the GHL rule: verified email senders allow automations by default (form default now on).
   Waiting on Jafar to tick "Allow automations to use this sender" on Raad's Office sender (agent was blocked).
   Then re-run the proof so a real review email reaches dev.jafarkhan+part8@gmail.com (job #23 can be reopened
   and finished again, or use another one-off job), then pause the recipe.
3. Close 4B: reduce the packet to its roadmap entry, pick the next part from ROADMAP.md.

Facts: Raad has no SMS number.
Known unrelated: `npm run check` needs NODE_OPTIONS=--max-old-space-size=8192; 3 "union type too complex"
errors and 75 failing quote/settings unit tests predate this. Never raise SQLSTATE 40001 for a stale edit;
use P0409. Supabase CLI is `npx supabase`.
