# CRM design system — focused foundation check

Checked 2026-10-11 on `main` at `40d7b7ca`, before this planning checkpoint. This is a source and saved-evidence review; no new browser run, build, database inspection or application change was performed.

## Question and boundary

What existing theme machinery can support a fresh organization-theme plan, and what remains unbuilt or unproven? Earlier campaign requirements and approvals are not carried forward. The platform remains one application: industry, package and permissions own capabilities, as described in [platform overview](../platform-overview.md).

## Verified in the current source

| Foundation | Evidence | Planning consequence |
| --- | --- | --- |
| Frame selection occurs before the shell renders. | [`(app)/+layout.server.ts`](../../src/routes/(app)/+layout.server.ts) selects Botanical only when `DESIGN_SHELL_PREVIEW=botanical` and the request hostname is localhost or 127.0.0.1; otherwise Classic. [`(app)/+layout.ts`](../../src/routes/(app)/+layout.ts) awaits one explicit dynamic frame import. | There is a presentation-selection seam, but no organization setting or user-facing picker in this path. |
| Both frames share shell behavior. | [`SharedAppShell.svelte`](../../src/lib/components/layout/SharedAppShell.svelte) owns navigation inputs, account/search/dialog state and shared header controls, then passes snippets to the selected frame. [`presentations/types.ts`](../../src/lib/components/layout/presentations/types.ts) defines the common frame interface. | Reuse behavior and access decisions; a theme need not duplicate business logic. |
| There are two frame implementations. | [`ClassicFrame.svelte`](../../src/lib/components/layout/presentations/ClassicFrame.svelte) and [`BotanicalFrame.svelte`](../../src/lib/components/layout/presentations/BotanicalFrame.svelte) arrange the header, navigation, notices and page slot differently. Botanical uses Bits UI for its phone drawer. | Layout differences are technically possible, beyond color changes. Their presence does not approve either theme for this fresh campaign. |
| The routed page body stays shared. | [`(app)/+layout.svelte`](../../src/routes/(app)/+layout.svelte) supplies the same routed children to the selected shell. | Selecting Botanical does not establish Botanical coverage of pages, forms, dialogs or record layouts. |
| Control Room has a Classic wrapper. | [`AppShell.svelte`](../../src/lib/components/layout/AppShell.svelte) imports ClassicFrame and SharedAppShell directly. | Applying organization themes to Control Room would require a separate product decision and implementation. |
| Existing light/dark choice is browser-local. | [`routes/+layout.svelte`](../../src/routes/+layout.svelte) reads `ucrm-theme` from local storage, falling back to the operating-system preference; [`Topbar.svelte`](../../src/lib/components/layout/Topbar.svelte) toggles and stores the choice. | Personal light/dark appearance and organization design are distinct decisions. Cross-device preference sync is not established. |
| Shared styling still exists. | [`app.scss`](../../src/lib/styles/app.scss) loads the global variables, fonts and baseline. [`_variables.scss`](../../src/lib/styles/_variables.scss) contains shared semantic values and dark overrides. Botanical's shell sets additional local color values. | Shell splitting is not proof of complete design-token or application-asset separation. Complete themes need coherent page/control coverage and verified appearance modes. |

## Existing runtime evidence, not rerun here

The [real-shell proof](selectable-real-shell-2026-10-11.md) links raw results and desktop/phone screenshots. Its recorded run covers SSR and hydration, selected-frame loading, idle/hover warming, navigation, shared controls, two permission roles and pinned form actions. The raw results record no inactive frame requests or browser errors in the four owner/width combinations.

Its stated limits remain relevant: page coverage and Botanical dark appearance are incomplete; some account/failure/draft journeys are not exercised; full type checking stalled; measured Classic dashboard loading and phone layout shift are poor. That evidence supports a reusable shell experiment, not release readiness, full asset isolation or a capacity claim.

## Recommendation for planning — not approved scope

Start from the existing shared shell and selected-frame seam if the new scope fits. Specify supported surfaces, complete theme choices, chooser permission, staff switching and appearance modes before implementation. Keep records, permissions and workflows authoritative outside the theme. Require a complete, checked experience for every surface offered under a theme; define exclusions explicitly rather than silently treating incomplete page coverage as finished.

The first decision round should settle the surface boundary, initial design choices and who controls the organization's choice. Appearance-mode details, safe switching and failure behavior can then be made precise against those answers.
