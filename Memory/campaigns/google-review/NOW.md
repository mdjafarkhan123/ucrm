# Google review — NOW

Goal: build the Google review campaign in `docs/google-review-campaign-owner-brief.md`.
Active part: 4B — automatic ask. Read `parts/04-automation.md` (4B section).

State 2026-09-26: 4A closed (`a4fbbc5`, `7953db8`). Nothing of 4B built yet.

Next action:
1. Run the performance-review design branch for 4B (new `job.work_completed` trigger fan-out on job close and
   recurring visit completion; 6-month per-client check), then build 4B per the packet.
2. Browser-verify: recipe preset can't activate without a Google link; a closed job creates an automatic
   request with a plain skip reason when ineligible.

Facts: Raad's only email sender is manual-only (`allows_automated` false), so automatic email refuses with
"not set up to send automatic messages"; Raad has no SMS number. Ask Jafar before changing Raad's sender.
Known unrelated: `npm run check` needs NODE_OPTIONS=--max-old-space-size=8192; 3 "union type too complex"
errors predate this. Never raise SQLSTATE 40001 for a stale edit; use P0409.
