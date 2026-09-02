# Jobber dispatch interactions — official-source findings

Research date: 2026-09-02. Scope: first-party Jobber Help Center material only. “New Schedule,” “Legacy
Schedule,” and the Jobber mobile app are kept separate because Jobber documents different behavior for each.
This note records facts and explicit evidence gaps only.

## Empty-slot creation when several item types exist

### Verified — New Schedule on Jobber.com

- In Day view, selecting an empty time opens a creation menu. The available types are **New job, new
  request, new task, and new event**, with New Job selected by default. The same article says the clicked
  date is prefilled; a newly created job visit defaults to Anytime unless the user clears the Anytime option
  and enters start/end times. [Day View of the Schedule | New Schedule](https://help.getjobber.com/en/articles/day-view-of-the-schedule-new-schedule/)
- Jobber documents the same empty-space → type-menu flow for Week view: New job, request, task, or event,
  with New Job as the default type. [Week View of the Schedule | New Schedule](https://help.getjobber.com/en/articles/week-view-of-the-schedule-new-schedule/)
- Find a Time is an alternate creation entry point on Month, Week, and Day. Its type selector has the same
  four choices, and New Job is the default. [Schedule Overview | New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/)

### Verified — Jobber mobile app

- Tapping a blank schedule spot opens a bottom menu for **New request, New job, or Add task**. If the blank
  spot belongs to an additionally displayed team member’s schedule, that team member is automatically
  assigned to the new item. The mobile article does not list Event in this blank-spot menu.
  [Schedule in the Jobber App](https://help.getjobber.com/en/articles/schedule-in-the-jobber-app/)

### Unverified / unavailable from official sources

- The reviewed first-party articles do **not** document click-and-dragging across an empty time range as a
  creation gesture, nor whether such a gesture prefills both start and end times. They document clicking an
  empty time for creation, dragging existing appointments for rescheduling/resizing, dragging unscheduled
  appointments onto the calendar, and click-drag selection while the bulk Reschedule & Reassign tool is
  active. [Day View of the Schedule | New Schedule](https://help.getjobber.com/en/articles/day-view-of-the-schedule-new-schedule/)
  [Route Optimization | New Schedule](https://help.getjobber.com/en/articles/route-optimization-new-schedule/)

## Multi-assignee Visit rendering, placement, and reassignment

### Verified — rendering and route visualization

- New Schedule cards show avatars for their assigned team members. If a team member has no profile image,
  Jobber uses initials. [Schedule Overview | New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/)
- When a visit has multiple assignees with different configured calendar colors, Jobber displays the color
  of the assignee whose color rule is closest to the bottom of the calendar-color list.
  [Calendar Colors](https://help.getjobber.com/en/articles/calendar-colors/)
- Vertical Day view gives each team member a dedicated column, while Horizontal Day view lists team members
  and Unassigned down the left and places assignments across the time axis. Anytime visits appear at the top
  of each team member’s vertical column; in Horizontal view, the Anytime count beside a team member expands
  that member’s Anytime details. [Day View of the Schedule | New Schedule](https://help.getjobber.com/en/articles/day-view-of-the-schedule-new-schedule/)
- On the supplementary map, hovering an appointment assigned to multiple team members shows directional
  route lines for **each** assigned team member’s route.
  [Route Optimization | New Schedule](https://help.getjobber.com/en/articles/route-optimization-new-schedule/)

### Verified — assignment and reassignment

- In either Day orientation, Jobber documents dragging appointments between team members as the quick
  reassignment gesture. [Day View of the Schedule | New Schedule](https://help.getjobber.com/en/articles/day-view-of-the-schedule-new-schedule/)
- Week-view reassignment is documented as opening the appointment, selecting Edit, then adding or removing
  people in the Team section rather than dragging between employee lanes.
  [Week View of the Schedule | New Schedule](https://help.getjobber.com/en/articles/week-view-of-the-schedule-new-schedule/)
- The bulk Reschedule & Reassign flow can select appointments from the schedule or map, set new assignee(s),
  and applies the update only when **Confirm** is selected; Jobber then shows success or retains the
  selection for retry after an error. [Schedule Overview | New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/)
- Editing a Visit’s assigned team normally changes only that Visit. For applicable future visits, Jobber
  exposes a separate **Save and update future visits** action.
  [Visits](https://help.getjobber.com/en/articles/visits/)

### Unverified / unavailable from official sources

- The reviewed first-party text does not state whether one multi-assignee appointment is rendered as a
  duplicated card in every assignee column/row, as one card spanning lanes, or in only one lane. Avatars and
  multi-route lines confirm multiple-assignee visibility, but not the card-placement rule.
- The official Day-view text says that dragging between team members “reassigns” an appointment, but does
  not specify what happens to an existing multi-assignee set: replacement of all assignees, removal of only
  the source-lane assignee, or addition of the destination assignee remains undocumented.
- The articles do not document collision behavior if a multi-assignee Visit overlaps another appointment
  for only one of its assignees.

## Mixed fixed-time and Anytime items on Map

### Verified — New Schedule

- The supplementary map can be added to Day or Week and shows directional lines for the order of
  appointments in each team member’s day. [Route Optimization | New Schedule](https://help.getjobber.com/en/articles/route-optimization-new-schedule/)
- New Schedule route optimization operates only on **Anytime visits**, defined there as visits without a
  scheduled start or end time. It can optimize up to seven days, for one team member, a group, or the whole
  team. [Route Optimization | New Schedule](https://help.getjobber.com/en/articles/route-optimization-new-schedule/)

### Verified — Legacy Schedule

- Legacy Map lists the day’s work grouped in this order: **scheduled, Anytime, then unscheduled**. Items
  linked to a client and property also appear as map pins.
  [Map View | Legacy Schedule](https://help.getjobber.com/en/articles/map-view-legacy-schedule/)
- Legacy daily routing excludes fixed-time scheduled visits: Jobber states that visits must be Anytime to
  participate in the route because scheduled visits must happen at their set time.
  [How to Route](https://help.getjobber.com/en/articles/how-to-route/)

### Verified — Jobber mobile app

- Mobile List view orders fixed-time appointments first and Anytime visits after them; the Anytime segment
  follows the routing order set on Jobber.com. Mobile Day view places Anytime appointments at the top and
  fixed-time items at their scheduled times. [Schedule in the Jobber App](https://help.getjobber.com/en/articles/schedule-in-the-jobber-app/)

### Unverified / unavailable from official sources

- The reviewed New Schedule sources do not explain whether fixed-time pins are inserted into the displayed
  route line between optimized Anytime stops, excluded from the route line, or shown in a separate sequence.
  They establish only that the map may display appointments while the optimizer reorders Anytime visits.
- The New Schedule sources do not define a single combined sidebar/list ordering for fixed-time, Anytime,
  and unscheduled items comparable to the documented Legacy grouping.

## Manual route controls and when route-order changes write

### Verified — New Schedule

- Before optimization, the dispatcher can drag the desired first appointment to the top and the desired
  last appointment to the bottom. In the optimizer dialog, **Keep first appointment at start of route** and
  **Keep the last appointment at end of route** preserve those endpoints. The route change is initiated only
  when the user selects **Optimize**; Jobber shows an in-progress message until it completes.
  [Route Optimization | New Schedule](https://help.getjobber.com/en/articles/route-optimization-new-schedule/)
- Only admin users can run New Schedule route optimization. Optimization is performed on Jobber.com, and
  the Jobber app reflects the optimized appointment order afterward.
  [Route Optimization | New Schedule](https://help.getjobber.com/en/articles/route-optimization-new-schedule/)
- New Schedule no longer uses the separate Legacy master route. It optimizes the selected days’ current
  Anytime visits directly from Schedule and may be run repeatedly as schedules change.
  [Route Optimization | New Schedule](https://help.getjobber.com/en/articles/route-optimization-new-schedule/)

### Verified — Legacy Schedule

- In Legacy daily Map, the sidebar supports drag-and-drop ordering of Anytime visits; Jobber states that the
  route line updates based on the chosen order. **Route From Here** makes a selected visit the starting point.
  [Map View | Legacy Schedule](https://help.getjobber.com/en/articles/map-view-legacy-schedule/)
  [How to Route](https://help.getjobber.com/en/articles/how-to-route/)
- A Legacy daily-route reorder applies only to that specific date. Long-lived default priority belongs to
  the separate master route under Settings > Route Optimization.
  [How to Route](https://help.getjobber.com/en/articles/how-to-route/)

### Unverified / unavailable from official sources

- New Schedule documentation does not expose or describe a general manual, persistent full-route reorder
  after optimization. Its documented manual drags set first/last endpoints before the explicit Optimize action.
- Legacy Help Center text says drag ordering immediately updates the route line, but does not name a Save or
  Confirm action for that reorder or say exactly when it is persisted server-side. Therefore immediate visual
  update is verified; the persistence/write boundary is unavailable.
- The Legacy master-route article documents manual insertion/reordering and an Optimize control, but the
  reviewed text does not identify a separate Save action or persistence timing for manual edits.
  [How to Route](https://help.getjobber.com/en/articles/how-to-route/)

## Schedule permissions: assigned-only versus full-team access

### Verified custom permission levels

- **View their own schedule** is read-only access to the user’s own schedule and does not permit completion.
  **View and complete their own schedule** adds completion of their own work.
  [User Permissions](https://help.getjobber.com/en/articles/user-permissions/)
- **Edit their schedule** permits editing items assigned to the user, including date and time. Jobber
  explicitly says this remains true when multiple users are assigned to the same item.
  [User Permissions](https://help.getjobber.com/en/articles/user-permissions/)
- **Edit everyone’s schedule** permits viewing, editing, and adding to all schedules. **Edit and delete from
  everyone’s schedule** additionally permits deletion across all schedules.
  [User Permissions](https://help.getjobber.com/en/articles/user-permissions/)
- Deleting a scheduled item such as a task or Visit requires **Edit and delete from everyone’s schedule**;
  it is not included in own-schedule edit permission. [User Permissions](https://help.getjobber.com/en/articles/user-permissions/)

### Verified preset differences

- Field crew can see their own schedule and complete work but cannot see another person’s schedule. Senior
  field crew retain that boundary and cannot change another person’s schedule. Crew leads can view and
  change everyone’s schedule; Managers include Crew lead capabilities.
  [User Permissions](https://help.getjobber.com/en/articles/user-permissions/)
- New Schedule route optimization is narrower than full-team schedule editing: Jobber documents it as an
  admin-only action. [Route Optimization | New Schedule](https://help.getjobber.com/en/articles/route-optimization-new-schedule/)

### Unverified / unavailable from official sources

- The reviewed sources do not describe the exact New Schedule filter, lane, or empty-state presentation
  shown to an own-schedule-only user, beyond the access boundary itself.
- The sources do not state whether an own-schedule editor can use a drag gesture that would remove themself
  from a multi-assignee item or assign that item to somebody else. They establish only that the user may edit
  an assigned multi-user item.
