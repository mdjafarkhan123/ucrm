# Jobber Events — official-source findings

Research date: 2026-09-02. This note records only behavior supported by Jobber's own Help Center, official Help Center screenshots, and first-party developer documentation. It distinguishes Jobber's legacy web Schedule, new web Schedule, and mobile app because the documented capabilities differ. It does not infer UCRM behavior.

## Event purpose and assignment

- Jobber describes an Event as a scheduled item suited to whole-team items such as a team meeting or company barbecue. Events are automatically assigned to the entire team, and Jobber says everyone can see them on their Schedule. ([Events](https://help.getjobber.com/en/articles/events), [Schedule Overview — New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/))
- The new-Schedule quick-create chooser describes New Event as an event “everyone can see.” ([Official quick-create screenshot](https://help.getjobber.com/_astro/36981433088535.Bb_1aXhj_2tQrTx.webp))
- The official sources inspected do not document choosing individual employees for an Event, removing employees from an Event, or creating an unassigned Event. They consistently describe whole-team automatic assignment. **Individual employee assignment: unavailable in the inspected first-party material.** ([Events](https://help.getjobber.com/en/articles/events), [Schedule in the Jobber App](https://help.getjobber.com/en/articles/schedule-in-the-jobber-app/))
- A calendar Event does not block a team member from assignment by Online Booking; Jobber recommends a task assigned to the employee for vacation/time-away blocking. ([Manage Team](https://help.getjobber.com/en/articles/manage-teamhow-to-add-manage-and-deactivate-team-members/), [Online Booking](https://help.getjobber.com/en/articles/online-booking/))

## Create surfaces and fields

### New web Schedule

- On the new web Schedule, an Event can be started by selecting an empty time or by selecting **Find a Time**, then changing the creation type to **New Event**. Find a Time is documented on Month, Week, and Day views. ([Schedule Overview — New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/))
- The compact Event create popover shown by Jobber contains the type chooser, Title, an **Add Details** affordance, Start Date, Start time, End time, an **Anytime** checkbox, a **Show availability** toggle, **More Options**, and **Save**. ([Official compact-create screenshot](https://help.getjobber.com/_astro/36981416811287.DdLEMq68_Z233sdG.webp))
- The expanded **Upcoming event** form shown by Jobber contains Title, Details, Start date, End date, Start time, End time, **All day**, and **Repeats**; the illustrated repeat value is **Never**. ([Official expanded-create screenshot](https://help.getjobber.com/_astro/36981416811287.DdLEMq68_Z233sdG.webp))
- The generic new-Schedule documentation says the Find a Time popover highlights availability dynamically and treats visits, tasks, and requests as occupying time when deciding whether a slot is open. Events are not included in that stated occupied-item list. The documentation does not say whether an existing Event removes a slot from availability. **Effect of Events on Find a Time availability: unverified.** ([Schedule Overview — New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/))

### Legacy web Schedule

- Jobber's Event-specific article says a user can create an Event by clicking an open spot in Month, Week, or List view. The first popover accepts name, details, and time; **More Options** exposes additional settings; **Save** creates the Event. ([Events](https://help.getjobber.com/en/articles/events))
- Jobber's legacy Schedule overview separately says Calendar Events are created from the Month or Week view through **More Actions → Calendar Event**. ([Schedule Overview — Legacy Schedule](https://help.getjobber.com/en/articles/schedule-overview-legacy-schedule/))

### Mobile app

- Events cannot be created in the Jobber mobile app. Events created on jobber.com are visible in the app. ([Schedule in the Jobber App](https://help.getjobber.com/en/articles/schedule-in-the-jobber-app/))

## Popover and editing

- On the new web Schedule, selecting an appointment opens an overview popover. The generic appointment flow offers **Edit** to change the appointment and **View details** for the fuller record. ([Schedule Overview — New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/))
- Jobber's Event-specific details screenshot shows an **Event** popover containing the Event title, date and start/end time, Details text, and **More Actions**. The screenshot does not expose the contents of More Actions. ([Official Event-details screenshot](https://help.getjobber.com/_astro/36981416813847.BbPhnw5s_1J2NcY.webp))
- The mobile Event details expose Event title, Details, Schedule (start date, end date, start time, end time, and how often the Event repeats), and Team. ([Schedule in the Jobber App](https://help.getjobber.com/en/articles/schedule-in-the-jobber-app/))
- The inspected first-party material does not enumerate which fields are editable after creation, whether editing occurs inline or in the expanded form, or whether editing a recurring Event prompts for one occurrence versus a series. **Exact edit form and recurring-edit scope: unavailable.** ([Events](https://help.getjobber.com/en/articles/events), [Schedule Overview — New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/))

## Privacy, masking, and permissions

- Jobber's official Event material states that Events are automatically assigned to the whole team and visible to all team members. The mobile Event's Team section likewise says Events can be viewed by all team members. ([Events](https://help.getjobber.com/en/articles/events), [Schedule in the Jobber App](https://help.getjobber.com/en/articles/schedule-in-the-jobber-app/))
- The inspected create and details screenshots do not show a privacy control, visibility selector, or masking control. This screenshot observation does not establish that no such control exists elsewhere. **Private Events, masked Event titles/details, and audience-specific Event visibility: unavailable in the inspected first-party material.** ([Official expanded-create screenshot](https://help.getjobber.com/_astro/36981416811287.DdLEMq68_Z233sdG.webp), [Official Event-details screenshot](https://help.getjobber.com/_astro/36981416813847.BbPhnw5s_1J2NcY.webp))
- Creating a calendar Event requires the Schedule permission **Edit their own schedule**. ([Events](https://help.getjobber.com/en/articles/events), [User Permissions](https://help.getjobber.com/en/articles/user-permissions/))
- Jobber's Schedule permission levels are: view own Schedule; view and complete own Schedule; edit items assigned to the user (including an item with multiple assignees); edit/add across everyone's Schedule; and edit/add/delete across everyone's Schedule. Only admins can change a user's permissions. ([User Permissions](https://help.getjobber.com/en/articles/user-permissions/))
- Jobber's permission guide says deleting scheduled items requires **Edit and delete from everyone's schedule**, giving tasks and visits as examples. It does not explicitly name Event deletion. **The permission required to delete an Event specifically is not directly stated.** ([User Permissions](https://help.getjobber.com/en/articles/user-permissions/))

## Recurrence

- The expanded Event form has a **Repeats** field, illustrated with **Never**, and the mobile Event details show how often the Event repeats. These first-party sources establish that Events can carry repeat information. ([Official expanded-create screenshot](https://help.getjobber.com/_astro/36981416811287.DdLEMq68_Z233sdG.webp), [Schedule in the Jobber App](https://help.getjobber.com/en/articles/schedule-in-the-jobber-app/))
- The inspected public documentation does not enumerate Event repeat frequencies, interval/custom-rule options, end conditions, occurrence exceptions, or time-zone behavior. It also does not document whether edits or deletes apply to one occurrence, this-and-future occurrences, or the entire series. **Recurrence rule set and series mutation semantics: unavailable.** ([Events](https://help.getjobber.com/en/articles/events))
- Jobber's public developer documentation says the complete, current GraphQL schema is available through authenticated GraphiQL, but its public “Important Objects” reference does not publish an Event type or Event mutations. **The current public developer page does not independently resolve Event recurrence or lifecycle mutation details.** ([Jobber Developer Center](https://developer.getjobber.com/docs/))

## Lifecycle and deletion

- After an Event's time passes, Jobber says it automatically appears greyed out with a green checkmark on the Schedule. The new-Schedule overview says the same treatment applies once the Event is completed or its date/time has passed. ([Events](https://help.getjobber.com/en/articles/events), [Schedule Overview — New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/))
- The mobile app explicitly says Calendar Events cannot be completed. The inspected first-party sources do not document a manual completion action on the web. **Manual Event completion behavior on jobber.com is unresolved; mobile manual completion is unavailable.** ([Schedule in the Jobber App](https://help.getjobber.com/en/articles/schedule-in-the-jobber-app/))
- The Event details screenshot exposes **More Actions**, but the Event article does not enumerate that menu. The inspected public documentation does not state whether Events can be deleted, whether deletion is permanent, what confirmation appears, or how deletion behaves for a recurring Event. **Event deletion lifecycle: unavailable.** ([Official Event-details screenshot](https://help.getjobber.com/_astro/36981416813847.BbPhnw5s_1J2NcY.webp), [Events](https://help.getjobber.com/en/articles/events))

## Schedule visibility

- On the new web Schedule, Events appear in Month, Week, and Day views. Without a custom calendar color they appear yellow; once completed or past their date/time, they show a checkmark and appear greyed out. ([Schedule Overview — New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/))
- The new web Schedule Type filter includes Events alongside visits, tasks, and requests; multiple types can be selected. Its Team filter can show one or more team members' Schedules. ([Schedule Overview — New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/))
- In the mobile app, Day view lays out visits, tasks, and Events on a timed calendar; Week and 3 Day views also show scheduled items, and List view shows daily appointment cards. Events are yellow and open to Event details when tapped. ([Schedule in the Jobber App](https://help.getjobber.com/en/articles/schedule-in-the-jobber-app/))
- Jobber defines the mobile Map as showing assessments, visits, and tasks with property addresses. Events are not included in that documented Map item list. **Whether any Event can appear on Map is not affirmatively documented; the published Map scope omits Events.** ([Schedule in the Jobber App](https://help.getjobber.com/en/articles/schedule-in-the-jobber-app/))
- Calendar colors appear on the web Month, Week, and Day views but not in the mobile app. Jobber documents colors based on assigned team member or title keyword; because Events are whole-team items, the exact precedence for an Event matching several team colors is not stated in the inspected material. **Event-specific calendar-color precedence: unavailable.** ([Calendar Colors](https://help.getjobber.com/en/articles/calendar-colors/))

## Unresolved official-evidence gaps

The following requested facts remain unverified because the inspected first-party public sources do not expose them:

1. Any privacy/private-Event control, masking rule, or reduced-detail presentation for some users.
2. Any Event-level employee assignment or reassignment other than automatic whole-team assignment.
3. The complete repeat-option list and recurring-series edit/delete prompts.
4. The Event-specific **More Actions** menu and Event deletion confirmation/recovery behavior.
5. A manual web completion action and its effect versus automatic past-time completion styling.
6. Whether Events consume availability in Find a Time or can appear on Map.

