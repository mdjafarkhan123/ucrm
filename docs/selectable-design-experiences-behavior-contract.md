# Selectable design experiences

**Status:** Planning 2026-10-11. Jafar authorized architecture investigation and wants Classic preserved alongside Botanical. Implementation and remaining rollout choices are not yet approved.

## Summary

Organizations will be able to use different complete presentations of the same CRM. Classic preserves the
current app; Botanical follows its separately approved demos. Layout, component structure and styling may
differ, while records, permissions, calculations and saving behaviour remain shared. Only the selected
design's exclusive code, styles and required assets should download within its workspace, alongside shared
foundations and pages the user actually opens or legitimately preloads. This is more than colour theming.
Botanical's sidebar/header approvals remain valid. This prerequisite is settled before their live rollout.

## Settled requirements

- Classic is the working name for the existing experience; preserve its actual appearance and behaviour.
- Botanical grows through focused demo approval. Its illustrative job-details reference does not establish
  complete coverage. Existing permissions and features cannot disappear in either presentation.
- Shared behaviour is referenced, not copied into separate design pages. Presentations may use different
  markup and arrangement. Shared controls are reused where their full presentation fits both experiences.
- Shared `design` guidance routes agents to separate Classic/Botanical guidance. Recover Classic from the
  pre-Botanical Git tree, reconciling stale instructions with verified implementation. Botanical guidance
  contains approved foundations and explicitly unfinished coverage. Future designs follow the same model.
- Shared base styles are distinct from design tokens and visual defaults. Loading all token sets and hiding
  them with selectors does not satisfy selected-only delivery. Keep component-local SCSS/BEM and Tabler icons.
- The first screen must use the resolved presentation; no visible flash of the other design. Preserve the SSR
  shell, CSR page-data model, TanStack Query cache and existing preload policy.
- Desktop web is primary. Phone reachability and accessibility remain supported and checked.

## Organization selection and rollout — approved direction

The organization owner chooses one design for all staff. Each person retains an independent light/dark
preference. Classic remains live and is the default. Botanical stays in private preview until every page
and state offered to that organization has complete, verified Botanical coverage; production does not mix
Classic fallback pages into Botanical. Jafar confirmed both choices on 2026-10-11.

The appearance preference must not be silently overwritten to compensate for missing Botanical dark
coverage. A supported Botanical dark palette is a readiness requirement before it is offered to customers.
Its design still needs focused approval; this decision does not approve an invented palette.

## Proposed execution order

1. Recover and reconcile Classic guidance; establish the shared router and Botanical skill with links and
   paired AGENTS/CLAUDE updates. Keep all application appearance unchanged.
2. Capture the current production-build baseline and prove selected-only shell/surface imports with two
   presentations in a development-only preview. Prove SSR, hydration, idle/hover warming and asset isolation
   before broad refactoring. Keep unapproved visual controls explicitly out of production rollout.
3. Implement the approved shell through the proven presentation seam, retaining Classic and shared behaviour.
   Verify navigation, permission differences, notices, dialogs, profile and pinned Save/Cancel geometry.
4. Resume the design campaign's job-details inventory and approved section-by-section work. Add coverage
   records for every route, state and shared root needed before an experience can be offered.
5. Once rollout choices and coverage are approved, build the saved selection and reviewed settings UI,
   including guarded reload, failed-save handling and tenant isolation. Then verify full offered journeys
   and measured delivery before enabling Botanical for organizations.

This order is proposed, not authorization for a full rewrite or a database migration.

## Still unclear

- First release scope: recommend Business Workspace only; keep Control Room and customer-facing surfaces
  separate until their designs and selection policy are approved.
- Botanical dark appearance and full surface readiness are unverified. Settle supported modes and coverage
  before customer selection. Default Classic until the selected alternative meets its release gate.

## Not doing

- New feature behaviour, permissions, packages, industry differences or infrastructure changes inside theming.
- A cloned application, duplicated business logic, a theme marketplace or user-supplied CSS.
- Claiming inactive asset isolation, faster loading or capacity before production-build evidence.
- Automatically changing an organization's design or dropping unfinished routes to make Botanical look ready.

## Research

[Architecture audit, source history and performance proof](research/selectable-design-experiences-audit-2026-10-11.md).
