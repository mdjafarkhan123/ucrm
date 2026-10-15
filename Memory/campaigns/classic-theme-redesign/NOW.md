# Classic theme redesign — now

**Goal:** Classic takes the new premium look (Claude concept, chosen 2026-10-13) — first the six record pages, then the whole app
**Target:**  Dont convert exsiting real app screen design to classic pencil design. Its not a conversion work neither a random design. A new design concept like how top ui/ux engnieer design their product on Dribbble. Jafar Like their design. Premium, Polished, Modern, Colored, Clarity, Clam, Meaningful. New design should meet what contractors really want to see - no vauge. Design should be based on real world related top product research to know what really works and what not, which layout or element to add not to add, their positioning etc. Different type of color (multicolor) is allowed where suits. Color should carries meaning or reason.

Control Room — built from shared blocks, with every existing feature, permission and save rule kept.
**Plan:** `docs/classic-theme-redesign-behavior-contract.md` — first version approved by Jafar 2026-10-13.
**Stage:** Build — `stages/first-version-build.md`; B3 shared UI integrated into `main` 2026-10-14; B4 Save bar merge candidate prepared on `codex/b4-save-bar-integration`, based on `32e5b80d`; waiting for the current main writer to save and release the Schedule Pencil work.

**Done:** Parts 1, 2, 2B (all six record pages approved), 3, B1, B2 and B3 — build order B1–B12 approved 2026-10-13
("all agreed"); [B1 tokens verified](../../../docs/research/classic-theme-b1-2026-10-13.md); B2 shell built,
live-checked and integrated 2026-10-14; B3 shared cards and controls screen-checked and integrated 2026-10-14; B4 Save bar live-checked and prepared for integration 2026-10-15. Message (not Text) and Settings pages in the next stage recorded in
the plan. Lighter record header approved 2026-10-14 (track without icon tiles, key-fact tiles kept, phone
layout) — recipe § Record page structure. Calm slate dark mode approved
2026-10-14 (option D) — recipe § Tokens; B2 shell already takes it.

**Next:** B4 is in published integration candidate `origin/codex/b4-save-bar-integration` at `a5b40c46`, with merge commit `1add398c` based on main `32e5b80d`. The root main checkout now has an active Schedule Pencil reservation and uncommitted `classic.pen` changes; I will update main after that work is saved and the reservation released. B4 live checks and screenshots are in [B4](parts/b4-save-bar.md), and its Svelte/TypeScript check remains inconclusive. B3 remains integrated: the Dashboard small-button contrast findings were fixed through the shared Button, the dark search shortcut label passes, and Botanical’s Dashboard actions and Settings shared styles match main. See [B3 checkpoint](parts/b3-shared-ui.md). The separate `crm-design-system` A2a work is an Appearance chooser/notice demo, not the token foundation and not a B3 dependency. The approved Settings-in-main-search addition belongs to the first later Settings stage, after the first version.

**Alongside:** List pages are designed before later-stage planning (Jafar, 2026-10-14): `Jobs`, `Clients`,
`Requests`, `Quotes` and `Invoices · 1440` are approved. See [Clients list](parts/clients-list.md),
[Requests, Quotes and Invoices](parts/requests-quotes-invoices-lists.md) and `parts/list-pages.md` on branch
`claude/jobs-list-design`. Schedule Week, Day and Month approved 2026-10-15 (no page header; calendar fills the page) —
[Schedule design](parts/schedule-design.md); Unscheduled drawer and its states approved 2026-10-15 (a new concept, its own panel beside the calendar); the New job dialog from an empty slot approved the same day; its Request and Event tabs and the Job error message approved the same day, with coloured kind icons; the remaining Schedule screens are listed in that note's Next. Home/Reports redesign — `../crm-launch-readiness/parts/part-13-home-reports.md`.

**Next session — replan, not build (Jafar, 2026-10-15):** restructure the roadmap so each session can take the next
step on its own. (1) Write Jafar's loop into the plan: per screen design → build → live check → remove the old
look and leftover variants (e.g. quick-create variant B) → next. (2) Add **B3b remaining shared parts** before B5:
Dialog, ConfirmDialog, DropdownMenu, Popover, Tabs, table/list rows, Banner/Toast/Tooltip, Avatar, FilterChip,
SearchInput, date picker, Segmented control icons — first as parts on the Pencil design-system page copied from
approved screens, then in code like B3. (3) Order every approved design after it: B5–B12 record pages, the five
lists, Schedule, Settings, Home/Reports. (4) A done-check per step. (5) Jafar approves the new order once. Use
planning.md § Split the work.

**Limits:** Settings remains on its older layout and clips at phone width and enlarged text; its layout is planned for the later Settings stage. See the B2 proof note. The optional service-area field was not present on the test account, so that individual field state was not checked.
