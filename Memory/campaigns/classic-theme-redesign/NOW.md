# Classic theme redesign — now

**Goal:** Classic takes the new premium look (Claude concept, chosen 2026-10-13) — first the six record pages, then the whole app including the
Control Room — built from shared blocks, with every existing feature, permission and save rule kept.
**Plan:** `docs/classic-theme-redesign-behavior-contract.md` — first version approved by Jafar 2026-10-13.
**Stage:** Build — `stages/first-version-build.md`; B2 shell integrated into `main`.

**Done:** Parts 1, 2, 2B (all six record pages approved), 3, B1 and B2 — build order B1–B12 approved 2026-10-13
("all agreed"); [B1 tokens verified](../../../docs/research/classic-theme-b1-2026-10-13.md); B2 shell built,
live-checked and integrated 2026-10-14. Message (not Text) and Settings pages in the next stage recorded in
the plan. Lighter record header approved 2026-10-14 (track without icon tiles, key-fact tiles kept, phone
layout) — recipe § Record page structure.

**Next:** B3 is active in `/home/jafar/Ucrm/.worktrees/classic-b3` on `codex/classic-b3` (base `ed18f953`). No B3 source files have changed yet. B1 already installs the approved `classic2-*` tokens on Classic pages and pop-ups; the shared components still use older generic variables, so B3 must connect their Classic styling to those approved tokens without changing Botanical. The separate `crm-design-system` A2a work is an Appearance chooser/notice demo, not the token foundation and not a B3 dependency. See [B3 checkpoint](parts/b3-shared-ui.md). The approved Settings-in-main-search addition belongs to the first later Settings stage, after the first version.

**Limits:** The old Dashboard body still has two phone contrast findings on small buttons; B3 owns shared
button styling. Settings remains on its older layout and clips at phone width and enlarged text; its layout is
planned for the later Settings stage. See the B2 proof note.
