# Jobber Events, Assessments, and empty-slot creation — official follow-up

Research date: 2026-09-02. Scope: factual Part 1a research only. Sources are Jobber's Help Center,
official Help Center screenshots, and Developer Center/API material. “Verified” means the cited first-party
source directly supports the claim. “Unverified” means the reviewed first-party material does not resolve it.
New Schedule, Legacy Schedule, and the Jobber mobile app are separated where Jobber documents different
behavior.

## 1. Events

### Product boundary and assignment

- **Verified:** An Event is a lightweight calendar item inside Schedule, used for non-client work such as a
  team meeting or company barbecue. Jobber documents Events as automatically assigned to the whole team and
  visible to everyone on their Schedule. This is not presented as a standalone operational module.
  [Events](https://help.getjobber.com/en/articles/events)
  [Schedule Overview | New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/)
- **Verified:** The New Schedule quick-create chooser describes **New event** as an event everyone can see.
  [Official quick-create screenshot](https://help.getjobber.com/_astro/36981433088535.Bb_1aXhj_2tQrTx.webp)
- **Unverified:** The reviewed first-party material does not document choosing individual assignees,
  removing a person from an Event, or creating an unassigned Event. Although Jobber's scheduling data model
  exposes `assignedUsers` on scheduled items, the user-facing Event documentation consistently describes
  whole-team automatic assignment.
  [Events](https://help.getjobber.com/en/articles/events)
  [Jobber Developer Center](https://developer.getjobber.com/docs/)
- **Verified:** A calendar Event does not prevent Online Booking from assigning work to a team member during
  that time. For vacation or blocked availability, Jobber instructs the user to create a Task assigned to the
  relevant employee.
  [Manage Team](https://help.getjobber.com/en/articles/manage-teamhow-to-add-manage-and-deactivate-team-members/)
  [Online Booking](https://help.getjobber.com/en/articles/online-booking/)

### Create surfaces and fields

- **Verified — New Schedule:** Selecting an empty calendar time or **Find a Time** opens the unified creation
  chooser; the user can change its type to **New event**. Find a Time is available in Month, Week, and Day.
  [Schedule Overview | New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/)
- **Verified — compact create:** Jobber's official screenshot shows Type, Title, **Add Details**, Start Date,
  Start time, End time, **Anytime**, **Show availability**, **More Options**, and **Save**.
  [Official compact-create screenshot](https://help.getjobber.com/_astro/36981416811287.DdLEMq68_Z233sdG.webp)
- **Verified — expanded create:** Jobber's official screenshot shows an **Upcoming event** form with Title,
  Details, Start date, End date, Start time, End time, **All day**, and **Repeats**. The illustrated repeat
  value is **Never**.
  [Official expanded-create screenshot](https://help.getjobber.com/_astro/36981416811287.DdLEMq68_Z233sdG.webp)
- **Verified — Legacy Schedule:** Jobber's Event article documents selecting an open spot in Month, Week, or
  List, entering a name, details, and time, optionally opening **More Options**, and selecting **Save**.
  [Events](https://help.getjobber.com/en/articles/events)
- **Verified — mobile:** Events created on jobber.com are visible in the Jobber app, but the app cannot create
  Events.
  [Schedule in the Jobber App](https://help.getjobber.com/en/articles/schedule-in-the-jobber-app/)
- **Unverified:** Jobber's Find a Time documentation says Visits, Tasks, and Requests occupy availability but
  does not name Events in that list. Whether an existing Event removes a slot from availability is therefore
  not established.
  [Schedule Overview | New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/)

### Popover and edit behavior

- **Verified:** Selecting an appointment in New Schedule opens an overview popover; Jobber's generic
  appointment flow provides **Edit** and **View details** actions.
  [Schedule Overview | New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/)
- **Verified:** The Event-specific official screenshot shows a popover with the Event label, title, date,
  start/end time, Details, and **More Actions**.
  [Official Event-details screenshot](https://help.getjobber.com/_astro/36981416813847.BbPhnw5s_1J2NcY.webp)
- **Verified — mobile detail:** The Event detail surface shows title, Details, Schedule (start/end dates and
  times plus repeat information), and Team.
  [Schedule in the Jobber App](https://help.getjobber.com/en/articles/schedule-in-the-jobber-app/)
- **Unverified:** The reviewed official pages do not enumerate the exact post-create edit form, the Event
  entries inside **More Actions**, or whether a recurring edit targets one occurrence, future occurrences, or
  the entire series.
  [Events](https://help.getjobber.com/en/articles/events)

### Privacy and masking

- **Verified:** Jobber's documented Event visibility rule is whole-team visibility: Events are automatically
  assigned to the team and all team members can view them.
  [Events](https://help.getjobber.com/en/articles/events)
  [Schedule in the Jobber App](https://help.getjobber.com/en/articles/schedule-in-the-jobber-app/)
- **Unverified:** No reviewed create/details screenshot or Help Center text exposes a private-event control,
  audience selector, title masking, or details masking. The absence of those controls in the cited screens is
  not proof that no other account state exposes them.
  [Official compact-create screenshot](https://help.getjobber.com/_astro/36981416811287.DdLEMq68_Z233sdG.webp)
  [Official Event-details screenshot](https://help.getjobber.com/_astro/36981416813847.BbPhnw5s_1J2NcY.webp)
- **Verified:** Creating a calendar Event requires **Edit their own schedule** permission.
  [Events](https://help.getjobber.com/en/articles/events)
  [User Permissions](https://help.getjobber.com/en/articles/user-permissions/)
- **Unverified:** Jobber says deleting scheduled items requires **Edit and delete from everyone's schedule**,
  but its examples name Tasks and Visits rather than Events. The Event-specific deletion permission is not
  directly stated.
  [User Permissions](https://help.getjobber.com/en/articles/user-permissions/)

### Recurrence and lifecycle

- **Verified:** Events support repeat information: the expanded create screenshot has **Repeats**, and mobile
  Event details show how often the Event repeats.
  [Official expanded-create screenshot](https://help.getjobber.com/_astro/36981416811287.DdLEMq68_Z233sdG.webp)
  [Schedule in the Jobber App](https://help.getjobber.com/en/articles/schedule-in-the-jobber-app/)
- **Not independently re-verified in this round:** The existing local Jobber reference records Event
  recurrence fields named `isRecurring`, `recurrenceSchedule`, and `recurringSummary`, but this follow-up did
  not capture the authenticated GraphiQL result that proves those exact fields. The public Developer Center
  explains that the complete current schema is exposed through authenticated GraphiQL, while its public
  “Important Objects” page does not expand Event fields. Treat the exact names as unverified until that
  primary artifact is captured.
  [Jobber Developer Center](https://developer.getjobber.com/docs/)
- **Unverified:** The public Help Center does not enumerate recurrence frequencies, custom intervals, end
  conditions, exceptions, time-zone rules, or one-occurrence/series edit and delete semantics.
  [Events](https://help.getjobber.com/en/articles/events)
- **Verified:** Once an Event's date/time passes, Jobber displays it greyed out with a green check mark on
  Schedule.
  [Events](https://help.getjobber.com/en/articles/events)
  [Schedule Overview | New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/)
- **Verified — mobile:** Calendar Events cannot be manually completed in the Jobber app.
  [Schedule in the Jobber App](https://help.getjobber.com/en/articles/schedule-in-the-jobber-app/)
- **Unverified:** The reviewed official material does not document a manual completion action on jobber.com,
  deletion confirmation/recovery, or recurring-series deletion behavior. The visible **More Actions** menu is
  not enumerated.
  [Official Event-details screenshot](https://help.getjobber.com/_astro/36981416813847.BbPhnw5s_1J2NcY.webp)
  [Events](https://help.getjobber.com/en/articles/events)

## 2. Assessments

### Object boundary and creation from Schedule

- **Verified:** An Assessment represents a trip to a client's property to assess and plan future work. In
  Jobber's public GraphQL model, `Assessment.request` is required and `Request.assessment` is optional and
  singular, so the Assessment belongs to a Request rather than existing as an independent calendar record.
  [Jobber Developer Center — Important Objects](https://developer.getjobber.com/docs/)
- **Verified:** From New Schedule, selecting an empty time or **Find a Time** opens the creation chooser with
  **New job**, **New request**, **New task**, and **New event**; **New job** is selected by default. Creating
  assessment-backed work from this surface begins by choosing **New request**.
  [Schedule Overview | New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/)
- **Verified:** In the Request workflow, selecting “Visit the property to assess the job before you do the
  work” adds an on-site Assessment with instructions, schedule, and team assignment.
  [Schedule an Assessment](https://help.getjobber.com/en/articles/schedule-an-assessment/)
- **Verified — mobile:** Creating a Request from a blank Schedule slot automatically includes its Assessment
  section. The Assessment defaults to one hour at the selected time and is assigned to the team member adding
  the Request; selecting another displayed team member's empty slot assigns that person.
  [Requests in the Jobber App](https://help.getjobber.com/en/articles/requests-in-the-jobber-app/)
  [Schedule in the Jobber App](https://help.getjobber.com/en/articles/schedule-in-the-jobber-app/)
- **Unverified — New Schedule desktop:** The reviewed first-party text does not say whether **New request**
  automatically enables the Assessment section, which clicked date/time values are prefilled, whether the
  selected team lane preassigns that team member, or whether the generic Anytime default applies to Requests.

### Scheduled, Anytime, and Unscheduled

- **Verified:** A timed Assessment has start/end dates and times. Selecting **Anytime** retains a date without
  a specific time. Selecting **Schedule later** creates the Request in **Unscheduled** status.
  [Schedule an Assessment](https://help.getjobber.com/en/articles/schedule-an-assessment/)
- **Verified — API/schema:** Assessment exposes `startAt`, `endAt`, `allDay`, and `duration`; the API docs
  define an unscheduled item by null `startAt` and `endAt` values.
  [Jobber Developer Center — Important Objects](https://developer.getjobber.com/docs/)
- **Verified:** Request status follows its Assessment: Unscheduled when enabled but not calendared;
  Upcoming/Today for a future/current appointment; Past Due for an earlier incomplete Assessment; Action
  Required after completion while the Request remains unconverted and unarchived.
  [Schedule an Assessment](https://help.getjobber.com/en/articles/schedule-an-assessment/)
- **Verified:** Client-provided preferred dates and arrival periods under “Your availability” are reference
  information; they do not themselves schedule the Assessment.
  [Requests in the Jobber App](https://help.getjobber.com/en/articles/requests-in-the-jobber-app/)
- **Unverified:** The New Schedule documentation describes its unscheduled drawer specifically as
  **Unscheduled visits** and does not explicitly confirm whether Unscheduled Assessments appear there.
  [Schedule Overview | New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/)

### Assignment and completion lifecycle

- **Verified:** The Assessment editor's **Assign** control selects the team members who will perform it; the
  API exposes `assignedUsers`. Assigned team members see the Assessment on their Schedule.
  [Schedule an Assessment](https://help.getjobber.com/en/articles/schedule-an-assessment/)
  [Requests in the Jobber App](https://help.getjobber.com/en/articles/requests-in-the-jobber-app/)
  [Jobber Developer Center — Important Objects](https://developer.getjobber.com/docs/)
- **Verified — API/schema:** Jobber exposes assessment create, edit, delete, complete, and uncomplete
  operations. This establishes reversible completion and a deletion operation at the API level, but not the
  desktop confirmation UI.
  [Jobber Developer Center](https://developer.getjobber.com/docs/)
- **Verified:** Completing an Assessment advances the Request to an action-required state until the Request
  is converted to a Quote or Job, left for later action, or archived.
  [Schedule an Assessment](https://help.getjobber.com/en/articles/schedule-an-assessment/)
- **Unverified:** The exact desktop presentation of one Assessment assigned to multiple team members, and the
  precise behavior of New Schedule's bulk **Reschedule & reassign** flow for such an Assessment, are not
  documented in the reviewed first-party material.

### Map inclusion and order

- **Verified — New Schedule map:** New Schedule can add a supplementary Map to Day, Week, or Month and show
  appointments for the selected period; pins use team calendar colors.
  [Schedule Overview | New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/)
- **Verified — Assessment routing model:** Jobber says Assessments can be routed with the day's Visits. Its
  GraphQL Assessment model includes `routingOrder` and `overrideOrder`.
  [Schedule an Assessment](https://help.getjobber.com/en/articles/schedule-an-assessment/)
  [Jobber Developer Center — Important Objects](https://developer.getjobber.com/docs/)
- **Verified — mobile:** The mobile Map shows today's scheduled Assessments and Visits, plus Tasks with
  property addresses. When **Show unscheduled appointments on map view** is enabled, it also shows
  Unscheduled Assessments, Visits, and Tasks, labeled Unscheduled with a crossed-calendar icon.
  [Schedule in the Jobber App](https://help.getjobber.com/en/articles/schedule-in-the-jobber-app/)
- **Verified — Legacy Schedule:** Legacy daily route optimization includes Assessments, Visits, and Tasks
  only when they are assigned to a team member and set to Anytime. A dispatcher can use **Route From Here**
  or drag items in the Map sidebar; the Jobber app then lists those item types in the saved order.
  [Daily Route Optimization | Legacy Schedule](https://help.getjobber.com/en/articles/daily-route-optimization-legacy-schedule/)
- **Unverified — New Schedule optimizer:** The current New Schedule optimization article repeatedly limits
  optimization to **Anytime visits** and does not name Assessments or Tasks. It does not resolve whether
  Assessments are eligible, how fixed-time Assessments join route lines, how Assessments order relative to
  fixed-time/Anytime Visits, or whether Unscheduled Assessments appear in the desktop Map.
  [Route Optimization | New Schedule](https://help.getjobber.com/en/articles/route-optimization-new-schedule/)

## 3. Empty-slot click and drag when several item types are available

- **Verified — New Schedule Day:** Selecting an empty time opens a creation menu with **New job, new request,
  new task, and new event**; **New job** is selected by default. The selected date is prefilled. A new Job's
  Visit defaults to Anytime unless the user clears Anytime and supplies start/end times.
  [Day View of the Schedule | New Schedule](https://help.getjobber.com/en/articles/day-view-of-the-schedule-new-schedule/)
- **Verified — New Schedule Week:** Selecting empty space opens the same four-type chooser, again defaulting
  to New job.
  [Week View of the Schedule | New Schedule](https://help.getjobber.com/en/articles/week-view-of-the-schedule-new-schedule/)
- **Verified — Find a Time:** Month, Week, and Day provide the same four creation choices through Find a Time,
  with New job as the default.
  [Schedule Overview | New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/)
- **Verified — mobile:** Tapping a blank Schedule spot opens **New request, New job, or Add task**. Event is
  not listed in this mobile blank-slot menu. When the spot belongs to another displayed team member, that
  person is automatically assigned to the new item.
  [Schedule in the Jobber App](https://help.getjobber.com/en/articles/schedule-in-the-jobber-app/)
- **Unverified — drag-create:** The reviewed official sources do not document click-dragging across an empty
  time range as a creation gesture or whether such a gesture prefills both start and end. They document
  selecting an empty time; dragging existing appointments to reschedule or resize; dragging unscheduled
  appointments onto the calendar; and click-drag selection only while the bulk **Reschedule & reassign** tool
  is active.
  [Day View of the Schedule | New Schedule](https://help.getjobber.com/en/articles/day-view-of-the-schedule-new-schedule/)
  [Schedule Overview | New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/)

## Remaining official-evidence gaps

1. Event privacy/private visibility and any audience-specific masking.
2. Event individual assignment/reassignment, despite scheduled-item `assignedUsers` in the API model.
3. Exact Event edit form, **More Actions** contents, deletion UI, and series edit/delete semantics.
4. Complete Event recurrence options and exception/time-zone rules.
5. Whether Events appear on a Map. Find a Time's documented occupancy list omits Events, consistent with
   Jobber's separate statement that Events do not block Online Booking; do not generalize beyond those two
   availability contexts.
6. New Schedule desktop defaults after choosing **New request** from an empty slot or Find a Time.
7. New Schedule desktop visibility of Unscheduled Assessments.
8. New Schedule optimizer eligibility/order for Assessments, especially beside fixed-time and Anytime Visits.
9. Empty-range drag-to-create behavior; official sources document click creation, not drag creation.

## 2026-09-02 current-source reconciliation

- The current New Schedule overview says an Event can be completed or can pass its date/time; either state
  gives it a checkmark and grey treatment. The web action that manually completes an Event remains
  undocumented, so only the resulting lifecycle state is verified.
  [Schedule Overview | New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/)
- Find a Time defines occupied appointments as visits, tasks, or requests and omits Events. Together with
  Jobber's statement that Events do not block Online Booking, this closes the earlier availability question
  for those two named contexts only.
  [Schedule Overview | New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/)
- New Schedule documents its desktop backlog as **Unscheduled visits**. With that drawer open, its Map adds
  those Visits. Mobile separately documents Unscheduled Assessments on Map. This is positive evidence for a
  Visit-only desktop drawer, but does not prove that an Unscheduled Assessment is absent from every desktop
  surface.
  [Schedule Overview | New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/)
  [Schedule in the Jobber App](https://help.getjobber.com/en/articles/schedule-in-the-jobber-app/)
- Manual ordering inside the Unscheduled Visit drawer persists automatically across sessions. This backlog
  ordering boundary is separate from New Schedule route optimization, whose documented write action remains
  **Optimize**.
  [Visits](https://help.getjobber.com/en/articles/visits/)
  [Route Optimization | New Schedule](https://help.getjobber.com/en/articles/route-optimization-new-schedule/)
