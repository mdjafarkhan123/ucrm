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
- [ ] Sidebar concepts — Jafar asked for different sidebar concepts. First try (2026-10-13), board of four
      (A grouped list, B Jobber-style Create button, C Stripe/Linear Shortcuts and More, D Slack-style compact
      rail): Jafar said "I dont like that" and deleted it. Next session: ask him what he disliked and what he
      wants to see before drawing again.
- [ ] Jafar answers the "Soon" menu items question (plan § Still unclear).
- [ ] Move superseded frames to an Archive area of `classic.pen`.
- [ ] Rebuild the Classic design-system page from recipe § Palette (with the contrast fixes) and the reference
      screens: named tokens with light and designed dark values; parts — Sidebar, Top bar, Card, Group header,
      Setting row (with optional status pill — the app shows "Incomplete" / "Not set"), Form card header,
      Field (input, select, locked, textarea), Toggle row, Buttons, Tab pill, Status pill, Count chip,
      Featured card, Save bar (resting and unsaved), rail cards. Point both screens at them; check dark mode.
      The old page (`lkPLl`, dark `lVZIm`) also feeds Home and Reports — retire it per Jafar's answer.
- [ ] Replace raw hex values in the recipe with the token names.

## Review fixes (agreed and applied 2026-10-13)

Listed in plan § Design review answers. Values the design-system page must keep: small grey text and
placeholders `#667085` (never `#98A2B3`/`#8A93A3` for text); sidebar group label `#7D8899`; green text
`#037741`; amber status text `#B45309`; no text under 11px. Still to draw: the Save bar's resting state (Save
disabled, nothing changed) — full-page forms show the bar all the time.

## Next

Ask Jafar about the sidebar concepts (above), then draw new ones; afterwards archive old frames and rebuild
the design-system page. Part 2B follows this part.
