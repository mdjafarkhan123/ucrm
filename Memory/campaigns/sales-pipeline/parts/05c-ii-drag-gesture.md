# Part 5C-ii: Drag gesture for both groups

## Scope

Wire `svelte-dnd-action` to the already-built `dragOpportunity()`/`allowedDragTargets()` (5B), add the
schedule-assessment dialog for the one drop that needs input, and browser-verify every row of 5B's approved
transition table for both groups, including that a refused move cannot even accept a drop.

## What shipped

- `src/lib/components/pipeline/PipelineColumn.svelte`: plain `dndzone` (not `dragHandleZone` — Jobber has no
  drag handle, the whole card drags). Each column mirrors its query's cards into a local `items` `$state`,
  one-way synced from the query via `$effect` (a successful move invalidates the board, the refetch corrects
  `items` on its own). `dropFromOthersDisabled` is computed per column from a board-wide `draggingFromStage`
  prop against `allowedDragTargets`, so a disallowed column refuses the drop while hovering, not just on
  release. A same-column drop (reorder) is reverted, not persisted — manual reordering isn't a feature.
- `src/lib/components/pipeline/ScheduleAssessmentDialog.svelte` (new): collects a day + start/end time,
  modeled on `MarkOpportunityLostDialog`, calling back to the column's own `dragOpportunity` call so
  success/failure handling stays in one place.
- `src/routes/(app)/pipeline/+page.svelte`: added the one piece of cross-column state a drag needs —
  `draggingFromStage`, plus one board-wide busy lock while a protected action is being collected or saved.
- Protected drops are server-confirmed rather than visually committed first. Every involved zone immediately
  restores its query-owned cards; a valid move shows a persistent loading toast, waits for the domain command
  and TanStack refresh, then shows success. Failure re-reads truth and shows an error. Refused/backward/outside
  and same-column drops make no request and show no toast.
- `src/lib/components/ui/ToastManager.svelte.ts`, `Toast.svelte`, and `ToastViewport.svelte`: reusable loading
  toast state with the existing spinner pattern, no timeout or dismiss button, `aria-busy`, and reduced-motion
  handling. Scheduling starts this feedback only after its Save passes client validation.
- `src/lib/components/pipeline/OpportunityCard.svelte`: **real bug fix, not just wiring.** The card's
  full-card "open" hit target was a native `<button>`. `svelte-dnd-action`'s drag-start guard refuses to
  start a drag when the pointerdown target has a defined `.value` and isn't the zone's own item root — every
  `<button>` has a `.value` property (empty string, never `undefined`), so with the button stretched over the
  entire card, a drag could never start for a real user, not just in testing. Fixed by swapping it to
  `div[role="button"][tabindex="0"]` with an `onkeydown` handler reproducing Enter/Space activation. Also
  added `role="presentation"` + `onpointerdown` stop-propagation on the owner-avatar control and the `...`
  menu so neither accidentally initiates a drag, and a `cursor: grab`/`grabbing` affordance gated on `canEdit`
  (Jobber has no visible handle, so the cursor is the only cue, and only once there's somewhere to drop).

## Verified

Focused Pipeline/toast vitest suite: 178/178 passing, including new browser-mode regression coverage for a
refused backward drop making no request, delayed success until refresh, schedule-before-save, failure recovery,
and the loading toast. Prettier clean. `npm run check` reports no changed-file issue; its full run is blocked by
four unrelated Team/Profile errors already present in the dirty worktree.

Browser-verified live (2026-08-23, both by Claude via browser automation and by Jafar directly):
- Click-to-open still works (the div-based open target didn't break it).
- A drag correctly picks up a card; only transition-table-valid columns light up as drop targets during the
  gesture -- confirmed "New requests" (backward from "Assessment unscheduled") stays unhighlighted while
  "Assessment scheduled" and "Assessment completed" do.
- Dropping onto "Assessment scheduled" (an `assessment_schedule` target) correctly opened
  `ScheduleAssessmentDialog`; its old visually-relocated behavior is superseded by the approved
  server-confirmed source-stage behavior and must be rechecked live.
- Jafar performed a live plain move (Assessment unscheduled -> Assessment completed, no dialog) himself and
  confirmed it works end to end.

Not yet independently re-confirmed after the live test: the schedule dialog's actual save round-trip, and a
Quotes-group move (`quote_draft -> quote_awaiting_response`, `quote_publish`). Both call the same
`dragOpportunity()` / `/api/pipeline/opportunities/[id]/move` path already covered by 5B's 15 vitest cases and
17 pgTAP assertions, so this is low risk, but note it as unconfirmed rather than assumed.

## Approved follow-up: accidental-drag recovery

Jafar approved the product principle on 2026-08-23, for a later coding session:

- Keep backward dragging blocked.
- Offer a short-lived Undo only when the real domain action is genuinely reversible, is still the latest
  action, and no later change has made reversal unsafe.
- Require confirmation before an irreversible drag action.
- Do not add a permanent generic "Go back" action to the card's three-dot menu.

This is approved behavior, not implemented behavior. Before coding, classify every 5B transition against its
real Request, Assessment, or Quote reverse command and agree the confirmation points, Undo duration,
concurrency guard, and acceptance checks. Do not implement a generic stage write or treat column order as
proof that an action can be reversed.

## Live gate: closed

Jafar directly verified all five live checks on 2026-08-23: backward/refused drop snaps back with no
request or toast; a plain forward drop stays at source showing "Saving change…" then moves and shows
"Change saved." after server-confirmed refresh; a schedule-target drop opens the dialog with no toast until
Schedule is pressed; empty-space drops work across the full column height in both groups; the full 5B
transition table holds, including every refused target. Part 5C-ii is closed.

## Non-goals

The `/pipeline` "Requests above Quotes in two sections vs. Jobber's one board" question (ROADMAP standing
decision) is untouched and not a gate here.

## Source pointers

- `parts/05b-drag-and-move-api.md` -- the approved transition table and the drag endpoint this part wires up.
- `parts/05c-i-quotes-board-read-model.md` -- the Quotes column group and card rendering this part now drags.
