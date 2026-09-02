# Schedule / Visits research evidence

Research captured from 2026-09-01 for the Schedule / Visits campaign. Competitor and local evidence is
indexed below. Jafar approved Schedule as a separate campaign, then required the no-guesswork research and
coverage audit to finish before any UCRM simplification. The behavior, UI/UX, release matrix and deferrals in
[`docs/schedule-behavior-contract.md`](../../docs/schedule-behavior-contract.md) are provisional hypotheses;
they will be evaluated only after the evidence register is complete.

## Jobber — verified live

The complete signed-in walkthrough is in [`jobber/`](./jobber/):

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

The Jobber and Autopilot findings above are direct live observations. The ContractorOs findings are direct
local source review. Autopilot's existing-item drag result and multi-stop route behavior remain unknown because
testing them would either mutate live data or require route-populated demo data that the inspected map did not
return.
