# B3b — remaining shared parts inventory

**Stage:** Preparation; [shared-parts order](../stages/shared-parts.md). **Next:** claim the Classic Pencil
design-system area, re-read the live file, and start B3b.1. The `classic.pen` file is
shared with other design sessions; this note records read-only findings, not a Pencil edit.

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

**Do next:** read the current Pencil instances again because other sessions may edit them; organize the needed
variants and states on both design-system frames; show Jafar the completed parts;
then implement B3b.2–B3b.4. Do not change `classic.pen` while its current design ownership is unclear.
