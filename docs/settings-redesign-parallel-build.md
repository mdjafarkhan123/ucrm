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
| Claude (communications handover) | communications/email, communications/sms, communications/website-chat | 3 | `codex/settings-communications-claude`, `/tmp/ucrm-settings-communications-claude` | 5214 |
| Claude | price-book, pipeline, checklists | 3 | `codex/settings-workflows-app`, `/tmp/ucrm-settings-workflows-app` | 5215 |

Jafar narrowed OpenCode's assignment to three pages on 2026-10-17. The other seven
routes (communications/balance, communications/blocked-addresses,
communications/templates, communications/snippets, alerts, inquiry-alerts and
contact-matching) are unassigned for a later batch. This supersedes earlier
ten-page OpenCode handoffs. EmailSetupCard remains owned by OpenCode for its three pages.

Jafar then narrowed the entire first batch to Codex 5, OpenCode 3 and Claude 3:
11 routes total. Codex billing and team implementation are paused. Claude's
price-book/import, automation (all four routes), forms and forms/[id] are deferred.
These reductions supersede all earlier wider handoffs and component ownership
applies only to the active routes. Keep any already started deferred work isolated
and checkpointed; it is outside this batch.

## Continuation and review queue

**Current communications owner:** Jafar transferred OpenCode's three pages to
Claude on 2026-10-17 after review. Old claim `8f01ab1601d5` released; Claude claim
`e54334278ed5` reserves the same implementation/progress areas in the new worktree
above. Existing code is preserved from `c1405242`. Read that branch's
`docs/settings-redesign-progress/communications-handover.md` and
`communications-review.md` for exact corrections and validation limits. The old
OpenCode worktree is retained for recovery and is no longer a writing assignment.

Jafar subsequently authorized Codex to continue with another claimed five-page
batch: Taxes, Payments, Quote settings, Invoice settings and Team (main page only).
Billing claim `46295b95f941`; Team keeps `d9d3f534a4db`. The first five business
pages are implemented and pushed on `codex/settings-business-app`, pending integration.

Claude's branch `codex/settings-workflows-app` now contains five implemented pages:
Price book, Pipeline settings, Checklists, Automation index and Request forms index
(commits `2b672e3d`, `3a56eb88`). Review all five before integration; see that branch's
`docs/settings-redesign-progress/workflows.md` for evidence and known gaps. Codex
owns this review after the current batch. It can resume in this or a new session;
the review is not complete just because the implementation was pushed. Expensive
validation remains deferred. The added two pages do not overlap Codex's next batch.

Codex parent reviews the business group and owns integration. OpenCode and
Claude are separate user-run sessions; they have not started just because this
brief exists. Each session must claim its group from its working folder before
editing. Read existing claims; held design, Schedule and Memory claims stay held.

## Startup and file boundaries

1. Read `AGENTS.md`, the campaign contract and this brief. Load campaign-memory,
   proven-development, design → design-classic and Svelte skills. Reuse settled
   product research; load domain-specific skills when touching their subject.
2. Read the latest brief in `/tmp/ucrm-settings-approval/docs/settings-redesign-parallel-build.md`
   if your worktree contains an older copy. Use the assigned branch and folder.
   Run the register's `list`, then `claim
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
