# Jobber Jobs: official behavior research

Researched 2026-08-31 for the Jobs campaign. This is documentation evidence, **not observed-live evidence** and not an approved implementation plan. The separate live tour must confirm account-specific rollout, exact controls, and destructive-operation warnings. No account records were accessed or changed for this research.

The primary sources are Jobber's Help Center. Its current `/en/articles/` pages contain recent 2026 updates; the retained `/hc/en-us/` Edit a Job article is dated 2024 and is explicitly treated as older evidence below. Existing local Jobber references supplied starting URLs, not verification.

## One-off creation

**Documented, updated July 15, 2026:** One-off jobs support single appointments and nonrepeating projects with multiple dates. Creation supports up to 20 visits in one flow, using a date range or separate selected dates. Individual visits can have their own times, assignment, and instructions; an action copies time/team to all. More visits can be added after saving. Selected visits can be moved independently or shifted together by a day offset. This bulk move method is one-off-only.

Schedule later creates an unscheduled placeholder according to this article; leaving time empty creates an anytime visit. Assignment can remain empty. Internal instructions and job-level checklists carry into visits. One-off additions to scope must be entered on the job's line items rather than an individual visit. Jobs support up to 100 line items. The creation page supports split payments as well as a default reminder upon closure. [Create a One-Off Job](https://help.getjobber.com/en/articles/create-a-one-off-job/)

## Recurring creation and price basis

**Documented, updated April 15, 2026:** Recurring jobs cover repeating work or repeating billing. Recurrence supports weekly, biweekly, monthly, and custom patterns, including multiple weekdays and ordinal weekdays. Contract end can be a duration or a specific date. The creation summary previews visit count and first/last visit dates. The contract start date is distinct from the first matching appointment date.

The as-needed recurrence option creates **no visits**; visits can be added later. Pricing can be per visit or a fixed amount per billing period. Fixed monthly pricing does not depend on visit count. Billing frequency is selected separately from the price basis. Per-visit service variations can be made after creation. The article describes the ongoing interface refresh and retirement of creating a job by selecting an existing quote from the job form; quote-to-job conversion remains available. [Create a Recurring Job](https://help.getjobber.com/en/articles/create-a-recurring-job/)

## Visits and edit scope

**Documented, updated July 21, 2026:** A visit can have date/time, date only, or neither. Editing its schedule converts between those forms. A single edit normally changes one visit. A separate future-update action applies selected time, recurrence, team, or line-item changes forward. Job-schedule regeneration instead replaces incomplete visits and warns about losing custom details.

Per-visit items flow to invoices for those dates, but not under fixed-price billing. Visit details include instructions, team, reminder/confirmation state, items, client, notes, and checklists. The New Schedule supports duplication into the same job. Completing from the schedule offers a return visit; completing from the job does not expose that shortcut. Individual rescheduling can prompt optional client notification.

**Documentation gap:** This article still describes a second checkbox for creating the unscheduled placeholder, unlike the one-off creation article. Verify the current account. [Visits](https://help.getjobber.com/en/articles/visits/)

## Older edit and deletion evidence

**Older documentation, updated March 26, 2024:** Schedule or team edits regenerate incomplete visits while preserving completed visits. However, job-level edits to line-item name, description, price, or quantity are explicitly described as overriding those values on completed visits. Schedule preservation must not be mistaken for full historical immutability.

The article allows changing recurring billing between per-visit and fixed-price. It locates job deletion at the bottom of a full edit screen and states that deletion cannot be recovered. The modern job page uses section editing, so the deletion location is stale until checked live. [Edit a Job — older article](https://help.getjobber.com/hc/en-us/articles/115009379087-Edit-a-Job)

## Job lifecycle and useful actions

**Documented, current Job Basics:** Job type cannot be switched after creation. A job can have multiple invoices; invoicing does not itself close the job. Modern edits occur through section pencils. Editing all visits updates incomplete visits.

Closing leads to Requires Invoicing when billing remains, otherwise Archived. The closure prompt treats visits earlier today and later today as eligible to complete; dates beyond today are offered for removal. Completing visits can charge the client if per-visit automatic payments are enabled. Archived jobs can be reopened.

Create Similar carries title, type, schedule without times, team, billing, items, and checklists; instructions do not copy. Other documented actions include PDF download, signature capture, booking confirmation, follow-up, invoice generation, and a permission-controlled emailed costing export. Signed job PDFs are stored as internal notes. Chemical tracking is documented for web, not the mobile app. [Job Basics](https://help.getjobber.com/en/articles/job-basics/)

## Cancellation

**Documented, updated March 2026:** Jobber's cancellation workflow is closing the job, after disabling that client's job-closure follow-up if enabled. It offers completing earlier work while removing future visits, or removing all incomplete visits. Completed work can remain as history. If no billing is wanted, outstanding invoice reminders must also be removed; otherwise the closed job remains in the billing queue. This is a multistep workflow with communication and billing consequences, not merely a status label. [What if a Job Gets Canceled?](https://help.getjobber.com/en/articles/what-if-a-job-gets-canceled/)

## Internal billing reminders

**Documented, updated March 31, 2026:** Invoice reminders are internal calendar prompts to create invoices. They are different from customer payment-chasing messages. A due reminder drives Requires Invoicing and makes the job available for batch invoicing.

Recurring reminder choices are after completion of each visit, on job closure, month end, a custom schedule, or no reminders. One-off closure reminders default on. Reminders can also be added manually under Billing, and an office user can be assigned as their owner in Work Settings. To clear a closed job's Requires Invoicing state, create an invoice or delete the outstanding reminder. Completed reminders remain visibly checked in the calendar. [Invoice Reminders](https://help.getjobber.com/en/articles/invoice-reminders/)

**Documented:** Calendar clutter can be reduced by filtering reminders out of the schedule instead of deleting the reminders that protect billing follow-through. [Reminders on the Schedule](https://help.getjobber.com/en/articles/reminders-on-the-schedule/)

## Progress invoicing

**Documented, updated March 31, 2026:** Payment schedules can originate on either a quote or a job, including jobs without quotes. Installments use percentages or fixed amounts and collectively match the total. The job displays paid, awaiting-payment, draft, and remaining portions. Each installment becomes an invoice through an explicit create/generate action. Scope changes require adjusting job pricing and remaining payment amounts. Progress-invoice line amounts are restricted; issued installments cannot be edited through the job payment schedule. Customers see full item value and the installment amount due separately.

**Unresolved contradiction inside this article:** Its main customer-view section says the invoice includes the payment schedule; its FAQ says future payments are absent and directs customers to the original quote. Its issued-invoice editing guidance also needs live verification before specifying exactly what remains editable. [Progress Invoicing](https://help.getjobber.com/en/articles/progress-invoicing/)

## Batch invoicing and combined billing

**Documented, updated March 31, 2026:** Batch creation makes draft invoices, followed by a separate batch-delivery step. It relies on due invoice reminders. Incomplete visits are excluded by default; manually including incomplete past or future visits also marks them complete. Different property tax rates can produce separate invoices for one client. [Batch Create Invoices](https://help.getjobber.com/en/articles/batch-create-invoices/)

**Documented:** Creating an invoice from a job can offer the client's other jobs needing billing. Jobs may be omitted for later. Service dates and addresses transfer to the invoice. [Invoice Basics](https://help.getjobber.com/en/articles/invoice-basics/)

## Automatic payments

**Documented:** Automatic payments create and charge invoices according to billing frequency instead of generating internal invoice reminders. Disabling automatic payments restores reminders. As-needed billing is incompatible with automatic payment. A dated billing run occurs at 9 PM account-local time, whereas visit completion can create and charge immediately. Manual invoice generation is removed for these jobs.

Only one automatic charge attempt is made; failure notifies admins and appears on the invoice, requiring follow-up. A converted quote's deposit applies to the first automatic invoice. Referral credits do not apply automatically. Completing visits can trigger charges even when the completing user's permissions do not permit configuring automatic payments. **These behaviors were documented only, never exercised.** [Automatic Payments](https://help.getjobber.com/en/articles/automatic-payments/)

## Visit reminders and arrival windows

**Documented, updated May 21, 2026:** Two appointment reminders can be scheduled with email/text channels. Anytime-visit SMS requires an explicit sending time. Settings use the company timezone. Newly eligible reminders may queue for up to an hour. Rescheduling cancels obsolete reminders and schedules replacements. Manual sends are additional to automated reminders. Per-client communication settings can disable reminders. Clients can confirm appointments through the reminder's Client Hub link, with confirmation visible in activity, client, job, and visit views. Individual rescheduling offers send/skip and message preview; it is not an assessment notification workflow. [Assessment and Visit Reminders](https://help.getjobber.com/en/articles/assessment-and-visit-reminders/)

**Documented, updated August 18, 2026:** Arrival windows have organization defaults and a **per-job duration override**. They apply across a job's visits, not as a separate per-visit setting. Choices range from none through four hours, with after-start or centered styles. Untimed/unscheduled work does not expose the window. The calendar still positions the actual scheduled time; details and client communications expose the window. Changing the default does not remove existing jobs' windows. Mobile can configure the window during creation; adding one to an existing job requires web. [Arrival Windows](https://help.getjobber.com/en/articles/arrival-windows/)

## As-needed operations across many jobs

**Documented, updated July 15, 2026:** The New Schedule provides bulk visit creation for existing recurring jobs, including weather-driven work. Filters include job description, line items, client tags, and the absence of incomplete visits before a selected date. The map can show up to 500 jobs, but generation is limited to 100 jobs per operation. The final step chooses date, crew, and shared instructions. This preserves the distinction between an ongoing agreement and an actual dispatch event. [Create New Visits — Snow Removal Workflow](https://help.getjobber.com/en/articles/create-new-visits-for-existing-recurring-jobs-snow-removal-workflow-new-schedule/)

## Field execution and checklists

**Documented, updated August 2026:** Mobile job creation infers recurring versus one-off from whether scheduling repeats. Jobs show five upcoming visits with a view-all/filter path. Visit actions include directions, calling/texting, on-my-way messages, timer, completion, new visit, and deletion. Deleting a visit affects that visit; deleting the job removes all its visits. Visit content is organized into Visit, Details, and Notes. Signatures become job PDF notes. Automatic-payment setup requires the web. Quote line-item images carry into jobs/visits but are edited on the quote. [Jobs in the Jobber App](https://help.getjobber.com/en/articles/jobs-in-the-jobber-app/)

**Documented, updated August 19, 2026:** Job forms are now called Checklists. They support checkboxes, choice lists, short/long answers, images, and signatures. Required fields show completion progress and missing-answer warnings; completing a visit can still leave checklist work outstanding, surfaced in the activity feed. Therefore requiredness must not be assumed to be a hard completion block. Forms can be filled on web/mobile, saved partway, and exported/shared as PDFs. Mobile stores checklist updates offline and syncs after reconnection. [Checklists](https://help.getjobber.com/en/articles/checklists/)

## Costs, permissions, and duplicate accounting

**Documented, updated July 28, 2026:** Costing now covers both job types. One-off calculation spans the whole job; recurring calculation covers the last 30 days including today. Fixed recurring revenue uses billing-reminder occurrences; visit-based revenue uses visits in that window. Inputs are item costs, labor time/rates, and expenses. Active work shows costs so far; completed work shows profit margin. Cost visibility is permission-controlled and internal. Changed labor rates apply prospectively. Recording the same material/labor cost in multiple inputs double-counts it. Recurring costing reporting is not available according to this article. [Job Costing](https://help.getjobber.com/en/articles/job-costing/)

**Documented, updated August 20, 2026:** Supplier-invoice upload extracts a draft expense and matches a job using a purchase-order number. An owner/admin reviews before expense creation; uploads are web-only and plan-gated. [Automated Job Costing](https://help.getjobber.com/en/articles/automated-job-costing/)

## List, attention states, and metrics

**Documented, updated July 9, 2026:** The jobs list filters by type and status, and sorts client, number, schedule, status, and total. Metrics distinguish recent visits from scheduled visits in the coming 30 days; these are not a cash-received measure. Pricing/view-all permissions gate metrics. Active, upcoming, today, late, unscheduled, action-required, requires-invoicing, ending-soon, and archived states have different operational meanings. Action-required describes active work without upcoming appointments. Ending-soon uses the contract end, not its last visit. Archived means closed with no outstanding need to invoice. [Jobs List Page and Key Metrics](https://help.getjobber.com/en/articles/jobs-list-page-and-key-metrics/)

## Live checks still needed before a proposal is treated as complete

This list was prepared before the live tour. For the resolved cases and remaining limits, use the [live coverage record](../../Design/Jobber%20Jobs/2026-08-31/README.md). In particular, current one-off placeholder behavior, multi-visit creation, final one-off completion, incomplete-visit instruction updates, and visit-only deletion were subsequently exercised. This documentation note alone does not establish broader persistence behavior.

These are research questions, not claims or implementation decisions:

1. Compare the two schedule-update paths above using past incomplete, completed, future, and customized visits. Inspect both preview and persisted outcomes.
2. Verify completed-visit pricing after job item edits and whether existing invoices remain unchanged.
3. Verify the exact deletion impact on notes, checklists, expenses, time records, invoices, quote/request links, and deposits. Official evidence above does not settle these consequences.
4. Inspect reopen behavior: do removed future visits regenerate or does scheduling need explicit action?
5. Resolve the one-off placeholder checkbox and current multi-visit creation controls.
6. Inspect the progress schedule's invoice edit restrictions and customer PDF/portal presentation.
7. Observe the last-visit completion flow, including whether closure is prompted separately for each job type and billing mode.
8. Confirm actual current recurrence end choices and any custom-rule restrictions; do not infer occurrence-count support from duration support.
9. Inspect checklist warning choices and distinction between saving incomplete answers and completing a visit.
10. Keep unavailable trial-plan, mobile-only, provider-connected, or external-message behaviors explicitly documented-only. Do not infer they are absent from Jobber.

## Implications for later simplification proposals

Inference from the evidence, not an approved plan: fewer visible controls can preserve capability if scheduling, pricing basis, invoice timing, payment collection, and field completion remain distinct decisions underneath. Good candidates for evaluation include one-visit defaults, progressively revealed recurrence/milestone controls, natural-language billing summaries, precise affected-visit previews, and cancellation that exposes its remaining billing/communication consequences together. Avoid simplifying by eliminating undated work, anytime work, variable visit services, fixed retainers, installment billing, return visits, or field records.
