# CRM design system

**Status:** Planning — two-stage goal, core theme choices and incremental Botanical workflow agreed 2026-10-11. Foundation agreement and delivery sequence approved 2026-10-12; Botanical starter/coverage planning is active. Implementation remains outstanding.
**Current part:** Part 2 Botanical starter/coverage planning, tracked in `Memory/campaigns/crm-design-system/ROADMAP.md`.

## Summary

Each organization can choose a theme that changes the CRM’s appearance and, where supported, its layout, similar to choosing different desktop experiences on Linux.

Jafar clarified on 2026-10-11 that this campaign should also achieve the Botanical campaign's visual goal: a premium, modern, polished, colourful CRM with improved composition, hierarchy, typography and spacing. Botanical is the redesigned experience offered through this design system. This is a fresh statement of intent; the previously chosen first-version Business Workspace boundary still stands unless Jafar expands it.

## Problem and audience

Organizations should be able to choose how their CRM looks and is arranged. The goal includes layout differences where a theme offers them, rather than limiting choice to colors.

## Fresh-start boundary

Jafar requested a fresh campaign and subsequently agreed with consolidating the Botanical redesign goal here. The [transfer check](research/crm-design-system-consolidation-2026-10-12.md) preserves useful work, exact approvals, references and outstanding limits. Earlier Botanical and selectable-design trackers redirect here; their historical roadmaps and evidence remain available. Earlier task order, broader rollout scope and individual approvals do not automatically define this campaign. Existing application code remains in place.

The existing private shell and loading mechanism supply the technical starting position; saved selection and safe application remain outstanding. Earlier redesign requirements enter this campaign only when Jafar explicitly brings them across, as with the visual goal below.

On 2026-10-11 Jafar explicitly asked to bring the Botanical campaign's goal into this campaign. Its saved goal and reference inform that visual objective. Old task order, individual approvals and broader rollout scope are not automatically imported; only explicitly reconfirmed references and scoped approvals enter the current agreement.

## Two main stages — direction confirmed 2026-10-11

Jafar described this campaign as building the theme foundation, then creating a real theme on top of it. These are two delivery stages, each containing smaller reviewable tasks; they are not two single-session implementation tasks or an approved detailed build order.

1. **Verify and finish the theme foundation.** Reuse the shared shell, presentation frames and relevant existing proof. Establish what is already complete and fill the remaining gaps so an organization can save its design choice, authorized owners/admins can change it, and staff can apply changes safely. Keep shared records, capabilities and permissions authoritative across designs. The source check already confirms shell separation, but does not establish a saved organization choice, a picker or complete theme coverage.
2. **Complete Botanical as a real theme.** Use that foundation to deliver the premium, polished redesign throughout the agreed Business Workspace: page layouts, controls, forms, dialogs and relevant states, with light/dark/follow-device appearance and phone support. Use Botanical v3 as a visual example. Develop missing designs through focused reviews and verify the implemented journeys while preserving Classic.

The foundation must support theme selection independently of any one visual design; Botanical supplies the first complete redesigned experience alongside Classic. Existing work is assessed and reused before new work is planned. This campaign's success requires both stages, including their appropriate verification.

Jafar explicitly approved this two-stage goal in the follow-up: "finish the theme foundation and then create a complete botanical theme on that foundation." The foundation agreement and delivery sequence were subsequently approved on 2026-10-12. Botanical portions and remaining release details are resolved through Part 2 and focused design reviews.

## Botanical starting point and agreed design workflow

Jafar asked to reuse his original redesign intent, recorded literally under [Jafar's intent and approved reference](uplift-design-refresh-behavior-contract.md#jafars-intent-and-approved-reference), and reconfirmed the Botanical job-details demo as the approved visual starting point. The preserved v3 reference and captures are in [Botanical foundations](design/botanical-v3/README.md). The existing [sidebar/header approval record](design/botanical-v3/sidebar-approval.md) identifies sidebar variant 2 revision 2 and header B revision 4, with exact source revisions and coverage. These records preserve approved appearance; they do not establish complete page capabilities, unshown states, dark-mode readiness or release verification.

**Workflow agreed in Jafar's follow-up on 2026-10-11:** Begin with the demonstrated Botanical foundations, then grow the design system with each approved portion:

1. Check and reuse the existing extracted colors, typography, spacing, panels and other demonstrated visual rules. Keep one authoritative home for each shared rule; do not restart extraction or invent every missing component in advance.
2. Design one coherent portion and its relevant states in a focused browser demo, using the established foundations. A new form or calendar can be explored before its pattern is added to the shared system.
3. Jafar reviews that portion; record its exact approved revision, coverage and exclusions.
4. Promote the approved reusable patterns into Botanical guidance and align the relevant design-skill modules. Implement or extend shared app components for that approved portion; keep page-specific arrangements local. Check effects on already approved uses when a shared pattern changes.
5. Implement and verify the portion in the real, private Botanical experience, then use the established patterns in the next demo. Continue until the agreed Business Workspace coverage is complete; final completeness and release checks remain distinct from individual visual approvals.

The theme foundation is the machinery for selecting and delivering a design. The Botanical design system is its visual rules and reusable patterns/components. They are related deliverables with different responsibilities. A complete visual system grows from the screens and states actually needed; neither a single approved screenshot nor waiting for every page establishes all component behavior.

**Evidence:** GOV.UK separately reviews reusable patterns for usefulness and uniqueness, then reviews implementations for usability, consistency and versatility; it also describes components evolving through a lifecycle. [Contribution criteria](https://design-system.service.gov.uk/community/contribution-criteria/), [Component lifecycle](https://design-system.service.gov.uk/community/component-lifecycle-statuses/). Our incremental design/review method is an adaptation of that discipline, not a claim of GOV.UK-equivalent user research. The earlier Botanical plan already describes a starter system growing through focused approvals; the agreed workflow here makes that method explicit within this campaign's narrower scope.

## Planning status and next planning step

The two-stage goal, core organization-theme decisions and incremental Botanical workflow are agreed. Jafar approved the complete foundation agreement and delivery sequence on 2026-10-12. This completes foundation planning, with implementation and verification still outstanding.

- **Theme foundation planning:** The [Stage A foundation agreement](crm-theme-foundation-behavior-contract.md) consolidates preview/save/switch/failure behavior, completion checks and release boundaries. Its linked delivery design establishes the feasible approach; the [foundation delivery parts](../Memory/campaigns/crm-design-system/stages/theme-foundation.md) are approved. Fresh-reader review passed and Jafar approved this planning step on 2026-10-12. Existing shell separation can be reused; saved organization selection and safe switching are not established by the inspected source.
- **Botanical planning:** Visual starting point and review method agreed. The [Stage B proposal](crm-botanical-theme-behavior-contract.md) now records starter gaps, initial portions, coverage order, skill maintenance and selected-only page/component delivery. Its linked route/overlay inventory and delivery map remain proposals for scoped review. Detailed visual decisions for later portions are made incrementally.

Foundation planning is complete; the active planning focus is Botanical. Building and proving the foundation remains its own subsequent delivery work; planning completion must not be reported as implementation completion.

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

The [primary-source research](research/crm-design-system-theme-approaches-2026-10-11.md) supports permission-controlled organization activation, preview before activation and shared behavior behind appearance/layout choices. Concrete foundation details and delivery order are approved in the linked Stage A agreement. That approval does not approve unshown Botanical designs or public release of incomplete coverage.

## Still unclear

- Botanical's starter-system gaps, first focused design portions and detailed coverage/release plan; plan these now that foundation planning is approved.

Coverage, initial themes, chooser authority, layout flexibility and appearance modes were answered fresh in this campaign. Jafar subsequently brought across Botanical's visual goal and references explicitly. Preserve those decisions while reviewing only the remaining proposed details.

## Success direction

An organization chooses an available theme and the application uses that theme's appearance and supported layout. The Stage A agreement defines foundation journey/failure checks; Stage B adds complete Botanical coverage and the final real Classic↔Botanical customer activation proof.
