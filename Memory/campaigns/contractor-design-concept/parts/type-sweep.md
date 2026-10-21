# Type sweep — typed-in font sizes to the variables

**Campaign:** contractor-design-concept. **Approved:** Jafar 2026-10-21 ("yes do the sweep, use variable"); he
chose to start it in the next session. **Stage:** built and screen-checked 2026-10-21 (`docs/evidence/2026-10-21-type-sweep/`); Pencil sweep done 2026-10-21 (below).
**Table (Jafar, 2026-10-21):** `typography.md` → Scale; tokens in `src/lib/styles/_variables.scss` are already set
(smaller 12, overline 12, small 14, label 14, base 14, large 16, larger 20, largest 24, display 28, stat 34).

## Goal

About 318 `font-size: <number>px|rem` lines in 102 files under `src` bypass the variables, so the table cannot
reach them. 64 are under 12px, which breaks the never-under-12 rule (`min-font-12` memory). Replace each with the
matching `var(--typography--fontSize-…)`, no new tokens.

Counts before: 13px ×74, 12px ×60, 11px ×44, 14px ×21, 16px ×21, 28px ×16, 15px ×13, 20px ×7, 17px ×7, 18px ×6,
10px ×4, 0.8125rem ×4, and a tail. Find them with
`grep -rnE "font-size: *[0-9.]+(px|rem)" src --include='*.svelte' --include='*.scss'`.

## Mapping (decide by role, not only by number)

- 9, 10, 11 → `-overline` (12). Never below 12.
- 12 → `-small` (14) for dates, meta, pills; `-overline` (12) for uppercase group and table labels.
- 13 → `-label` (14). 14 → `-base`. 15, 16, 17 → `-base` or `-large` by role. 18 → `-large` or `-larger`.
- 20 → `-larger`. 24 → `-largest`. 28 → `-display`. 32, 34 → `-stat`. 36, 40, 48 → `-jumbo`, `-extravagant`.
- Hard-coded `rem` follows the same table. Pencil text on off-scale sizes (~400) is a separate, later sweep.

## Watch for

Text that grows (12→14, 13→14) can wrap or clip in tight places: pills, table cells, calendar cards, number cards,
the sidebar. Fix a clip with spacing, not by shrinking text. Do it in a worktree under a claim, in a few commits
by area, not one giant one.

## Done when

Zero typed-in sizes left except icons or fixed artwork (list any kept, with the reason); screens checked at a
1440 window, light and dark: Home, Jobs, Schedule, a record page (job, client), a pop-up, a form. No Chrome
extension? Use Playwright with the owner login in `Login.md` (log in after the page hydrates), as in
`docs/evidence/2026-10-21-batch52/README.md`. Evidence in `docs/evidence/`, committed and pushed.

## Pencil sweep (2026-10-21)

`concept.pen`: 9,096 text items; 393 typed-in sizes now use the variables (7/9 → overline; 15 → large when
semibold/bold, else base; button labels base; 17, 18 → large, date range and month title → larger; 22 → larger;
26 → largest; 30 → stat; 40 → jumbo; 52 → extravagant). Kept: 5 handwritten signatures at 64 (artwork). Typed-in
left: 5. Clipping check: 287 → 288; the one new is `$15,200` on the money card (board `N4Lsst`), 3px wider than its
box at 34 but inside the card. File-type tabs and avatar initials checked at 12.
