# Time clock

**Status:** First version built and verified 2026-10-12 (proof: `docs/research/time-clock-final-proof-2026-10-12/final-proof.md`).
Including choices 1–5 and the build order, it was approved by Jafar on 2026-10-11.

## Summary

Crew members tap **Start** when they arrive at a visit and **Stop** when they leave, and **Clock in** and
**Clock out** for their working day. Those hours appear on a **Timesheets** page for the day and the week,
and the hours spent on a visit go onto that Job's labour cost by themselves. A manager can see everyone's
hours, fix mistakes, stop a timer someone forgot, and approve the week so it cannot quietly change later.
This replaces typing hours in by hand afterwards, which is the only option today.

## Problem and audience

Today the app records hours only when someone types them into a Job's Labor section after the work is done.
Hours typed in afterwards are often guessed, forgotten or padded, so job costs are wrong. The owner also
has no single place to see who worked how long this week, which they need for payroll. Field crews use a
time clock every day, which is why the launch roadmap puts it first (roadmap Part 16).

- **Field crew:** start and stop timers on a phone, and see their own hours.
- **Owner, office or crew lead:** see, correct and approve everyone's hours before payroll.

## First version

Visit timers, day clock-in and clock-out, a Timesheets page with day and week views, corrections with a
visible history, hours that land on the Job once, a "timers only" permission for crews, weekly approval,
and Assessment timers as the last part.

## Timers

- **Visit timer.** On a visit the person can see (from the Schedule or the Job), they tap **Start** to begin
  their own timer and **Stop** to end it. Each person on a visit runs their own timer.
- **Day clock.** **Clock in** starts general time: paid time that belongs to no Job, such as travel or the
  shop. **Clock out** ends it.
- **Only one timer runs at a time.** Starting a visit timer while clocked in pauses the day clock, and the
  hours go to the visit instead. Stopping the visit timer resumes the day clock. A second visit timer
  cannot start until the first stops.
- **Clocking in is optional.** A visit timer can run without clocking in; stopping it then leaves nothing
  running. Clocking in while a visit timer runs starts the day clock when that timer stops (our
  adaptation). **Clock out** stops a running visit timer too, because the working day is over.
- **Completing a visit stops every timer running on it**, and the Stop button is not needed first. To
  restart a timer on a completed visit, the visit has to be reopened.
- **Hours belong to the day the timer started**, in the business's time zone. A timer that runs past
  midnight stays on its starting day.
- **A timer stopped in under a minute records nothing** and says so, because it was almost certainly a
  mistaken tap. (Our adaptation; Jobber's behaviour here is not documented.)
- **The running timer is visible.** The person sees which visit or "General" is running and for how long,
  wherever they are in the app. The visit's Job shows a running-clock mark in its Labor section.
- **Needs a connection.** Starting or stopping needs a signal. When a tap does not go through, the app says
  the timer did not start or stop, and the person can try again (Jafar, 2026-10-11).

## Forgotten timers

- A timer is never stopped automatically, because that would invent an end time nobody worked (Jafar,
  2026-10-11; matches Jobber).
- A timer running for more than 12 hours is flagged on Timesheets and on the person's running-timer display.
- A timer running for more than 24 hours cannot be stopped as it is. Someone who can correct that person's
  hours chooses the real end time. A crew member with "timers only" is told to ask a manager.
- A bell, email and browser reminder at 12 hours is built (Alerts, roadmap Part 12). A true phone reminder waits for the native Android and iPhone apps.

## Hours on the Job

- When a visit timer stops, the hours appear once in that Job's Labor section, and the person's current
  cost rate is copied onto them, as hand-typed hours already work. Labour cost is counted only once the
  timer stops.
- General time and Assessment time never land on a Job and have no Job cost. They count toward the person's
  daily and weekly totals.
- A closed Job's hours can still be changed only by someone who manages the team's time (the existing
  rule). Every addition, correction and removal stays in the Job's costing history.

## Timesheets page

- A **Timesheets** page in the main navigation, with **Day** and **Week** views, arrows, a date picker and
  **Today**. Times are shown in hours and minutes. The week starts on Sunday, as the Schedule's does.
- **Day view:** one row per person with their total for the day. Opening a row lists each entry: what it
  was for (a Job visit, an Assessment or General), notes, start time, end time and duration.
- **Week view:** one row per person with a total for each day and for the week. Opening a row lists the
  entries.
- **Who sees whom:** people limited to their own time see only themselves. People who manage the team's time
  see everyone and can filter to chosen people. Someone who has left still appears for weeks they worked.
  The list is everyone active who may time their own work, plus anyone with hours that week or a timer
  running.
- **Running timers:** a running timer shows beside its person but counts in the totals only once it stops.
- **Jobs the reader cannot open:** an entry on such a Job shows "Job #N" only, without its title or client,
  and is not a link; its hours still count, so totals add up.
- **Existing hours:** hours already typed into Jobs' Labor sections appear on Timesheets as Job entries.
  Hours typed there later appear too; it is one set of hours shown in two places.
- **Add entry:** pick a Job (and, optionally, its visit) or General, a date, start and end times, and
  optional notes. The duration is calculated from the times. A manager also picks the person.
- **Edit or delete an entry:** the person, what it was for, date, times and notes can be changed. While a
  timer is still running, only its start time and notes can be changed, and it cannot be deleted.
- **Edit history:** each entry shows who changed what, when, and the old and new values.
- **Manager actions:** clock a team member in or out, and stop a forgotten timer at the real end time.
  Stopping at a chosen time ends the working day: nothing starts again afterwards (our adaptation, built
  2026-10-12).
- **Moving hours to another person** prices them at that person's current cost rate, the way hours typed for
  them would be (our adaptation, built 2026-10-12).
- **Warnings:** an entry that overlaps another of the same person's entries, and a timer running more than
  12 hours, are flagged so they can be checked.

## Weekly approval

Jafar chose to include it on 2026-10-11, following Jobber.

- A manager opens **Approve**, chooses a cut-off date and the people to include, and approves. Every
  stopped entry up to and including that date is approved.
- A running timer is never approved. It is listed as "still running" so it can be stopped first.
- Approved entries are locked for people limited to their own time. People who manage the team's time can
  still change them; the entry shows that it is approved, and the change appears in its history.
- The lock applies wherever the entry is shown, including the Job's Labor section.
- Not approving changes nothing else: unapproved hours still count on Job costs.

## Assessment timers

Jafar chose to include them as the last build part on 2026-10-11, following Jobber.

- On an Assessment scheduled for today, a person taps **Start** and **Stop**, like a visit timer. Jobber
  allows Assessment timers only on the current date.
- The time appears on the Timesheets page against the Assessment's Request, pauses the day clock like a
  visit timer, and has no Job cost.

## Permissions

| Permission                                 | Can do                                                                                   |
| ------------------------------------------ | ---------------------------------------------------------------------------------------- |
| Start and stop their own timers (new)      | Own timers and day clock, and see own Timesheets; cannot add, change or delete any hours |
| Record and change their own hours          | The above, plus add and correct own entries until they are approved                      |
| Record and change anyone's hours           | All of the above for everyone, the manager actions, approval, and changing approved hours |

- The Field preset moves to "Start and stop their own timers", like Jobber's Field crew (Jafar,
  2026-10-11). Existing field members can no longer type or change their own hours; the office corrects
  them. Businesses' custom roles keep what they were given.
- Built 2026-10-12: every role that records its own hours also holds the timers rung, so Team access reads
  as a ladder. A member individually denied "their own hours" is denied the timers rung too, so nobody gains
  timers they did not have. The accountant's time report still needs "Record and change their own hours"
  (our adaptation): a timers-only crew member reads their hours on Timesheets.

## Success checks

- A crew member on a phone starts a timer on today's visit, stops it 40 minutes later → the Job's Labor
  section shows one 40-minute entry at their rate, and their Timesheets day shows the same 40 minutes.
- A crew member clocks in at 8:00, starts a visit at 9:00, stops it at 11:00, clocks out at 12:00 → the day
  shows 2 hours General and 2 hours on the visit, a 4-hour total, with no overlap.
- Pressing Stop twice, or on two devices, still records the hours once.
- A crew member completes a visit with its timer running → the timer stops and the hours land once.
- A crew member left their timer running overnight → the manager sees the warning, stops it at 5:30 pm the
  day before, and the history shows who did it.
- A "timers only" crew member can start and stop, but cannot add or change hours, on screen or through the
  `/api` routes.
- A manager approves last week → the crew member can no longer change those entries; the manager still can,
  and the history records it.
- A crew member without "anyone's hours" cannot see or change a teammate's entries, including through the
  `/api` routes.
- The week view's speed is measured with the performance review on a 15-person team's full week of
  entries before the campaign closes.

## Assumptions

- Crews use the web app on their phones; no separate phone app is planned — confirmed by the current
  product.
- The Schedule's week starts on Sunday (`src/lib/schedule/filters.ts`) — confirmed 2026-10-11.

## Still unclear

Nothing for the first version.

## Not doing

- Working without a signal — later (Jafar, 2026-10-11): taps saved on the phone would let anyone change the
  time they claim to have started.
- GPS location trails and location-triggered (geofenced) timers — they need a native phone app running in
  the background and raise privacy questions. Jobber puts them on higher plans.
- Breaks, drive and office time labels, and clocking in a whole crew at once — Jobber Plus features for
  larger teams.
- Undoing an approval — managers can change approved entries instead. Jobber's help does not document an
  undo either.
- Payroll (marking hours paid, Gusto or QuickBooks sync) and overtime rules — Jobber does not calculate
  overtime either; payroll comes with integrations later.
- A separate timesheet report under Reports — Reports is roadmap Part 13. The existing accountant time
  report keeps working for Job hours.

## Sources and design decisions

- [Jobber: Timesheets](https://help.getjobber.com/hc/en-us/articles/115009543028-Timesheets) — Day and Week
  views, entry fields, running-timer edit limits, edit history, Labor and costing rules.
- [Jobber: Timers and Timesheets in the app](https://help.getjobber.com/hc/en-us/articles/7447924360855-Timers-and-Timesheets-in-the-Jobber-App)
  — clock in and out, one timer at a time, the visit timer pausing general time, completing a visit,
  overnight timers, Assessment timers on the current date, and the three permission rungs.
- [Jobber: Approving Timesheets](https://help.getjobber.com/hc/en-us/articles/115009614247-Approving-Time-Sheets)
  — approving up to a chosen date, and the lock with its permission exception.
- `.claude/skills/jobber/jobber-04-jobs-visits-scheduling.md` § Permissions — Jobber's Field crew preset.
- `docs/research/jobber-feature-catalog-2026-10-08.md` § 2.5 — which plan each time feature belongs to.
- Existing behaviour: `job_time_entries` and `add_job_time_entry` in
  `supabase/migrations/20260101000000_baseline_structure.sql`, and `src/lib/components/jobs/JobLaborSection.svelte`.
