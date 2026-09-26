# Google review — NOW

Goal: build the Google review campaign in `docs/google-review-campaign-owner-brief.md`.
Active part: 4A — reminder plan. Read `parts/04-automation.md` (4A section).

State 2026-09-26: 4A built and committed (migration `20260926120000_review_request_reminders.sql` applied;
drain `src/lib/server/reviews/reminders.ts` rides the automation wake; settings "Request behavior" timeline in
`ReviewRequestPlanEditor.svelte`; panel shows plan + reminder progress). DB path proven in a rolled-back
transaction (create, idempotent retry, not-due, waits for first send, manual-only sender stops it, automated
sender sends slot 1 with its own link, Google click stops + cancels waiting reminder). Unit tests + svelte-check pass.

Next action:
1. Browser-verify as owner: `/reviews/settings` → Request behavior (add/remove/edit wording, warnings, save,
   reload, stale-save conflict), then the Request a review panel note + recent-requests reminder lines;
   field member still limited to own jobs.
2. Run the performance verification branch for the reminder drain (claim EXPLAIN on
   `review_requests_next_reminder_idx`), then close 4A and start 4B.

Facts: Raad's only email sender is manual-only (`allows_automated` false), so its email reminders stop with
"not set up to send automatic messages"; Raad has no SMS number. Ask Jafar before changing Raad's sender.
Known unrelated: `npm run check` needs NODE_OPTIONS=--max-old-space-size=8192; 3 "union type too complex"
errors predate this. Never raise SQLSTATE 40001 for a stale edit; use P0409.
