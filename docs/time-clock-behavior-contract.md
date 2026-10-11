# Time clock

**Status:** Planning — first-version behaviour drafted 2026-10-11 from Jobber; five choices wait for Jafar
(see Still unclear).

## Summary

Crew members tap **Start** when they arrive at a visit and **Stop** when they leave, and **Clock in** and
**Clock out** for their working day. Those hours appear on a **Timesheets** page for the day and the week,
and the hours spent on a visit go onto that Job's labour cost by themselves. A manager can see everyone's
hours, fix mistakes, and stop a timer someone forgot. This replaces typing hours in by hand afterwards,
which is the only option today.

## Problem and audience

Today the app records hours only when someone types them into a Job's Labor section after the work is done.
Hours typed in afterwards are often guessed, forgotten or padded, so job costs are wrong. The owner also
has no single place to see who worked how long this week, which they need for payroll. Field crews use a
time clock every day, which is why the launch roadmap puts it first (roadmap Part 16).

- **Field crew:** start and stop timers on a phone, and see their own hours.
- **Owner, office or crew lead:** see and correct everyone's hours, and check the week before payroll.

## First version

Visit timers, day clock-in and clock-out, a Timesheets page with day and week views, corrections with a
visible history, and hours that land on the Job once. Choices 1–5 in **Still unclear** decide whether a
"timers only" crew permission, weekly approval and Assessment timers are included.

## Timers

- **Visit timer.** On a visit (from the Schedule or the Job), a person taps **Start** to begin their own
  timer and **Stop** to end it. Each person on a visit runs their own timer.
- **Day clock.** **Clock in** starts general time: paid time that belongs to no Job, such as travel or the
  shop. **Clock out** ends it.
- **Only one timer runs at a time.** Starting a visit timer while clocked in pauses the day clock, and the
  hours go to the visit instead. Stopping the visit timer resumes the day clock. A second visit timer
  cannot start until the first stops.
- **Completing a visit stops the timer running on it**, and the Stop button is not needed first. To restart
  a timer on a completed visit, the visit has to be reopened.
- **Hours belong to the day the timer started**, in the business's time zone. A timer that runs past
  midnight stays on its starting day.
- **The running timer is visible.** The person sees which visit or "General" is running and for how long,
  wherever they are in the app. The visit's Job shows a running-clock mark in its Labor section.

## Hours on the Job

- When a visit timer stops, the hours appear once in that Job's Labor section, and the person's current
  cost rate is copied onto them, as hand-typed hours already work. Labour cost is counted only once the
  timer stops.
- General time never lands on a Job and has no Job cost. It counts toward the person's daily and weekly
  totals.
- A closed Job's hours can still be changed only by someone who manages the team's time (the existing
  rule). Every addition, correction and removal stays in the Job's costing history.

## Timesheets page

- A **Timesheets** page in the main navigation, with **Day** and **Week** views, arrows, a date picker and
  **Today**. Times are shown in hours and minutes.
- **Day view:** one row per person with their total for the day. Opening a row lists each entry: what it
  was for (a Job visit or General), notes, start time, end time and duration.
- **Week view:** one row per person with a total for each day and for the week. Opening a row lists the
  entries.
- **Who sees whom:** people with only their own time see only themselves. People who manage the team's time
  see everyone and can filter to chosen people. Someone who has left still appears for weeks they worked.
- **Add entry:** pick a Job visit or General, a date, start and end times, and optional notes. The duration
  is calculated from the times.
- **Edit or delete an entry:** the person, what it was for, date, times and notes can be changed. While a
  timer is still running, only its start time and notes can be changed, and it cannot be deleted.
- **Edit history:** each entry shows who changed what, when, and the old and new values.
- **Manager actions:** clock a team member in or out, and stop a timer someone forgot (choosing the real
  end time).
- **Warnings:** an entry that overlaps another of the same person's entries, and a timer that has been
  running unusually long, are flagged so they can be checked.

## Permissions

The app already has two permissions, which keep working:

| Permission | Can do |
| --- | --- |
| Record and change their own hours | Start and stop own timers, clock in and out, add and correct own entries |
| Record and change anyone's hours | All of the above for everyone, plus the manager actions |

Choice 1 below decides whether a third, lower rung is added for crews.

## Success checks

- A crew member on a phone starts a timer on today's visit, stops it 40 minutes later → the Job's Labor
  section shows one 40-minute entry at their rate, and their Timesheets day shows the same 40 minutes.
- A crew member clocks in at 8:00, starts a visit at 9:00, stops it at 11:00, clocks out at 12:00 → the day
  shows 2 hours General and 2 hours on the visit, a 4-hour total, with no overlap.
- Pressing Stop twice, or on two devices, still records the hours once.
- A crew member completes a visit with its timer running → the timer stops and the hours land once.
- A crew member left their timer running overnight → the manager sees the warning, stops it at 5:30 pm the
  day before, and the history shows who did it.
- A crew member without "anyone's hours" cannot see or change a teammate's entries, including through the
  `/api` routes.
- The week view's speed is measured with the performance review on a 15-person team's full week of
  entries before the campaign closes.

## Assumptions

- Our Schedule's week start (from the browser's language settings) is used for the Timesheets week too —
  unverified until build.
- Crews use the web app on their phones. No separate phone app is planned — confirmed by the current
  product.

## Still unclear

1. **"Timers only" for crews.** Jobber has a lowest rung, "Start and stop their own timers": the person can
   time their work but cannot type or change hours. Jobber's Field crew preset uses it. Recommendation: add
   it and move the Field preset to it, so hours come from real taps. Downside: a crew member who forgets to
   press Start must ask the office to fix it. Existing field members would lose the ability to type their
   own hours.
2. **Weekly approval.** Jobber lets a manager approve everyone's hours up to a chosen date. Approved hours
   are then locked except for people who manage the team's time. Recommendation: include it as the
   "manager's check" the roadmap asks for. Unapproved hours still count on Job costs, so owners who skip
   approval lose nothing.
3. **Forgotten timers.** Jobber never stops a timer by itself; the person or a manager stops it later.
   Recommendation: do the same, and flag long-running timers on Timesheets. Automatic clock-out would
   invent an end time nobody worked. A reminder on the phone waits for Alerts (roadmap Part 12).
4. **No phone signal.** Jobber's timers work offline and sync later. Recommendation: the first version
   needs a connection to start or stop, and says clearly when a tap did not go through; offline comes later.
   Accepting taps saved on the phone would let anyone change the time they claim to have started.
5. **Assessment timers.** Jobber also times Assessments (time spent quoting at a client's property) and
   puts it on the timesheet. Recommendation: include it as the last build part of this campaign. Until
   then, crews are clocked in for that time, so it is still paid.

## Not doing

- GPS location trails and location-triggered (geofenced) timers — they need a native phone app running in
  the background and raise privacy questions. Jobber puts them on higher plans.
- Breaks, drive and office time labels, and clocking in a whole crew at once — Jobber Plus features for
  larger teams.
- Payroll (marking hours paid, Gusto or QuickBooks sync) and overtime rules — Jobber does not calculate
  overtime either; payroll comes with integrations later.
- A separate timesheet report under Reports — Reports is roadmap Part 13. The existing accountant time
  report keeps working for Job hours.

## Sources and design decisions

- [Jobber: Timesheets](https://help.getjobber.com/hc/en-us/articles/115009543028-Timesheets) — Day and Week
  views, entry fields, running-timer edit limits, edit history, Labor and costing rules.
- [Jobber: Timers and Timesheets in the app](https://help.getjobber.com/hc/en-us/articles/7447924360855-Timers-and-Timesheets-in-the-Jobber-App)
  — clock in and out, one timer at a time, the visit timer pausing general time, completing a visit, and
  overnight timers.
- [Jobber: Approving Timesheets](https://help.getjobber.com/hc/en-us/articles/115009614247-Approving-Time-Sheets)
  — approving up to a chosen date, and the lock with its permission exception.
- `.claude/skills/jobber/jobber-04-jobs-visits-scheduling.md` § Permissions — Jobber's three time-tracking
  permission rungs and the Field crew preset.
- `docs/research/jobber-feature-catalog-2026-10-08.md` § 2.5 — which plan each time feature belongs to.
- Existing behaviour: `job_time_entries` and `add_job_time_entry` in
  `supabase/migrations/20260101000000_baseline_structure.sql`, and `src/lib/components/jobs/JobLaborSection.svelte`.
