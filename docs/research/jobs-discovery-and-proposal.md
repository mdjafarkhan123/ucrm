# Jobs campaign: discovery and proposal

Prepared for Jafar on 2026-08-31. **Research complete for the core desktop paths; proposal awaiting approval. No application implementation is authorized or included.**

## Recommendation

Keep our existing list, creation, and detail page structures. Make the common job easy to enter, then reveal additional visits, repetition, payment installments, and field controls when relevant. Preserve Jobber's separation between the agreement, each visit, invoicing, and payment.

This is a proposal about presentation and workflow, not permission to remove capabilities. The proposed improvements are design inferences from the tour, not findings from contractor usability interviews. They still need representative contractor validation.

## Evidence and scope

- [Screenshot gallery](../../Design/Jobber%20Jobs/2026-08-31/gallery.html): 72 screenshots, comprising 69 Jobber captures and three of our current app.
- [Live evidence and coverage](../../Design/Jobber%20Jobs/2026-08-31/README.md): screen groups, persisted experiments, and limitations. Jobber captures have matching DOM text snapshots.
- [Official Jobber behavior research](jobber-jobs-official-behavior-2026-08-31.md): primary sources, dates, and contradictions. Documentation-only evidence is distinct from live verification.
- Product constraints: [PRODUCT sections 13–16](../PRODUCT.md) and [Quote behavior contract](../quote-behavior-contract.md).

Two clearly named research jobs were created using the existing sample client, exercised, and deleted with their visits. The original job remains. No invoice was saved, no signature was submitted, and we did not send messages or collect payments. No client, catalog item, expense, time entry, note, or checklist was created. Normal activity/numbering traces may remain. [Cleanup ledger](../../Design/Jobber%20Jobs/2026-08-31/test-records.json).

Our live app currently exposes Jobs, Schedule, and Invoices as coming soon. Quotes already demonstrates the shared listing, record form, detail header, pricing area, and right rail that Jobs should reuse. Older reference notes implying these modules are already shipped must not override the current app and source.

## What the tour established

| Area | Observed behavior | Design implication |
| --- | --- | --- |
| Job creation | One-off starts with a visit. Multiple-date creation offers range or custom dates, up to 20 selected. Visits have independent schedule, crew, title, and instructions. | A simple default can retain a strong multi-visit editor. |
| Unscheduled work | Schedule later produces an undated visit; a date without time can be anytime. Recurring as-needed saved with zero visits. | Distinguish an undated task from an ongoing agreement with no dispatch yet. |
| Recurrence | Visit repetition and invoice frequency have separate controls and previews. Custom weekly/monthly rules, duration/date endings, and as-needed work are available. | Do not use one repeat selector to mean both visits and billing. |
| Pricing | One-off has a job total and optional split payments. Recurring has fixed or visit-based pricing. Per-visit service editing exists on recurring visits. | Make the price basis explicit before displaying the billing schedule. |
| Editing | Edit All Visits can delete and regenerate incomplete visits. A separate future-update dialog offers selected fields. | Show scope and consequences where the user makes the change. |
| Completion | Completing the final one-off visit opens Close Job, Schedule new visit, or Leave as Action Required. Invoice creation is separate. | Completing a visit, finishing a job, and settling money are distinct events. |
| Billing | Invoicing and Reminders are separate tabs. An invoice handoff can select other jobs for the client. | Retain combined billing and explain that internal reminders do not contact the client. |
| Field records | Time, expenses, notes, attachments, checklists, signatures, arrival windows, and history have separate entry points. | Keep them discoverable without making every new job fill every form. |
| Closing/deleting | Close warns about future visits. Delete explicitly requires acknowledging associated visit deletion. | Cancellation, completion, and permanent deletion require different explanations. |
| Costing | One-off showed whole-job costs; recurring showed a last-30-days period. List activity metrics are not cash received. | Label periods and distinguish estimates, costs to date, invoiced amounts, and collected money. |

## Proposed experience, inside our existing structures

### 1. Creation: one useful default, optional depth

Use the existing record form shell, client/property picker, pricebook, optional sections, notes rail, and sticky actions. The normal job opens with client/property, job title, services/prices, one visit, and a short billing summary.

The visit presents **Set date and time**, **Anytime on a date**, or **Schedule later**. Default its title from the job and keep the override available. Expose **Add visits** and **Repeat visits** beside it; these reveal independent visit cards or recurrence controls. Keep crew and instructions accessible, with a copy-to-all action for repeated input.

Preserve the familiar one-off/recurring model. Explain recurring as “repeated service or ongoing billing”; its as-needed choice means “create visits when work is needed.” Do not manufacture an undated visit for an as-needed agreement. Type selection must be clear before save if it will remain immutable afterward.

No extra wizard for a simple job. Complex schedules still need date/count previews and access to individual overrides. Save remains the primary action; sending a booking confirmation is an explicit separate choice.

### 2. Billing: explain the agreement in plain language

Keep three distinct decisions:

| Question | Choices to preserve | Example summary |
| --- | --- | --- |
| How is the work priced? | One-off job total; recurring per-visit amount; recurring fixed amount per billing period | “$120 per completed visit” or “$500 each month regardless of visit count” |
| When should we invoice? | Closure, each eligible completed visit, month end, custom dates, manually/no reminders; one-off installments | “Invoice completed visits at month end” |
| How is payment collected? | Manual collection and supported automatic payment arrangements | “You send the invoice; automatic charging is off” |

These are illustrative labels and examples, not newly approved billing rules. A fixed amount with manual timing needs an explicit explanation of what each invoice covers. Never silently reinterpret it as the lifetime contract total.

Show only compatible combinations, with a visible explanation when switching would change existing plans. Preserve percentages and fixed installment amounts, deposits, invoice grouping, tax/discount behavior, and issued-invoice history through their existing or future subsystem contracts.

Label internal calendar prompts **Remind our team to invoice**. Keep customer payment reminders and automatic charging separate. Present the resulting rule as one sentence before saving. Do not enable external delivery or charging as a side effect of choosing a billing frequency.

### 3. Details: next work first, full records one step away

Reuse our shared detail shell, header, client/facts section, service table, and notes/cost rail. Proposed main content order: job summary, visits, services, billing, then labor/expenses and additional records. Exact placement is subject to approval; it is not yet an authoritative Jobs blueprint.

The visits section should immediately show the next work and anything needing scheduling, with completed visits available through filters. Keep Add visit, edit, complete, per-visit services, team, instructions, reminders, checklists, attachments, and bulk operations. Avoid making users navigate to the calendar for every small visit change.

Use the right rail consistently with our other records. Internal costs/profit remain permission-controlled. When space is limited, collapsed sections should show useful summaries such as time tracked, expense count, or checklist progress rather than appearing empty.

### 4. Visit changes: scope before save

Offer clear scopes appropriate to the action: **This visit**, **Future unfinished visits**, or **All unfinished visits**. These are not interchangeable. Keep selected-field propagation distinct from replacing an entire schedule.

Before a destructive schedule regeneration, show affected count/date range, which custom details would change, and which completed visits remain. Prefer preserving overrides unless the user explicitly chooses to replace them; that is a proposed improvement over Jobber and needs approval. Completed schedule preservation must not be presented as proof that completed pricing is immutable—the older Jobber documentation describes different pricing behavior.

Keep bulk move/delete and return visits. Do not turn a repeated visit into a disconnected job merely to simplify editing.

### 5. Finish, cancel, and invoice without surprises

At the final visit, ask **Is all work finished?** Offer Finish job, Add a return visit, or Keep open. Show invoice now/later as a separate decision so a finished job can still await billing or payment.

Proposed cancellation flow: one consequences preview covering incomplete visits, completed history, outstanding billing, and any configured messages/charges. Preserve completed work and financial history unless a separate authorized operation changes them. Permanent Delete remains a clearly destructive action and should not be the normal cancellation path.

Do not silently suppress an already configured payment agreement or automation. Show its consequence and require the appropriate explicit choice under the existing automation/payment rules.

### 6. Field tools: fewer initial fields, no feature removal

Keep checklists/forms, photos/files, notes, signature/PDF evidence, timers/time entries, expenses/receipts, arrival windows, reminders, and crew assignments available from the visit or job context. Preserve permissions, partial saves, offline/sync requirements where applicable, and audit history. Required checklist warnings versus hard completion blocking is an unresolved product choice; Jobber documentation describes warnings, not an absolute block.

Dispatch, routes, batch as-needed visit creation, client confirmation, automated delivery/collection, supplier-document costing, chemical records, and mobile capabilities must retain explicit ownership in the campaign or their dependency campaigns. A feature being unavailable in this trial does not justify dropping it.

## Feature-preservation acceptance examples

Before declaring the eventual Jobs implementation complete, demonstrate at least these contractor journeys and the applicable permission boundaries:

1. A one-visit job created quickly, with crew assignment optional and a valid unscheduled state.
2. A project with independently dated/timed visits, bulk rescheduling, individual instructions, and a return visit.
3. Weekly service billed per completed visit at month end, including changed quantities for one visit.
4. Repeated service billed at a fixed monthly amount, independent of actual visit count.
5. An as-needed agreement with zero initial visits, later dispatched without duplicating the agreement.
6. A one-off job with deposit/progress/final billing; totals reconcile and previously issued documents remain traceable.
7. Quote conversion preserves the accepted published snapshot, lineage, and deposit ownership, and repeated conversion cannot create duplicates.
8. A visit edited alone, selected details propagated forward, and an entire unfinished schedule replaced with accurate consequences.
9. Completion, cancellation, invoice generation, payment failure, and reopening retain the correct work/financial history and automation behavior.
10. Field execution records survive navigation/retry/reconnection as specified; office-only financial information stays protected.

These scenarios are a scope-preservation checklist, not claims that all underlying modules already exist or that Jobber passed every case live.

## Proposed delivery order after approval

This is a dependency sequence for review, not a code/schema plan or authorization to start it.

1. Agree on Jobs behavior and content placement within the shared screens, then establish Jobs foundation and the existing Quotes campaign's conversion handoff.
2. Deliver visits and schedule integration across one-off, multi-visit, recurring, and as-needed work, with explicit edit scopes.
3. Connect pricing, invoice timing, installments, deposits, and invoice/payment dependencies without combining their state machines.
4. Complete field records, costing, communication/automation hooks, and lifecycle consequences with the owning subsystems.
5. Verify the preserved journeys, permissions, recovery behavior, mobile requirements, and measured performance before making completion or capacity claims.

No feature is dropped by appearing later in this sequence. Any proposed deferral or scope reduction must be brought back to Jafar.

## Remaining verification and approval boundary

Live close/reopen was not executed because of possible automated follow-up consequences. Future-update controls were inspected, but a changed value was not propagated through that second flow. Completed-visit price edits, deletion with existing invoices/deposits/expenses, customer progress-invoice presentation, actual checklist completion, native mobile/offline, route optimization, imports, booking, signatures/PDF generation, and connected-payment/message delivery remain unverified live. The evidence index explains what was inspected instead.

These gaps do not prevent reviewing the proposed UI direction. They do prevent treating the relevant persistence, financial, or automation behavior as settled implementation requirements. Resolve them safely in the relevant approved part before coding that behavior.

Approval requested: preserve the shared page structures and Jobber's job/visit/billing model, while proceeding with the six simplifications above. Approval of this direction should be followed by a concrete behavior/placement plan and dependency boundaries before implementation. No app code has been changed by this research.
