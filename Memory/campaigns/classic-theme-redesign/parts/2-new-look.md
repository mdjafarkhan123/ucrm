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

- [x] Claude concept drawn 2026-10-13 — Settings Home (`XwqtP`) and Business profile (`ofzTY`). Jafar: "This
      will be our classic design … No more old version."
- [x] 0. `classic.pen` holds both frames, committed in `daf368cc`.
- [x] Design review 2026-10-13 (recipe step 5 at full size, app code compared, WCAG contrast measured). Fixes
      below; product questions added to plan § Still unclear.
- [ ] Jafar answers the plan's § Still unclear design questions (six ideas, old screens, Home and Reports,
      "Control room" name, Business group split, category pills) and agrees the fixes; record his answers.
- [ ] Apply the agreed fixes to both screens; re-export and check.
- [ ] Rebuild the Classic design-system page from recipe § Palette (with the contrast fixes) and the reference
      screens: named tokens with light and designed dark values; parts — Sidebar, Top bar, Card, Group header,
      Setting row (with optional status pill — the app shows "Incomplete" / "Not set"), Form card header,
      Field (input, select, locked, textarea), Toggle row, Buttons, Tab pill, Status pill, Count chip,
      Featured card, Save bar (resting and unsaved), rail cards. Point both screens at them; check dark mode.
      The old page (`lkPLl`, dark `lVZIm`) also feeds Home and Reports — retire it per Jafar's answer.
- [ ] Replace raw hex values in the recipe with the token names.

## Review fixes proposed to Jafar (2026-10-13)

1. Contrast (WCAG AA 4.5:1 for text): `#98A2B3` small text 2.6 → `#667085`; placeholder `#8A93A3` 3.1 →
   `#667085`; sidebar group label `#5E6B7E` 3.5 → `#7D8899`; green breadcrumb, "Ready", "Live preview"
   `#16A34A` 3.0 → `#15803D`; "In review" `#D97706` 2.9 → `#B45309`. 10px eyebrows → 11px.
2. Setup status header says "2 to do" but only Payments needs action → "1 to do".
3. One-tile group (Automation) leaves half its card empty → the tile spans the full width.
4. Regional and Service area cards differ in height → equal heights.
5. App wording: currency lock "Currency is locked because a quote has already been sent to a customer.";
   Address subtitle ends "Optional." (drop the per-field tag); top search "Search clients, work, or
   conversations"; "Radius (miles)" + "miles" chip says it twice → label "Radius".
6. Save bar: Business profile is a full-page form, so the app's bar is always visible with Save disabled until
   a change — draw its resting state too.

## Next

Wait for Jafar's answers, then apply fixes and rebuild the design-system page. Part 2B follows this part.
