# Classic theme redesign — now

**Goal:** Classic takes the new premium look (Claude concept, chosen 2026-10-13) — first the six record pages, then the whole app including the
Control Room — built from shared blocks, with every existing feature, permission and save rule kept.
**Plan:** `docs/classic-theme-redesign-behavior-contract.md` — first version approved by Jafar 2026-10-13.
**Stage:** Build — `stages/first-version-build.md`; B3 shared UI integrated into `main` 2026-10-14; B4 is implemented and screen-checked on `codex/classic-b4-save-bar`, waiting to merge.

**Done:** Parts 1, 2, 2B (all six record pages approved), 3, B1, B2 and B3 — build order B1–B12 approved 2026-10-13
("all agreed"); [B1 tokens verified](../../../docs/research/classic-theme-b1-2026-10-13.md); B2 shell built,
live-checked and integrated 2026-10-14; B3 shared cards and controls screen-checked and integrated 2026-10-14. Message (not Text) and Settings pages in the next stage recorded in
the plan. Lighter record header approved 2026-10-14 (track without icon tiles, key-fact tiles kept, phone
layout) — recipe § Record page structure. Calm slate dark mode approved
2026-10-14 (option D) — recipe § Tokens; B2 shell already takes it.

**Next:** Update B4 against current `main`, rerun `npm run check`, and integrate when the main workspace is clean and its writer reservation is available. Its live Classic and Botanical checks are complete; the full checker hung without output. Jafar approved the two Save bar states in `classic.pen` on 2026-10-15; screenshots and the remaining integration step are in [B4](parts/b4-save-bar.md). B3 remains integrated: the Dashboard small-button contrast findings were fixed through the shared Button, the dark search shortcut label passes, and Botanical’s Dashboard actions and Settings shared styles match main. See [B3 checkpoint](parts/b3-shared-ui.md). The separate `crm-design-system` A2a work is an Appearance chooser/notice demo, not the token foundation and not a B3 dependency. The approved Settings-in-main-search addition belongs to the first later Settings stage, after the first version.

**Alongside:** List pages are designed before later-stage planning (Jafar, 2026-10-14): `Jobs`, `Clients`,
`Requests`, `Quotes` and `Invoices · 1440` are approved. See [Clients list](parts/clients-list.md),
[Requests, Quotes and Invoices](parts/requests-quotes-invoices-lists.md) and `parts/list-pages.md` on branch
`claude/jobs-list-design`. Schedule Week, Day and Month approved 2026-10-15 (no page header; calendar fills the page) —
[Schedule design](parts/schedule-design.md); Unscheduled drawer drawn, waiting for his yes; the remaining Schedule screens are listed in that note's Next. Home/Reports redesign — `../crm-launch-readiness/parts/part-13-home-reports.md`.

**Limits:** Settings remains on its older layout and clips at phone width and enlarged text; its layout is planned for the later Settings stage. See the B2 proof note. The optional service-area field was not present on the test account, so that individual field state was not checked.
