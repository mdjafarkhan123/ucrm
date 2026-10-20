# Book work pop-up and time picker brought to the drawing — 2026-10-20

Jafar saw the Schedule booking pop-up and its time picker did not match `concept.pen` (Schedule pop-ups `GsICu`:
Book work `FTWqY`, hand-off `E568E5`; Pickers v2 `uSXlT`, Time box `K5xBS4`). Look only; saving a job, request
hand-off and event hand-off behave as before.

## What changed

- Date and time row: Date | Start → End with every label on one line; arrow-right between Start and End; the
  "Time" group name is for screen readers only; the length chip (hourglass) sits after the pair or under it when
  the row is tight. Shared `ui/TimePicker` + `ui/DateTimePicker`, so New event and every range picker follow.
- Time dial (`ui/TimePickerField`): "Start time" title with the "N hr after start" chip, hour : minute behind one
  indigo band, values fading away from it, no scrollbars or column labels, AM/PM upright switch, footer
  "↑ ↓ turn the dial" and Done. The column turns to the picked value on every pick. Clock tile turns solid
  indigo while open, like the date box.
- First visit: bordered card (radius 16) with a subtle head row and padded body.
- Who is going: `TeamPicker` gains a `chips` mode using the approved `PersonPickChip`; teams over 12 keep the
  search box so the list stays short.
- Notify customer sits under a top line.
- Request / Event hand-off: 44 indigo date tile (month over day), 14/600 day, 13 quiet time with indigo clock.
- `ui/Dialog`: the "lone footer group sits at the right" rule was scoped to Dialog itself and never matched;
  now `:global`, so footers like New event's Cancel / Create sit at the right as `modals.md` says.

## Proof

- Chrome, Raad LTD owner, worktree app on port 5182, 1512 wide: Job tab light and dark, dial open and turning
  (picked 12 moved into the band), Request and Event tabs, New event. Nothing was saved.
  `request-tab-light.jpg` is the Request tab.
- `npx vitest run src/lib/components/schedule/ScheduleJobCreate.svelte.spec.ts` — 7 pass.
- `npx vitest run src/lib/components/ui/CalendarPicker.svelte.spec.ts src/lib/components/ui/date-time.spec.ts
  src/lib/components/schedule/VisitPreview.svelte.spec.ts` — 22 pass.
- Svelte autofixer reports only "expected a valid CSS identifier" on each file: it reads SCSS as plain CSS; Vite
  compiled every file and the pages rendered without errors.
