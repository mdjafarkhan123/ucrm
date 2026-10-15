# B3b — remaining shared parts inventory

**Stage:** B3b.1 designed in Pencil; awaiting Jafar's visual approval and save.
**Next:** Jafar reviews sections 09–11 on both `Classic design system · light` and `· dark`, says yes or
requests changes, then saves `classic.pen` with Ctrl+S. Obtain the main integration claim and commit only
the saved Pencil file under its shared-area claim before B3b.2–B3b.4 code work. The live canvas changes
are not yet saved to disk.

On 2026-10-15 the active `/home/jafar/Ucrm/classic.pen` was the correct Classic file. Its light and dark
design-system frames (`GIgyC`, `yRKPF`) contain the B1–B4 foundations. The reusable component list has the
shell, buttons, labels, fields, cards, Save bar and a basic Segmented control. The B3b Dialog,
ConfirmDialog, DropdownMenu, Popover, Tabs, table/list rows, Banner, Toast, Tooltip, Avatar, FilterChip,
SearchInput and date picker are **not yet reusable Pencil parts**. Some already appear as local groups on
approved screens (for example Tabs, avatars and table rows), so copy and refine those examples instead of
inventing a separate style. The approved Schedule popup needs an icon-capable Segmented control.

The application already has named components for those controls, including `Dialog`, `ConfirmDialog`,
`DropdownMenu`, `Popover`, `Tabs`, `DataTable`, `Banner`, `Toast`, `Tooltip`, `Avatar`, `FilterChip`,
`SearchInput`, `SegmentedControl`, `CalendarPicker` and `DateTimePicker` under `src/lib/components`.
Inventory the current behavior and reuse them before changing styling. A file's existence is not proof its
Classic design or states are finished.

**2026-10-15 design:** Under reservation `cd2e1e6c6010`, added 14 reusable masters and their light/dark
specimens to sections 09–11: Dialog, ConfirmDialog, DropdownMenu, Popover, Tabs, icon Segmented control,
SearchInput, FilterChip, Avatar, table row, date picker, Banner, Toast and Tooltip. The specimens show
focus, hover, disabled, selected, destructive, success, error and loading states where relevant. Examples
were adapted from approved screens and use existing `classic2` variables. Structural checks found no layout
problems in the six new sections. Review images are in
`docs/research/classic-b3b-2026-10-15/` (`Sa5uz`/`byn4H`, `C1w5Y`/`Axx59`, `Y8esV`/`dGylR`).

**Handover:** `codex/classic-b3b-shared-parts` in
`/home/jafar/.codex/worktrees/classic-shared-parts/Ucrm` holds this note and review images. The shared
`/home/jafar/Ucrm/classic.pen` remains open in Pencil and unsaved; another design session may have its own
screen work there, so re-read the design-system frames before editing or committing the file. Do not start
implementation until Jafar approves these named sections. After his yes and save, obtain the main
integration claim, commit only `classic.pen` from main, then implement B3b.2–B3b.4 on the branch and run
the app checks.
