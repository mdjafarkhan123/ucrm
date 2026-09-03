# Schedule campaign roadmap

Jafar approved Schedule as a separate campaign on 2026-09-02 and required a complete verified-research pass
before any UCRM simplification. Parts 1a and 1b are closed, and docs/schedule-behavior-contract.md is now the
approved product/UI and release boundary.

| Part | Release | Outcome | State | Dependency | Completion gate |
| --- | --- | --- | --- | --- | --- |
| 1a | Research | Exhaustively document factual Jobber and supporting primary-source behavior without adapting it to UCRM | Complete — coverage audit closed 2026-09-02 | Existing Jobber, Autopilot and ContractorOs evidence; Jobs Part 12 transfer | Passed: every required screen, state, branch and workflow is backed by saved live/primary evidence or explicitly marked unavailable; no UCRM choice was made |
| 1b | Synthesis | Compare the complete evidence with UCRM, decide simplifications, and finalize ownership, behavior/UI, card matrix, releases and deferrals | Complete — final contract approved 2026-09-02 | Part 1a closed | Passed: every match, adaptation, omission and deferral is explicit; proven outcomes are preserved; Jafar approved the final contract |
| 2a | V1 | Build the bounded Schedule foundation and desktop shell | Implemented 2026-09-02 | Part 1b; source-domain permissions; organization timezone/working-hours readiness | Passed: /schedule presents permission-shaped Visit truth for one bounded window, with URL-held date/view/employee/status state, honest loading, empty, filtered-empty, truncated and failed states, and explicit timezone and working-hours sources |
| 2b | V1 | Verify that foundation and close Part 2 | Complete — Part 2 gate passed 2026-09-02 | Part 2a | Passed: both endpoints observed through a signed-in session, a 500-visit window recorded at 397,819 bytes with `truncated` true, a member denied settings.business.view still read the real timezone and hours while direct table reads returned nothing, and the browser test project runs green |
| 3a | V1 | Deliver the adaptive Visit card, the compact preview and the Week grid | Complete 2026-09-02 | Part 2b | Passed: Week is the default view with an Anytime lane, painted hour lines, working-hours bands from the confirmed weekly pattern only, a current-time line, side-by-side overlaps, density that falls to Micro on its own, and one Bits UI popover anchored to the selected card |
| 3b | V1 | Deliver the employee-oriented Day dispatch board | Complete 2026-09-02 | Part 3a | Passed: horizontal time axis with pinned name and Anytime columns, Unassigned row first, every employee kept even with an empty day, an off-roster assignee given their own row, rows growing by lane on overlap, a shared Visit drawn in both rows with a shared cue and both highlighting on select, and the employee filter narrowing to one row |
| 3c | V1 | Deliver the dense Month grid and close Part 3 | Complete 2026-09-02 | Part 3a | Passed: padded 42-day window, three compact rows per date with + N more handing the preview its own anchor, and the density/state matrix — micro/compact/standard, today, late, completed, unassigned, shared, selected and the filtered-empty note — seen in all three views |
| 4a | V1 | Deliver move, resize and reassignment with explicit save | Complete 2026-09-02 | Part 3c; existing Jobs visit commands | Passed: drag and resize in Week and Day propose rather than write, the confirmation shows old versus proposed with bounded overlap and working-hours warnings, recurring changes offer This visit only or This and later through the existing apply-to-future command while date and shape changes stay single-Visit, a shared Visit dropped in another row opens the assignment editor instead of swapping the crew, and Reschedule gives every drag a button path |
| 4b | V1 | Replace the provisional direct-Visit empty-slot flow with Jobber's Job-first creation flow | Complete — live-verified 2026-09-03 | Part 4a; Jobs-owned create contract and canonical Job form handoff | Passed: Week click/drag-range/Anytime, Day click/Anytime, Month click and the header "New job" all open the compact Job draft seeded from the gesture (Month + Anytime lanes force Anytime; header = schedule-later); Save created Job #3 + first Visit and it landed on the grid; More options carried the draft into `/jobs/new`; Escape/Cancel wrote nothing; no Visit option appears |
| 4c | V1 | Deliver the Unscheduled backlog drawer and close Part 4 | Complete — live-verified 2026-09-03 | Part 4b; a window read for undated Visits | Passed: docked non-modal drawer, live count badge, search + employee filter with filtered-empty, drag a backlog card onto Week/Day (Move confirm → placed), a placed visit sent back via both the card menu and a drag onto the drawer behind an explicit confirm, undated create lands in the drawer, honest empty/filtered-empty/failed states. Visit-status filter dropped (undated visits are all statusless). Drag-onto-grid is Week/Day only; Month uses the Schedule button |
| 5 | V1 | Deliver Jobs-owned completion integration and Job Visits parity | Complete — 5a + 5b live-verified 2026-09-03 | Part 4c; Jobs Part 13a | Passed: 5a completion (complete/uncomplete + Finish job/Add a return visit/Keep open) uses Jobs truth; 5b redesigned the Job detail Visits card to the contract — To be scheduled/Upcoming/Past groups, next-three Upcoming + Show all, collapsed Past, recurrence summary + count + range, Edit Schedule, Add one vs multiple, as-needed vs empty, Overdue flag, completed-date history. Two contract items deferred to Jobs backend (no data source): completed-by name and the off-series marker — see deferred/job-visit-card-backend-fields |
| 6a-1 | V1.1 | Add Request-owned Assessments to the calendar (read + render + preview + slot creation) | Complete — tested + browser-verified 2026-09-03 | Part 5; Request/Assessment readiness | Passed: Assessments render on Week/Day/Month as their own type; preview opens the owning Request; the empty-slot chooser (`ScheduleJobCreate` Job/Request tabs, Job default) stages the slot and opens `/requests/new` with its on-site assessment pre-booked onto the slot's date/time/Anytime (no Request picker); existing Requests still schedule from the Request surface; no new schema. Schedule header button relabelled "New job" → "New" |
| 6a-2 | V1.1 | Add Schedule-owned lightweight Events | Planned | Part 6a-1 | One-time timed/Anytime whole-team Event exists only through a Schedule popover/create-edit modal with no assignment, privacy, client/property or address fields; no separate Event module; create/edit/delete gated on jobs.schedule (the existing calendar-change authority) |
| 6b | Deferred | Add general Tasks and Quote/Invoice reminders only after their owners expose calendar-capable contracts | Deferred by approved Part 1b contract | General Task and reminder owner readiness | Re-scope from the owning contracts; Schedule never reinterprets opportunity-scoped pipeline tasks or copies reminder truth |
| 7 | V1.2 | Add contextual Map and manual Anytime routing | Planned | Part 5; dated geocoded Visits; Part 6a for Assessments; Part 1b-approved map/directions provider boundary | Same Schedule state, one selected employee, Visits/Assessments, numbered/grouped markers, fixed-time anchors, saved Anytime Visit order, route line, Directions and honest address/provider failures |
| 8 | Closure | Verify integrated desktop journeys | Planned | Parts 2–7 | Unscheduled Visit → place → assign → move/resize → complete → Job parity passes with permissions, recurrence, keyboard, failure recovery and bounded-date evidence |

Automatic route optimization, traffic, live GPS, broad map layers, nearby backlog, calendar sync, day sheets,
bulk tools, Find a Time, custom layouts, canceled/no-show outcomes and the mobile app are outside this campaign.

Additional Visit creation remains owned by the Job Visits section. Schedule may duplicate an existing Visit;
the Jobber-style bulk Create New Visits tool for eligible as-needed recurring Jobs is outside V1 and requires
its own measured need. A generic empty-slot "Visit to existing Job" path is rejected.

## Team assignee picker — Built + verified 2026-09-03

Replaced the flat assignee checkbox list with a shared searchable multi-select: `src/lib/components/team/TeamPicker.svelte`,
a Bits UI `Combobox` with `type="multiple"` showing selected members as removable avatar chips over a
scrollable, height-capped list. Owns its own `fetchAssignableTeam` query (gated by the caller's `open`), same
pattern as `ClientPicker`. Wired into `ScheduleJobCreate.svelte` and `JobVisitDialog.svelte`, both now just
`bind:value={assigneeIds}`. No DB/RLS/permission impact.

Correctness note for future changes to this component: do not bind Bits UI's `Combobox.Root` `inputValue` to
this component's own search-filter text (one-way or two-way). Bits UI's multi-select internally writes the
picked item's label into that same box as part of committing a toggle, and binding it two-way let that
internal write and this component's own reset fight over the same channel — verified live to occasionally
drop a real assignee from `value` on save. The shipped version keeps `query` (the filter text) entirely
local, never passed to `Combobox.Root`; the only user-visible cost is that the search box can show the
last-picked name until the user types again, which is cosmetic only.

## Grid zoom / density control — Built + verified 2026-09-03

Jafar approved 2026-09-03 (proven pattern — Google Calendar "Compact/Comfortable"). A view-only control, NOT a
filter: Compact (default) / Comfortable / Spacious, a small SegmentedControl beside View, hidden in Month.
Compact matches the original grid size, so no existing view shifts. Implemented: `src/lib/schedule/density.ts`
(zoom type, per-view pixel maps, localStorage read/write), Week `HOUR_HEIGHT` and Day `HOUR_WIDTH` now derived
from zoom, page holds the choice and passes it down. Existing adaptive card density follows the room for free.
No DB / write / RLS / permission impact. `npm run check` 0 errors; drag + layout specs 51 pass; prettier clean.
Verified 2026-09-03: in Compact density a Week click on the 2pm row seeded exactly 2:00–3:00 PM, so the
denser row height still maps clicks to the correct time.
