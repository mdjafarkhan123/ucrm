# Part 4b — Job-first creation

## Approved behavior

- Empty calendar space opens Jobber's work-type creation surface; Job is selected by default whenever more
  than one available type makes the chooser visible.
- Version 1 enables Job only, so it does not render a redundant one-option selector. Request and Event join
  in Part 6a; Task stays absent until its owner is ready.
- Visit is never a chooser type and there is no "Visit to existing Job" toggle.
- The compact Job draft accepts client/property, work details/line items, team and the gesture-seeded first
  Visit schedule. More Options transfers the same draft to the canonical full Job form.
- Save uses the Jobs-owned create contract and creates the Job plus its first Visit atomically. Nothing
  writes before Save.
- Click seeds one hour, drag seeds its range, Anytime seeds date-only, and Month seeds date-only.
- Additional Visits remain owned by Job detail; Schedule may duplicate an existing Visit in a later bounded
  slice. Unscheduled Visits are placed through Part 4c.

## Acceptance checks

- Remove Schedule empty-space and header paths that open `JobVisitDialog(mode="create")`; keep Job-owned Add
  Visit behavior unchanged.
- Job is the only Version 1 creation type; unavailable types are not rendered as fake controls.
- Compact Save and More Options preserve client/property, work details, line items, team and schedule without
  duplicating domain validation or mutation ownership.
- Week click/drag/Anytime, Day click/drag/Anytime, Month click and the header create action preserve their
  expected schedule seed and cancel cleanly.
- Permissions, query invalidation, toast feedback, keyboard behavior and failure recovery use existing app
  contracts.
- Grid zoom still passes its pending live verification alongside the corrected create flow.

## Non-obvious risk

The broad Job creation tour is complete, but the Job-selected Schedule compact form and exact More Options
draft handoff were not captured. Verify only that narrow interaction before implementation. The existing full
Job form may not yet accept a transferable Schedule draft; establish that boundary before building the compact
form and do not create a second divergent Job schema or mutation.
