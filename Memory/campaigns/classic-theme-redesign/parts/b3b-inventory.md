# B3b — remaining shared parts

**Stage:** B3b.1 done — Jafar approved sections 09–11 (light and dark) on 2026-10-15 ("your design approved")
and saved `classic.pen`. **Next:** build B3b.2–B3b.4 in code, then B5.

**Decision (2026-10-15):** Jafar compared two full sets of the 14 parts in Pencil — A "polished" (approved
look, rough edges fixed) and B "new concept" (tray footers, ink selection, card rows, dark toasts) — and
answered "A". B was deleted. Pencil is the visual guide for this redesign, not the old `design-classic`
modules (Jafar, same day).

**Where it lives:** `classic.pen` → `Classic design system · light` and `· dark`, sections 09–11. The 14
reusable masters sit in the light page; the dark page holds instances plus state examples. Masters: Dialog ·
default, Confirm dialog · destructive, Dropdown menu, Popover · information, Tabs, Segmented control · icons,
Search input, Filter chip, Avatar · initials, Table row, Date picker, Banner · success, Toast · success,
Tooltip. Next to each master are state examples (hover, focus, disabled, selected, error, loading).

**What A changed from the earlier draft:** no light-green fills in light mode; tabs show counts, a green
underline when chosen and a green ring on keyboard focus; menu has a group label, record-type icon colours, a
disabled item with its reason and a red danger item below a divider; confirm shows what will be removed;
table rows have tick boxes, hover arrow button and a green left edge when selected; date picker separates
today (outline) from the chosen day (filled) and has a Today button; banners are white with a tinted icon
tile; toasts carry Undo/Retry (the live `Toast` already supports one action). New token
`classic2-solid-rose` (#BE123C light, #E11D48 dark) for red buttons with white text — add it to
`src/lib/styles/_classic-theme-tokens.scss` when building.

**Build notes:** the app components already exist (`Dialog`, `ConfirmDialog`, `DropdownMenu`, `Popover`,
`Tabs`, `SegmentedControl`, `SearchInput`, `FilterChip`, `Avatar`, `DataTable`, `CalendarPicker`/
`DateTimePicker`, `Banner`, `Toast`, `Tooltip` under `src/lib/components`). Restyle them for Classic only via
the theme foundation; keep their behaviour. The menu's "Needs a job first" reason and the confirm's preview
line need checking against each real caller before use — show them only where the app already knows the fact.

**Leftovers:** the unmerged `codex/classic-b3b-shared-parts` branch holds the superseded review images and an
added "Top-tier UI/UX (Dribbble)" line for the plan; carry that line over when the plan document is next
saved, then remove the branch and its worktree.
