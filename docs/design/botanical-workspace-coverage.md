# Botanical Business Workspace coverage inventory

**Snapshot:** 2026-10-12, source at `cc65e4a2`. Source inventory only; no fresh live audit or new design approval. Refresh before each family and release.
**Authority:** [Botanical agreement](../crm-botanical-theme-behavior-contract.md), [parent agreement](../crm-design-system-behavior-contract.md), [approved foundation](../crm-theme-foundation-behavior-contract.md).
**Counts:** 77 page files under the app route group: 69 staff pages, four detached document views and four development previews. Shell, child components and overlays are additional coverage, not extra page-file counts.

## Ledger rules

All staff page entries below currently have **inventory-only** status. This does not erase existing v3/shell approvals: those exact approvals remain in the [foundations](botanical-v3/README.md) and [shell record](botanical-v3/sidebar-approval.md), with earlier private [runtime evidence](../research/selectable-real-shell-2026-10-11.md). No whole staff route is claimed complete.

For each bounded portion, replace inventory-only with a linked record identifying: route and component/overlay coverage; current capability and save ownership; permission/package/industry variants; states and retained view state; exact demo revision, approval date and exclusions; guidance/module; implementation revision; screen/live/automated/asset evidence; remaining gaps. Keep design approval and implementation proof separate. The same shared control may cover many routes, but each page still needs its composition and reachable-state check.

A family cannot close until its nested imports, conditional panels, menus, dialogs, portal content and app-wide surfaces are accounted for. Include reachable but unlinked routes; navigation alone is not the inventory. Check changed routes against the source manifest at release. Any staff page added before activation joins coverage. No unclassified page may silently use Classic fallback and count as Botanical complete.

## Staff route families

| Family         | Page files | Coverage beyond the list                                                                                                                  |
| -------------- | ---------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| Jobs           | 3          | Job sections, all job/visit modes and commands, child records, pricing restrictions, create form and list controls                        |
| Schedule       | 1          | Calendar views, unscheduled/anytime work, event/visit/task dialogs, drag and narrow layouts                                               |
| Timesheets     | 1          | Day/visit timing, running timers in shared header, corrections, role-dependent entries and approvals as currently implemented             |
| Clients        | 5          | Properties, contacts, linked work/history, communications, merge/consent dialogs and import steps                                         |
| Requests       | 3          | Assessments, intake fields, scope, conversion and editors                                                                                 |
| Pipeline       | 2          | Board/card/detail panels, filters, outcomes and existing commands                                                                         |
| Quotes         | 3          | Scope/options, approval/deposit status, editors, sends and customer-preview opening                                                       |
| Invoices       | 5          | Work selection, ready-to-bill/send queues, deposits, collection/refund/replacement dialogs and staff payment states                       |
| Payments       | 1          | Allocation/receipt/refund staff interactions and provider-result states                                                                   |
| Dashboard      | 1          | Conditional setup/readiness/permission panels, metrics and loading stability                                                              |
| Communications | 1          | Conversation list/context/composer, attachments, channel and delivery states, templates/snippets and library dialogs                      |
| Files          | 1          | Search/filter, details/shares, picker/upload, staged files, lightbox and permissions                                                      |
| Marketing      | 4          | Campaign creation/edit/steps, audience selection, delivery/review/results and exceptional states                                          |
| Reviews        | 2          | Staff requests, feedback/results and review settings; customer rating pages stay outside this scope                                       |
| Settings       | 32         | Editors, imports, forms/automation builders, billing/provider setup and access states; future Appearance page added by Stage A joins here |
| Setup          | 4          | Dynamic section/question branches, submission/handover, blocked/waiting/help/support states                                               |

## Exact staff page paths

Paths below are relative to `src/routes/(app)`; route parameters retain the source notation. Every line is inventory-only.

### clients

- `/clients`
- `/clients/[id=uuid]`
- `/clients/[id=uuid]/edit`
- `/clients/import`
- `/clients/new`

### communications

- `/communications`

### dashboard

- `/dashboard`

### files

- `/files`

### invoices

- `/invoices`
- `/invoices/[id=uuid]`
- `/invoices/new`
- `/invoices/ready-to-bill`
- `/invoices/send`

### jobs

- `/jobs`
- `/jobs/[id=uuid]`
- `/jobs/new`

### marketing

- `/marketing`
- `/marketing/campaigns/[id=uuid]`
- `/marketing/campaigns/[id=uuid]/edit`
- `/marketing/campaigns/new`

### payments

- `/payments/[id=uuid]`

### pipeline

- `/pipeline`
- `/pipeline/outcomes`

### quotes

- `/quotes`
- `/quotes/[id=uuid]`
- `/quotes/new`

### requests

- `/requests`
- `/requests/[id=uuid]`
- `/requests/new`

### reviews

- `/reviews`
- `/reviews/settings`

### schedule

- `/schedule`

### settings

- `/settings`
- `/settings/automation`
- `/settings/automation/[id]`
- `/settings/automation/[id]/edit`
- `/settings/automation/new`
- `/settings/branding`
- `/settings/business-hours`
- `/settings/business-profile`
- `/settings/checklists`
- `/settings/communications/balance`
- `/settings/communications/blocked-addresses`
- `/settings/communications/email`
- `/settings/communications/sms`
- `/settings/communications/snippets`
- `/settings/communications/templates`
- `/settings/communications/website-chat`
- `/settings/contact-matching`
- `/settings/forms`
- `/settings/forms/[id]`
- `/settings/inquiry-alerts`
- `/settings/invoices`
- `/settings/invoices/opening-balances/import`
- `/settings/payments`
- `/settings/pipeline`
- `/settings/price-book`
- `/settings/price-book/import`
- `/settings/quotes`
- `/settings/security`
- `/settings/taxes`
- `/settings/team`
- `/settings/team/[userId]`
- `/settings/team/activity`

### setup

- `/setup`
- `/setup/[section]`
- `/setup/check-and-send`
- `/setup/handover`

### timesheets

- `/timesheets`

## Shared and nested surfaces

These source families are inspection starting points, not proof of completeness:

| Surface                                                                                      | Existing reuse starting points                                                                               | Evidence still required                                                                                        |
| -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------- |
| Shell, account/security/profile, search, notifications, creation shortcuts and running timer | `layout/`, `profile/`, `search/`, `time-clock/`, `owner/`                                                    | Current controls/roles, phone/header additions, dark appearance, overlays, errors and excluded-consumer impact |
| Record pages and drafts                                                                      | `layout/RecordDetailLayout.svelte`, `RecordFormLayout.svelte`, `work/`, `collaboration/`                     | Open versus dirty, single save ownership, failed/stale saves, staged attachments and state retention           |
| Primitive controls and status                                                                | `ui/`, `forms/`, `data-display/`                                                                             | Demonstrated states, accessibility, both modes, separate exclusive assets and reuse consumers                  |
| Domain panels and dialogs                                                                    | `jobs/`, `schedule/`, `calendar/`, `clients/`, `requests/`, `quotes/`, `invoices/`, `payments/`, `pipeline/` | Conditional branches, pricing/role restrictions, child saves, deep actions, lazy loading                       |
| Campaigns, conversation and files                                                            | `marketing/`, `communications/`, `files/`, `reviews/`                                                        | Composer drafts, pending operations, failure/empty states, preview boundaries                                  |
| Settings, setup, billing and support                                                         | `settings/`, `setup/`, `support/`, `packages/`, `team/`, `automation/`                                       | All dynamic branches, restrictions, Business Workspace consumers versus Control Room/customer consumers        |
| Global exception states                                                                      | Root/app layout, route skeleton/error surfaces and account gates                                             | Loading/not-found/read denial, offline/save errors, grace/paused/setup restrictions, theme-read/load recovery  |

Directory names alone do not decide scope: follow each actual consumer. Shared controls used in Control Room or customer pages must preserve those presentations.

## Detached documents and exclusions

Four app-group files reset the layout using `+page@.svelte`:

- `/invoices/[id=uuid]/preview`
- `/jobs/[id=uuid]/report/preview`
- `/payments/[id=uuid]/receipt`
- `/quotes/[id=uuid]/preview`

These are candidate unchanged customer-document boundaries. Corroborate content/consumers in the live inventory: the customer document keeps its existing presentation; any staff-only surrounding controls remain in scope. Embedded customer documents and third-party payment content get the same boundary check. Route location by itself does not establish audience.

Development-only previews:

- `/dev-preview/collaboration`
- `/dev-preview/pencil-button`
- `/dev-preview/section-block`
- `/dev-preview/toggle`

Development previews are verification tools, not customer release surfaces. Customer booking/portal/forms/payment pages outside the workspace, login/password pages and `/jafar` Control Room stay excluded by the approved first-version boundary. Preserve their functionality and presentation when shared components change.

## Release reconciliation

Compare the current route manifest with this snapshot; inventory added/renamed routes and changed conditional branches. Require evidence for all offered staff surfaces in light/dark, relevant role/package/industry states and phone layouts. Use the parent Stage A requirements for safe switching and selected-only loading. Close no family on a file count, a shared outer frame or an approved screenshot alone.
