# Batch 62 · White buttons — approved B, waiting to be built

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
- **Builder next:** `ui/Button` white kinds (`button--secondary`, danger, icon, menu; drop the `--button--edge`
  green border, keep the pressed/switched-on border) and every joined group in code (Schedule toolbar, date
  arrows); check 1440 light and dark against `SU6gO`.
