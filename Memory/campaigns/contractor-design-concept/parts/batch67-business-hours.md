# Batch 67 · Business hours

**Board:** `concept.pen` → "Concept · Batch 67 · Business hours · Options A and B · 2026-10-22" (`a554I`), right
of Batch 66. **Waiting for Jafar** to pick. Piece: `(app)/settings/business-hours` (list-6a). Opened from Business
hours on the approved Settings home (Batch 63 A). Reuses the approved week planner (Batch 39 B, `DhRBV`,
`inputs.md` § Weekly hours) unchanged.

## Research (what to show, not the look)

- Google Business Profile: open now / closes at, hours in the business's time zone, closed days.
- Jobber, Housecall Pro: business hours drive online booking times.
- Intercom office hours: replies and messages wait for opening time.
- What hours change in our app today (code): booking forms' times (`form_booking_day_bands`), Schedule shades
  closed days and warns when moving work outside hours (`ScheduleMonth`, `MoveConfirm`), automatic thank-you
  emails wait for business hours (`automation/worker.ts`).

## Live behaviour kept

Week planner (open/closed, open 24 hours, up to three periods); By appointment only; three starting points when
nothing is set; Save and Cancel; leave-page warning; staff read-only with last editor; someone-saved-first.

## Options

- **A · Week planner page** (`ViXZ0`, dark `lNjGx`): improved live page. A slim bar: Weekly hours / By
  appointment only switch, "Right now" (Open now pill, closes at), time zone with Change (to Business profile);
  the planner across the page; "What these hours change" card (Online booking, Schedule, Automatic messages);
  floating save bar.
- **B · Week at a glance** (`RPXDk`, dark `CTEEK`; editing `Y8KYw`): new concept, read first. "Your week" as a
  calendar (Sun–Sat, 6 AM–8 PM, today marked, now line, closed days grey, legend with time zone) with Edit hours;
  side column: Right now card (Open now, closes in, day bar, time zone, next closed day) and What these hours
  change. Edit hours opens the planner across the page (green edge, mode switch in its header, footer with
  Cancel and Save hours).

## For the builder / Jafar

- Display-only additions (no new data): open now / closes at in the business time zone, weekly total, next
  closed day, what-it-changes copy. The counts ("3 forms take bookings", "2 automations wait") need a small
  read the page doesn't do today.
- Not drawn (idea only, needs Jafar's yes and new data): holiday / special closed days, like Google's special hours.
- After approval: draw Not set yet (three starting points), By appointment only, staff view, someone saved first.
