# Part 4 — Reminders + automatic ask

Product truth: brief § "How the automation is set up" (owner decisions 2026-09-26, following HighLevel).
Split: **4A reminder plan** (every request, manual included), then **4B automatic ask** (Automations recipe).

## 4A — Reminder plan (build first)

Behavior:
- Reviews settings gains "Request behavior": first message timing (default Right away; or a delay in hours/days),
  reminders (default 2: 3 and 5 days after the first message), and the text of every message per channel and
  style (reminder copy gets its own starting text). Shown as a readable timeline; warn (don't block) when the
  pattern looks pushy (e.g. more than 3 reminders or gaps under 2 days). Technical ceiling: 10 reminders
  (needs Jafar's OK — brief says "no fixed maximum").
- Every request (manual now, automatic in 4B) follows the plan. Manual "Send now/Schedule" sets the first
  message; reminders count from when the first message actually sent.
- Stops (brief § When the sequence stops): Google click, private feedback submitted, cancel, any message of the
  request failed/bounced/STOP/unsubscribed, client deleted, job reopened or cancelled. Cancel works while any
  message is still pending (today it only works before the first send).

Chosen engineering shape (performance design verdict to finish in the build session):
- Reminders are queued lazily, one at a time (automation contract: never pre-expand; recheck consent, balance,
  sender and current copy at send). Pre-queuing all reminders was rejected: it would hold SMS credit for days
  and freeze the text.
- The raw link token is never stored (only `token_hash`), so each message mints its own link, like the quote
  follow-up worker (`QuoteAccessLink` in `src/lib/server/automation/worker.ts`). Needs a per-message token
  table that the feedback page resolves (`private.live_review_request` today reads `review_requests.token_hash`).
- Due reminders: a `next_send_at`-style due marker per request, claimed with `FOR UPDATE SKIP LOCKED`, a
  per-organization cap, and a lease, drained by the existing automation worker process and wake (no new service,
  no new cron). Queueing reuses Part 3's SMS/email queue code in `create_review_request`.
- Status/history: one row per message (request, slot, delivery intent); the request status reads slot 0 plus
  the stop reason.

Acceptance: manual request → first message → reminder queued at +3 days local time → clicking Google or
submitting feedback cancels the pending reminder; a failed message stops the rest; settings timeline saves
with revision conflict protection; field member still limited to own jobs.

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
