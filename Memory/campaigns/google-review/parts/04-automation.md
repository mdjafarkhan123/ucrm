# Part 4 — Reminders + automatic ask

Product truth: brief § "How the automation is set up" (owner decisions 2026-09-26, following HighLevel).
Split: **4A reminder plan** (every request, manual included), then **4B automatic ask** (Automations recipe).

## 4A — Done 2026-09-26 (see ROADMAP). Facts 4B relies on

- Every request follows the saved plan; reminders are queued lazily by `claim_review_reminders` /
  `send_review_reminder` (drain `src/lib/server/reviews/reminders.ts`, rides the automation wake). An automatic
  request must go through the same `create_review_request` so it gets the same plan and stops.

## 4B — Automatic ask (after 4A)

- New trigger `job.work_completed` (subject `job`): emitted in the job-close transaction when every Visit is
  completed (a close that removed unfinished Visits never emits), and on each completed Visit of a recurring job
  with the completed-visit count. Trigger config: recurring "after every N completed visits", off by default.
- New action `action.send_review_request` (no copy in the recipe; content comes from Reviews settings, as
  HighLevel's action points to Reputation Settings). Preset "Ask for a Google review". Cannot activate without a
  saved Google link.
- Action-time rechecks: job still eligible, a usable main contact for the chosen channel, Google link present,
  no automatic request to this client in 6 months (manual requests don't count). Skips show a plain reason.
- Automatic email uses a sender with `allows_automated`.
- Engine touch points: `intake_automation_events`, `advance_automation_work_item`, a job stop-outcome function,
  worker effect, `catalog.ts`, `presets.ts`, and definition validation.
