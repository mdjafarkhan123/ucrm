# 2 — Design: new Classic look and its design system

**Campaign:** classic-theme-redesign · **Plan:** `docs/classic-theme-redesign-behavior-contract.md` § Direction
agreed so far (New Classic look, design system rebuilt, colour), § Still unclear
**Stage:** Design
**Code:** `classic.pen` in the main folder (Pencil saves there); commit it from main in its own commit, under a
claim covering `classic-pen`.
**Done when:** Jafar approves the reviewed reference screens and the rebuilt Classic design-system page (light
and dark); his answers to every § Still unclear design question are recorded in the plan.
**Read next:** the design recipe (`docs/classic-theme-redesign-design-recipe.md`); design skill § Design in
Pencil first; Pencil's skill and `execute.md`.

## Steps

- [x] 2026-10-13: concept drawn (`XwqtP`, `ofzTY`), reviewed, Jafar's answers applied (plan § Design review
      answers; § Green buttons, black-green sidebar; § Settings additions). Sales & work uses the app's teal
      (tile `#F3FBFC`/`#DEF3F7`, icon `#0E6171`, solid `#118197`, dot `#15A4C1`). Jafar approved both
      reference screens ("approved"), deep green version, `38bce4e2`.
- [x] Sidebar direction closed 2026-10-13 — three structurally different comparisons (split rail,
      navigation tiles and editorial column) were drawn, then rejected and deleted at Jafar's request.
      Keep the sidebar already present on the approved Settings reference screens.
- [ ] Jafar answers the "Soon" menu items question (plan § Still unclear).
- [x] 2026-10-13: superseded frames archived — record concepts renamed `Archive · … · first concept` and moved
      to the archive row (top right) beside the old design-system pages `lkPLl`/`lVZIm`.
- [x] 2026-10-13: Classic design-system page rebuilt — `Classic design system · light` (`GIgyC`) and its dark
      copy (`yRKPF`), top left of `classic.pen`, reference screens beside them (renamed `Settings · Home ·
      1440`, `Settings · Business profile · 1440`). 70 `classic2-*` tokens with light and dark values; 40
      parts (list in recipe § Tokens). Both reference screens are now instances of those parts, and their
      light export is pixel-identical to the approved screens. Dark mode checked on all four frames.
- [x] Raw hex in the recipe replaced with token names (recipe § Tokens holds the values).
- [ ] Jafar presses Ctrl+S in Pencil; commit `classic.pen` from main.
- [ ] Jafar approves the design-system page, light and dark (new since his last look: dark values, the
      collapsed sidebar, field focus and error states, toggle off, resting Save bar wording "No unsaved
      changes / Change any field, then press Save.").

## Review fixes (agreed and applied 2026-10-13)

Listed in plan § Design review answers. Values the design-system page must keep: small grey text and
placeholders `#667085` (never `#98A2B3`/`#8A93A3` for text); sidebar group label `#7D8899`; green text
`#037741`; amber status text `#B45309`; no text under 11px. Still to draw: the Save bar's resting state (Save
disabled, nothing changed) — full-page forms show the bar all the time.

## Next

Show Jafar the two design-system frames and the dark versions; record his yes here and in the plan. The old
page `lkPLl` still feeds the Home and Reports screens (crm-launch-readiness Part 13) through the old
`color-*` tokens — leave it until those screens are restyled. Part 2B follows this part.
