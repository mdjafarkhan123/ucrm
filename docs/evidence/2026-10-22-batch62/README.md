# Batch 62 — white buttons as raised keys

Approved B (Pencil `SU6gO`, Jafar 2026-10-22). Built in `ui/Button.svelte` (secondary/tertiary, danger,
switched on), the joined groups in `calendar/CalendarBar.svelte`, `schedule/ScheduleControls.svelte` and
`marketing/CampaignBlockEditor.svelte` (one key, a thin `--color-border` line between buttons), and the
unavailable More button in `ui/DropdownMenu.svelte`. Tokens in `_variables.scss` (light, dark, dark pop-ups).

Checked on the branch's own dev server (port 5262), signed in as the Raad LTD owner, at 1440:
- Job page, light and dark: pencil, history, More, Add visits, Start timer, ⋯, Add are raised keys with no line;
  Create invoice is the only green button. More on hover lifts and warms as drawn.
- Schedule toolbar, light and dark: ‹ Today ›, Map | Filters one key each; Unscheduled switched on shows its green
  border and label; off it is a plain key (`after-schedule-toolbar-unscheduled-on-light.png`; before:
  `before-schedule-toolbar-light.png`).
- The test account's theme was switched back to dark afterwards. No form was saved.

Svelte autofixer: CalendarBar clean; Button reports the same SCSS-parse note as the unchanged file (`//` comments
inside `lang="scss"`), so nothing new. No type check or lint (campaign rule).
