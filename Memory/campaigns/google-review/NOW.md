# Google review — NOW

Goal: build the Google review campaign in `docs/google-review-campaign-owner-brief.md`.
Active part: 4B — automatic ask. Read `parts/04-automation.md` (4B section).

State 2026-09-26: 4B engine (`ea9840c`) and builder (`0cbdf66`) committed; performance checks done.

Next action:
1. Live proof (no-sender case) PASSED 2026-09-26: job #23 closed -> automatic request "Not sent" with reason,
   seen on screen in the job's Request a review panel. Recipe `34803b3e` is still ACTIVE in Raad.
2. GHL sender rule shipped (`c2a1904`). Jobs #23 and #14 are used up (one ask per one-off job; both recorded
   "Not sent" because the operational-email-ses session removed Raad's Office sender at 04:24 for its step 5).
   Wait until that campaign recreates Raad's sender (check `communication_email_senders`: enabled, default,
   allows_automated). Then finish a fresh one-off job whose client email is Jafar's (#14's client
   e10eed2b has dev.jafarkhan+part8@gmail.com; add a new job for it), check the request shows sent and the
   email arrives, then pause recipe `34803b3e`. Agent needs Jafar in manual mode to send real email.
3. Close 4B: reduce the packet to its roadmap entry, pick the next part from ROADMAP.md.

Facts: Raad has no SMS number.
Known unrelated: `npm run check` needs NODE_OPTIONS=--max-old-space-size=8192; 3 "union type too complex"
errors and 75 failing quote/settings unit tests predate this. Never raise SQLSTATE 40001 for a stale edit;
use P0409. Supabase CLI is `npx supabase`.
