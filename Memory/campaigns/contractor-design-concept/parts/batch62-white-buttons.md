# Batch 62 · White buttons — approved B, built 2026-10-22

- **Why:** Jafar 2026-10-22: the brand-green edge on white buttons (set 2026-10-21) "does not look premium".
- **Approved:** Jafar said yes to **B · raised white key, no line** on 2026-10-22, for every white button
  (secondary, More menu, icon, pencil, danger, joined groups). Unchanged: main, danger-confirm, quiet buttons,
  switched-on (keeps its green border and label on the key), field boxes, filter chips. Option A deleted.
- **Pencil (`concept.pen`):** board `SU6gO`; components `qpjlj`, `nkuNU`, `nIDZt`, `oxEbC` changed at the source,
  Parts board button states, Schedule joined groups and date-box arrows updated; new variables
  `color-surface-key`, `-hover`, `-pressed`. Pencil shadows are the light values.
- **Design skill:** `buttons.md`, `shadows.md`, `borders.md`, `colors.md`, guide rule 7.
- **Tokens added** (`_variables.scss`, light, dark and dark pop-ups): `--color-surface--key`, `--key-hover`,
  `--key-pressed`; `--shadow-button--key`, `--key-hover`, `--key-pressed`. `--shadow-button` is unchanged (chips
  and tabs still use it).
- **Built 2026-10-22** on branch `claude/design-batch62` (`docs/evidence/2026-10-22-batch62/`): `ui/Button`, joined
  groups in CalendarBar, ScheduleControls, CampaignBlockEditor, DropdownMenu's unavailable More. Checked 1440 light
  and dark on the branch server. Merged to main `43e76ae4` with Jafar's pending main edits (his yes, 2026-10-22). Pencil tidy-up of `SU6gO` left.
