# CRM design system

**Status:** Planning — registered 2026-10-11. First-version scope and build order are not yet approved.
**Current part:** Part 1 Fresh scope, tracked in `Memory/campaigns/crm-design-system/ROADMAP.md`.

## Summary

Each organization can choose a theme that changes the CRM’s appearance and, where supported, its layout, similar to choosing different desktop experiences on Linux.

## Problem and audience

Organizations should be able to choose how their CRM looks and is arranged. The goal includes layout differences where a theme offers them, rather than limiting choice to colors.

## Fresh-start boundary

Jafar requested a fresh campaign. The existing `selectable-design-experiences` and `uplift-design-refresh` campaign records remain untouched; cleanup is postponed until he asks. Their plans, tasks, design approvals, and build order do not define this campaign. Existing application code remains in place.

Only the implemented theme foundation from the selectable-design campaign may inform this campaign’s starting position. Do not use the old redesign campaign as a source of new requirements.

## Existing foundation — reported, awaiting focused recheck

Earlier selectable-design work reports a shared shell, separate Classic/Botanical presentation frames, Classic as the current default, a private Botanical preview, and selected-only loading/shared-shell proof.

Relevant source pointers:

- `src/lib/components/layout/SharedAppShell.svelte`
- `src/lib/components/layout/presentations/ClassicFrame.svelte`
- `src/lib/components/layout/presentations/BotanicalFrame.svelte`
- `docs/research/selectable-real-shell-2026-10-11.md`

These are technical starting points, not approved theme choices for this campaign. Registration has not reverified the application or established complete theme coverage or an organization theme picker.

## First version

Not yet agreed. Part 1 checks the built foundation and researches proven approaches before bringing product choices to Jafar.

## Still unclear

- First-release themes and application surfaces covered.
- Who may choose an organization’s theme and how staff experience a switch.
- Supported layout differences and light/dark appearance.
- Expected behavior for incomplete coverage, accessibility, unsaved work, and switching failures.

No answer is inherited from the earlier plans. The previously asked surface-coverage question remains unanswered; research precedes further questions.

## Success direction

An organization chooses an available theme and the application uses that theme’s appearance and supported layout. Concrete journey and failure checks follow agreement on the first version.
