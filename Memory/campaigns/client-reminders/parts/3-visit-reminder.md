# 3 — Visit reminder

**Campaign:** client-reminders · **Plan:** `docs/client-reminders-behavior-contract.md` § Visit and assessment reminders, § Customer messages: shared rules
**Code:** worktree `/tmp/ucrm-visit-reminder`, branch `claude-client-reminders-visit-reminder`
**Done when:** A visit for tomorrow 9 am sends one reminder on time; moving it moves the reminder; cancelling it sends nothing.

## Design (technical, chosen 2026-10-09)

- Reminders are found by a scan each automation wake (the worker already wakes every minute), not by booking
  events: the reminder time is computed from the visit's live date and time, so a move needs no bookkeeping, and
  turning the automation on covers visits already booked (Jobber computes reminders at send time).
- New trigger `appointment.reminder_due` (subject `appointment`; database subject types `job_visit` and
  `assessment`). Trigger config holds the timing: `{ mode: 'before', amount, unit: hours|days }` (1 hour–7 days)
  or `{ mode: 'fixed_time', days_before, time }`. A visit with no set time: 9 am, days-before rounded up to 1.
- `public.emit_due_appointment_reminders(limit)` runs first in each wake: per active recipe, visits and
  assessments whose reminder time has arrived, start still ahead, reminder time after both when the visit was
  last scheduled (new `schedule_set_at` column) and the recipe version's `activated_at`. Emits one event per
  visit and recipe (`source_event_id` derived from both, so never twice); intake checks `payload.recipe_id`.
- Advance stops when the visit is gone, completed, its job closed, its start passed, the client was removed, or
  the client's `appointment_reminders` switch is off. New action `action.send_appointment_email` with variables
  customer, business, date, time, address; its effect enqueues through the Communications outbox (model:
  `private.enqueue_automation_inquiry_email`), logical send key per enrollment.
- Preset "Visit reminder", 1 day before. Client switch shows "Not sending — turn it on in Automations".

## Steps

- [ ] Migration written in the worktree
- [ ] Catalog, validator, worker, preset, email variables, builder timing editor
- [ ] Client switch status in Communication settings
- [ ] Unit tests
- [ ] Apply migration (needs the `migrations`/`remote-db` areas — held by Part 2's Codex session on 2026-10-09)
- [ ] Prove on the live app; merge to `main`; remove worktree

## Next

Write the migration in the worktree.
