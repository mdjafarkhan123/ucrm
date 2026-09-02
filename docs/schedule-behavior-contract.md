# Schedule, Visits, and Dispatch behavior contract

Status: **Research in progress. Jafar approved a separate Schedule campaign on 2026-09-02, but every UCRM
behavior, UI, release and simplification proposal remains provisional until the verified-research pass is
complete.**

Owner: Schedule campaign

## Purpose and decision rule

Schedule is the contractor's desktop dispatch desk: see operational commitments, place unscheduled work,
assign the right people, recognize conflicts, and understand the day's route without leaving the calendar.

This is a working hypothesis document, not the final behavior contract. Remaining Jobber branches listed in
the Schedule checkpoint must be verified without mutation first. Approval of the separate campaign
authorizes research and planning only. It does not approve the proposed UCRM behavior or authorize
application code, schema, permission, API, provider, or infrastructure changes.

Use proven Jobber and mature field-service behavior by default. During evidence collection, record what the
reference product does without adapting it to UCRM or deciding whether it is too complex. Only after the
research coverage audit closes may the evidence be compared with UCRM's ownership model and smallest useful
contractor workflow. At that later stage, do not ask Jafar to re-decide proven interactions unless there is a
real conflict or simplification choice; preserve the user outcome and make every removed capability explicit.

Authoritative evidence is indexed in
[Design/schedule-visits-research/README.md](../Design/schedule-visits-research/README.md). Jobber supplies
the proven field-service behavior, Autopilot supplies useful direct-manipulation references, and the local
ContractorOs Visits card supplies the starting visual structure. The UpliftContractor design system owns
the final visual language.

## Required decision sequence

The campaign must pass these stages in order:

1. **Factual research:** capture Jobber and other primary evidence, with verified and unverified labels. Do
   not select UCRM features, release boundaries, card variants or simplifications in this stage.
2. **Coverage audit:** check every required screen, state, branch and workflow. Close each gap with live or
   primary-source evidence, or explicitly mark it unavailable.
3. **UCRM synthesis and simplification:** only after the coverage audit closes, compare the complete evidence
   with UCRM's existing ownership boundaries and decide what to match, adapt, defer or omit.
4. **Final contract approval:** present the resulting behavior, UI/UX, release grouping and explicit
   differences to Jafar. Implementation planning begins only after approval.

## Evidence and open-verification register

Do not treat every sentence in this working contract as a claim about Jobber. The plan has three kinds of
statements:

- **Verified precedent:** observed directly in Jobber/Autopilot or confirmed by an official primary source.
- **Provisional UCRM proposal:** a hypothesis awaiting the completed research and simplification stages.
- **Open verification:** a Jobber branch that has not yet been safely observed and cannot guide
  implementation until it is verified or explicitly labeled unavailable.

Verified so far:

- Jobber Month, Week and Day views, Week/Day Anytime lanes, employee-oriented Day layout, filters,
  Unscheduled access, compact Visit popover and contextual split Map.
- Jobber Job-detail Visit summary/table, single/multiple Visit creation and recurrence consequences.
- Autopilot Week/Day/Month/Employees views, explicit-save empty-slot drag creation and separate Event form.
- ContractorOs recurrence summary and To be scheduled/Upcoming/Past Visit grouping.
- Jobber has no separate Event navigation/workflow in the inspected account; Event lives inside Schedule.
- Assessment remains Request-owned rather than becoming a generic Event.

Open verification before the Part 1a coverage audit can close:

1. Jobber Event popover/create/edit fields, assignment, privacy masking, recurrence and lifecycle behavior.
2. Assessment creation or scheduling from Schedule, its Unscheduled/Anytime behavior, and Map position.
3. Empty-slot click/drag behavior when multiple writable scheduled-item types are available.
4. Multi-assignee Visit rendering and reassignment from employee-oriented Day.
5. Mixed fixed-time/Anytime Map ordering, manual route controls and when a route-order change writes.
6. Any permission differences between seeing the full team Schedule and only assigned work.

The Version 1 release split, adaptive card system, explicit Save Move, Visit-first delivery, bounded conflict
warnings and deferred advanced Map scope are provisional UCRM proposals. They are not represented as Jobber
observations and must not be finalized or simplified while factual research remains open. If competitor
evidence is genuinely unavailable, that fact must be recorded before the coverage audit can close. No
implementation begins until the later synthesis is approved by Jafar.

## Product ownership

The Job is the agreement. A Visit is one occurrence of performing that agreement. Schedule presents and
operates those records; it never creates a second Visit model.

| Product truth | Authoritative owner | Schedule responsibility |
| --- | --- | --- |
| Job identity, scope, billing setup and lifecycle | Jobs | Open the Job and show permitted context |
| Visit identity, recurrence, assignment, timing and completion | Jobs | Present and invoke Jobs-owned Visit actions |
| Assessment identity and outcome | Requests | Present and invoke Request-owned Assessment actions |
| Event identity and scheduling | Schedule | Create and manage lightweight Events inside Schedule |
| Task identity and completion | Tasks | Present and invoke Task-owned actions |
| Quote reminder | Quotes/Automation | Display and open its owner; never copy it |
| Invoice reminder | Jobs/Invoices | Display and open its owner; never copy it |
| Calendar views, backlog, drag interactions and conflict presentation | Schedule | Own |
| Map and manual route presentation | Schedule | Own without copying Visit truth |
| Customer/staff message delivery | Communications/Automation | Surface known consequences; do not send independently |

There is one Schedule destination and one interpretation of its selected date, team, type, status and view.
Calendar and Map must never maintain independent copies of this state.

## Provisional release ladder

This section is retained as a hypothesis so the completed evidence can later confirm, revise or reject it.
It is not an approved release commitment during factual research.

### Version 1 — Visit scheduling and dispatch

Version 1 is independently useful for a contractor operating Jobs and Visits:

- desktop Week, Day and Month views;
- Scheduled, Anytime and Unscheduled Visits;
- the provisional adaptive Visit card system;
- date navigation and Team, Visit status and assignment filters;
- compact Visit preview and existing Job/Visit detail paths;
- an Unscheduled drawer;
- create a Visit against an existing Job;
- assign, move, resize and convert between schedule shapes with explicit save;
- recurring-edit scope and conflict warnings;
- Jobs-owned completion when its lifecycle prerequisite exists; and
- a refined Job detail Visits card that shows the same truth.

Version 1 does not manufacture placeholder Events, Tasks, Assessments or reminders. It also does not include
Map, route optimization, a mobile field application, customer-notification automation, Find a Time, bulk
rescheduling or custom Schedule settings.

### Version 1.1 — Unified operational calendar

Version 1.1 adds source types only when their owning workflow is real and permission-safe:

- Assessments owned by Requests, with navigation back to their Request;
- one-time lightweight Events owned entirely inside Schedule, with a popover and create/edit modal rather
  than a separate Event module;
- timed, date-only and unscheduled Tasks owned by Tasks, with repeating Tasks and Task notifications later;
- display-only Quote reminders; and
- display-only Invoice reminders.

Each type keeps its own form, actions, status and meaning. The calendar unifies presentation, not business
objects.

### Version 1.2 — Contextual Map and manual routing

Version 1.2 adds an on-demand Map workspace inside Schedule:

- the same selected date, employee and filters as the calendar;
- one selected employee route at a time;
- ordered stop list and matching numbered markers;
- fixed-time stops anchored chronologically;
- manual ordering for Anytime Visit stops only;
- explicit Save Route Order;
- a directional route line;
- Directions for one stop or the route;
- honest invalid-address and provider-failure states; and
- one stop for a shared Visit in the selected employee's route.

Nearby Unscheduled work, automatic optimization and live tracking remain later releases.

## Information architecture

The desktop page has three stable regions:

1. **Page row:** Schedule title and one primary New Visit action in Version 1. The label broadens to
   New Scheduled Item only when Version 1.1 supports multiple writable types.
2. **Control row:** previous/next, Today, selected date or range, scheduled-item Type when relevant,
   Employee, Status, Week/Day/Month switch, Unscheduled count and Map toggle when released.
3. **Workspace:** the selected calendar. Unscheduled and Map open contextually without navigating to a
   separate product.

The selected date, view and filters survive reload and are shareable. Changing view preserves the closest
equivalent date and active filters. Week is the default for a first visit; the contractor's last chosen view
may be remembered later without adding custom layout settings.

Filter meanings stay distinct:

- Employee contains All employees, Unassigned and each active employee; it is the assignment filter.
- Status contains the source type's derived outcomes, such as Upcoming, Today, Late and Completed for
  Visits.
- Type means Visit, Assessment, Event, Task or reminder after Version 1.1; it never means Scheduled,
  Anytime or Unscheduled.
- Schedule shape is expressed by the timed grid, Anytime lane and Unscheduled drawer rather than being
  mixed into Status.

## Calendar views

### Week

- Seven desktop day columns.
- Persistent Anytime lane above the timed grid.
- Timed blocks visibly represent duration.
- Current-time line on the current week.
- Overlaps render side by side rather than hiding one item.
- Working hours use subdued background treatment.

Week is the default planning view. It prioritizes coverage and timing, not full record detail.

### Day

- Horizontal time axis with Unassigned first, followed by employee rows.
- Anytime is a dedicated first column.
- A shared Visit appears in every assigned employee row so workload remains honest, but it remains one
  underlying Visit and carries a shared-assignment indicator.
- The employee row already supplies identity, so cards do not repeat the employee name or avatar.
- Selecting one rendering of a shared Visit highlights every rendering. Dragging a single-assignee Visit to
  another row proposes replacing its assignee. A multi-assignee Visit opens the assignment editor after
  drop; row dragging never silently replaces the whole team.

Day is the dispatch view for gaps, overlaps, assignments and responsibility.

### Month

- Dense high-level coverage view, not precise time placement.
- Each date shows a small fixed number of compact rows followed by + N more.
- Selecting + N more opens that date's agenda/overflow.
- Selecting an item opens the shared compact preview.
- Selecting empty space starts date-prefilled Visit creation.
- Multi-day drag creation is not part of the campaign.

### Anytime, all-day and reminders

These concepts share an upper date region but never share meaning:

- an Anytime Visit or Assessment is dated, has no clock time and consumes operational capacity; saved
  manual route ordering is initially Visit-only;
- an all-day Event occupies the date but is not a routeable Visit;
- a date-only Task is work due that day and follows Task behavior; and
- a reminder is a display-only date marker and does not consume field capacity or create a conflict.

## Card and density system

Cards adapt to available space rather than relying on one fixed layout:

| Density | Required content |
| --- | --- |
| Micro | type/status cue plus abbreviated time and title |
| Compact | time, short client/title and employee accent |
| Standard | time, client/title, locality cue, status and additional-assignee count |
| Expanded | adds permitted instructions or secondary context only when space genuinely allows |

The hierarchy is time or Anytime, primary label, short context, location cue, assignment, then status.
A single-assignee item uses that employee's narrow accent. A multi-assignee item uses a neutral shared
accent plus an assignee count; no unowned lead-employee concept is invented. Type uses an icon/label, and
status uses text/icon treatment. Full saturated card fills are avoided, and color is never the only carrier
of meaning.

| Surface | Provisional card behavior |
| --- | --- |
| Week timed | Adaptive block; time, client, short Visit/Job title, accent and status |
| Week Anytime | Compact routeable card with Anytime label and optional route-order number |
| Day employee | Start/end, client, short title/locality and shared-assignment cue |
| Month | One compact time · client row, accent/status cue, then + N more |
| Unscheduled drawer | Client, Visit/Job title, property, age, assignment and Schedule action |
| Map stop | Stop number, time/Anytime, client, full address, assignment, status and Directions |
| Compact preview | Operational summary and fast actions; never a miniature Job detail page |
| Job detail Visit | Dense row with date/time, assignment, title/instructions, status and secondary menu |
| Drag ghost | Proposed date/time/duration and assignment, clearly temporary |

Type-specific labels prevent the unified calendar from assuming every item has a client:

| Type | Card content priority |
| --- | --- |
| Visit | time/Anytime, client, Job or Visit title, property |
| Assessment | time/Anytime, client, Request or Assessment title, property |
| Event | time/All day, Event title, optional location |
| Task | time/date-only, Task title, optional owning record |
| Quote reminder | reminder purpose, client and Quote reference |
| Invoice reminder | reminder purpose, client and Invoice or Job reference |

Every surface covers normal, hover, focus, selected, completed, late, unassigned, multiple-assignee,
recurring-exception, conflict, dragging, saving, failed-save, missing-address and read-only states as
applicable. Private Event content is masked outside permitted detail views.

An Anytime route-order number appears only after Version 1.2 has a saved route order.

Very short timed items keep their true duration. When content cannot fit, the Micro form is used and the
full summary remains available through focus/preview.

Arrival windows and Visit duration are different. If Jobs later supplies an arrival window, the card may
show that window while its grid size continues to represent expected working duration.

## Opening, creating and editing

Version 1 uses a deliberately small interaction stack:

- select a card to open a compact operational popover;
- use Edit or Move/Reschedule to open the owning existing dialog;
- use Open Job or Open Details to navigate to the existing owning record page.

A new Schedule-specific rich detail panel is not part of Version 1.

Version 1.1 keeps the distinction explicit:

- choosing Assessment selects an existing Request and invokes its Request-owned Assessment form; Schedule
  never creates a Request;
- an existing unscheduled Assessment may be placed through that same owning workflow;
- an Assessment preview opens its owning Request/Assessment context;
- an Event opens a compact Event popover and its Schedule-owned create/edit modal;
- Events have no sidebar destination, separate list page or full detail page; and
- an Event linked optionally to a client/property may open that related record, but the Event itself still
  lives only in Schedule.

Version 1.1 Events are deliberately one-time, timed or all-day blocks. They require a title and one or more
assigned employees; description, location, client/property link and privacy are optional. Assigned Events
block those employees' availability by default. People permitted to see the Schedule but not the private
details see only Busy and the occupied time. The creator and users with Event-management authority may edit
or delete the Event; assigned users may see its permitted details. Event recurrence, completion and
cancellation workflows are later scope.

The primary New Visit action selects an existing Job and uses the Jobs-owned Visit form. Full Job creation
remains in Jobs.

Empty timed-space interaction follows the proven calendar pattern:

- click starts a Visit at that time with a fixed one-hour Version 1 default, editable before Save;
- click-drag draws a temporary block and prefills start/end;
- click in Anytime starts a date-only Visit; and
- dragging an existing Unscheduled Visit onto the calendar schedules that Visit rather than creating one.

No gesture writes immediately. The user reviews the proposal and presses Save. Escape or Cancel removes the
temporary state.

## Moving, resizing and recurrence

- Drag proposes a new date/time or employee.
- Resizing proposes a new duration.
- Timed to Anytime removes clock time while retaining the date.
- Anytime to timed adds start and duration.
- Unscheduled to calendar adds its chosen schedule.
- Calendar to Unscheduled removes date/time only after explicit confirmation.

After a drop, a compact confirmation shows the old and proposed schedule, assignment and any known
notification consequence. Save Move commits; Cancel restores the item.

Recurring changes follow the existing Jobs contract rather than one blanket dialog:

- changing time, duration, Scheduled/Anytime shape or assignment offers This Visit Only or This and Future
  Incomplete Visits;
- moving a Visit to another date or returning it to Unscheduled changes This Visit Only;
- changing the series' weekday/date pattern uses Edit Schedule, with the existing consequence preview that
  regenerates all incomplete Visits; and
- Completed Visits never change under any scope.

The small move confirmation never hides the destructive Edit Schedule behavior. Schedule invokes Jobs-owned
recurrence commands rather than reimplementing them. Every drag action has an equivalent Move or reschedule
button/keyboard path.

## Conflict boundary

Version 1 warns about:

- overlapping timed assignments for the same employee; and
- placement outside organization working hours.

Warnings are visible before Save but do not prohibit an intentional overlap. Beginning in Version 1.1,
assigned timed and all-day Events contribute to overlap/availability warnings. Travel time, skills,
territory, equipment, crew capacity and traffic are outside Version 1.

## Unscheduled work

The Unscheduled button opens a contextual drawer and preserves its filters during the current Schedule
session. Version 1 contains Visits only and provides:

- live count;
- search, assignment and Visit-status filters;
- client, title, property/location and age;
- drag handle;
- explicit Schedule action; and
- honest empty, filtered-empty and failed states.

In Version 1.1, an existing Assessment without a date may join the backlog and Schedule opens its
Request-owned form to place it. An unassigned or unscheduled Task may join after Task scheduling is approved.
Events and reminders never enter this backlog.

## Completion and Visit outcomes

Completion belongs to Jobs. Schedule invokes the Jobs-owned complete/uncomplete command and presents the
result. It never creates a Schedule-only completion state.

The full proven completion decision remains:

- complete the Visit;
- Invoice Now or Later when the Invoice boundary exists; and
- on the final Visit, answer whether all work is finished with Finish job, Add a return visit or Keep open.

Version 1 completion depends on the bounded Jobs lifecycle prerequisite. If the Invoice boundary is not yet
ready, Schedule must not invent Invoice Now; it presents only the actions the Jobs contract can honor.

Upcoming, Today, Late and Completed remain derived. Canceled and No-show are excluded until Jobs defines
their durable meaning and downstream consequences. They never count as Completed.

## Contextual Map and route behavior

Map is an on-demand split workspace within Schedule, following Jobber's contextual pattern. It may expand
for route work, but it is not a separate sidebar destination and never resets the selected date, employee or
filters.

Saved manual order is scoped to the selected employee and date. It is a dispatch preference, not a change
to the Visit's appointment time or ownership. A shared Visit may therefore appear once in each assigned
employee's route at the position saved for that employee while remaining one Visit everywhere else.

The first Map release:

- requires one selected employee; opening Map from All employees or a multi-selection asks the dispatcher
  to choose and never silently picks someone;
- includes that employee's dated Visits and, after Version 1.1, mappable Assessments;
- shows fixed-time Visits and Assessments as locked chronological anchors;
- allows flexible Anytime Visit stops to move before, between or after those anchors while only the Anytime
  Visit rows are draggable;
- preserves fixed-time anchors;
- saves route order only after Save Route Order;
- uses one stop for a shared Visit in the selected employee's route;
- keeps invalid addresses in the stop list with an explanation;
- leaves the ordered list usable when map or route rendering fails; and
- offers Directions without promising in-product turn-by-turn navigation.

Assessment order remains Request-owned/read-only until Requests defines a route-order action. Multiple items
at one property remain distinct stop-list entries and use a grouped/stacked marker so none is hidden. If an
external Directions provider cannot accept the whole route's waypoint count, whole-route Directions explains
the limit while every individual stop still offers Directions.

An Unscheduled Visit has no date. It is therefore not silently inserted into a selected day's route.
Showing geographically nearby Unscheduled work is a later optional map layer using property location,
not a fabricated schedule date.

## Job detail Visits card

The current ContractorOs structure is retained and refined:

- rename the section Visits;
- keep recurrence summary, count and schedule range;
- use To be scheduled, Upcoming and Past groupings;
- show the To be scheduled count separately, then exactly the next three Upcoming Visits;
- use Show all inline to expand the remaining groups rather than inventing a separate Visits page;
- collapse Past by default;
- avoid repeating shared property information on every row;
- show date/time or Anytime, assignment, title/instructions and status;
- retain completed-by/completed-at history;
- use a compact completion control rather than a repeated large button;
- keep edit and other secondary actions in a menu;
- use Edit Schedule for recurring work;
- distinguish Add one Visit from Add multiple Visits;
- mark a Visit that differs from its recurring series; and
- distinguish an as-needed Job from an accidental empty schedule.

Schedule may refine this cross-surface card during its parity part, but Jobs remains the source of Visit
truth and actions. Invoice or billable indicators wait for the Invoice boundary.

## Time, privacy, permissions and recovery

- Organization timezone controls the calendar.
- Date-only values remain date-only and never shift through UTC conversion.
- Schedule grants no new access: each item is visible only when its source-domain view permission permits
  it. The current Jobs model is organization-wide under jobs.view; this campaign does not invent an
  assigned-only visibility model.
- Visit create, assignment and rescheduling require the existing jobs.schedule authority. Visit completion
  requires the Jobs-owned completion authority when Part 13a introduces it.
- Assessment context and actions follow Request permissions. Event details/actions follow the Event rules
  above. Tasks and reminders follow their owning permissions.
- Unavailable actions are absent or honestly disabled; drag is unavailable without the owning scheduling
  permission.
- Private Event details are masked for users without permission.
- First load uses calendar-shaped skeletons without blocking the app shell.
- Empty, filtered-empty and failed states preserve the selected date and controls.
- Saving locks only the affected proposal/item.
- A failed move restores the original item and offers Retry.
- Successful writes update Schedule and the owning record consistently and use the shared toast pattern.

Version 1.1 Task behavior is bounded: a timed Task with an expected duration occupies that employee's grid
and participates in overlap warnings; a date-only Task does not consume timed capacity; an unscheduled Task
may enter the backlog; and Tasks do not appear on Map in this campaign.

## Campaign completion journeys

Version 1 is complete when a permitted dispatcher can:

1. find an Unscheduled Visit;
2. place it into Week or Day;
3. assign one or more employees;
4. move or resize it with the correct recurring scope;
5. recognize overlap and working-hours warnings;
6. complete it through Jobs-owned behavior when that prerequisite is available; and
7. see identical timing, assignment and status on the Job detail Visits card.

Version 1.1 is complete when each enabled Assessment, Event, Task and reminder appears with its own meaning,
actions and permissions while sharing the finally approved calendar language.

Version 1.2 is complete when a dispatcher can open the contextual Map for one employee, understand the
selected day's stops, manually order Anytime stops, save that order, handle an unmappable address and open
Directions without leaving Schedule state behind.

The campaign closes only after the combined Version 1, 1.1 and 1.2 journeys pass desktop accessibility,
permission, recurrence, failure-recovery and bounded-date evidence.

## Explicitly outside this campaign

- Mobile application and field-worker mobile workflows
- Automatic route optimization
- Traffic-aware ETAs and route origin/end configuration
- Live GPS or employee tracking
- Leads, clients, territories and vehicles as general map layers
- Nearby Unscheduled work on the Map
- External calendar synchronization
- Day-sheet generation or printing
- Find a Time
- Bulk reschedule or reassignment
- Multi-day Month drag creation
- Customer-notification automation
- Recurring Events and Event completion/cancellation workflows
- Repeating Tasks and Task reminders/notifications
- Advanced arrival-window settings
- Custom per-user calendar layouts/settings
- Canceled and No-show Visit outcomes

These are not rejected. Each is reconsidered only when its dependency or real usage justifies the extra
surface.
