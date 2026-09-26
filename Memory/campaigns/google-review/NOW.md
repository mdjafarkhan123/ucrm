# Google review — NOW

Goal: build the Google review campaign in `docs/google-review-campaign-owner-brief.md`.
Active part: 4B — automatic ask. Read `parts/04-automation.md` (4B section).

State 2026-09-26: 4B engine (`ea9840c`) and builder (`0cbdf66`) committed; performance checks done.

Next action:
1. Ask Jafar to approve the live proof on Raad (packet § Remaining), then run it and browser-check the
   "Not sent" / "Automatic email" history line.
2. Close 4B: reduce the packet to its roadmap entry, pick the next part from ROADMAP.md.

Facts: Raad's only email sender is manual-only (`allows_automated` false), so automatic email refuses with
"not set up to send automatic messages"; Raad has no SMS number. Ask Jafar before changing Raad's sender.
Known unrelated: `npm run check` needs NODE_OPTIONS=--max-old-space-size=8192; 3 "union type too complex"
errors and 75 failing quote/settings unit tests predate this. Never raise SQLSTATE 40001 for a stale edit;
use P0409. Supabase CLI is `npx supabase`.
