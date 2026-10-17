# Settings redesign — parallel build, 2026-10-17

## Agreement

Implement Phase A of `docs/contractor-design-concept-behavior-contract.md`.
Jafar approved the original Settings direction on 2026-10-17, including original
Taxes `o1A1w` and Checklists `YZ8Wg`, rather than variant B. Preserve existing
behaviour, data, permissions, validation and saves. This is a visual implementation.

Jafar asked to defer TypeScript checks, lint, tests and other expensive checks until
all screens are implemented. Record those as deferred. Each changed screen still
needs a quick live browser check, console-error inspection and screenshots against
Pencil at desktop widths, in light and dark mode. Desktop-only scope is the campaign
agreement. Run no full build or project checks during this batch.

## Ownership

All paths in this table are relative to `src/routes/(app)/settings/` and include
their page-local components. Counts are routes, not independently designed layouts.

| Session | Routes | Count | Branch / working folder | Port |
| --- | --- | --- | --- | --- |
| Codex business sub-agent | root, business-profile, business-hours, branding, security | 5 | `codex/settings-business-app`, `/tmp/ucrm-settings-business-app` | 5211 |
| Codex billing sub-agent | taxes, payments, quotes, invoices, invoices/opening-balances/import | 5 | `codex/settings-billing-app`, `/tmp/ucrm-settings-billing-app` | 5212 |
| Codex team sub-agent | team, team/activity, team/[userId] | 3 | `codex/settings-team-app`, `/tmp/ucrm-settings-team-app` | 5213 |
| OpenCode | communications/email, communications/sms, communications/website-chat | 3 | `codex/settings-communications-app`, `/tmp/ucrm-settings-communications-app` | 5214 |
| Claude | price-book, price-book/import, automation, automation/new, automation/[id], automation/[id]/edit, forms, forms/[id], pipeline, checklists | 10 | `codex/settings-workflows-app`, `/tmp/ucrm-settings-workflows-app` | 5215 |

Jafar narrowed OpenCode's assignment to three pages on 2026-10-17. The other seven
routes (communications/balance, communications/blocked-addresses,
communications/templates, communications/snippets, alerts, inquiry-alerts and
contact-matching) are unassigned for a later batch. This supersedes earlier
ten-page OpenCode handoffs. EmailSetupCard remains owned by OpenCode for its three pages.

Codex parent reviews the first three groups and owns integration. OpenCode and
Claude are separate user-run sessions; they have not started just because this
brief exists. Each session must claim its group from its working folder before
editing. Read existing claims; held design, Schedule and Memory claims stay held.

## Startup and file boundaries

1. Read `AGENTS.md`, the campaign contract and this brief. Load campaign-memory,
   proven-development, design → design-classic and Svelte skills. Reuse settled
   product research; load domain-specific skills when touching their subject.
2. Use the assigned branch and folder. Run the register's `list`, then `claim
   contractor-design-concept settings-<group>-app --owner <session> --mode write
   --area settings-<group>-ui`. Groups: business, billing, team, communications,
   workflows. Reserve `settings-<group>-progress` for the group's progress note.
3. Inspect only the group's original frames through Pencil MCP. Use the existing
   design notes at
   `/home/jafar/Ucrm/.worktrees/settings-design/Memory/campaigns/contractor-design-concept/parts/a2-settings-design.md`
   for frame IDs and earlier approved choices. Pencil is shared: read/export only.
   The live canvas has later polish that may not yet be in committed `classic.pen`.
4. Reuse existing UI components. Each group owns its exclusive components under
   `src/lib/components/settings/`: business owns WeeklyHoursEditor and
   SettingsDestinationCard; billing owns TaxDefaultDialog, TaxRateDialog,
   AccountingExportSection, QuoteTermsEditor, InvoicePaymentTermDialog,
   InvoiceDefaultsDialog and RepresentativeSignatureInput; team owns
   TeamAccessEditor and MemberAvailabilityEditor; communications owns
   EmailSetupCard; workflows owns PipelineStageList, PipelineStageRemoveDialog,
   PipelineLostReasonList, ChecklistTemplateDialog, `automation/` and `forms/`.
   Request any other shared component change from the Codex reviewer first.
5. Global UI, shell, styles, APIs, database, dependencies, `AGENTS.md`, `CLAUDE.md`
   and shared campaign Memory stay outside these assignments. Main already has
   other sessions' edits. Work from committed files in your own folder. If the
   approved design requires an unavailable token or shared change, report it;
   do not copy unknown edits or invent a second component system.

## Delivery

Implement the drawn, approved screens first. Sub-pages are assigned for coverage;
assignment alone does not approve a new unseen layout. Reuse a matching approved
layout only within the design rule; record any sub-page needing a new Pencil
approval and continue independent approved screens. Preserve loading, empty, error,
permission and saving states. Show real data, never decorative invented metrics.

Use `Login.md` for local browser access and the assigned port. Preserve the existing
app and query architecture. No remote writes, schema changes or provider changes
are part of this visual batch. Use read-only inspection for destructive controls.

Commit and push each coherent slice. Write
`docs/settings-redesign-progress/<group>.md` with route-by-route status, actual
browser evidence, screenshot paths, known gaps, deferred checks and next action.
Mark implemented work as pending final validation. Leave merges into main to the
Codex parent. Keep the claim until safe integration or an explicit handover.

After Settings and the other campaign screens are implemented, run the deferred
checks, resolve failures, verify combined journeys and then declare completion.
The six A4 sections still need their own approved designs. Schedule's existing
branch still awaits Jafar's explicit merge instruction.
