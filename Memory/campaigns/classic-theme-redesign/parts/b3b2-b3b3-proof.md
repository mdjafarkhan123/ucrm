# B3b.2 and B3b.3 — completed shared parts

**Stage:** Complete 2026-10-15; integrated through `codex/classic-before-b5`. B3b.4 was already integrated.
Next is B5. Jafar confirmed every other session was closed before recovery.

**Recovered:** B3b.2 commit `d48a29c6` contained the overlay implementation, without live proof.
B3b.3 commit `76956cd3` contained only a task note, so its controls were implemented here.
The visual agreement remains B3b.1 Option A, approved 2026-10-15, saved in `classic.pen` sections 09–11.
No new screen concept or contractor workflow was introduced.

**Built and corrected:** Classic Dialog, ConfirmDialog, DropdownMenu, Popover, Tabs and segmented icons;
SearchInput, FilterChip, Avatar, DataTable and CalendarPicker. Portal/primitive elements require global
selectors under the Classic root guard: the recovered scoped selectors were discarded by Svelte.
Added explicit dialog-title classes for the installed Bits UI DOM. Disabled menu reasons use the caller's
existing `note`; no reason is invented. Destructive text uses the readable rose token, while solid buttons
use solid rose. Selected tabs retain neutral count backgrounds in light mode.

Rows preserve caller-owned selection, sort and activation; selected rows have a green edge. Where the
caller has row activation but no custom actions, Classic gets a hover/focus arrow. The existing table
selection copies now use SvelteSet. Search, filter reset and avatar fallback retain their existing behavior.
DateTimePicker reuses CalendarPicker, so it receives the calendar updates without another implementation.
Today stages the date through the existing callback and respects readonly/disabled, min/max, unavailable
dates, disabled dates and validation; it never saves a record. Botanical hides the Classic-only footer.

**Evidence:** Focused ESLint, Prettier, whitespace and Svelte-autofixer checks pass. Existing segmented DOM
measurement effects were retained; they measure the moving selection marker rather than derived data.
Live authenticated preview at `/dev-preview/shared-parts`: 1440/1100 light/dark plus 390 regression;
search/reset, filtering/reset, selection, keyboard row opening, tabs, segmented choices, dialog dismissal,
confirmation cancellation, popover/menu dismissal and disabled items pass. Today works and is disabled
when minValue excludes today. Real Clients and Schedule screens checked. Screenshots are
`/tmp/classic-shared-*.png`; check script `/tmp/classic-before-b5-check.cjs`. Botanical checked using the
same server with `DESIGN_SHELL_PREVIEW=botanical`; no Classic tokens or overlay styling leak.

No full-project check: Jafar requested focused verification because the full Svelte check used 4.2 GiB RAM.
Stop the temporary preview server after proof. Preserve main's unrelated uncommitted instructions/Memory.

**Pencil match, 2026-10-15:** Jafar found list rows smaller than `Clients · 1440` (`iJgiT`). Fixed: 32px list
avatars with 11px bold initials on all five lists; capital, spaced column titles (sortable ones too) in a
36px header with the sorted one in ink; 64px rows, 14px names, 13px body text; 19px status and tag chips;
tags as one chip plus "+N"; Lead amber. The rest of the approved Clients layout (book tiles, dark card,
filters in the card header, phone above email, Person/Company line) is stage L work, not built yet.
