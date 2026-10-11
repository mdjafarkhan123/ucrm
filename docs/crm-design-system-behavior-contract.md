# CRM design system

**Status:** Planning — registered 2026-10-11; initial surface, theme and authority decisions agreed with Jafar on 2026-10-11. Full first-version scope and build order are not yet approved.
**Current part:** Part 1 Fresh scope, tracked in `Memory/campaigns/crm-design-system/ROADMAP.md`.

## Summary

Each organization can choose a theme that changes the CRM’s appearance and, where supported, its layout, similar to choosing different desktop experiences on Linux.

## Problem and audience

Organizations should be able to choose how their CRM looks and is arranged. The goal includes layout differences where a theme offers them, rather than limiting choice to colors.

## Fresh-start boundary

Jafar requested a fresh campaign. The existing `selectable-design-experiences` and `uplift-design-refresh` campaign records remain untouched; cleanup is postponed until he asks. Their plans, tasks, design approvals, and build order do not define this campaign. Existing application code remains in place.

Only the implemented theme foundation from the selectable-design campaign may inform this campaign’s starting position. Do not use the old redesign campaign as a source of new requirements.

## Existing foundation — focused source check complete

The [focused foundation check](research/crm-design-system-foundation-2026-10-11.md) confirms a shared shell, separate Classic/Botanical frames, Classic as the current default and a localhost-only Botanical preview. Existing selected-frame browser evidence was inspected, not rerun. Page content and global styling remain shared; this is not a complete theme system or release proof.

Relevant source pointers:

- `src/lib/components/layout/SharedAppShell.svelte`
- `src/lib/components/layout/presentations/ClassicFrame.svelte`
- `src/lib/components/layout/presentations/BotanicalFrame.svelte`
- `docs/research/selectable-real-shell-2026-10-11.md`

There is no organization theme picker or saved organization selection in the inspected selection path. These technical starting points carry no earlier campaign approvals. Jafar's fresh choices below establish this campaign's initial direction; unfinished Botanical designs still need review.

## First version

### Agreed direction — 2026-10-11

- Themes cover the whole signed-in Business Workspace, including pages, forms and dialogs.
- The initial choices are Classic and a completed Botanical. Existing Botanical code is a starting point; unfinished screens require Jafar's design approval.
- The business owner and administrators may change the theme for the whole business. Other staff use the organization's selected theme.
- Customer-facing booking/portal pages and the Uplift Control Room are outside this campaign's first-version theme coverage.
- Page-content layouts may differ too, while preserving the same records, available features and actions. Jafar named Botanical v3 as an example, not a requirement to copy every illustrated layout or behavior.
- Both themes support light, dark and follow-device appearance. Each person chooses their appearance on their device independently of the organization's design.
- Businesses choose a finished design. They keep their existing business name and logo; custom colors, fonts and user-arranged layouts are outside the first version.
- Existing and new businesses start with Classic until an owner or administrator deliberately chooses another design.
- Staff already working see a notice when the organization's design changes. They can apply it after saving or discarding unfinished work; their next fresh visit uses the latest organization choice automatically.

The [primary-source research](research/crm-design-system-theme-approaches-2026-10-11.md) supports permission-controlled organization activation, preview before activation and shared behavior behind appearance/layout choices. The remaining decisions below must be settled before the full first-version agreement and build order.

## Still unclear

- Jafar said "I also have more to say" after answering the eight scope questions. Keep planning open and hear his additions before final synthesis or approval.
- Expected behavior for incomplete coverage, accessibility, unsaved work, and switching failures.

No answer is inherited from the earlier plans. Coverage, initial themes, chooser authority, layout flexibility and appearance modes were answered fresh in this campaign; the remaining questions follow those decisions.

## Success direction

An organization chooses an available theme and the application uses that theme’s appearance and supported layout. Concrete journey and failure checks follow agreement on the first version.
