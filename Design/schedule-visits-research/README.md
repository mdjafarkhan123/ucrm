# Schedule / Visits research evidence

Research captured from 2026-09-01 through 2026-09-02 for the Schedule / Visits campaign. Competitor and local evidence is
indexed below. Jafar approved Schedule as a separate campaign, then required the no-guesswork research and
coverage audit to finish before any UCRM simplification. The behavior, UI/UX, release matrix and deferrals in
[`docs/schedule-behavior-contract.md`](../../docs/schedule-behavior-contract.md) are provisional hypotheses;
they will be evaluated only after the evidence register is complete.

## Jobber — verified live

The signed-in walkthrough to date is in [`jobber/`](./jobber/):

1. `01-week-schedule.png` — week grid, Anytime lane, filters, unscheduled count, map entry point
2. `02-visit-popover.png` — compact visit actions and assignment
3. `03-edit-visit-modal.png` — visit scheduling and content fields
4. `04-find-a-time.png` — availability-aware scheduling side editor
5. `05-month-schedule.png` — month planning view
6. `06-day-schedule.png` — horizontal day/crew view
7. `07-day-map.png` — map integrated into the schedule
8. `08-schedule-more-menu.png` — bulk tools, day sheets, settings
9. `09-schedule-settings.png` — layout, working hours, colors, sync, day sheets
10. `10-job-detail-visits.png` — job detail context
11. `11-job-visits-card.png` — visits card summary and actions
12. `12-job-visits-table.png` — compact visit table
13. `13-add-single-visit.png` — single visit creation
14. `14-add-multiple-visits.png` — multi-visit creation
15. `15-add-multiple-date-picker.png` — range/custom-date selection
16. `16-empty-slot-event-inline.png` — empty timed-slot chooser with the lightweight Event draft
17. `17-event-full-form-recurrence.png` — expanded Event form and recurrence selector
18. `18-request-assessment-timed-form.png` — Request creation with an embedded timed on-site Assessment
19. `19-anytime-request-inline.png` — Request selected from an Anytime cell before opening the full form
20. `20-anytime-request-full-form.png` — full Request form after the Anytime handoff inconsistency
21. `21-day-map-unassigned-anytime.png` — one unassigned Anytime Visit beside the contextual Day Map
22. `22-empty-range-drag-create.png` — unchanged Week view after a safe empty-range drag attempt
23. `23-month-cell-eight-items.png` — one month date holding eight items after a temporary write test

Month cell density, observed live on 2026-09-02 through a temporary write test that Jafar authorized. Eight
Events were created on one date and all eight were deleted afterwards; the account returned to its prior
state:

- **Jobber's month cell has no `+ N more`.** The week row grows taller to fit its busiest date and the month
  grid scrolls. Eight items on one date were all drawn, with no cap, truncation, or overflow control.
- Items inside a cell follow the documented order: Anytime first, then timed by start time.
- An Anytime item draws its title alone. A timed item draws its start time before the title. A Visit's title
  is `Client - Job title`.
- The count chip beside the date counts Visits only; Events are not counted.
- Selecting empty space inside a month cell opens the same Job/Request/Task/Event chooser with the date
  prefilled and **Anytime already checked**, so a month click creates an Anytime item by default.
- Selecting an item opens a compact popover carrying title, type, start and `Edit` / `Details`. Delete lives
  behind Details → More Actions and confirms before it removes the record.

Observed live on 2026-09-02 without saving or mutating records:

- Selecting an empty timed slot opens one inline chooser with **Job, Request, Task, and Event**; Job is the
  default. Selecting a blank Anytime cell opens the same chooser with **Anytime** already checked.
- Event is a lightweight Schedule item. Its compact draft contains title, details, date/time, Anytime,
  availability, More Options, and Save. The expanded **New Event** modal contains only title, description,
  start/end dates and times, Anytime, and recurrence. No client, address, individual assignment, privacy, or
  audience control appeared in either inspected Event draft.
- The Event recurrence selector offered Never, Daily, Weekly on the selected weekday, Monthly on the selected
  day number, and Custom schedule. No Event was saved, so existing-Event popover actions and series edit/delete
  consequences remain unavailable in this account under the no-mutation boundary.
- Selecting **Request** from a timed slot opens a full New Request page with **On-site assessment** already
  included. The clicked one-hour time range is prefilled, the account's only team member is preassigned, and
  Schedule later and Anytime are initially off.
- Selecting **Request** from an Anytime cell shows an inline date-only Assessment draft. Its **More Options**
  handoff then opened the full Request form with both Schedule later and Anytime checked and all date/time
  fields disabled. This is a directly observed inconsistency in the inspected Jobber flow, not a recommended
  behavior.
- A deliberate drag across an empty two-hour range completed without opening a chooser or draft. In this
  inspected Week view, empty-space creation was click-based; drag is used for existing scheduled items rather
  than for creating a new range.
- The demo contains one team member and one unassigned Anytime Visit. Day view placed the Visit in the
  Unassigned row and showed zero appointments for the only employee; Map showed its property pin. A real
  multi-assignee card or mixed fixed-time/Anytime route cannot be observed here without writing test data.

## Jobber — official primary-source follow-up

- [`official/jobber-events-assessments-followup.md`](./official/jobber-events-assessments-followup.md) —
  lightweight Event behavior, Request-owned Assessments, scheduling states, and empty-slot creation
- [`official/jobber-dispatch-permissions-followup.md`](./official/jobber-dispatch-permissions-followup.md) —
  multi-assignment, New/Legacy routing behavior, save boundaries, and Schedule permissions

## Autopilot CRM — verified live after fresh login

The verified captures are in [`autopilot/`](./autopilot/):

- `01-week-schedule.png` — week grid with Any Time lane and Day/Week/Month/Employees modes
- `02-create-event.png` — private event, notes, time, address, embedded location map
- `03-jobs-list.png` — job-centric technician statuses and scheduled appointment information
- `04-map-workspace.png` — separate map workspace with Jobs & Estimates list, employee/tag/date filters, and
  optional Jobs, Clients, Leads, and Employees layers
- `06-week-calendar-fresh.png` — authenticated current-week calendar and working-hour shading
- `07-day-view.png` — vertical single-day time grid
- `08-month-view.png` — month grid
- `09-employees-view.png` — horizontal day timeline with one resource row per employee
- `10-week-populated.png` — three scheduled jobs rendered as timed cards
- `11-calendar-job-drawer.png` — large job-details modal opened directly from a calendar card
- `12-drag-create-chooser.png` — selected time range followed by a Job/Event type chooser
- `13-drag-create-event-form.png` — Event form with the dragged date and time prefilled
- `14-drag-create-job-form.png` — Job form with dragged schedule and current employee prefilled
- `15-day-populated.png` — full-width cards in the vertical Day view
- `16-month-populated.png` — compact time/name rows inside a month cell
- `17-employees-populated.png` — employee resource row with jobs placed along a horizontal time axis
- `18-anytime-create-chooser.png` — date-only lane selection followed by Job/Event chooser
- `19-map-missing-scheduled-jobs.png` — Map showing zero jobs for a date where Schedule showed three

Observed behavior after the fresh login:

- Week and Day have a dedicated **Any Time** lane. Week is a seven-day vertical time grid; Day is the same
  vertical model widened to one date.
- Employees is a separate resource-timeline mode: employee rows on the left and a horizontal 24-hour axis.
- Month uses compact `time + client name` rows inside each day cell.
- Existing timed cards expose both draggable and resizable calendar handles. They were not moved because a
  drop might update the live record; Autopilot's post-drop save/notification behavior remains unverified.
- Clicking and dragging an empty time range draws a temporary block and opens a small chooser with **Job**
  and **Event** only. Task was not offered in the inspected account.
- Choosing Job opens the full Job creator with date, start/end and the current employee prefilled. It also
  exposes recurrence, additional days, private notes, scheduled SMS, lead source, tags and job type.
- Choosing Event opens a separate Event form with privacy, title, notes, all-day option, start/end and an
  optional address. Neither draft is created until its explicit Create button is pressed.
- Clicking a calendar Job opens a large modal containing client/address and Street View, schedule days,
  field techs, timer entries, notes, attachments, items, payments, totals, contracts and job metadata.
- Clicking an empty Any Time cell opens the same Job/Event chooser. In the inspected Event draft, selecting
  August 17 produced start August 16 and end August 17, so its all-day/date conversion has an apparent
  timezone or exclusive-end defect; do not copy it.
- Map is a separate navigation destination and resets its date independently of Schedule. For August 20,
  Schedule showed three jobs assigned to Austin Lb while Map reported zero Jobs & Estimates with Jobs and
  Employees layers enabled. This inconsistency is direct evidence for keeping our route map inside the
  Schedule context.

`05-map-populated.png` remains a troubleshooting capture from the earlier unstable session. Product owner
Jafar confirmed that Autopilot can draw routes for scheduled jobs, but a multi-stop route line and route-order
interaction could not be verified against the available demo data.

## Local ContractorOs reference — verified from source

The existing job-detail Visits card was reviewed at
`D:/Projects/ContractorOs/src/lib/components/jobs/JobVisitsSection.svelte`. Its strongest ideas are the
operational To be scheduled / Upcoming / Past grouping, explicit single-visit versus all-visits editing,
shared add/edit/completion flows, and a details dialog behind row selection.

Current-state captures are preserved in [`contractoros/`](./contractoros/):

- `01-current-job-visits-card.png` — current card at working viewport size
- `02-current-job-detail-full.png` — current card in its full job-detail context

The main redesign opportunity is density: avoid a large repeated Complete button on every row, show more
useful visit content in the collapsed state, give the empty state a clear action, and keep canceled/no-show
separate from genuinely completed work.

## Evidence boundary

The Jobber and Autopilot findings above are direct live observations; the two official follow-ups are
first-party Jobber research. The ContractorOs findings are direct local source review. No Jobber records were
created or changed. Existing-Event lifecycle actions, true multi-assignee placement/reassignment, Assessment
placement in the Unscheduled drawer or New Schedule optimizer, and mixed fixed-time/Anytime route write
behavior remain unavailable in the inspected account because establishing those states would require a live
write. Autopilot's existing-item drag result and multi-stop route behavior remain unknown for the same reason.

## Part 1a coverage audit — closed 2026-09-02

The audit reconciled all five checkpoint clusters against the saved live captures and current first-party
Jobber sources. Every requested branch is now either verified or explicitly unavailable:

1. **Event:** create fields, whole-team assignment, absence of an observed privacy control, recurrence entry,
   and passed/completed visual lifecycle are verified. Exact edit form, manual-complete action, More Actions,
   delete behavior, private/audience controls, and recurring-series mutation semantics remain unavailable.
2. **Assessment:** Request ownership, timed/Anytime/Unscheduled states, assignment, completion and mobile Map
   inclusion are verified. Jobber documents the desktop Unscheduled drawer as Visits; Assessment appearance
   in any other desktop backlog surface and eligibility in the New Schedule optimizer remain unavailable.
3. **Creation gesture:** Jobber is verified as click-to-create with Job, Request, Task and Event choices.
   Empty-range drag did nothing in the safe live test and is not documented officially. UCRM's empty-range
   drag-create is an explicitly approved adaptation from Autopilot, not a Jobber behavior claim.
4. **Multi-assignee Visit:** the assignee set, avatars, route lines, edit/bulk controls and future-Visit scope
   are verified. Exact duplicate/spanning lane placement and the set mutation caused by dragging a shared
   Visit remain unavailable without live writes.
5. **Map/order/save:** New Schedule Map scope, Anytime-Visit-only optimization, endpoint controls and the
   explicit Optimize action are verified. Unscheduled Visit manual ordering auto-persists. Mixed fixed-time/
   Anytime route-line ordering, shared-Visit per-assignee positions and arbitrary post-optimization ordering
   remain unavailable. Legacy-only save behavior is not projected onto New Schedule.

Permissions are covered by official evidence. No required screen, state, branch, or workflow remains
unlabeled, so Part 1a is complete. This audit makes no UCRM simplification, release, card, or deferral choice;
Part 1b has not begun.
