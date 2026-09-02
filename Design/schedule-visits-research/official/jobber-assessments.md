# Jobber assessments — official-source findings

Research scope: assessment creation/scheduling from Schedule, Request ownership, schedule state, assignment,
calendar presentation, and Map/routing behavior. Sources are limited to Jobber's Help Center and Developer
Center. Where first-party material differs by surface or Schedule generation, the distinction is preserved.

## 1. Object and Request ownership

- Jobber defines an assessment as a trip to a client's property to assess and plan future work. In its public
  GraphQL model, `Assessment.request` is a required `Request!`, while `Request.assessment` is an optional,
  singular `Assessment`; the public model therefore represents the assessment as belonging to a Request, not
  as a standalone calendar record. [Jobber Developer Center — Important Objects](https://developer.getjobber.com/docs/)
- The same API type requires an assessment client (`client: Client!`), permits an optional property
  (`property: Property`), and exposes `instructions`, `title`, completion fields, schedule fields, assignees,
  and route-order fields on the assessment itself. [Jobber Developer Center — Important Objects](https://developer.getjobber.com/docs/)
- Jobber's user documentation says assessments are scheduled on Requests and that enabling the on-site
  assessment section adds the assessment to the Schedule. [Schedule an Assessment](https://help.getjobber.com/en/articles/schedule-an-assessment/)
- A Request can instead be converted directly to a Quote or Job without scheduling an assessment.
  [Schedule an Assessment](https://help.getjobber.com/en/articles/schedule-an-assessment/)

## 2. Creating and scheduling from Schedule

### Jobber.com — New Schedule

- From Jobber.com's New Schedule, an empty calendar time or **Find a Time** can start creation of a new Job,
  Request, Task, or Event; **New Job** is the default type and the user changes the type to **New Request**.
  [Schedule Overview | New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/)
- The Schedule availability calculation treats existing Requests as appointments that occupy time, alongside
  Visits and Tasks. [Schedule Overview | New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/)
- Separately, the Request workflow adds an on-site assessment by selecting “Visit the property to assess the
  job before you do the work,” then accepts assessment instructions, schedule, and team assignment.
  [Schedule an Assessment](https://help.getjobber.com/en/articles/schedule-an-assessment/)

**Unverified in first-party desktop documentation:** whether choosing **New Request** from an empty New
Schedule slot automatically enables the assessment section; which clicked date/time fields are prefilled for
that Request; whether a clicked team-member lane preassigns that person; and whether the New Schedule's
generic “created as Anytime by default” statement applies identically to Requests rather than only Jobs.

### Jobber mobile app

- In the Jobber app, a Request can be created by tapping a blank space in the Day or Week Schedule and choosing
  **New request**, or from quick create. When created from Schedule, its assessment section is already added.
  [Requests in the Jobber App](https://help.getjobber.com/en/articles/requests-in-the-jobber-app/)
- A Request created from a Schedule slot defaults its assessment to one hour beginning at the selected time and
  assigns it to the team member who is adding the Request. [Requests in the Jobber App](https://help.getjobber.com/en/articles/requests-in-the-jobber-app/)
- More generally, tapping another team member's empty Schedule slot automatically assigns that team member to
  the newly created Schedule item. [Schedule in the Jobber App](https://help.getjobber.com/en/articles/schedule-in-the-jobber-app/)

## 3. Scheduled, Anytime, and Unscheduled behavior

- A scheduled assessment has start/end dates and start/end times. Selecting **Anytime** retains the scheduled
  date but removes a specific time; selecting **Schedule later** creates the Request in **Unscheduled** status.
  [Schedule an Assessment](https://help.getjobber.com/en/articles/schedule-an-assessment/)
- The mobile flow states the same sequence another way: the assessment date initially remains Unscheduled;
  after a date is selected, the assessment can receive a scheduled time or remain Anytime.
  [Requests in the Jobber App](https://help.getjobber.com/en/articles/requests-in-the-jobber-app/)
- The public API exposes `startAt`, `endAt`, `allDay`, and `duration` for an Assessment and documents both
  `startAt` and `endAt` as null for an unscheduled item. [Jobber Developer Center — Important Objects](https://developer.getjobber.com/docs/)
- Request status follows assessment state: **Unscheduled** means the assessment is enabled but not calendared;
  **Upcoming/Today** is a future/current scheduled assessment; **Past Due** is a prior-day assessment not yet
  completed; and **Action Required** follows completion when the Request has not been converted or archived.
  [Schedule an Assessment](https://help.getjobber.com/en/articles/schedule-an-assessment/)
- Client-provided preferred dates and arrival periods under “Your availability” are reference information and
  do not themselves book the assessment on the Schedule. [Requests in the Jobber App](https://help.getjobber.com/en/articles/requests-in-the-jobber-app/)

## 4. Assignment

- The assessment editor's **Assign** control selects the team members who will perform the assessment, and the
  API exposes the result as an `assignedUsers: UserConnection`. [Schedule an Assessment](https://help.getjobber.com/en/articles/schedule-an-assessment/) [Jobber Developer Center — Important Objects](https://developer.getjobber.com/docs/)
- Assigned team members see the assessment on their Schedule. [Requests in the Jobber App](https://help.getjobber.com/en/articles/requests-in-the-jobber-app/)
- On the New Schedule, the Team filter filters calendar items by assigned team member; unassigned appointments
  use a red unassigned-person pin in the Day map. [Schedule Overview | New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/) [Day View of the Schedule | New Schedule](https://help.getjobber.com/en/articles/day-view-of-the-schedule-new-schedule/)

**Unverified in first-party documentation:** the exact desktop card duplication/placement when one assessment
has multiple assignees, and the exact reassignment behavior for an assessment selected through New Schedule's
bulk **Reschedule & reassign** tool.

## 5. Schedule/calendar presentation

- Jobber.com's New Schedule has Month, Week, and Day views and displays Requests as assessment time blocks;
  the Type filter has a **Requests** option. [Schedule Overview | New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/)
- Completed assessments show a check mark and are greyed on New Schedule by default, while the account can
  configure completed appointments to be greyed or struck through. [Schedule Overview | New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/)
- Current first-party pages conflict on the default Request color: the New Schedule overview says Requests are
  bronze when no calendar color is assigned, while the assessment article says request assessments appear as
  indigo Requests. This is likely a New-versus-older Schedule documentation difference, but the reason is not
  stated by Jobber. [Schedule Overview | New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/) [Schedule an Assessment](https://help.getjobber.com/en/articles/schedule-an-assessment/)
- Assessment booking Requests awaiting approval appear on the Schedule as outlined blocks; the time is held but
  is not confirmed until the Request is accepted. [Schedule an Assessment](https://help.getjobber.com/en/articles/schedule-an-assessment/)
- The Day view's horizontal layout groups date-only appointments under an **Anytime** count per team member,
  while the vertical layout displays Anytime appointments at the top of each team-member column.
  [Day View of the Schedule | New Schedule](https://help.getjobber.com/en/articles/day-view-of-the-schedule-new-schedule/)

**Unavailable in first-party documentation:** assessment-specific card fields and truncation rules in each
Month/Week/Day layout, and explicit confirmation that Unscheduled assessments appear in Jobber.com's New
Schedule unscheduled drawer. The current overview describes that drawer specifically as **Unscheduled visits**.

## 6. Map inclusion and route order

### New Schedule on Jobber.com

- New Schedule can add a supplementary Map to the Day, Week, or Month view; it displays appointments for the
  selected period and uses team calendar colors for pins. [Schedule Overview | New Schedule](https://help.getjobber.com/en/articles/schedule-overview-new-schedule/)
- Jobber says assessments can be routed with the day's Visits, and the Assessment API type carries both
  `routingOrder` and `overrideOrder`. [Schedule an Assessment](https://help.getjobber.com/en/articles/schedule-an-assessment/) [Jobber Developer Center — Important Objects](https://developer.getjobber.com/docs/)
- However, the current New Schedule route-optimization article repeatedly limits optimization to **Anytime
  visits** and does not name assessments or tasks. It supports automatic ordering, optional preservation of
  the first/last appointment, and route visualization with directional lines. [Route Optimization | New Schedule](https://help.getjobber.com/en/articles/route-optimization-new-schedule/)

**Unverified for New Schedule:** whether assessments are currently accepted by the optimizer despite the
article's “Anytime visits only” wording; whether fixed-time assessments participate in route lines/order; how
assessments are ordered relative to a mix of fixed-time and Anytime Visits; and whether an Unscheduled
assessment appears in the desktop Map when an unscheduled panel is open.

### Jobber mobile app

- Mobile Map displays today's scheduled Assessments and Visits, plus Tasks with property addresses, for the
  selected users. [Schedule in the Jobber App](https://help.getjobber.com/en/articles/schedule-in-the-jobber-app/)
- With **Show unscheduled appointments on map view** enabled, the mobile Map also shows Unscheduled Visits,
  Assessments, and Tasks; these cards are labeled **Unscheduled** and use a crossed-calendar icon.
  [Schedule in the Jobber App](https://help.getjobber.com/en/articles/schedule-in-the-jobber-app/)

### Legacy Schedule routing (explicitly legacy, not evidence of New Schedule parity)

- Legacy daily route optimization explicitly includes Assessments, Visits, and Tasks only when they are
  assigned to a team member and set to Anytime rather than to a fixed time. [Daily Route Optimization | Legacy Schedule](https://help.getjobber.com/en/articles/daily-route-optimization-legacy-schedule/)
- In that legacy flow, the dispatcher can choose **Route From Here** or drag items in the Map's left panel to
  change daily order, and the Jobber app lists Assessments, Visits, and Tasks in the route order saved on
  Jobber.com. [Daily Route Optimization | Legacy Schedule](https://help.getjobber.com/en/articles/daily-route-optimization-legacy-schedule/)

## Evidence gaps requiring direct product verification

1. Desktop New Schedule's exact Request/assessment defaults after an empty-slot click or **Find a Time**.
2. Desktop presentation of one assessment assigned to multiple team members.
3. Assessment eligibility and ordering in the current New Schedule optimizer, especially alongside fixed-time
   and Anytime Visits.
4. Desktop New Schedule Map inclusion for Unscheduled assessments.
5. Which default Request color is current in the live New Schedule (bronze versus indigo).
