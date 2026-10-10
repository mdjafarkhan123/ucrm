# Uplift design refresh

**Status:** Visual direction and incremental review process approved by Jafar on 2026-10-10. Fresh campaign setup authorized in this conversation. Individual new demos and live-app rollout still require their own approvals.

## Summary

Redesign Uplift into a premium, modern, polished, colourful and attractive product, using Botanical v3 as the approved visual direction. Improve layout, information hierarchy, typography, spacing and composition as well as colour. Preserve existing capabilities, permissions and approved workflows. Establish a starter design system from the selected reference, then grow it through small reviewed demos. Jafar reviews each focused portion in a standalone HTML/SCSS browser demo before it reaches the real app. Revisions are agreed together; shared design decisions update the guidance and design skill before dependent implementation. Each session handles one focused part, so later agents extend the same identity rather than reinventing it. This document supersedes the leftover earlier campaign instructions, including the requirement to finish the whole job demo before extracting foundations.

## Jafar's intent and approved reference

Original request:

> If you update the design or our current app which will look more premium, more modern, polished based on research, then how would the app looks like on your design? can you design the job details page with apps sidebar, header included with a brand new design system rather using current desing skill? Can you show me a staic html/scss demo version first?

Jafar additionally requested a colourful and attractive design and approved the interpretation below in this conversation:

- A substantial redesign of composition and hierarchy, with polished everyday use; changing colours alone does not satisfy the goal.
- A distinctive Botanical identity: rich forest-green navigation, warm neutral canvas, clear panels, purposeful accent colours, tinted surfaces and clear emphasis. Preserve this character as new screens are added; colour should aid understanding as well as appeal.
- Research-informed usability and interaction patterns, adapted to this visual language. Research supports decisions; it does not replace Jafar's visual approval or establish that our adaptation is user-tested.
- A new system derived from the selected design, rather than the existing design skill's old appearance.
- Complete capabilities and relevant states, reviewed in small browser demos before implementation.

The canonical selected reference is `/demo/job-details`, redirecting to `/demo/job-details/index.html`, maintained in `static/demo/job-details/`. Read its README and render the actual HTML/CSS before extracting or extending it. The selected version is Botanical v3 with balanced typography and five sample visits. The earlier `codex/job-design-concept` branch is historical and may inform coverage after inspection; it is not the visual authority.

Approval covers v3's visual direction, not every illustrative navigation item, missing section, interaction, mobile treatment or accessibility result. Its omissions never authorize feature removal. The current reference contains successive style overrides; derive foundations from final rendered values, not just its first declarations. Its README describes roughly 15px main text, 13px supporting text and 18px section headings; verify the actual font rendering before documenting exact values.

## Authority and starter design system

Preserve a stable v3 baseline and desktop/phone screenshots before modifying preview styles. Keep the baseline available for side-by-side comparison with later demos; identify its source revision and viewport sizes with the reference assets. Avoid creating another application copy.

Extract the demonstrated colours and their roles, typography, spacing, radii, borders, shadows, buttons, panels and composition into permanent design guidance. Show representative component states in a browser gallery as foundations mature. Patterns v3 does not establish, such as complex forms or calendars, remain explicitly unapproved until their focused demo review. The starter system can be established before the complete job demo is finished.

Use one authoritative home for each design value or rule. The design skill should be a clear entry point to that guidance, approved references, examples and verification, rather than a competing copy. Inspect the current skill for contradictory visual rules and update it before new design work uses it. Retain applicable screen checks, accessibility practices and engineering constraints. Keep existing save/cancel semantics and other workflow rules traceable to their behavior authority when reorganizing the skill.

During transition, read the current design skill for its checks and existing behavior constraints; its old colours, section-border treatment and layout blueprints do not override v3. Document how approved new guidance applies to migrated surfaces while untouched surfaces retain their current appearance. Skill changes alone must not restyle the live app.

The approved visual reference governs appearance; approved product contracts and verified implementation govern existing behavior. Jafar decides any proposed change to either. When these sources disagree, investigate and present the concrete choice before dependent work.

## One focused part at a time

For each portion:

1. Inspect existing components, source and relevant live behavior. List the capabilities, permission differences and states this portion must preserve. Reuse or extend suitable shared components.
2. Research unresolved interaction or layout patterns using official product sources and maintained standards. Record what was verified and what is our adaptation; follow settled decisions without repeating unnecessary research.
3. Build a standalone HTML/SCSS demo with realistic fictional data and small JavaScript interactions where needed. Simulate changes in memory, resetting on reload. Clearly label simulated actions and destination previews; use no real sends, payments, uploads or API writes.
4. Check desktop (1440px) and phone (390px), relevant populated/empty/loading/error/editing states, long content, keyboard focus, dismissal, navigation and overflow. Present the demo URL, what is included and any gaps to Jafar.
5. Revise with Jafar until approved. Record the exact demo revision, portion, states, date and remaining exclusions in the permanent guidance or linked approval record. Existing v3 approval does not approve newly designed patterns.
6. Promote shared decisions into the system and align the skill. Keep page-specific arrangements local. A shared change needs an impact check against previously migrated surfaces and approval for material visible consequences.
7. Implement only the approved portion using shared Svelte components and project conventions. Compare the real result with the approved demo, verify the main journey live and relevant edge cases with appropriate checks, then commit and push.

Stop at the current part's done-check and checkpoint for the next session. Do not automatically combine several redesign parts. A section and its editor can form a coherent part; all detail pages together cannot. Separate demo review and implementation checkpoints so an agent cannot infer approval from having built its own demo.

## Initial sequence and later rollout

The first assignment is reference preservation and starter design guidance, leaving the live app and selected demo unchanged. Next align the design skill, then prepare a sidebar/header demo against the real navigation and permissions, including reachable phone navigation. Implement that shell only after its review; account for its effect across pages before rollout. Then inventory job details and agree small demo/implementation parts with Jafar.

For that job inventory, inspect nested components and the live page as well as the [Jobs contract](jobs-behavior-contract.md). The prior inspection suggested job identity/status/source, client/property, products/services, labor/expenses, checklists, visits/recurrence, crew instructions, notes/history, photos/files, signatures, work reports, totals/costing, billing/payment stages, reminders, ready-to-bill visits/periods, discount and property tax. Treat this as a starting checklist, not verified completeness. Include relevant editors, save/cancel, scheduling, review requests and close/reopen actions. Show mutually exclusive job/billing modes in separate labelled scenarios when the relevant part needs them.

The whole-app ambition includes the Business Workspace, Uplift Control Room and customer-facing surfaces. Follow the [platform overview](platform-overview.md): share the visual language while keeping layouts and workflows suited to each industry and audience. Existing feature campaigns continue to own their behavior. Inventory remaining surfaces and settle rollout order incrementally; this plan does not approve detailed designs or broad cross-app changes in advance.

## Research pointers

These are reference leads, not proof that every v3 decision is validated. Verify the relevant source when using it for a new decision:

- [USWDS design tokens](https://designsystem.digital.gov/design-tokens/): reusable named visual foundations.
- [Atlassian colour](https://atlassian.design/foundations/color/): colour roles and accents.
- [Linear interface refresh](https://linear.app/now/behind-the-latest-design-refresh): hierarchy and composition.
- [Jobber Job Basics](https://help.getjobber.com/en/articles/job-basics/): contractor job structure; use the project Jobber skill for workflow work.
- [W3C text resizing](https://www.w3.org/WAI/WCAG21/Understanding/resize-text): readability beyond default sizing.

## Still unclear

- Patterns absent from v3, dark-theme direction and any phone treatments requiring new design approval; resolve in the relevant focused parts.
- Exact remaining surface inventory and rollout order beyond the initial sequence; agree after inspection, rather than redesigning all pages at once.
- Completeness of the current job demo and real-app readiness remain unverified. Neither blocks extracting the demonstrated foundations.

## Not doing

- App, demo, token or design-skill changes in the campaign-creation session; this session creates the handoff records only.
- Feature removal, new workflows, schema, API, permission or infrastructure changes hidden inside a visual redesign.
- A full-app redesign in one session, a second application copy, or implementation before the relevant demo approval.
- Treating the historical branch or old design skill as the selected visual authority; browser demos are the review medium, not Pencil.
