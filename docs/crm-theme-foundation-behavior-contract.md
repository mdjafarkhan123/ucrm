# CRM theme foundation

**Status:** Draft for scoped review, 2026-10-12. The core choices listed below are already agreed; the proposed journey, safeguards and delivery sequence need final review. No implementation is authorized by this draft.
**Parent agreement:** [CRM design system](crm-design-system-behavior-contract.md). This is its Stage A agreement, not a separate campaign.

## Result and boundary

One Business Workspace can use an organization-selected design without changing its records, available features, staff access or business workflows. Classic and Botanical may arrange page content differently while sharing behavior. The foundation supplies selection, delivery, appearance mode and safe switching; Stage B supplies complete Botanical appearance and page coverage.

The two stages have separate completion checks. Foundation proof uses a private test presentation and isolated test selection state, plus real database-backed preference, permission and conflict checks using isolated test data. Public Classic/Botanical activation is verified after Botanical is complete. A passing foundation proof does not mean Botanical is ready to offer to businesses.

## Already agreed with Jafar

- Cover the whole signed-in Business Workspace, including forms and dialogs. Login/password pages, customer-facing pages and the Uplift Control Room keep their existing presentation.
- Offer Classic and a complete Botanical; both existing and new businesses start with Classic until an owner or administrator chooses otherwise.
- Owners and administrators choose the design for the organization. Other active staff use that organization choice; personal layout overrides are excluded.
- Offer fixed designs with the existing business name and logo. Custom colors, fonts and user-arranged layouts are excluded.
- Each person chooses Light, Dark or Follow device on their device, separately from the organization design.
- Existing staff sessions receive a notice and apply a new design when ready, after saving or discarding unfinished work. A fresh visit uses the latest organization choice.

The parent records the approved visual goal, references and incremental Botanical demo/review/implementation workflow. The details below are proposed adaptations of the [primary-source research](research/crm-design-system-theme-approaches-2026-10-11.md), for approval as one complete foundation agreement.

## Choose and preview

An owner or administrator opens **Settings → Appearance**. The page identifies the saved organization design and explains that saving a different design affects everyone in that business. It shows the available designs with representative previews and separate personal appearance controls.

Selecting a design stages a choice. It does not save or change other staff sessions. **Preview** opens a labelled, read-only example with fictional data in the selected design and appearance mode. It is isolated from the current workspace and cannot create records, send messages, take payments or change permissions. Closing preview returns to the staged selection. Preview is optional before saving.

The public catalog contains only complete, approved and verified designs. Incomplete Botanical work and the synthetic foundation test presentation remain in private development previews. They cannot be activated by forging a public save request. Until Botanical is ready, businesses stay on Classic; the foundation can be implemented and checked privately during that period.

## Save the organization choice

**Save theme for everyone** is enabled only when the staged choice differs from the saved choice. Cancel restores the saved selection. Saving shows progress and prevents duplicate submission.

The server verifies active membership, organization ownership of the request, owner/admin authority and availability of the selected design at the time of saving. Being able to open settings is not sufficient authority. Another organization's identifier, an unknown theme, or an incomplete theme cannot grant access or change a preference.

A successful save stores the organization's choice and confirms it. It does not automatically remount the saving person's workspace or anyone else's active workspace. The saving person receives the same apply-when-ready choice as other staff. Saving the already-current choice is harmless and does not generate a new change notice.

If another administrator changes the choice after the page was loaded, the stale save does not overwrite them. Show the latest saved design, retain the user's staged choice and ask them to review before saving again. There is no theme-change history browser in this version.

If a save definitely fails, retain the previous saved choice and the staged selection, show an actionable error and allow retry. If the response is lost and the outcome is uncertain, re-read the saved choice before saying it failed or retrying. An unreachable server shows that the outcome could not be confirmed; it never claims success.

## Notice and apply safely

A working session keeps the presentation it has already applied. Discovering a newer organization choice shows a non-blocking **New design ready** notice; it does not replace page contents, navigate, close an editor or discard data. Show the latest choice if administrators make several changes. Remove the notice if the latest choice matches the applied design.

Proposed freshness: check on returning to the app, after navigation, and at most once per 60 seconds while a tab is visible and online. A continuously active session normally discovers a reachable saved change within that interval plus request time. Hidden/offline tabs do not poll; they check when usable again. A failed check keeps the applied design and retries at the next check, without an error popup every minute.

**Apply now** first checks all open drafts, staged attachments, open editors and pending writes/uploads in the current tab. If any prevent a safe switch, explain what must be finished and leave the workspace intact. The notice never saves or discards business work itself. Existing page Save/Cancel buttons continue to own that decision. An unclassified surface blocks application conservatively until its safety is established.

Once safe, fetch the latest available organization choice and prepare its required presentation. Keep the current usable presentation until preparation succeeds. Recheck edit/operation safety immediately before replacement: if an editor, draft or pending operation changed during preparation, keep the current workspace and require a new Apply attempt after that work is finished.

Apply the new design at the same route and record, retaining the current filters, selected tab and scroll position. The route/overlay inventory must identify the state retained on each surface before its integration; dropping meaningful view state requires Jafar's decision rather than an undocumented exception. Place keyboard focus on the resulting notice or page heading. If preparation fails, keep the current presentation with Retry; do not rewrite the saved organization preference or silently claim another design was applied.

The organization choice remains authoritative for fresh visits. A hard refresh or newly opened tab is a fresh visit; normal unsaved-work warnings still apply if someone tries to leave an unfinished page. Browser crashes or manually overriding a leave warning are outside the no-loss guarantee. An existing session may defer application until its next fresh visit.

## Appearance and access states

Light and Dark are explicit device choices; Follow device tracks the operating system's current preference and subsequent changes. A personal mode change does not save the organization's theme, refresh the page or interrupt an editor. Store a person's explicit choice per signed-in user on that device; it is not cross-device synchronization. With no explicit choice, use Follow device. Avoid painting a contradictory mode before applying the saved preference.

Ordinary staff can use the personal mode controls but cannot save the organization's theme through the page or API. Removed or deactivated staff cannot retain organization access. Account pauses and setup restrictions remain authoritative: the theme never opens a blocked workspace or bypasses permitted setup/support access. A paused account cannot change the organization theme. Organization theme choice does not select an industry, alter package entitlement or add a paid feature gate.

Failure to read the organization's preference on a fresh visit shows a clear retry state instead of guessing and saving a new preference. An invalid stored choice or a released design whose assets cannot load provides a recovery screen with Retry and a supported way to contact Uplift; do not silently overwrite it with Classic. Later removal of an offered theme requires its own migration policy; removing an active released theme is outside this version.

## Foundation completion checks

1. Two organizations and owner/admin/staff roles: each sees its own selected design; only owner/admin changes it. Direct unauthorized, inactive-member and cross-organization requests fail without a write.
2. Private isolated fixture: choose → preview → cancel leaves selection unchanged; choose → save persists the test organization's choice; a fresh session uses it. In addition to harness checks, real database-backed tests prove preference writes/reads, revision checks, RLS/authorization and conflicts against isolated test data, with verified cleanup/rollback. Test state cannot affect public organization preferences or make an incomplete design publicly available. Never call an in-memory result proof of database persistence.
3. Multiple sessions: a save produces a notice in another active session within the stated check interval; no automatic remount occurs. A second save supersedes the pending choice; returning to the applied design removes the notice.
4. Draft matrix: create/edit forms, detail blocks, settings/setup editors, message/campaign composers, dialogs, staged files and writes in progress survive a theme change notice. Apply blocks until work is explicitly saved/discarded and operations finish. Unclassified surfaces fail closed.
5. Conflict and failure: competing saves, a lost save response, offline state, rejected permissions, failed preference reads and failed presentation loading give the outcomes above. A retry does not create a second effective change.
6. Apply: safe application retains the route, record and inventoried view state, with reachable focus and a recoverable loading failure. Starting an edit/upload during presentation preparation cancels the swap without losing work. Personal modes work in both directions without changing organization selection.
7. Delivery: SSR contains the selected shell; inactive exclusive design assets are absent from cold ordinary loads and warming. Explicit preview/apply may load that requested design. After a deliberate switch, previously downloaded modules may remain in memory; verify that only the applied theme's exclusive styles affect the workspace.
8. Design checks: chooser, preview, notice and recovery states are checked at 1440px and 390px, with keyboard use, text resizing, long names and relevant loading/error states. Existing Classic remains usable. Botanical's full visual checks belong to Stage B.

Foundation completion means the machinery and these checks pass for the isolated tested scope. Final customer release additionally requires complete Botanical Business Workspace coverage in both appearance modes, approved responsive layouts, affected performance checks and the real organization save/apply journey on the completed designs. No customer/traffic capacity is established by these checks.

## Proposed delivery sequence

The [campaign roadmap](../Memory/campaigns/crm-design-system/ROADMAP.md) owns proposed parts and dependencies. The focused [implementation design](research/crm-theme-foundation-delivery-design-2026-10-12.md) records feasibility, safe-switch integration and performance evidence required before implementation can be called complete.

## Not doing

- New business workflows, customer-facing redesigns, Control Room redesign, a theme marketplace, arbitrary uploaded themes or a drag-and-drop page builder.
- New infrastructure, a second application copy, production rollout before the completed theme checks, or an assurance that an approved screenshot proves every behavior/state.
- Automatic saving/discarding of records during a theme switch, personal layout overrides, cross-device mode synchronization or unrestricted custom design values.

## Approval still needed

Approve this complete foundation agreement, including the proposed preview, failure/conflict handling, active-session checking, personal-mode storage and private-proof/public-release boundary. Existing choices are retained; only these newly concrete details and delivery parts are being reviewed. Botanical screen designs will continue through their own focused approvals.
