# C1c — Live sidebar: coloured icons

**State:** Done — merged into main 2026-10-17 and checked on main's running app.

**Agreed:** Jafar is happy with the live sidebar's layout (2026-10-17) and declined a new sidebar design ("Version B", deleted). Only the icons take colour by meaning. Approved 2026-10-17 in `concept.pen` board "Live sidebar · coloured icons" (Today / light / dark). The current page stays brand green with a white icon. The `/jafar` panel keeps neutral icons.

**Built:** `tone` on `NavItem` (`src/lib/components/layout/navigation.ts`), set per item in `SharedAppShell.svelte`; `Sidebar.svelte` colours the icon via `--sidebar-item-tone`. Section colour families `time`, `conversation`, `growth`, `review` added to `_variables.scss` (light and dark), mapped to existing base colours.

**Checked:** Live screenshots at 1440 (light, dark, collapsed) and 390 (phone menu), owner login; computed icon colours match the map. Type check and slow suites deferred to campaign end (Jafar, 2026-10-17).

**Next:** Nothing. Type check runs with the campaign's final checks.

**Tiles (2026-10-18):** Jafar kept the live groups and asked for the soft coloured tile behind each icon. Built:
24 tile in `--color-<tone>--surface`, 14 icon, `--radius-tile-small`; white tile on hover; current page = white
tile with a green icon on the green row. `concept.pen` Sidebar part now uses the live groups. Checked with
Playwright (owner): 1440 light/dark, hover, collapsed, 390 phone menu.
**Rolled back the same day (Jafar):** the live sidebar is back to coloured icons only (`Sidebar.svelte` as before
`0f7d6e94`). The concept sidebar in `concept.pen` keeps its tiles and the live groups.
