# Uplift design refresh

**Status:** Direction and first milestone approved by Jafar on 2026-10-10. Job demo completion is next; later stages require their own detailed planning and visual approvals.

## Summary

Reimagine Uplift as a premium, modern, polished application while preserving its approved capabilities. Jafar approved the forest-green sidebar, warm neutral canvas, white panels, restrained accents, and final balanced typography of the job details concept. The immediate deliverable is a complete job details browser demo, including the sidebar and header, for his approval. The first concept established visual direction; its omitted sections were never approved for removal. Complete that demo before extracting the new design system or redesigning other pages. Browser demos are the review medium; Pencil is omitted. After approval, document the reusable system and repair the existing design skill so future sessions reproduce the same direction. Design the remaining pages in groups before applying their approved designs to the real app.

## Original request and visual authority

Jafar’s original request:

> If you update the design or our current app which will look more premium, more modern, polished based on research, then how would the app looks like on your design? can you design the job details page with apps sidebar, header included with a brand new design system rather using current desing skill? Can you show me a staic html/scss demo version first?

The approved job concept answers that request and is the visual authority for this campaign. Open and render its HTML/CSS before extending it. Follow its actual composition, colors, typography, spacing, and restrained styling; use the final balanced-type version in the preview branch history to distinguish the approved reference from later unfinished edits. Future sessions extend that design rather than independently reinventing it. The existing design skill’s old colors, heading weights, section-border treatment, and blueprints must not override the approved new direction. Retain applicable screen checks, accessibility checks, engineering constraints, and existing product behavior.

Research any design pattern the reference does not cover using relevant primary product sources. Cite the finding that informs the adaptation, then express that pattern in the approved visual language. Completeness alone is insufficient: newly added sections must look like they belong to the same premium, modern, polished interface. Review new sections side by side with the approved reference at desktop and phone widths before seeking Jafar’s approval. The first deliverable remains a standalone HTML/SCSS browser demo, with small JavaScript interactions only for previewing states.

## First milestone: complete job details demo

### Approved visual reference

The latest approved concept is in branch `codex/job-design-concept`, under `design-previews/job-details/`. Preserve its final appearance as the baseline, including 15px main text, 13px supporting details, approximately 17–18px section headings, stronger secondary contrast, and comfortable controls. These describe the approved concept, not a completed accessible design system. Check actual rendered styles before extracting tokens; the demo currently contains successive overrides and fallback font rendering.

### Completeness before approval

Inspect the current job page, its child components, the approved Jobs contract, and the live app. Maintain a coverage checklist that maps each existing section, action, dialog, conditional feature, and permission difference to its demo representation. Inventory the real sidebar and header as well: the initial concept's navigation is illustrative and differs from the real application.

The first inspection identified: job identity/status/facts and source; client/property; products and services; labor; expenses; checklists; visits and recurrence; crew instructions; notes/history; photos/files; signatures; work reports; job totals; costing; billing and payment stages; invoice reminders; visits or periods ready to bill; discount; and property tax. This list starts the audit and does not replace reading the nested components.

Represent title/instructions editing and the page's staged save/cancel bar, along with section-owned editors, visit records and scheduling, report commands, review requests, and close/reopen controls where the implementation offers them. Preserve existing permissions and lifecycle behavior. Layout may adapt to the approved visual direction, but capabilities must remain accounted for. Do not add functionality merely because an older contract mentions it; flag any meaningful code/contract discrepancy for a separate decision.

### Browser scenarios and interactions

Use realistic synthetic data. Cover populated and empty one-off jobs, recurring per-visit and per-period billing, as-needed scheduling, closed jobs, restricted staff, long content, loading, errors, and editing. Mutually exclusive billing modes appear in separate clearly labelled scenarios. Preview controls open their corresponding menus, editors, or confirmations. Changes stay in temporary memory and reset on reload; no real messages, invoices, payments, uploads, or customer actions occur. Clearly distinguish simulated saves from real persistence. Links to destination pages outside the demo are labelled previews.

### Approval evidence

Review the real page read-only using an existing test login, and use its behavior to validate the inventory. Check the demo at desktop and phone widths, including reachable mobile navigation, overflow, long text, keyboard focus, dialog dismissal, and the pinned editing bar. Compare coverage against the current source again before presenting the completed demo. Report what is covered and any remaining gap explicitly. Jafar approves both appearance and completeness; approval of the original concept is not approval of this unfinished milestone.

## After job demo approval

Extract the visual foundations into shared named tokens and reusable demo styles. Build a browser component gallery with controls and states. Repair contradictory or stale design-skill guidance, separating approved new design guidance from the existing app during transition. Keep authoritative values in one place and use the skill as a clear entry point with examples and checks.

Inventory remaining application surfaces, agree page groups and build parts, and produce complete demos from the shared system for Jafar's review. Plan owner, industry-specific, and customer-facing surfaces explicitly rather than assuming the contractor job page establishes their layouts. Carry approved designs into shared Svelte components and real pages only after their visual reviews, preserving workflows and verifying the main journeys live. Detailed rollout parts are not approved yet.

## Still unclear

- No decision blocks the first demo milestone. Complete its inventory before implementation and resolve any new behavior choice with Jafar.
- Remaining page groups, additional surface scope, dark-theme direction, and implementation rollout order will be settled after the complete job demo is approved.

## Not doing

- Pencil designs — browser demos are the chosen review workflow.
- Live app styling, design-skill rewrites, infrastructure, API, schema, or permission changes in the first milestone.
- Feature removal or new product behavior hidden inside a visual redesign.
- Completing missing demo sections in the campaign-creation session: Jafar explicitly requested campaign records only.

## Research and existing authority

- [Jobs behavior contract](jobs-behavior-contract.md) and the current implementation own the existing workflow.
- [Platform overview](platform-overview.md) owns the platform and industry boundaries.
- [Linear interface refresh](https://linear.app/now/behind-the-latest-design-refresh) informed the calmer visual hierarchy.
- [Jobber Job Basics](https://help.getjobber.com/en/articles/job-basics/) informed the original job structure.
- [USWDS design tokens](https://designsystem.digital.gov/design-tokens/) supports reusable named foundations for later system extraction.
- [W3C text resizing](https://www.w3.org/WAI/WCAG21/Understanding/resize-text) informs readability checks beyond default font size.
