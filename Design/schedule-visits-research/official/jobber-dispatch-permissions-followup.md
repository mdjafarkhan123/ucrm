# Jobber dispatch, routing, and Schedule permissions — official follow-up

Research date: 2026-09-02. Scope: first-party Jobber Help Center and Jobber Developer Center sources only.
This note separates New Schedule, Legacy Schedule, and the Jobber mobile app because Jobber documents
different interaction models for each. It records competitor facts and evidence gaps only; it does not
propose ContractorOs behavior.

## Multi-assignee Visit rendering and reassignment

### Verified — data and card identity

- A Visit has an `assignedUsers` connection, so assignment is a set of users rather than a single-user
  field. The same Visit type also exposes separate `routingOrder` and `overrideOrder` fields; Jobber describes
  `overrideOrder` as ordering for Anytime and unscheduled items. [Jobber Developer Center — API schema](https://developer.getjobber.com/docs/)
- New Schedule cards display assigned-team avatars; Jobber's calendar-color article illustrates a Visit with
  two avatars. If multiple assignees have different calendar colors, the Visit uses the color rule nearest
  the bottom of the configured color list. [Calendar Colors](https://help.getjobber.com/en/articles/calendar-colors/)
- A Visit preview identifies the full Team assigned to that Visit. Editing the Visit's team changes only that
  Visit unless the user deliberately chooses **Save and update future visits** for applicable future Visits.
  [Visits](https://help.getjobber.com/en/articles/visits/)

### Verified — employee Day and map surfaces

- In New Schedule's vertical Day view, each displayed team member has a dedicated column and their Anytime
  Visits appear above their timed appointments. In horizontal Day view, team members and Unassigned are
  rows; each row has an expandable Anytime count. The Team filter adds or removes team members from the
  view. [Day View of the Schedule | New Schedule](https://help.getjobber.com/en/articles/day-view-of-the-schedule-new-schedule/)
- In the Jobber app, Day and List initially show the current user's schedule. When permissions allow team
  view, additional employees can be added side-by-side and each schedule is labeled with that employee's
  name. [Schedule in the Jobber App](https://help.getjobber.com/en/articles/schedule-in-the-jobber-app/)
  [Fieldworkers — How Jobber Works for Different Roles](https://help.getjobber.com/en/articles/fieldworkers-how-jobber-works-for-different-roles-in-a-company/)
- On New Schedule's supplementary map, hovering a Visit assigned to multiple team members shows the route
  lines for every assigned team member. [Route Optimization | New Schedule](https://help.getjobber.com/en/articles/route-optimization-new-schedule/)

### Verified — reassignment

- In either New Schedule Day orientation, dragging an appointment between team members is the documented
  quick-reassignment gesture. [Day View of the Schedule | New Schedule](https://help.getjobber.com/en/articles/day-view-of-the-schedule-new-schedule/)
- In New Schedule Week view, reassignment is performed by opening the appointment, choosing Edit, and adding
  or removing people in the Team section. [Week View of the Schedule | New Schedule](https://help.getjobber.com/en/articles/week-view-of-the-schedule-new-schedule/)
- New Schedule's bulk **Reschedule & reassign** tool accepts selections from either the schedule or map,
  permits one or more new assignees, and does not apply the update until **Confirm**. On failure, the user's
  selections remain available for **Try again**. [Schedule Overview | New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/)
- A user with **Edit their schedule** may edit an item assigned to them even when multiple users are assigned
  to that item. This proves shared Visits remain editable under own-assigned-work permission, subject to that
  permission level. [User Permissions](https://help.getjobber.com/en/articles/user-permissions/)

### Unverified / unavailable from first-party text

- Jobber's articles do not say whether one multi-assignee Visit is rendered once in every assignee's Day
  lane, once in a single lane, or as one card spanning lanes. Multiple avatars and multiple route lines prove
  shared assignment, but not the calendar-card placement rule.
- The phrase "drag and drop appointments between team members to reassign them" does not define the set
  mutation for an already multi-assigned Visit. Official text does not say whether the gesture replaces all
  assignees, removes only the source employee, or adds the destination employee.
- Collision and availability treatment is not documented for the case where a multi-assignee Visit conflicts
  with another appointment for only one assignee.

## Fixed-time and Anytime items on Map

### Verified — New Schedule

- New Schedule optimization operates on **Anytime Visits only**: Visits without a scheduled start or end
  time. Fixed-time Visits are not eligible for optimization. It can process up to seven selected dates for
  one team member, a selected group, or the whole team. [Route Optimization | New Schedule](https://help.getjobber.com/en/articles/route-optimization-new-schedule/)
- The supplementary map can be added to Day or Week and displays directional lines for the order of
  appointments through each team member's day. [Route Optimization | New Schedule](https://help.getjobber.com/en/articles/route-optimization-new-schedule/)
- In the mobile app, fixed-time appointments are displayed first in List view and Anytime Visits follow.
  Within the Anytime section, order follows the routing order saved on Jobber.com. Day view instead places
  Anytime appointments at the top and timed work at its scheduled time. [Schedule in the Jobber App](https://help.getjobber.com/en/articles/schedule-in-the-jobber-app/)
- The API schema stores `routingOrder` and `overrideOrder` on the Visit itself. `overrideOrder` is explicitly
  described as applying to Anytime and unscheduled items. [Jobber Developer Center — API schema](https://developer.getjobber.com/docs/)

### Verified — Legacy Schedule, retained only as historical behavior

- Legacy daily routing explicitly excludes fixed-time Visits because they must occur at their scheduled
  time; only Anytime work participates in route ordering and blue route lines. [How to Route](https://help.getjobber.com/en/articles/how-to-route/)
- Legacy Map groups the day's sidebar work as scheduled first, Anytime second, and unscheduled last. This is
  a display grouping, not a single optimized mixed route. [Map View | Legacy Schedule](https://help.getjobber.com/en/articles/map-view-legacy-schedule/)

### Unverified / unavailable from first-party text

- New Schedule sources do not define how fixed-time pins participate in the displayed directional route
  lines when the same employee also has optimized Anytime Visits. They do not say whether timed stops are
  inserted chronologically, excluded from route lines, or shown as a separate sequence.
- New Schedule sources do not publish a combined Map/sidebar ordering rule for fixed-time, Anytime, and
  unscheduled items comparable to the Legacy Map grouping.
- The optimizer documentation confirms selection by employee and date but does not explain how one
  multi-assignee Anytime Visit receives potentially different positions in each employee's route. The map
  can display each employee's line through that shared Visit, but the ordering calculation is undocumented.

## Manual route controls and save semantics

### Verified — New Schedule

- Before optimizing, the dispatcher can drag the intended first Visit to the top and intended last Visit to
  the bottom. The optimization dialog can preserve either endpoint through **Keep first appointment at
  start of route** and **Keep the last appointment at end of route**. [Route Optimization | New Schedule](https://help.getjobber.com/en/articles/route-optimization-new-schedule/)
- **Optimize** is the documented action that begins the reorder. Jobber shows an in-progress message until
  the operation finishes, and the Jobber app subsequently reflects the optimized order. Optimization must
  be run on Jobber.com and is admin-only. [Route Optimization | New Schedule](https://help.getjobber.com/en/articles/route-optimization-new-schedule/)
- New Schedule optimizes the selected dates' current Anytime Visits directly from Schedule. It no longer
  depends on the separate Legacy master-route template and may be run repeatedly as schedules change.
  [Route Optimization | New Schedule](https://help.getjobber.com/en/articles/route-optimization-new-schedule/)

### Verified — Legacy Schedule, retained only as historical behavior

- Legacy daily Map supports **Route From Here** and drag-and-drop reordering in the sidebar. Jobber says the
  resulting order applies only to that specific date; enduring property priority belongs to the master
  route. [How to Route](https://help.getjobber.com/en/articles/how-to-route/)
- Legacy master-route setup supports either automatic optimization or a fully manual sequence: choose a
  starting property, select the remaining properties in order, then select **Save**. Insertions/removals are
  shown as pending changes and **Save** finalizes the overwrite. [Route Optimization Through the Settings Menu](https://help.getjobber.com/en/articles/route-optimization-through-the-settings-menu/)

### Unverified / unavailable from first-party text

- New Schedule documents manual dragging only for first/last endpoint selection before **Optimize**. It does
  not document arbitrary manual ordering of every stop after optimization.
- New Schedule does not state whether dragging an endpoint immediately persists any order before
  **Optimize**, or whether those drags are only input to the later Optimize operation. There is no separately
  documented Save/Confirm control for endpoint dragging.
- Legacy daily Map text documents immediate route-line changes after drag ordering but does not name a Save
  or Confirm action for daily route reordering or identify the server-write boundary. This differs from the
  Legacy master-route screen, whose explicit **Save** boundary is verified above.

## Schedule permissions: assigned work versus full-team Schedule

### Verified — five capability levels

- **View their own schedule** is read-only access to the user's own schedule. **View and complete their own
  schedule** adds completion of their own scheduled work. [User Permissions](https://help.getjobber.com/en/articles/user-permissions/)
- **Edit their schedule** permits editing items assigned to the user, including date and time, even when
  multiple users share the item. [User Permissions](https://help.getjobber.com/en/articles/user-permissions/)
- **Edit everyone's schedule** permits viewing, editing, and adding across all schedules. **Edit and delete
  from everyone's schedule** adds deletion across all schedules. [User Permissions](https://help.getjobber.com/en/articles/user-permissions/)
- The assigned-work boundary is substantive rather than a display preference: when choosing a Visit or
  Assessment for a mobile timesheet entry, a user without permission to view everyone's schedule sees only
  items assigned to them. [Timers and Timesheets in the Jobber App](https://help.getjobber.com/en/articles/timers-and-timesheets-in-the-jobber-app/)
- Deleting a Visit requires **Edit and delete from everyone's schedule**; the Jobber app hides Delete Visit
  without that permission. [Schedule in the Jobber App](https://help.getjobber.com/en/articles/schedule-in-the-jobber-app/)

### Verified — presets and team view

- The Field crew preset can see and complete its own schedule but cannot see anyone else's. Senior field
  crew retains that cross-team restriction. Crew lead can view and change everyone's schedule, and Manager
  includes Crew lead capabilities. [User Permissions](https://help.getjobber.com/en/articles/user-permissions/)
- The Jobber app exposes side-by-side employee schedules only when permissions allow team view. When
  permitted, users add other employees through View options. [Fieldworkers — How Jobber Works for Different Roles](https://help.getjobber.com/en/articles/fieldworkers-how-jobber-works-for-different-roles-in-a-company/)
  [Schedule in the Jobber App](https://help.getjobber.com/en/articles/schedule-in-the-jobber-app/)
- New Schedule route optimization is stricter than full-team Schedule editing: the optimization article says
  only admins can run it. [Route Optimization | New Schedule](https://help.getjobber.com/en/articles/route-optimization-new-schedule/)

### Verified — Event exception relevant to assigned-only users

- Events are lightweight Schedule items automatically assigned to the entire team, so they appear on every
  team member's Schedule. Creating an Event requires **Edit their own schedule**. [Events](https://help.getjobber.com/en/articles/events/)
  [Schedule Overview | New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/)

### Unverified / unavailable from first-party text

- Official sources do not show the desktop New Schedule Day UI while signed in as an own-schedule-only
  user. The access rule is verified, but whether other lanes, Team filters, and Unassigned controls are
  hidden, disabled, or present-but-empty is not documented.
- Official sources do not state whether an own-schedule editor can drag a shared Visit in a way that removes
  themself from it or assigns it to another employee. They only establish that the user can edit an item to
  which they are assigned, even when it has multiple assignees.
- Direct-link behavior for unassigned or other-team Visits under assigned-only permissions is not documented.
- Schedule permissions do not by themselves establish which client details, pricing, notes, or job fields
  appear inside an assigned Visit; Jobber documents those as separate permission categories.
