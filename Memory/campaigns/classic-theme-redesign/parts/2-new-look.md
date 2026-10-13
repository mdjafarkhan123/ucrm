# 2 — Design: new Classic look and its design system

**Campaign:** classic-theme-redesign · **Plan:** `docs/classic-theme-redesign-behavior-contract.md` § Direction
agreed so far (New Classic look, design system rebuilt, colour), § Still unclear
**Stage:** Design
**Code:** `classic.pen` in the main folder (Pencil saves there); commit it from main in its own commit, under a
claim covering `classic-pen`.
**Done when:** Jafar approves the reviewed reference screens and the rebuilt Classic design-system page (light
and dark); his answers to the three questions below are recorded in the plan.
**Read next:** the design recipe (`docs/classic-theme-redesign-design-recipe.md`); design skill § Design in
Pencil first; Pencil's skill and `execute.md`.

## Steps

- [x] Claude concept drawn 2026-10-13 — `Settings · Home · Claude concept · 1440` (`XwqtP`) and `Settings ·
      Business profile · Claude concept · 1440` (`ofzTY`), below the older screens. Jafar 2026-10-13: "This
      will be our classic design … No more old version."
- [ ] 0. Confirm `classic.pen` holds both frames and is committed; if it is uncommitted, claim with
      `--adopt-existing` and commit it.
- [ ] Design review of both reference screens — Jafar asked for one ("need review on what you designed").
      Run recipe step 5 at full size; also check usefulness for an owner (find a setting in seconds?),
      hierarchy, WCAG AA contrast (small `#98A2B3` text is likely too light), click targets, consistency
      between the screens, and how Stripe, Linear and Attio settings solve the same things. Give Jafar each
      finding with a recommendation; fix what he agrees.
- [ ] Ask Jafar the three questions below; record the answers in the plan.
- [ ] Rebuild the Classic design-system page from recipe § Palette and the reference screens: named tokens
      with light values and designed dark values; reusable parts — Sidebar, Top bar, Card, Group header,
      Setting row, Form card header, Field (input, select, locked, textarea), Toggle row, Buttons, Tab pill,
      Status pill, Count chip, Featured card, Save bar, rail cards. Point both screens at them; check dark mode. The old page (`lkPLl`, dark `lVZIm`) also feeds the Home and Reports screens — see
      question 3 before retiring it.
- [ ] Replace raw hex values in the recipe with the token names.

## Questions for Jafar, word for word

1. "Which of these six ideas should the app really get? A 'Search settings' box · the Setup status card · the
   text balance on Settings home · the 'What customers see' preview · the 'Where this is used' card · the
   'You have unsaved changes' words on the Save bar."
2. "The old screens in the Pencil file — the first job, quote, invoice and Settings designs — shall I delete
   them, or move them to an 'Archive' corner of the file?"
3. "The Home and Reports screens you are reviewing for the launch were drawn in the old look. Shall they
   switch to the new look before you approve them?"

## Next

Steps in order from step 0. Part 2B (record pages in the new look) follows this part.
