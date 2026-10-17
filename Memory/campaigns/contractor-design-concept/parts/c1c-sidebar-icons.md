# C1c — Live sidebar: coloured icons

**State:** Built on branch `claude/concept-sidebar-variant` (worktree `.worktrees/concept-sidebar-variant`); Waiting to merge.

**Agreed:** Jafar is happy with the live sidebar's layout (2026-10-17) and declined a new sidebar design ("Version B", deleted). Only the icons take colour by meaning. Approved 2026-10-17 in `concept.pen` board "Live sidebar · coloured icons" (Today / light / dark). The current page stays brand green with a white icon. The `/jafar` panel keeps neutral icons.

**Built:** `tone` on `NavItem` (`src/lib/components/layout/navigation.ts`), set per item in `SharedAppShell.svelte`; `Sidebar.svelte` colours the icon via `--sidebar-item-tone`. Section colour families `time`, `conversation`, `growth`, `review` added to `_variables.scss` (light and dark), mapped to existing base colours.

**Checked:** Live screenshots at 1440 (light, dark, collapsed) and 390 (phone menu), owner login; computed icon colours match the map. Type check and slow suites deferred to campaign end (Jafar, 2026-10-17).

**Next:** Jafar saves `concept.pen` (Ctrl+S); commit it on this branch; merge into main.
