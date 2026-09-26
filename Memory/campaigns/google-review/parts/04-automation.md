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

Builder half done `0cbdf66` (browser-checked on Raad: recurring control, SMS/Email warnings, draft save).
Perf verified 2026-09-26 (rolled back, single samples, no capacity claim): recipe probe, six-month query and
visit count all use their indexes; `complete_job_visit` ~14 ms without a recipe, ~24 ms with one; intake of
the one event ~21 ms. Batch intake of many job events not measured.

Remaining (needs Jafar's yes — it switches a real automation on in Raad):
- Live proof: activate draft recipe `34803b3e-…` ("Ask for a Google review", Raad, Email, every 4 visits),
  close a one-off job, run the wake; expect a "Not sent" request (Raad has no automatic sender) with its reason
  in the job's Request a review panel and "Automatic email" in the line. Then pause/archive it.
