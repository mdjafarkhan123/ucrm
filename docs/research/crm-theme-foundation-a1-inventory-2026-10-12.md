# A1 — delivery and apply-safety inventory

**Scope:** Source checked against main `d2b1de1b`, then the A1 private fixture changes. No business editor is wired to an apply guard yet. This inventory assigns the work; it does not declare any route safe. The approved foundation and Botanical sequence and exact v3/sidebar/header approvals are unchanged.

The [source snapshot](crm-theme-foundation-a1-2026-10-12/source-inventory.json) enumerates all 73 `(app)` page routes, common layout dependencies, reachable stateful/editable components, layout-owned controls, local state names/line pointers and source hashes. It follows explicit local imports, including literal dynamic imports. This is a static aid, not a Svelte parser: nonliteral imports, prop-owned/bound state, derived dirty signals, store/library state and pending promises need inspection when a batch starts. New routes/components remain unclassified until verified. Even a page with no local state can own a child editor.

## Rechecked delivery boundary

- `(app)/+layout.server.ts` defaults to Classic, with environment + loopback-host opt-in for the private Botanical shell. It does not read or write an organization theme. `(app)/+layout.ts` awaits one explicit frame import for SSR/hydration. No eager presentation barrel was found.
- `SharedAppShell` owns navigation permissions, account actions, notifications, search, profile-photo and header-timer state; both frames receive those controls once. The app layout owns account standing, support and the daily route warmer. Recent time-clock work changed these shared controls, so A1 reruns current real-shell proof instead of assuming the entire October 11 run is unchanged.
- Real frames and their navigation/header components use injected, component-scoped SCSS. Their source approval record is retained. The current page/control dependency graph is still shared. A1 does not migrate actual business pages or assert that future Botanical pages are isolated.
- `src/routes/+layout.svelte` imports `app.scss` once. `_variables.scss` defines Classic root tokens and global dark handling; `app.scss` contains shared reset/base/helper rules and five Inter font faces. Botanical currently inherits this baseline. Fonts are shared today, not proven exclusive Botanical fonts or approved Inter rendering of v3.
- `ui/Dialog.svelte`, `ConfirmDialog.svelte` and `Lightbox.svelte` use Bits UI portals outside shell ancestry. Dialog classes and root-level toasts cannot inherit a future shell-only token override automatically. Theme-specific overlay markup must carry its own scope/token host, or an explicit overlay-root presentation scope, before migration. Do not change document-wide tokens on private preview or assume a shell selector reaches portals.
- The private loading fixture reuses explicit lazy imports, the real route warmer, injected styles and the installed Dialog wrapper. Selection is request-local URL data plus component-local state. Keying the workspace by the fixture design fixes the previous `onMount` reuse hazard on an intentional cross-design navigation. No cookie, storage, organization identifier, service adapter or preference write is present.
- Cold/ordinary warming loads only the selected synthetic shell/page. Overlay content loads on hover/focus/open; opposite presentation navigation disables preloading until requested. Scoped shell and portalled content styles are checked after both designs have been downloaded. The dialog frame remains the existing shared Classic wrapper; these synthetic content colors approve no Botanical dialog design.

**Engineering method:** SvelteKit universal loads for selected SSR constructors, context/component ownership instead of mutable server globals, Svelte scoped/injected CSS and Bits UI portal/focus behavior. Existing verified project seams are retained. See [SvelteKit loading](https://svelte.dev/docs/kit/load), [state management](https://svelte.dev/docs/kit/state-management), [scoped styles](https://svelte.dev/docs/svelte/scoped-styles) and the installed Dialog implementation. Official Svelte MCP documentation and installed source were consulted for this slice.

## A3 shared integration

`RecordDetailLayout` already receives `editing`, `dirty` and `saving`; only its Save/Cancel bar consumes them. Add safety reporting at that boundary while preserving open-but-clean blocking and failed-save guards. Requests, clients, jobs, quotes, invoices and team-person detail use it. Payment detail uses the layout read-only but owns separate actions, so layout presence alone proves nothing.

`RecordFormLayout` accepts title/main/rail/actions/error, with no common editing/dirty/saving contract. The five shared forms (`ClientForm`, `RequestForm`, `QuoteForm`, `JobForm`, `InvoiceForm`) own draft values and mutation state; expose them explicitly rather than detecting inputs. Include client edit, form line items, contact/property selection, recurrence and attachments. Settings pages also using this layout still belong to A4a for their bespoke save lifecycles.

`AttachmentsCard` exposes `onPendingChange`, `saveAll(id)` and `discardChanges()`; page effects call these with `untrack`. Capture staged additions/removals and in-flight or failed operations without adding a second saver. Child records with their own Save remain separate owners even when their parent detail is clean.

A3 supplies a component-lifetime registry and generation token, with conservative unknown coverage. Register the state owner, not every input; parent/child contributions may overlap safely but cannot cancel one another. Leave warnings and apply guards serve different actions; existing `beforeNavigate` guards do not protect a remount.

## Bounded later deliveries

These subdivisions refine the already approved A4 scope; they add no product behavior or parallel-writer authorization. Each starts with its assigned source snapshot and rechecks current imports. Before A5 integrates a route, its common and exceptional owners must both pass.

| Part | Assigned surfaces and source homes | Required proof focus |
| --- | --- | --- |
| A4a1 Identity and personal settings | Business profile, branding, business hours, inquiry alerts, contact matching, security | Staged logo/photo, clean-open editor, password/change operations, failed save and existing leave warnings |
| A4a2 Work defaults and catalogs | Payments, quotes, invoices, taxes, checklists, price book, pipeline settings | Child dialogs, list-row edits, defaults, pending provider actions; imports join A4b8 |
| A4a3 Communication and review settings | All `settings/communications/*`, `reviews/settings` | Domain/sender setup, templates/snippets, blocked addresses, credit actions, review settings and unsaved content |
| A4a4 Team settings | Team list/person/activity | Invitations, person editing/permissions, resend/remove operations and read-only activity view |
| A4a5 Form builder | `settings/forms` and `[id]` | Independent build/identity/booking baselines, publish/revise/default operations, clipboard status retained |
| A4a6 Automation builder | All `settings/automation/*` | Rule/action drafts, revisions, activation-impact dialog, live lifecycle operations |
| A4a7 Setup | All `setup/*` and shared setup fields | Touched answers, debounced autosave queue, failed autosave, completing/sending/handover and setup/support restrictions |
| A4b0 Workspace overlays | Shared shell, support messenger/conversation, search, profile photo, notifications, header timer | Hidden/popped composer, staged photo/crop/object URL, writes, timer Stop and registration cleanup across routes |
| A4b1 Inbox | `communications`, all communication composer/attachment/forward/template children | Email/SMS/chat drafts, channel/recipient/subject, scheduled send, upload failures and popped composer |
| A4b2 Growth | `marketing/*`, `reviews` | Campaign editor/recipient groups/templates/test/send operations, review cancellation and feedback selections |
| A4b3 Client and request children | `clients/*`, `requests/*`, collaboration components | Property child Save, consent/communication/merge/manual email, assessment/action dialogs, notes/tags/files |
| A4b4 Financial record children | `quotes/*`, `invoices/*`, `payments/*` | Email/signature/send, deposits/refunds/payments, replacement/lifecycle/move dialogs and pending bulk/send flows |
| A4b5 Job children | `jobs/*`, job components | Visits, reports/checklists/signatures, expenses/time entries, payment schedule and future-visit confirmation |
| A4b6 Schedule | `schedule`, schedule components | Drag/move/resize pending confirmation, route ordering, previews, maps and event editor; preserve calendar/board state |
| A4b7 Pipeline and timesheets | `pipeline/*`, `timesheets`, pipeline/time-clock children | Drag busy state, selected opportunity, lost/reopen/task/assessment dialogs, time edits/delete/history and timer Stop |
| A4b8 Files and imports | `files`, file components, `clients/import`, `settings/price-book/import`, invoice opening-balance import | Upload queues/object URLs, selected library files, share/labels/folder edits and every import step/commit |
| A5 read-state coverage | Dashboard, settings landing and all lists/details once their above owners are complete; dev-preview routes remain private/unclassified | Declare proven read-only coverage explicitly; preserve meaningful view state and keep unknown routes blocked |

**Common acceptance for every A4 batch:** notice leaves work mounted; Apply blocks for open/dirty/staged/busy/failed work; only existing explicit Save/Cancel (or established setup autosave completion) releases it; background/hidden child owners remain registered; closing/navigating unregisters; permission/account restrictions are unchanged; beginning work during preparation invalidates the safety generation. Tests cover failures and cleanup; one representative live main journey proves the integration. A5 remains blocked until all batches required by the route/overlay matrix are complete.

## Retained view-state contract for later integration

Prefer keeping shared state owners mounted while replacing presentation. Where markup replacement would remount them, hoist UI state into the route's context/controller or explicitly capture/restore it; it is not a second server cache. TanStack Query continues to own record data. Preserve the complete pathname, search parameters, hash, active record and all relevant scroll containers. No meaningful state drop is approved.

| Family | State that must survive deliberate application |
| --- | --- |
| Shared shell | Sidebar collapse and navigation scroll; support open/screen/conversation/context; selected read-only overlay and its scroll; pending notice and focus. Editable overlays block apply. Do not silently dismiss a read-only overlay to ease swapping. |
| Daily lists | Search and debounce value, filters/open-filter panel, sort/direction, selected row IDs, loaded-page extent and list/table scroll. Clients also tag/status; jobs type/date; requests/quotes selection; invoices status/date and send selection. |
| Record details/forms | Record ID, active tab/section, accordion expansion, main/rail scroll, lightbox selection. Open form/edit blocks and staged child records block Apply; no draft serialization is a substitute for the guard. |
| Pipeline/outcomes | URL-backed filters, remembered board view, phone column, selected card, board horizontal/vertical scroll, outcome filters/list position. Dragged/pending cards block apply. |
| Schedule | URL date/view/employee filters, zoom, selected visit/assessment/event, backlog open/search/employee, map/open employee selection, board/route/scroll position. Pending moves/order changes block apply. |
| Inbox | Selected group/conversation, search/filters, active channel, thread scroll/stick-to-bottom, phone panels. Draft/subject/recipient/library attachments/scheduled send/popped composer block apply until settled. |
| Files | Rail view, folder/label/search/debounce, grid/list mode, selected file and chosen-file set, panel/lightbox and photo index, loaded extent and scroll. Upload/edit/share drafts block apply. |
| Marketing/reviews | URL active tab, campaign/recipient-group selection, list searches/filter/sort, review status/channel, feedback selection and scroll. Campaign and child editors block apply. |
| Timesheets | URL week/person filters, expanded person rows, history selection, table position. Entry edit/delete/stop operations block apply. |
| Settings/builders | Route/tab, open read-only sections, table filters/sort/page/scroll. Independent builder baselines are all guarded; one clean tab cannot clear another tab's draft. |
| Imports/setup | Current step/section, mappings/validation/result selections and scroll. Unfinished file selection/import commit or autosave blocks Apply; successful autosave alone does not grant unsafe route coverage. |
| Dashboard/private previews | Dashboard selected/read-only panel and scroll; child timer/support state owned above. Dev-preview pages are not public route coverage and stay unknown until explicitly integrated or excluded from applying. |

A1 establishes these retention obligations and their owners, not runtime restoration. Per-route state pointers are in the snapshot. A5 must extend it when a later change adds a new state owner and prove same-record/filter/tab/scroll behavior on representative routes. Unknown coverage blocks Apply rather than relying on empty inputs.
