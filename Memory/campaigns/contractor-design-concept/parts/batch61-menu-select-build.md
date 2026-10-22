# Batch 61 — shared menu and select build

**Stage:** Waiting to merge. Approved Menu B and Select B, Pencil board `bM4k0` (2026-10-22).
**Branch/worktree:** `codex/build-batch61` · `/home/jafar/Ucrm/.worktrees/build-batch61`.
**Claim:** `7178952f7c9b` (`shared-menu-select`); keep until safe integration.

`src/lib/components/ui/Select.svelte` now draws the approved 40px trigger, chevron well,
status tile, radio choices, selected edge and disabled state. `DropdownMenu.svelte` draws the
approved panel, icon squares, headings, current-choice mark and final red action strip.
Both retain Bits UI keyboard and focus behavior; existing call sites need no hand-drawn copy.
The remaining native `<select>` controls were replaced in `FieldWorkerHome`,
`TeamAccessEditor`, and `ImportMapStep`. Suggestion `<datalist>` options remain native
because they are text suggestions, not dropdown selects. Source search now finds no
native `<select>` in `src/`.

**Proof:** Svelte autofixer clean on both scripts/markup, both components compiled with SCSS,
focused ESLint and Prettier passed, and `git diff --check` passed. Browser preview at
`127.0.0.1:5174/pipeline`: select open/selected, keyboard Escape, action menu, light/dark,
desktop and 390px phone checked. No server mutation performed.
The follow-up browser pass checked the team role picker, field worker property and request
forms, customer-to-property choice/reset, and 390px light/dark form states. The import
mapping component compiled and passed focused checks; its live mapping step was not
entered because doing so requires uploading a file.

**Next:** Integrate after main's other writers save their uncommitted work. From a clean main,
claim `main-integration`, merge this branch, run focused combined checks, update `NOW.md` to
mark Batch 61 built, push main, then release both claims.
