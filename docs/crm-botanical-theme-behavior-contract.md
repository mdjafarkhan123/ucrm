# Complete Botanical theme

**Status:** Part 2 planning proposal, 2026-10-12. The visual goal, starting references and incremental workflow are approved; the initial portions and coverage sequence below await scoped review. No new appearance is approved by this document.
**Parent:** [CRM design system](crm-design-system-behavior-contract.md). Stage A is the [approved theme foundation](crm-theme-foundation-behavior-contract.md).

## Result and audience

Owners, office staff and field crews can use a complete Botanical Business Workspace: purposeful colour, clear hierarchy, polished typography, spacing and page composition, including usable phone layouts and both appearance modes. Classic remains available with the same records, permitted capabilities and operations. Botanical may rearrange content within those constraints.

## Starting point and gaps

Reuse the [v3 foundations](design/botanical-v3/README.md), selected job-detail direction and exact [sidebar/header approvals](design/botanical-v3/sidebar-approval.md). The job reference is source `faeccae3b021ab763c0406d989b2aca0d25ba15a`; sidebar variant 2 revision 2 is `983dcecb`; header B revision 4 is `c5c6ad89`. Preserve their demonstrated appearance without re-requesting those approvals. Existing private shell implementation and [loading proof](research/selectable-real-shell-2026-10-11.md) are reusable evidence, with their stated limits.

| Established starting point | Work still needing focused review/proof |
| --- | --- |
| Forest navigation, warm canvas, softly tinted hero/panels, purposeful subject accents | Dark palette, contrast across control states, readability with realistic content |
| Measured typography and spacing examples | Actual bundled-font comparison; a coherent reusable scale where needed |
| Approved expanded/collapsed sidebar, phone drawer and desktop-first header | New header additions, universal account/search/notification/support surfaces and relevant failure states |
| Populated job composition, selected section strip, illustrated status and primary action | Complete real job capabilities, editing, validation, loading/empty/error, narrow financial rows, long content |
| Extracted starter guidance and separate Classic/Botanical skills | Pattern guidance and reusable components grown only as focused portions are approved |

The reference's illustrative Create invoice/Edit job controls are not authority to add actions or change workflows. For example, current job title editing stages a draft in the page's existing Save/Cancel contract; a new header preserves that behavior. Status wording, pricing visibility and lifecycle commands come from current product contracts and verified implementation.

## Coverage boundary

The [coverage inventory](design/botanical-workspace-coverage.md) snapshots 69 Business Workspace pages, four detached document pages and four development previews. Counts describe files, not demonstrated readiness. All reachable staff pages, their nested editors, overlays, notices, setup/support and permission-dependent variants must be covered before public selection. The inventory is refreshed before each family starts and before release, including routes added by other campaigns.

Customer documents remain in their existing customer-facing presentation, including when viewed from inside the workspace. Staff controls that open, configure, send or collect against those documents belong to Botanical coverage. Verify the detached preview paths and embedded document boundaries before implementing them. This applies the agreed customer-facing exclusion; any disputed mixed surface comes back to Jafar before its design is changed.

Industry, package and permission choices still decide what appears. This campaign redesigns available capabilities; it does not implement planned Medspa features or hide an existing feature to finish coverage. Any new Business Workspace surface released before Botanical activation joins the inventory. Later feature campaigns must cover both offered themes before releasing their new surface.

## Initial proposed portions

1. **Inspect the real job journey and reused shell.** Corroborate existing shell evidence against current additions; inventory job capabilities, roles, modes, child dialogs, save owners and view state. Produce a bounded list of job portions. Source inspection has begun; a fresh live walkthrough remains outstanding.
2. **Review typography and Botanical dark direction.** Use the approved light job identity and shell as context. Compare actual font rendering with the baseline, then review dark shell/hero/panel/text/status/action/focus roles. Include a small set of control-state samples; this establishes only the demonstrated foundations, not all forms or dialogs. Light layout approvals remain valid.
3. **Review job identity and title editing.** A focused demo covers title/status/type/lineage/facts, client/property context, existing header actions and title editing with the existing page Save/Cancel behavior. Show permitted and restricted-price variants, long names, loading/error, unchanged-open editor, dirty draft, validation and save failure at desktop/phone in light/dark. Deep action dialogs retain separate later portions; opening one in this demo identifies its simulated destination rather than approving its design.
4. **Promote and implement that approved portion privately.** Update only demonstrated reusable guidance/components, preserve page-owned queries/mutations/permissions, and prove the real title-save/cancel journey plus failures and Classic preservation. Stage A delivery must be complete before Stage B real-theme implementation. Demos and planning can proceed earlier.

The [delivery map](../Memory/campaigns/crm-design-system/stages/botanical.md) separates demo approval, system promotion and implementation. Remaining job portions are agreed from the first inventory, rather than treating the entire job page as one task.

## Proposed coverage sequence

Start with the remaining job detail sections and editors, then job creation/list and scheduling/time tracking. Continue through clients/requests/pipeline, quotes/invoices/payments, dashboard, communications/files, marketing/reviews, then remaining settings/setup and shared exception states. Complete each family through small demos and verified private implementations; settings and shared controls needed by an earlier journey move into that earlier portion. This is a coverage order, not permission to build an entire family in one session. The exact next bounded parts are agreed when their inventory makes them precise.

Every family includes its meaningful populated/empty/loading/error/disabled/saving/conflict states, relevant permissions and package restrictions, phone access, light/dark and Follow device transitions. Existing search/filter/sort/pagination, selections, files and saved work remain available. Domain-specific workflows stay with their approved contracts; unresolved behavior is researched before asking for a product decision.

## Skills and design-system maintenance

Always enter through the shared design skill. Classic guidance maintains Classic; Botanical guidance and its alignment register direct redesign. The parent campaign owns scope, the current part owns next work, visual approval records own exact revisions/states/exclusions, and the foundation guide owns shared extracted values. Runtime component code remains the implementation authority. These are linked responsibilities, not competing token specifications.

After each focused approval, update the relevant Botanical module/register and extend suitable existing components before implementation. Keep page-specific arrangements local. Recheck already approved uses when a shared pattern changes. A materially changed shared appearance needs scoped review; a bug fix restoring an approved appearance does not need the original decision repeated. Future sessions read only established guidance for the portion; missing patterns enter a focused demo.

## Selected-theme-only delivery

Preserve Jafar's reaffirmed requirement: ordinary loads and warming download shared functionality plus the selected presentation, with no inactive exclusive theme components/styles. Different markup uses explicit presentation loading behind shared behavior; merely hiding a second rendered component does not meet the requirement. Shared tokens and runtime controls must not become an eager bundle of both themes' exclusive assets. Body pages, lazy editors, portal/dialog styles, typography assets and navigation warming join the asset proof as they migrate.

Explicit preview/apply may download that requested theme. Previously downloaded modules can remain after deliberate switching; only the applied theme's exclusive styles affect the workspace. Each coherent implementation records appropriate asset/performance evidence under the performance-review gate. Final release repeats the completed-theme request/style proof; earlier shell evidence does not prove future pages or zero overhead.

## Completion and release checks

- Each inventoried route/overlay has exact approved design coverage and private implementation evidence; missing permission or rare failure states remain visibly unfinished. Screens pass the shared design check at 1440px/390px, in both modes, with keyboard use, focus/dismissal, 200% text resizing, long content and relevant contrast/reflow checks. More demanding controls receive their appropriate checks; screenshots alone do not establish accessibility.
- Each changed behavior's main journey is proven once on the running app; edge cases have appropriate automated checks. Verify field/office roles and price restrictions, child-record versus page Save/Cancel, operations in flight and theme-notice safety. The theme does not change business authority.
- Classic remains usable in light/dark with no unintended visual or behavioral changes on shared consumers, including excluded Control Room/customer surfaces.
- Stage A real persistence/authorization/conflict proof passes. Final completed Classic↔Botanical organization selection, preview/save, multi-session notice, draft-blocked Apply, safe Apply and fresh visits pass with real authorized sessions.
- Selected-theme-only page/shell/overlay assets, style isolation, navigation/warming and appropriate performance checks pass on the release build. Existing unrelated performance issues are reported separately. No traffic capacity claim follows from theme completion.
- Only then can complete Botanical enter the customer catalog. Record the release/readiness decision separately; no infrastructure deployment is authorized here.

## Planning check

A fresh read-only reviewer checked the proposal, coverage ledger, initial dependencies and named sources on 2026-10-12. No important planning blockers or contradiction with Stage A remained. The review confirmed that visual decisions stay focused, loading covers page/overlay/font assets, and Classic/excluded-consumer checks remain explicit. It identified historical authority pointers in the baseline guide; those pointers were reconciled without changing reference values or approvals. Runtime/design completion is still unverified.

## Assumptions and remaining review

Existing behavior and assets are inspected for reuse; current pages are not assumed functionally complete merely because they exist. The coverage snapshot is source-derived, not a fresh live audit. The remaining scoped decision is the proposed initial portions and coverage order. Future visual decisions stay with their focused demos.

## Not doing

Customer-facing or Control Room redesign, new business workflows, arbitrary theme editors, planned industry-feature implementation, a second app copy, automatic scope expansion from old trackers, or public mixed Classic fallback pages presented as complete Botanical.

## Sources and decisions

The incremental workflow is already approved. GOV.UK separately evaluates usefulness/uniqueness and implementation usability/consistency/versatility, and documents evolving component confidence: [contribution criteria](https://design-system.service.gov.uk/community/contribution-criteria/), [lifecycle](https://design-system.service.gov.uk/community/component-lifecycle-statuses/), checked 2026-10-12. We adapt its reuse/review discipline; this is not equivalent user-research evidence. [W3C text resizing](https://www.w3.org/WAI/WCAG22/Understanding/resize-text.html) supports testing 200% enlargement without losing functionality. [Original intent](uplift-design-refresh-behavior-contract.md#jafars-intent-and-approved-reference) and [Job contract](jobs-behavior-contract.md) preserve design intent and behavior authority respectively.
