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
- [x] 2026-10-13: Jafar chose to hide the "Soon" menu items (plan § Direction).
- [x] 2026-10-13: superseded frames archived — record concepts renamed `Archive · … · first concept` and moved
      to the archive row (top right) beside the old design-system pages `lkPLl`/`lVZIm`.
- [x] 2026-10-13: Classic design-system page rebuilt — `Classic design system · light` (`GIgyC`) and its dark
      copy (`yRKPF`), top left of `classic.pen`, reference screens beside them (renamed `Settings · Home ·
      1440`, `Settings · Business profile · 1440`). 70 `classic2-*` tokens with light and dark values; 40
      parts (list in recipe § Tokens). Both reference screens are now instances of those parts, and their
      light export is pixel-identical to the approved screens. Dark mode checked on all four frames.
- [x] Raw hex in the recipe replaced with token names (recipe § Tokens holds the values).
- [x] 2026-10-13: Jafar saved in Pencil; `classic.pen` committed from main (`41d154c6`).
- [x] 2026-10-13: Jafar approved the design-system page, light and dark, with its new dark values, collapsed
      sidebar, field states and resting Save bar ("ok including earlier … i approve your recommendation").

## Review fixes (agreed and applied 2026-10-13)

Listed in plan § Design review answers. Values the design-system page must keep: small grey text and
placeholders `#667085` (never `#98A2B3`/`#8A93A3` for text); sidebar group label `#7D8899`; green text
`#037741`; amber status text `#B45309`; no text under 11px. Still to draw: the Save bar's resting state (Save
disabled, nothing changed) — full-page forms show the bar all the time.

## Next

Part 2 is Done (2026-10-13). The old page `lkPLl` still feeds the Home and Reports screens (crm-launch-readiness
Part 13) through the old `color-*` tokens — leave it until those screens are restyled. Continue with Part 2B.

## Coloured icons (approved 2026-10-13)

Jafar asked to carry the Settings coloured icon tiles onto the new screens, then set the rule: colour must be
meaningful and representative. Drawn on the six record pages per recipe § Colour rule — key facts neutral
unless their value needs attention, invoice row blue, automation amber, waiting items amber, the rest neutral.
Home and Reports still use the old look, so left alone. Jafar said "yes" 2026-10-13 to Job, Quote, Invoice, Request, Payment and Client details · 1440; saved and committed.

## Lighter record header (approved 2026-10-14)

Jafar felt the header cards were crowded. Claude drew `Concept · Lighter record header` in `classic.pen`
(approved card beside the lighter one for Job, Quote, Invoice, Request, plus four 390 phone cards). Jafar:
"its better but we can keep icon as it is now for the bottom row" — track tiles removed, key-fact tiles kept.
Applied the same day to the Job, Quote, Invoice, Request and Payment `· 1440` screens, so they match the board
and the recipe; B5 builds from them.

## Calm slate dark mode (approved 2026-10-14)

Jafar found the Pencil dark mode "Neon/alien/tech dashboard like" and preferred the app's current Jobber dark
look. Options A–C (border tweaks on green-black) were drawn and dropped; D (Jobber slate surfaces, solid brand
green main buttons, softer `#4CB782` green text) approved: "I approved D". Applied to every `classic2-*` dark
value in `classic.pen` (42 green buttons repointed to `solid-green`), `_classic-theme-tokens.scss` and the
recipe. The live app's content area still shows the old Jobber colours until B3+ restyles it.
