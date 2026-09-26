# Part 4 — Reminders + automatic ask

Product truth: brief § "How the automation is set up" (owner decisions 2026-09-26, following HighLevel).
Split: **4A reminder plan** (every request, manual included), then **4B automatic ask** (Automations recipe).

## 4A — Done 2026-09-26 (see ROADMAP). Facts 4B relies on

- Every request follows the saved plan; reminders are queued lazily by `claim_review_reminders` /
  `send_review_reminder` (drain `src/lib/server/reviews/reminders.ts`, rides the automation wake). An automatic
  request must go through the same `create_review_request` so it gets the same plan and stops.

## 4B — Automatic ask (engine half done `ea9840c`)

Built: event `job.work_completed` via trigger on `job_events` (one-off `job_closed`, recurring `visit_completed`),
emitted only while the org has an active recipe on it. `close_job` already refuses unfinished visits, so a close
is never a cancellation here. Trigger config `recurring_every_visits` (absent = off). Action
`action.send_review_request` config `{channel}`; effect = `automation_review_request_draft` +
`perform_automation_review_request_effect` (six-month rule counts only automatic requests that sent a message;
per-client advisory lock). Skips create a visible request: status `not_sent`, stop_reason `not_sent` /
`no_contact` / `recently_asked` + detail. Activate route refuses without a Google link (resume does not; the
effect then records "Add your Google review link").

Remaining:
- Builder: trigger control "Recurring jobs: don't ask / after every N completed visits" (1–52); a
  `ReviewRequestActionEditor` reusing `ComposerChannelMenu` (SMS/Email, not-ready reason + setup link,
  readiness from `loadReviewChannelReadiness` via a new automation-permission GET, plus "wording and reminders
  come from Review settings" link and a missing-Google-link warning); "Add a review request" button; step icon;
  always-on stop description currently says "website inquiries" — make it subject-neutral.
- Labels for `not_sent`, `recently_asked` ("Already asked automatically in the last 6 months"), and origin
  "Automatic" in `src/lib/reviews/requests.ts` and the panel history.
- Worker spec case; SummaryRail, RecipeDetailView, activation-preview step labels.
- Performance verification: EXPLAIN the recipe probe (`automation_recipes_active_trigger_idx`) and the cooldown
  query (`review_requests_client_idx`); time `complete_job_visit` with an active recipe (rolled back); intake of
  a batch of job events. Capacity not established.
