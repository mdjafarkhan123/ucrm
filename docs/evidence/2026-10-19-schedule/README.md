# Schedule build verification — 2026-10-19

Branch: `codex/approved-shared-schedule-build`. Built against the approved frames listed in
`Memory/campaigns/contractor-design-concept/parts/c8-schedule.md`. Merged to main at Jafar’s explicit request on 2026-10-19. These results
are application verification, not an infrastructure deployment. Pencil and the design skill were read-only. Integration preserved the newer main design approvals and made no application-code changes to the verified branch.

## Browser proof

The branch app ran at `http://127.0.0.1:5181`, signed in as the contractor owner. Comparisons used the
1440px design viewport and a wider window. Jafar's clarification takes precedence over the earlier page
wrapper: the app fills the available width; 1440 is only the Pencil comparison width. Intentionally narrow
forms retain their own width.

- Week, Day, Month and Map: light/dark captures, existing records, completed/late/unassigned states,
  business closed-hours shading, and a larger window. Month keeps six scrollable rows and three items before
  More. The 390px check reports document/body/viewport all 390px: no page overflow. Phone design remains
  outside this desktop campaign.
- Visit/Assessment/Event previews, event form, Request/Event hand-offs, selected-client booking form,
  Filters, Directions and event-delete confirmation: inspected without submitting customer changes.
- Keyboard move: an Anytime visit moved into a proposal with Right + Enter, then Cancel; no write occurred.
  Escape dismissed the popovers and returned focus.
- Event completion: created **Design proof — event completion (test)**, ID
  `42ff0305-725e-4cd3-b174-2c6cffbcdbce`; pressed Mark complete, saw disabled actions while waiting,
  then reopened with Completed and no completion action. The proof event remains in place.
- The three Jobs dialogs use their real components in a temporary isolated route, removed before commit.
  Finish disabled all choices and displayed Finishing; Apply stayed disabled until selected and disabled
  controls while saving; Create disabled repeat submission and preserved two picked dates after a simulated
  failure. Light/dark captures are named `final-visit-*`, `create-visits-*`, `apply-future-*`.
- The live backlog was empty. `unscheduled-ages-*` uses three in-memory samples (today, one day, seven days),
  including a long client name, to verify blue/amber/red and clipping. No sample jobs were stored.
- A two-stop existing Map day rendered with no browser errors. Both addresses share a stored map location,
  so their markers overlap; that capture does not prove a geographically separated route line.

## Focused checks

- `npx vitest run src/routes/api/schedule/events/\[id\]/complete/complete.spec.ts src/lib/components/schedule/VisitPreview.svelte.spec.ts src/lib/components/schedule/ScheduleJobCreate.svelte.spec.ts`
  — **18 pass**, 11 seconds. Covers tenant/permission validation, idempotent event completion, failures,
  permitted visit actions and booking draft hand-off.
- After the final booking/preview changes, the two affected browser test files ran again: **11 pass**,
  6 seconds. The completion endpoint was unchanged.
- Edited Svelte components were SCSS-preprocessed and compiled directly: 31 in the main slice, then 13
  final refinements, **zero compiler errors or warnings**. The Svelte MCP autofixer found no new correctness
  issues. Its existing navigation warning is a false positive: the page resolves `/(app)/schedule` before
  adding the query and calling goto. Existing form-reset, clock, DOM-measurement and imperative Mapbox
  advisories were inspected and retained; unrelated refactors were not part of this visual build.
- Full-project type/lint/test suites deferred at Jafar's request.

## Database outcome

Migration `20261019080728_schedule_event_completion.sql` was applied remotely using psql, with its ledger
insert in the same transaction. MCP confirmed nullable timestamptz and the matching migration version.
Do not reapply. No RLS or permission changes, backfill, default or new index.

## Scope retained

Existing scheduling commands, permissions, email-only notices, query ownership, the live Sunday week-start
and bounded team picker remain. Day booked hours count timed work; undated/Anytime work has no invented
hours. No customer job, reminder, invoice or payment was changed during this visual proof.
