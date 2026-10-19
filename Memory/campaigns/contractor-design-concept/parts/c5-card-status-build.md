# Card and StatusBadge — branch build

**Stage:** Implemented; final Pencil comparison pending. Not ready to merge.
**Branch:** `codex/approved-shared-schedule-build`
**Workspace:** `/home/jafar/.codex/worktrees/approved-shared-build/Ucrm`
**Claim:** `fff612924b43`, owner `codex-approved-build`; retained until integration.
**Authority:** Jafar 2026-10-19: build Card/StatusBadge, then Schedule including event completion and approved Jobs pop-ups. Claude reviews and merges; never merge to main. Pencil is read-only; do not change its open file or edit design skills.

## Implementation

- Card: radius 16, no shadow, padding 20; headed cards reuse CardHeader and expose icon/tone/hint/actions. Existing children remain direct descendants to preserve caller layouts. Removed public form's shadow override so shared Card rolls out there too.
- StatusBadge: same five semantic tones and text; full pill radius, 600 weight, base 12px/6px dot, small and existing compact alias 11px/5px dot. Follows approved `cards.md`/`badges.md`; no behavior change or new dependency.
- Inspected all Card imports and StatusBadge consumers. CSS-only work does not trigger a performance audit.

## Proof

- Focused ESLint passed for Card and StatusBadge; Prettier and `git diff --check` passed.
- Svelte compiler after SCSS preprocessing: both files, zero warnings. Svelte MCP autofixer on preprocessed components: zero issues/suggestions. Raw SCSS nesting produced false unused-selector warnings, resolved by checking preprocessed code.
- Running branch app at `http://127.0.0.1:5181`: signed in with existing contractor owner. Form editor Card and Jobs compact status labels checked at 1440 and 390 widths, light/dark; narrow table uses its existing horizontal scroll. No records changed. Screenshots: `docs/evidence/2026-10-19-card-status/`.

## Blocker and next

Pencil app is running, but its socket file `/home/jafar/.pencil/socket/pencil-desktop.sock` is missing; Claude retains an existing connection. Both the provided Pencil tool and a fresh bridge returned transport-not-connected. Do not restart Pencil while Claude has unsaved work. Jafar asked to reconnect; asked him to have Claude save and reopen Pencil with concept.pen. No Pencil files or app state changed.

1. Once Pencil reconnects, read approved Card/StatusBadge frames, compare light/dark screenshots, fix differences and tick Built ✅ only then. Drawing cleanup belongs to Claude.
2. Commit/push any corrections; Claude reviews and merges.
3. Continue Schedule in the same branch after reviewing `c8-schedule.md`, actual frame references and relevant database/permission tests. Schedule and its three Jobs pop-ups are approved; no Schedule code or remote database changed yet.
