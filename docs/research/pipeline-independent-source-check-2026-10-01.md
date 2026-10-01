# Independent source check: pipeline claims from the Claude conversation

Checked 2026-10-01. This report independently checks the competitor-product claims in the pasted
conversation against current first-party documentation from Jobber, Housecall Pro, Pipedrive, HubSpot,
and ServiceTitan. It does **not** re-audit UCRM's implementation.

## Executive verdict

Claude's central Jobber findings are mostly right: Jobber uses system-owned request/assessment/quote stages,
opens a real action when a card is dropped into a built-in stage, distinguishes sending a quote from merely
marking it awaiting response, supports direct request-to-job conversion, marks approved quotes or created jobs
Won, removes Won/Lost from the active board, permits Lost except for Draft Quote, and supports up to 25 custom
stages. [Jobber: Sales Pipeline](https://help.getjobber.com/en/articles/sales-pipeline/)

The conversation becomes unreliable when it turns Jobber behavior into a universal industry rule or labels
unsourced screenshot observations as current product parity:

- **Forward-only is Jobber's rule, not the industry rule.** Pipedrive supports moving a deal to another stage
  at any time, and HubSpot only blocks backward moves when an administrator deliberately enables that pipeline
  rule. [Pipedrive: Move a deal to another pipeline](https://support.pipedrive.com/en/article/how-can-i-move-a-deal-to-another-pipeline) ·
  [HubSpot: Set up rules for object pipelines](https://knowledge.hubspot.com/object-settings/set-up-pipeline-rules)
- **“Jobber parity” was overstated** for a lead-source chip/filter, an Email button in the Opportunity Brief, a
  Pipeline-specific `+ New`, a deletion dialog that relocates cards, and reopening Lost. Jobber's current
  Pipeline documentation does not document any of those behaviors. Its documented board filters are salesperson
  and created-date range; its documented card fields are client, value, date, and freshness.
  [Jobber: Sales Pipeline](https://help.getjobber.com/en/articles/sales-pipeline/)
- **Per-column independent scrolling/infinite loading is unverified.** None of the reviewed official Jobber,
  HubSpot, Pipedrive, Housecall Pro, or ServiceTitan pages specifies that loading model. It may be observable in
  a live product, but it should not be cited as a documented competitor convention.
- **The stale-card proposal is a real improvement backed by Pipedrive, but not copied exactly as described.**
  Pipedrive supports a per-stage inactivity threshold and resets the clock for completed activities, notes/files,
  emails, and edits. A future scheduled activity does not stop rotting. [Pipedrive: The Rotting feature](https://support.pipedrive.com/en/article/the-rotting-feature)
- **The stronger reporting proposal is well supported.** Pipedrive and HubSpot report conversion and deal
  duration; ServiceTitan reports close rate, days to close, stage duration, and closed-lost reason. Jobber's
  documented Sales Outcomes report is much narrower. [Pipedrive: Deal conversion](https://support.pipedrive.com/en/article/insights-reports-deal-conversion) ·
  [Pipedrive: Deal duration](https://support.pipedrive.com/en/article/insights-reports-deal-duration) ·
  [HubSpot: Sales analytics reports](https://knowledge.hubspot.com/reports/create-sales-reports-in-the-sales-analytics-suite) ·
  [ServiceTitan: CRM Insights](https://help.servicetitan.com/shared/a7eef90a-beff-488f-b12b-027f1c1a39ce)

The planning direction is therefore good, but the plan should describe each item accurately as one of:
**Jobber parity**, **a wider CRM/field-service pattern**, or **a deliberate UCRM improvement**.

## Claim-by-claim source check

### 1. Stages, status ownership, and automatic movement

**Verified for Jobber, qualified for the industry.** Jobber's built-in active sequence is New Request,
Assessment Unscheduled, Assessment Scheduled, Assessment Completed, Draft Quote, Awaiting Response, and Changes
Requested. Requests and quotes create opportunities automatically, and actions on the underlying record move the
card. Approved quotes and created jobs close the opportunity as Won.
[Jobber: Sales Pipeline](https://help.getjobber.com/en/articles/sales-pipeline/)

Housecall Pro also syncs its boards with changes on Leads, Estimates, and Jobs, but it has three separate boards
and combines manual status changes with configurable automations. Its Lead board, for example, has New Lead,
First/Second/Third Contact, Won, and Lost; the contact stages are described as manual.
[Housecall Pro: Getting Started with Pipeline](https://help.housecallpro.com/en/articles/6185127-getting-started-with-pipeline) ·
[Housecall Pro: Pipeline FAQs](https://help.housecallpro.com/en/articles/6185346-pipeline-faqs)

ServiceTitan's CRM uses New, Qualify, Propose, Follow Up, and Closed Won/Lost. Selling or dismissing estimates can
update the opportunity automatically, but some movement is manual. This establishes system-driven movement as a
mature pattern, not identical workflows across vendors.
[ServiceTitan: Manage opportunities in Job Pipeline](https://help.servicetitan.com/shared/ef0855f1-4d8b-40fe-966f-7688f25bee8e)

**Correction to the conversation:** “Jobber, Housecall Pro, and ServiceTitan all work this way” is too broad.
They all synchronize business actions with pipeline state, but their board structure and manual-move rules differ.

### 2. Moving forward, backward, and correcting mistakes

**Verified for Jobber only.** Jobber says backward movement through its built-in stages is unsupported; dropping
onto a built-in stage starts the required action, and a card bounces back when its criteria are not met. Custom
stages accept unrestricted drag/drop. [Jobber: Sales Pipeline](https://help.getjobber.com/en/articles/sales-pipeline/)

**Contradicted as an industry rule.** Pipedrive says deals may be moved to another pipeline and stage “at any
time,” and its automation documentation explicitly recognizes both forward and backward stage changes.
[Pipedrive: Move deals](https://support.pipedrive.com/en/article/how-can-i-move-a-deal-to-another-pipeline) ·
[Pipedrive: Automation conditions](https://support.pipedrive.com/article/workflow-automation-conditions)

HubSpot supports free stage movement by default and offers optional rules to prevent skipping stages or moving
backward. Its rule documentation explicitly preserves reopening from a closed stage.
[HubSpot: Pipeline rules](https://knowledge.hubspot.com/object-settings/set-up-pipeline-rules)

Housecall Pro exposes both drag/drop and a status dropdown and may request required data in a dialog; its official
documentation does not impose a general forward-only rule.
[Housecall Pro: Getting Started with Pipeline](https://help.housecallpro.com/en/articles/6185127-getting-started-with-pipeline)

**Recommended interpretation:** protect irreversible business facts, but provide an explicit correction or
reopen path where correction is legitimate. Do not call forward-only an industry standard.

### 3. Sending a quote versus marking it sent

**Exactly verified for Jobber.** A Draft Quote is one that has neither been sent nor marked sent. Dropping it into
Awaiting Response prompts the user to send by email/text, mark it Awaiting Response, or view it; the card stays in
its original stage until the chosen action completes.
[Jobber: Sales Pipeline](https://help.getjobber.com/en/articles/sales-pipeline/) ·
[Jobber: Quote Basics](https://help.getjobber.com/en/articles/quote-basics/)

HubSpot also demonstrates why delivery state must not be faked: finalizing/sharing a quote and actually sending
it are separate, with separate `Last published date` and `Last sent date` properties.
[HubSpot: Create and send quotes](https://knowledge.hubspot.com/quotes/create-and-send-quotes) ·
[HubSpot: Quote properties](https://knowledge.hubspot.com/quotes/quote-properties)

Housecall Pro documents sending estimates by email or text, but no equivalent “mark sent without sending” action
was found. ServiceTitan uses a different Propose/Follow Up model.
[Housecall Pro: How to Send an Estimate](https://help.housecallpro.com/en/articles/120533-how-to-send-an-estimate) ·
[ServiceTitan: Manage opportunities in Job Pipeline](https://help.servicetitan.com/shared/ef0855f1-4d8b-40fe-966f-7688f25bee8e)

**Verdict:** Claude was right that UCRM must never silently equate a board move with customer delivery. The
send-or-mark-sent dialog is exact Jobber parity and a sound data-integrity rule.

### 4. Request/lead directly to a job

**Verified as a field-service pattern.** Jobber allows a request to convert directly to a job, and job creation
makes the opportunity Closed Won. Housecall Pro lets a lead be copied directly to a Job or Estimate and marks it
Won. ServiceTitan CRM leads can convert to a Job or Opportunity.
[Jobber: Convert a request to a quote or job](https://help.getjobber.com/en/articles/converting-a-request-to-a-quote-or-job/) ·
[Jobber: Sales Pipeline](https://help.getjobber.com/en/articles/sales-pipeline/) ·
[Housecall Pro: Leads on mobile](https://help.housecallpro.com/en/articles/12833580-how-to-use-leads-on-mobile) ·
[ServiceTitan: Manage Leads in CRM](https://help.servicetitan.com/shared/6d1e129a-448c-4d31-a6ed-557f5798a84c)

**Verdict:** Claude's direct-to-job gap is well founded and should be treated as launch-level workflow integrity,
not an optional extra.

### 5. Won, Lost, loss reasons, and reopening

Jobber removes Won/Lost opportunities from the active board. Lost is manual, unavailable for Draft Quote, takes
an optional reason, and archives the underlying request/quote. Current official documentation does not document
reopening Lost or owner-editable reason lists.
[Jobber: Sales Pipeline](https://help.getjobber.com/en/articles/sales-pipeline/)

Pipedrive supports freeform reasons or up to 100 administrator-defined reasons, optional comments, list filtering,
and Insights reporting. Its data model supports `open`, `won`, and `lost`, but the current help pages reviewed do
not clearly document the exact UI flow for reopening a lost deal.
[Pipedrive: Lost reasons](https://support.pipedrive.com/en/article/lost-reasons) ·
[Pipedrive Deals API](https://developers.pipedrive.com/docs/api/v1/Deals)

HubSpot has Open/Won/Lost status groupings and default Closed Lost Reason/Closed Won Reason fields; its pipeline
rules explicitly discuss reopened records. ServiceTitan permits a Closed opportunity to be reopened and reports
the Closed-Lost Reason.
[HubSpot: Default deal properties](https://knowledge.hubspot.com/properties/hubspots-default-deal-properties) ·
[HubSpot: Pipeline rules](https://knowledge.hubspot.com/object-settings/set-up-pipeline-rules) ·
[ServiceTitan: CRM Opportunities drawer](https://help.servicetitan.com/shared/2cc0f291-0649-48ef-8937-0e68b0759857) ·
[ServiceTitan: CRM Insights](https://help.servicetitan.com/shared/a7eef90a-beff-488f-b12b-027f1c1a39ce)

**Verdict:** optional reasons are Jobber parity; owner-managed predefined reasons are strongly supported by
Pipedrive; reopening is a verified HubSpot/ServiceTitan pattern, not verified Jobber parity. Keeping old reason
labels immutable in historic reports is a sensible UCRM data-design choice, not a sourced vendor behavior here.

### 6. Custom columns/stages and limits

- **Jobber:** up to 25 custom stages; built-in entry stages stay locked; system state overrides placement in a
  custom stage; custom stages do not trigger automations. Custom stages can be renamed, reordered, and deleted,
  but the official page does **not** document a delete-and-relocate-cards dialog.
  [Jobber: Sales Pipeline](https://help.getjobber.com/en/articles/sales-pipeline/)
- **Housecall Pro:** custom columns and multiple statuses inside columns; required statuses are locked. A status
  in use must have its cards and automations cleared before it can be turned off. No numeric limit is documented.
  [Housecall Pro: Pipeline FAQs](https://help.housecallpro.com/en/articles/6185346-pipeline-faqs)
- **Pipedrive:** pipelines and stages are customizable on all current plans; no numeric stage maximum was found
  in the reviewed official documentation. Deleting a stage deletes the deals still in it, so Pipedrive explicitly
  tells users to move them first.
  [Pipedrive: Design your sales process](https://support.pipedrive.com/en/article/how-can-i-customize-my-pipeline-stages)
- **HubSpot:** customizable pipelines/stages are verified; pipeline-count limits vary by subscription. No
  stage-count maximum was found in the reviewed official documentation.
  [HubSpot: Set up and manage pipelines](https://knowledge.hubspot.com/object-settings/set-up-and-customize-pipelines) ·
  [HubSpot: Product & Services Catalog](https://legal.hubspot.com/hubspot-product-and-services-catalog)
- **ServiceTitan:** its September 2026 custom-staging release supports renamed/inserted stages, custom win
  probability, and up to 12 stages per pipeline, but the cited release is commercially focused and availability
  must be checked for the customer's edition/region.
  [ServiceTitan: Custom Staging](https://help.servicetitan.com/release-hub/docs/match-your-sales-process-with-custom-staging-in-servicetitan-crm)

**Verdict:** custom stages are a mature-product convention. The safe relocation dialog is still a good design,
but it is an improvement, not demonstrated Jobber parity.

### 7. Stale/rotting attention rules

Jobber's documented freshness rule is blunt: green under one hour and red over 24 hours, based on opportunity
age. It does not document per-stage thresholds or an activity reset.
[Jobber: Sales Pipeline](https://help.getjobber.com/en/articles/sales-pipeline/)

Pipedrive directly supports a different inactivity duration for each stage. Completed activities, notes/files,
email actions, and edits reset the inactivity count. Scheduling a new activity can restore a rotten deal visually,
but an activity scheduled in the future does not prevent rotting by itself.
[Pipedrive: The Rotting feature](https://support.pipedrive.com/en/article/the-rotting-feature)

HubSpot now exposes adaptive stalled-deal and time-in-stage data, while ServiceTitan exposes Age, Last Activity,
overdue/untouched work, and stage duration. These are attention models, not identical red-card thresholds.
[HubSpot: Default deal properties](https://knowledge.hubspot.com/properties/hubspots-default-deal-properties) ·
[HubSpot: Stage calculated properties](https://knowledge.hubspot.com/properties/stage-calculated-properties) ·
[ServiceTitan: CRM Insights](https://help.servicetitan.com/shared/a7eef90a-beff-488f-b12b-027f1c1a39ce)

**Verdict:** Claude's recommendation to replace the fixed 24-hour rule is well supported. It should be labeled
“Pipedrive-inspired UCRM improvement,” with exact reset events defined explicitly.

### 8. Search, filters, lead source, and sorting

Jobber currently documents pipeline search; salesperson and created-date filters; and sorting by time in stage,
created date, or value. It explicitly says search does not include custom-field values. It does **not** list lead
source as a card field or pipeline filter.
[Jobber: Sales Pipeline](https://help.getjobber.com/en/articles/sales-pipeline/)

Housecall Pro supports board search by ID/customer/address/employee and filters for employee, tags, customer,
created date, status, value, and scheduled date. It uses Lead Source in records, automations, and reports, but its
current board-filter list does not include Lead Source.
[Housecall Pro: Getting Started with Pipeline](https://help.housecallpro.com/en/articles/6185127-getting-started-with-pipeline) ·
[Housecall Pro: Lead Sources](https://help.housecallpro.com/en/articles/5434315-how-to-use-lead-sources)

Pipedrive supports broad search, reusable filters, source fields, and pipeline sorting including expected close
date. HubSpot supports quick/advanced filters and saved views and stores record/traffic source properties.
[Pipedrive: Search](https://support.pipedrive.com/en/article/search-finding-what-you-need) ·
[Pipedrive: Quick filters](https://support.pipedrive.com/en/article/quick-filters) ·
[Pipedrive: Lead source in deals](https://support.pipedrive.com/en/article/lead-source-deals) ·
[Pipedrive: Prioritize deals](https://support.pipedrive.com/en/article/how-are-deals-ordered-in-the-pipeline-view) ·
[HubSpot: View and filter records](https://knowledge.hubspot.com/records/view-and-filter-records) ·
[HubSpot: Default deal properties](https://knowledge.hubspot.com/properties/hubspots-default-deal-properties)

**Verdict:** board search is Jobber parity. Lead-source display/filtering is a defensible cross-product
improvement, but the current official Jobber page contradicts the claim that it is documented Jobber Pipeline
behavior.

### 9. Tasks, schedule, mentions, attachments, contact actions, and create buttons

**Verified Jobber behavior:** opportunity tasks have owner/due date; a due task appears on its assignee's Schedule;
an Opportunity Brief supports up to five open and five completed tasks; and `@` mentions in Brief notes notify
teammates. Jobber's general Notes feature supports photos/files, but the current Pipeline article's Brief add-note
steps do not explicitly expose attachment upload.
[Jobber: Sales Pipeline](https://help.getjobber.com/en/articles/sales-pipeline/) ·
[Jobber: Notes and Attachments](https://help.getjobber.com/en/articles/notes-and-attachments/)

**Unverified Jobber claims:** the current Pipeline article does not document an Email button in the Brief, Text or
Call buttons, or a Pipeline-specific `+ New`. Jobber has global creation routes, but that is not the same claim.
[Jobber: Request Basics](https://help.getjobber.com/en/articles/request-basics/) ·
[Jobber: Quote Basics](https://help.getjobber.com/en/articles/quote-basics/)

**Verified wider patterns:** Housecall Pro's card quick view exposes CALL, CHAT, and EMAIL, and its global
`+ Create` handles new records; the Pipeline page itself says it is a view, not the record creator.
[Housecall Pro: Getting Started with Pipeline](https://help.housecallpro.com/en/articles/6185127-getting-started-with-pipeline)

HubSpot board cards can create notes/tasks/meetings and can expose email, call, note, task, meeting, Preview, and
AI Summary quick actions. HubSpot supports record mentions and attachments. Pipedrive deal detail includes
activities, notes, emails, files/documents; current Pipedrive also supports mentions/comments.
[HubSpot: Manage records in board view](https://knowledge.hubspot.com/records/manage-records-in-board-view) ·
[HubSpot: Customize board cards](https://knowledge.hubspot.com/records/customize-the-updated-board-cards) ·
[HubSpot: Mention a user](https://knowledge.hubspot.com/records/mention-a-user-on-a-record) ·
[HubSpot: Attachments](https://knowledge.hubspot.com/records/add-and-remove-attachments-from-records) ·
[Pipedrive: Deal detail view](https://support.pipedrive.com/en/article/deal-detail-view) ·
[Pipedrive: Mentions and comments](https://support.pipedrive.com/en/article/mentions-and-comments-beta)

HubSpot explicitly supports notification settings for newly assigned tasks. Pipedrive has assigned-to-you
notifications, activity reminders, and mobile notifications when an activity is added to a deal, but its current
help pages do not describe the exact same always-notify-on-assignment rule as HubSpot.
[HubSpot: User notifications](https://knowledge.hubspot.com/user-management/how-to-set-up-user-notifications-in-hubspot) ·
[Pipedrive: Notifications](https://support.pipedrive.com/en/article/notifications) ·
[Pipedrive: Mobile push notifications](https://support.pipedrive.com/en/article/push-notifications-in-the-mobile-app)

### 10. Long columns, independent scroll, and incremental loading

**Unverified.** Official board documentation from Jobber, HubSpot, Pipedrive, Housecall Pro, and ServiceTitan
describes cards, stages, sorting, dragging, and filtering but does not specify independent vertical scrolling per
lane, infinite loading, batch size, or a “Load more” interaction. The statement “Jobber and HubSpot do it this
way” should be removed unless a dated live-product observation is recorded separately.

This is still a legitimate UCRM interaction/performance decision. It needs usability and measured-load evidence,
not an unsupported parity claim.

### 11. Mobile pipeline

**HubSpot verified.** The current mobile-app documentation supports pipeline selection, list or board view,
swiping between stages/statuses, filtering/sorting, and changing a record's stage/status.
[HubSpot: Records in the mobile app](https://knowledge.hubspot.com/records/work-with-records-in-the-hubspot-mobile-app)

**Housecall Pro verified and omitted from Claude's comparison.** Its mobile app exposes Lead, Estimate, and Job
boards; users can swipe between columns, drag/drop cards or use a status dropdown, open card details, and create
new records. Access is limited to Admin and Office Staff roles.
[Housecall Pro: Pipeline FAQs](https://help.housecallpro.com/en/articles/6185346-pipeline-faqs)

**Pipedrive verified.** Its mobile feature list includes Pipeline view plus filtering, deal detail, activities,
calendar, files/photos, and offline support.
[Pipedrive: Mobile app features](https://support.pipedrive.com/en/article/what-features-do-the-mobile-apps-have)

**Jobber only partly verified.** Jobber explicitly says Opportunity Brief tasks and notes are Jobber.com-only and
unsupported in the mobile app, but the current page does not explicitly say the whole Pipeline board is absent.
“Jobber's app has no pipeline at all” should therefore be labeled unverified from current written documentation.
[Jobber: Sales Pipeline](https://help.getjobber.com/en/articles/sales-pipeline/)

**ServiceTitan verified with availability caveat.** Mobile CRM Opportunities supports opportunity lists,
filters/sorts/saved views, stage editing, tasks, activities, attachments, contacts, and quotes, but the release is
not evidence that every ServiceTitan plan/customer has it.
[ServiceTitan: Mobile CRM Opportunities](https://help.servicetitan.com/release-hub/docs/manage-your-sales-pipeline-in-the-field-with-mobile-crm-opportunities)

**Verdict:** a responsive/mobile UCRM pipeline is strongly supported by the wider market even if Jobber lags.

### 12. Reporting: loss reasons, conversion, and time to win

Jobber's Sales Outcomes report documents title, client, created date, won/lost date, total, and date/type filters.
It does not document loss-reason breakdown, stage conversion, or days-to-close in that report.
[Jobber: Sales Pipeline](https://help.getjobber.com/en/articles/sales-pipeline/)

That does not mean Jobber has no funnel reporting anywhere: Jobber Central has a lead funnel covering leads,
sent quotes, and jobs, but Jobber Central is the multi-account experience for group service providers.
[Jobber: Lead Funnel in Jobber Central](https://help.getjobber.com/en/articles/lead-funnel-jobber-central/)

Housecall Pro reports lead and estimate conversion, including views by date, employee, and lead source; its cited
report does not include loss-reason breakdown or time-to-win.
[Housecall Pro: Conversion Rate Reporting](https://help.housecallpro.com/en/articles/6499730-conversion-rate-reporting)

Pipedrive reports funnel conversion/win-loss and average sales-cycle/stage duration. HubSpot reports deal funnel
conversion, skipped stages, time in stage, deal loss reasons, deal velocity, and sales velocity. ServiceTitan CRM
Insights reports close rate, average days to close, per-record days to close, stage duration, and Closed-Lost
Reason.
[Pipedrive: Deal conversion](https://support.pipedrive.com/en/article/insights-reports-deal-conversion) ·
[Pipedrive: Deal duration](https://support.pipedrive.com/en/article/insights-reports-deal-duration) ·
[HubSpot: Sales analytics](https://knowledge.hubspot.com/reports/create-sales-reports-in-the-sales-analytics-suite) ·
[ServiceTitan: CRM Insights](https://help.servicetitan.com/shared/a7eef90a-beff-488f-b12b-027f1c1a39ce)

**Verdict:** add the three proposed measures. Attribute the precedent to Pipedrive, HubSpot, ServiceTitan, and
Housecall Pro where applicable—not solely to Jobber.

### 13. AI summaries

**HubSpot verified.** HubSpot supports an AI Summary quick action on eligible board cards and AI deal insights
based on deal data and recent interactions. [HubSpot: Customize board cards](https://knowledge.hubspot.com/records/customize-the-updated-board-cards) ·
[HubSpot: Manage deals in Sales Workspace](https://knowledge.hubspot.com/prospecting/create-and-manage-deals-in-the-sales-workspace)

**Pipedrive adjacent, not equivalent.** Pipedrive documents AI email-thread summaries and an optional AI deal
handover brief when creating/linking a Project, but no persistent AI summary on each pipeline deal card was found.
[Pipedrive: Pipedrive AI](https://support.pipedrive.com/en/article/pipedrive-ai) ·
[Pipedrive: Deals vs projects](https://support.pipedrive.com/en/article/projects-vs-deals)

**Jobber unverified.** The current Pipeline page documents client, value, date, freshness, tasks, and notes, but no
AI card summary. Jobber AI quote drafting and general AI features are different capabilities.
[Jobber: Sales Pipeline](https://help.getjobber.com/en/articles/sales-pipeline/) ·
[Jobber: Automations](https://help.getjobber.com/en/articles/automations/)

ServiceTitan has adjacent paid/limited AI opportunity recap products, not evidence that AI summaries are baseline
pipeline functionality. [ServiceTitan: Re-Engage](https://help.servicetitan.com/residential-s-r/docs/follow-up-on-opportunities-with-re-engage-in-field-pro)

**Verdict:** deferring AI summaries and making them optional is reasonable. They are not a launch-level industry
standard based on the reviewed primary sources.

## Verified, contradicted, and unverified summary

### Verified

- Jobber's system-owned stages, automatic movement, forward-only built-in workflow, send-or-mark-sent prompt,
  direct request-to-job Won, approved-quote/job-created Won, manual Lost except Draft, optional lost reason,
  search, up to 25 custom stages, Schedule-linked tasks, and note mentions.
- Pipedrive-style per-stage activity-aware rotting, customizable lost-reason lists, source fields, conversion and
  duration reporting, and mobile Pipeline view.
- HubSpot board/mobile stage management, optional backward/skip restrictions, activities/contact quick actions,
  assignment notifications, conversion/duration/loss reporting, and AI summaries.
- Housecall Pro card Call/Chat/Email actions, custom boards/statuses, broad search/filtering, conversion reports,
  full mobile Pipeline boards, and direct Lead-to-Job/Estimate Won.
- ServiceTitan automatic Won/Lost updates, reopen, loss reasons, custom staging (with availability caveats),
  mobile CRM, and deep conversion/time-to-close reporting.

### Contradicted or materially overstated

- “Cards can only move forward” as an industry standard.
- “Every competitor” behaves like Jobber's one request-to-quote board.
- Lead source on each Jobber Pipeline card and a Jobber Pipeline lead-source filter, based on the current official
  documented card fields and filter list.
- Describing Jobber's Sales Outcomes list as all Jobber funnel reporting without noting Jobber Central.
- Treating ServiceTitan/custom-stage availability as universal across all editions and customer segments.

### Unverified from current official sources

- Jobber Lost reopening, editable Jobber lost-reason list, Opportunity Brief Email/Call/Text buttons, a
  Pipeline-specific `+ New`, deletion that asks where to move cards, attachment upload inside the Brief, and the
  claim that the whole Jobber mobile app has no Pipeline.
- Independent per-column scrolling and automatic infinite loading in Jobber or HubSpot (or the other reviewed
  products).
- Exact numeric stage limits for Housecall Pro, Pipedrive, and HubSpot.
- A persistent Pipedrive or Jobber AI summary on every pipeline card.

## Major mature-product capabilities missing from the conversation

These are not automatically requirements, but the build plan should explicitly accept, defer, or reject them:

1. **Configurable stage automation.** Housecall Pro can send messages, update status, or archive after a delay;
   HubSpot can create/assign tasks, notify users, edit records, and run workflows on stage entry; Pipedrive has
   stage/idle/won/lost automation templates. Jobber's own custom stages notably do not trigger automations.
   [Housecall Pro: Pipeline automations](https://help.housecallpro.com/en/articles/6185127-getting-started-with-pipeline) ·
   [HubSpot: Pipeline automations](https://knowledge.hubspot.com/object-settings/set-up-pipeline-automations-for-objects) ·
   [Pipedrive: Automation templates](https://support.pipedrive.com/en/article/workflow-automation-templates) ·
   [Jobber: Sales Pipeline](https://help.getjobber.com/en/articles/sales-pipeline/)
2. **Required data, approvals, and stage guardrails.** HubSpot can require stage data, prevent skips/backtracking,
   restrict record editing by stage, and require deal approval. This is the mature extension of UCRM's proposed
   “tell me why the move is blocked” behavior. [HubSpot: Pipeline rules](https://knowledge.hubspot.com/object-settings/set-up-pipeline-rules)
3. **Multiple pipelines or separate boards.** Pipedrive and HubSpot support multiple pipelines; Housecall Pro
   separates Leads, Estimates, and Jobs; ServiceTitan manages named pipelines. UCRM should decide whether one
   locked contractor workflow is permanent or only the launch default.
   [Pipedrive: Multiple pipelines](https://support.pipedrive.com/en/article/how-can-i-have-multiple-pipelines) ·
   [HubSpot: Product Catalog](https://legal.hubspot.com/hubspot-product-and-services-catalog) ·
   [Housecall Pro: Getting Started](https://help.housecallpro.com/en/articles/6185127-getting-started-with-pipeline) ·
   [ServiceTitan: Custom Staging](https://help.servicetitan.com/release-hub/docs/match-your-sales-process-with-custom-staging-in-servicetitan-crm)
4. **Saved views, table view, bulk actions, and persistent filters.** Housecall Pro offers Board/Table views and
   persisted filters; HubSpot and Pipedrive provide saved/advanced filters and bulk editing. These become important
   long before a board reaches tens of thousands of records.
   [Housecall Pro: Getting Started](https://help.housecallpro.com/en/articles/6185127-getting-started-with-pipeline) ·
   [HubSpot: Manage records in board view](https://knowledge.hubspot.com/records/manage-records-in-board-view) ·
   [Pipedrive: List view](https://support.pipedrive.com/en/article/list-view)
5. **Permissions and visibility.** Jobber gates Pipeline access by permissions, Housecall Pro mobile Pipeline by
   role, and HubSpot supports pipeline visibility plus stage-based editing restrictions. A production CRM needs an
   explicit answer for who can view values, change stages, close/reopen, and configure stages.
   [Jobber: Sales Pipeline](https://help.getjobber.com/en/articles/sales-pipeline/) ·
   [Housecall Pro: Pipeline FAQs](https://help.housecallpro.com/en/articles/6185346-pipeline-faqs) ·
   [HubSpot: Limit access to assets](https://knowledge.hubspot.com/account-security/limit-access-to-your-hubspot-assets) ·
   [HubSpot: Pipeline rules](https://knowledge.hubspot.com/object-settings/set-up-pipeline-rules)
6. **Stage history and auditability.** Pipedrive shows days spent in each stage; HubSpot maintains date-entered and
   time-in-stage properties; ServiceTitan reports stage duration. Accurate funnel and time-to-win reports require
   immutable stage-entry/exit history, so the deferred activity-history problem is a reporting prerequisite, not
   merely a nice card timeline.
   [Pipedrive: Deal detail](https://support.pipedrive.com/en/article/deal-detail-view) ·
   [HubSpot: Stage calculated properties](https://knowledge.hubspot.com/properties/stage-calculated-properties) ·
   [ServiceTitan: CRM Insights](https://help.servicetitan.com/shared/a7eef90a-beff-488f-b12b-027f1c1a39ce)
7. **Archive/on-hold without corrupting loss reporting.** Pipedrive supports archiving inactive deals/leads without
   deleting them; Housecall Pro automates archiving after Won/Lost or other statuses. UCRM should distinguish a
   genuinely lost sale from paused/frozen work.
   [Pipedrive: Account cleanup and archiving](https://support.pipedrive.com/en/article/how-can-i-free-up-space) ·
   [Housecall Pro: Getting Started](https://help.housecallpro.com/en/articles/6185127-getting-started-with-pipeline)
8. **Forecasting as an explicit product decision.** The claim that contractors do not use stage probability is
   too strong: ServiceTitan's contractor CRM now supports per-stage win probability and weighted pipeline, while
   Pipedrive and HubSpot also support probability-based forecasting. It may still be unnecessary for UCRM's first
   customer segment, but it should be consciously deferred rather than dismissed as non-contractor behavior.
   [ServiceTitan: Custom Staging](https://help.servicetitan.com/release-hub/docs/match-your-sales-process-with-custom-staging-in-servicetitan-crm) ·
   [Pipedrive: Design your sales process](https://support.pipedrive.com/en/article/how-can-i-customize-my-pipeline-stages) ·
   [HubSpot: Set up and manage pipelines](https://knowledge.hubspot.com/object-settings/set-up-and-customize-pipelines)

## Corrected planning position

Proceed with the core fixes and additions, but update the rationale:

- **Exact Jobber parity:** real send-or-mark-sent, direct request-to-job Won, built-in system stage integrity,
  optional Lost reason, search, Schedule-linked tasks, mentions, and custom stages up to 25.
- **Wider mature-product pattern:** mobile boards, contact quick actions, configurable loss reasons, stage-aware
  staleness, task notifications, saved views/bulk tools, reopen/correction flows, deeper reports, and permissions.
- **Deliberate UCRM improvements:** collapsed Assessment by default, safe custom-stage deletion with relocation,
  explicit non-drag Move control, exact blocked-move guidance, preserved historic reason labels, and activity-aware
  stale defaults tailored to contractor response times.
- **Requires a separate decision:** multiple pipelines, user-configurable stage automation, approvals/required
  fields, archive/on-hold semantics, probability forecasting, and AI summaries.
- **Requires live-product or usability verification:** independent lane scrolling and infinite loading.

This corrected framing preserves the good substance of Claude's plan without claiming unsupported competitor
behavior as fact.
