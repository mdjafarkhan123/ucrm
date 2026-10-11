# CRM design system

**Status:** Planning — registered 2026-10-11; initial surface, theme and authority decisions agreed with Jafar on 2026-10-11. Full first-version scope and build order are not yet approved.
**Current part:** Part 1 Fresh scope, tracked in `Memory/campaigns/crm-design-system/ROADMAP.md`.

## Summary

Each organization can choose a theme that changes the CRM’s appearance and, where supported, its layout, similar to choosing different desktop experiences on Linux.

Jafar clarified on 2026-10-11 that this campaign should also achieve the Botanical campaign's visual goal: a premium, modern, polished, colourful CRM with improved composition, hierarchy, typography and spacing. Botanical is the redesigned experience offered through this design system. This is a fresh statement of intent; the previously chosen first-version Business Workspace boundary still stands unless Jafar expands it.

## Problem and audience

Organizations should be able to choose how their CRM looks and is arranged. The goal includes layout differences where a theme offers them, rather than limiting choice to colors.

## Fresh-start boundary

Jafar requested a fresh campaign and subsequently agreed with consolidating the Botanical redesign goal here. Preserve the old campaign records while the useful work and references are transferred and checked; close its active tracker after that handover. The selectable-design foundation is inspected for reuse. Earlier task order, broader rollout scope and individual approvals do not automatically define this campaign. Existing application code remains in place.

The implemented theme foundation supplies the technical starting position. Earlier redesign requirements enter this campaign only when Jafar explicitly brings them across, as with the visual goal below.

On 2026-10-11 Jafar explicitly asked to bring the Botanical campaign's goal into this campaign. Its saved goal and reference may now inform that visual objective. Old task order, individual approvals and broader rollout scope are not automatically imported. The earlier campaign records remain unchanged during planning; Jafar's additions are recorded before the full agreement is synthesized.

## Two main stages — direction confirmed 2026-10-11

Jafar described this campaign as building the theme foundation, then creating a real theme on top of it. These are two delivery stages, each containing smaller reviewable tasks; they are not two single-session implementation tasks or an approved detailed build order.

1. **Verify and finish the theme foundation.** Reuse the shared shell, presentation frames and relevant existing proof. Establish what is already complete and fill the remaining gaps so an organization can save its design choice, authorized owners/admins can change it, and staff can apply changes safely. Keep shared records, capabilities and permissions authoritative across designs. The source check already confirms shell separation, but does not establish a saved organization choice, a picker or complete theme coverage.
2. **Complete Botanical as a real theme.** Use that foundation to deliver the premium, polished redesign throughout the agreed Business Workspace: page layouts, controls, forms, dialogs and relevant states, with light/dark/follow-device appearance and phone support. Use Botanical v3 as a visual example. Develop missing designs through focused reviews and verify the implemented journeys while preserving Classic.

The foundation must support theme selection independently of any one visual design; Botanical supplies the first complete redesigned experience alongside Classic. Existing work is assessed and reused before new work is planned. This campaign's success requires both stages, including their appropriate verification.

Jafar explicitly approved this two-stage goal in the follow-up: "finish the theme foundation and then create a complete botanical theme on that foundation." Detailed delivery parts and remaining release rules still need agreement.

## Botanical starting point and proposed design workflow

Jafar asked to reuse his original redesign intent, recorded literally under [Jafar's intent and approved reference](uplift-design-refresh-behavior-contract.md#jafars-intent-and-approved-reference), and reconfirmed the Botanical job-details demo as the approved visual starting point. The preserved v3 reference and captures are in [Botanical foundations](design/botanical-v3/README.md). The existing [sidebar/header approval record](design/botanical-v3/sidebar-approval.md) identifies sidebar variant 2 revision 2 and header B revision 4, with exact source revisions and coverage. These records preserve approved appearance; they do not establish complete page capabilities, unshown states, dark-mode readiness or release verification.

**Clarification requested:** Jafar is deciding whether to create the visual design system before further demos or derive the complete system after all screens are approved. He favors reviewing and implementing small portions gradually.

**Recommendation awaiting agreement:** Begin with the demonstrated Botanical foundations, then grow the design system with each approved portion:

1. Check and reuse the existing extracted colors, typography, spacing, panels and other demonstrated visual rules. Keep one authoritative home for each shared rule; do not restart extraction or invent every missing component in advance.
2. Design one coherent portion and its relevant states in a focused browser demo, using the established foundations. A new form or calendar can be explored before its pattern is added to the shared system.
3. Jafar reviews that portion; record its exact approved revision, coverage and exclusions.
4. Promote the approved reusable patterns into Botanical guidance and align the relevant design-skill modules. Implement or extend shared app components for that approved portion; keep page-specific arrangements local. Check effects on already approved uses when a shared pattern changes.
5. Implement and verify the portion in the real, private Botanical experience, then use the established patterns in the next demo. Continue until the agreed Business Workspace coverage is complete; final completeness and release checks remain distinct from individual visual approvals.

The theme foundation is the machinery for selecting and delivering a design. The Botanical design system is its visual rules and reusable patterns/components. They are related deliverables with different responsibilities. A complete visual system grows from the screens and states actually needed; neither a single approved screenshot nor waiting for every page establishes all component behavior.

**Evidence:** GOV.UK separately reviews reusable patterns for usefulness and uniqueness, then reviews implementations for usability, consistency and versatility; it also describes components evolving through a lifecycle. [Contribution criteria](https://design-system.service.gov.uk/community/contribution-criteria/), [Component lifecycle](https://design-system.service.gov.uk/community/component-lifecycle-statuses/). Our incremental design/review method is an adaptation of that discipline, not a claim of GOV.UK-equivalent user research. The earlier Botanical plan already describes a starter system growing through focused approvals; the proposal here makes that method explicit within this campaign's narrower scope.

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
- Agree the proposed starter-system and incremental demo/review/implementation workflow above. Jafar has confirmed the two-stage goal and gradual intent; he asked for a recommendation on when the visual system should be created.
- Expected behavior for incomplete coverage, accessibility, unsaved work, and switching failures.

No answer is inherited from the earlier plans. Coverage, initial themes, chooser authority, layout flexibility and appearance modes were answered fresh in this campaign; the remaining questions follow those decisions.

## Success direction

An organization chooses an available theme and the application uses that theme’s appearance and supported layout. Concrete journey and failure checks follow agreement on the first version.
