# Card and StatusBadge — branch build

**Stage:** Merged 2026-10-19 at Jafar’s explicit request.
**Branch:** `codex/approved-shared-schedule-build`
**Workspace:** `/home/jafar/.codex/worktrees/approved-shared-build/Ucrm`
**Claim:** `fff612924b43`, owner `codex-approved-build`; release after the integration push.
**Authority:** Jafar 2026-10-19: build Card/StatusBadge, then Schedule including event completion and approved Jobs pop-ups. Original boundary: Claude reviews and merges; superseded by Jafar’s explicit merge request on 2026-10-19. Pencil is read-only; do not change its open file or edit design skills.

## Implementation

- Card: radius 16, no shadow, padding 20; headed cards reuse CardHeader and expose icon/tone/hint/actions. Existing children remain direct descendants to preserve caller layouts. Removed public form's shadow override so shared Card rolls out there too.
- StatusBadge: same five semantic tones and text; full pill radius, 600 weight, base 12px/6px dot, small and existing compact alias 11px/5px dot. Follows approved `cards.md`/`badges.md`; no behavior change or new dependency.
- Inspected all Card imports and StatusBadge consumers. CSS-only work does not trigger a performance audit.

## Proof

- Focused ESLint passed for Card and StatusBadge; Prettier and `git diff --check` passed.
- Svelte compiler after SCSS preprocessing: both files, zero warnings. Svelte MCP autofixer on preprocessed components: zero issues/suggestions. Raw SCSS nesting produced false unused-selector warnings, resolved by checking preprocessed code.
- Running branch app at `http://127.0.0.1:5181`: signed in with existing contractor owner. Form editor Card and Jobs compact status labels checked at 1440 and 390 widths, light/dark; narrow table uses its existing horizontal scroll. No records changed. Screenshots: `docs/evidence/2026-10-19-card-status/`.

## Pencil comparison and next

Pencil reconnected after Jafar restarted it. Read-only comparison 2026-10-19: Foundation `z1I4U` (Status pill), `hHVVU` (Card header), `BFOzz` (parts); the pill’s full radius, 5×11 padding, 6px dot, 12/600 text and header anatomy match. Compared light/dark live proof with Foundation and its theme tokens; no Pencil edits, save, file switch or skill edits.

Also completed page-parts batch 4; see `c5-page-parts-build.md`. Card body now explicitly uses the base text size. Shared parts and Schedule are integrated. Claude retains ownership of Pencil draft cleanup.

Next: the remaining approved shared-parts queue. Schedule/database outcome is recorded in `docs/evidence/2026-10-19-schedule/README.md`; do not repeat the applied migration.
