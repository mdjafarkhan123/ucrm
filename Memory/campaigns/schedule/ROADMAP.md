# Schedule campaign roadmap

Jafar approved Schedule as a separate campaign on 2026-09-02 and required a complete verified-research pass
before any UCRM simplification. The working product/UI and release ideas in
docs/schedule-behavior-contract.md are provisional hypotheses until Parts 1a and 1b close.

| Part | Release | Outcome | State | Dependency | Completion gate |
| --- | --- | --- | --- | --- | --- |
| 1a | Research | Exhaustively document factual Jobber and supporting primary-source behavior without adapting it to UCRM | In progress — paused for fresh-session Jobber research | Existing Jobber, Autopilot and ContractorOs evidence; Jobs Part 12 transfer | Every required screen, state, branch and workflow is backed by saved live/primary evidence or explicitly marked unavailable; the coverage audit finds no unlabeled gap; no UCRM choice is made |
| 1b | Synthesis | Compare the complete evidence with UCRM, decide simplifications, and finalize ownership, behavior/UI, card matrix, releases and deferrals | Planned | Part 1a closed | Every match, adaptation, omission and deferral is explicit; proven outcomes are preserved; Jafar gives final contract approval |
| 2 | V1 | Deliver the bounded Schedule foundation and desktop shell | Planned | Part 1b; source-domain permissions; organization timezone/working-hours readiness | One date-window Schedule presents permission-shaped Visit truth with stable date/view/employee/status state and honest loading, empty and failed states; timezone and working-hours sources are explicit |
| 3 | V1 | Deliver Week, employee-oriented Day and Month views with the adaptive Visit card system | Planned | Part 2 | Week default, Day employee rows, dense Month, Anytime lane, Unassigned row, filters and compact preview match the Part 1b-approved density/state matrix |
| 4 | V1 | Deliver Visit creation and dispatch interactions | Planned | Part 3; existing Jobs scheduling and recurrence commands; working-hours source | Create against an existing Job; schedule backlog work; assign, move and resize with explicit save; time/assignment changes use existing future scope, date moves stay single-Visit, series changes use Edit Schedule, and warnings remain bounded |
| 5 | V1 | Deliver Jobs-owned completion integration and Job Visits parity | Planned | Part 4; Jobs Part 13a | Complete/uncomplete and Finish job/Add a return visit/Keep open use Jobs truth; compact Job card and Schedule show identical timing, assignment and status |
| 6a | V1.1 | Add Request-owned Assessments and Schedule-owned lightweight Events | Planned | Part 5; Request/Assessment readiness | Assessment selects/opens an existing Request; one-time timed/all-day Event exists only through Schedule popover/modal with defined assignment, privacy and blocking behavior; no separate Event module |
| 6b | V1.1 | Add bounded Tasks and reminders | Planned | Part 5; Task and Quote/Invoice reminder readiness | Timed/date-only/unscheduled Tasks use Task actions and Part 1b-approved capacity rules; reminders are display/open-owner items; repeating Tasks and Task notifications remain outside |
| 7 | V1.2 | Add contextual Map and manual Anytime routing | Planned | Part 5; dated geocoded Visits; Part 6a for Assessments; Part 1b-approved map/directions provider boundary | Same Schedule state, one selected employee, Visits/Assessments, numbered/grouped markers, fixed-time anchors, saved Anytime Visit order, route line, Directions and honest address/provider failures |
| 8 | Closure | Verify integrated desktop journeys | Planned | Parts 2–7 | Unscheduled Visit → place → assign → move/resize → complete → Job parity passes with permissions, recurrence, keyboard, failure recovery and bounded-date evidence |

Automatic route optimization, traffic, live GPS, broad map layers, nearby backlog, calendar sync, day sheets,
bulk tools, Find a Time, custom layouts, canceled/no-show outcomes and the mobile app are outside this campaign.
