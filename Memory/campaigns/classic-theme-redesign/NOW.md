# Classic theme redesign — now

**Goal:** Classic takes the new premium look (Claude concept, chosen 2026-10-13) — first the six record pages, then the whole app including the
Control Room — built from shared blocks, with every existing feature, permission and save rule kept.
**Plan:** `docs/classic-theme-redesign-behavior-contract.md` — first version approved by Jafar 2026-10-13.
**Stage:** Build — `stages/first-version-build.md`; B2 is built and verified on its branch, waiting to merge.

**Done:** Parts 1, 2, 2B (all six record pages approved), 3 and B1 — build order B1–B12 approved 2026-10-13
("all agreed"); [B1 tokens verified](../../../docs/research/classic-theme-b1-2026-10-13.md). Message (not Text)
and Settings pages in the next stage recorded in the plan.

**Next:** Integrate B2 from branch `codex/classic-b2` into current `main` under a separate integration
reservation, preserve work already present in the main workspace, run the combined checks, and push. Then
start B3 (shared cards, buttons, fields and pills). The approved Settings-in-main-search addition belongs to
the first later Settings stage, after the first version. The `crm-design-system` worktree still owns only its
Appearance demo; its shared shell files were untouched.

**Limits:** The old Dashboard body still has two phone contrast findings on small buttons; B3 owns shared
button styling. Settings remains on its older layout and clips at phone width and enlarged text; its layout is
planned for the later Settings stage. See the B2 proof note.
