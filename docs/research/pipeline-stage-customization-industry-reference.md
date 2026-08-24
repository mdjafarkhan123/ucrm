# Pipeline stage customization: industry reference

Researched 2026-08-24 from vendor-owned help centers and product documentation. This note distinguishes documented behavior from gaps; an undocumented item must not be treated as evidence that a product supports or forbids it.

## Decision summary for UCRM

The best fit is a **protected core + optional presentation detail + custom follow-up stages** model:

1. New accounts start with five visible columns: **New Request → Assessment → Draft → Awaiting Response → Changes Requested**.
2. **Assessment** is a collapsed presentation of three system states: assessment unscheduled, scheduled, and completed. A setting called **Show detailed assessment stages** expands that one column into those three columns. This changes the board presentation, not the underlying request state or history.
3. The five core columns and their underlying workflow keys are protected. They cannot be deleted, renamed, or reordered across the Request → Quote boundary. Their labels may be localized later, but an account administrator cannot redefine their meaning.
4. A later release may add **custom follow-up stages** within either the Request section or Quote section. They may be named, reordered within their section, hidden/disabled, and deleted safely. They never substitute for a system state.
5. The first protected stage in each record section stays fixed: New Request for requests and Draft for quotes. This directly follows Jobber's strongest guardrail.
6. A system event always wins over manual organization: scheduling/completing an assessment or drafting/sending/approving a quote moves the opportunity to its corresponding system stage even when it was parked in a custom stage.
7. Custom stages do not trigger lifecycle automations or rewrite Request/Quote status. If UCRM later supports custom-stage automations, dependencies must be visible in settings and must block disable/delete until removed or reassigned.
8. Deleting or disabling a populated custom stage must be blocked until the administrator selects a destination stage and confirms a bulk move. Never silently delete cards, archive opportunities, or guess a destination.
9. Stage configuration belongs in **Settings → Pipeline**, available only to the owner/admin permission. The board may provide a **Customize pipeline** shortcut that deep-links there.
10. Keep Won and Lost as outcomes outside the active columns. Preserve stage-entry history so reports do not change retroactively when a stage is renamed, hidden, or deleted.

This supports the agreed launch sequence: ship the five-column default and detailed-assessment toggle first. Arbitrary custom stages can follow. The evidence supports eventual custom stages, but it does **not** show that they must be in the first release: both Jobber and HighLevel explicitly emphasize useful defaults or keeping pipelines simple.

## Cross-product comparison

| Product | Protected/system stages | Add, insert, rename, reorder | Hide/disable/delete populated stage | Automations and reporting | Reset/restore and limits |
| --- | --- | --- | --- | --- | --- |
| **Jobber** | Built-in stages are system-driven. The first Request and Quote stages cannot be replaced or moved. Only custom stages can be renamed. A qualifying product action automatically returns a card to its system stage. | Up to **25 custom stages**. A custom stage may be inserted before, after, or between existing stages, in either the Request or Quote section. Custom stages can be renamed, reordered, and deleted. | The current official article says a custom stage can be deleted, but does **not document what happens to cards in it**, whether deletion is blocked, or whether cards must be reassigned. Hide/disable is not documented. | Built-in stages drive automations; custom stages do not. Built-in stages have entry criteria, and invalid manual drops bounce back. Won/Lost leave the active board and remain in Sales Outcomes reporting. | No reset-to-default or deleted-stage restore behavior is documented. The 25-custom-stage limit is explicit. |
| **Housecall Pro** | Required statuses/columns show a lock and cannot be hidden. Other preset columns can be visible or hidden. | Admins can add a custom column to the left or right of a selected column. Creating a column also creates a same-named status. They can add multiple statuses within a column, rename/delete custom columns and statuses, reorder columns, reorder statuses, and move statuses between columns. | A status in use cannot be turned off until **all cards are moved** and **linked automations are disabled**. The docs tell the admin to reassign cards on the board. Custom-column deletion warns that child statuses will be removed; the article does not clearly state whether populated-column deletion is independently blocked, so that is undocumented. | Automation dependencies explicitly block turning off a status. Broader reporting consequences are not documented in this FAQ. | Reset-to-default/restore and maximum counts are undocumented. |
| **JobNimbus** | Reporting **Stages** are built-in and cannot be renamed. Custom **Statuses** sit within those stages. Stage order is linear (Lead → Estimating → Sold → In Production → Accounts Receivable → Completed); Lost can occur anywhere. | Account-settings users create/edit workflows and configure their statuses. Statuses must remain in the valid stage order; an invalid move changes the stage assignment to None. New statuses/workflows are not automatically added to boards. | A whole workflow can be hidden while keeping its records and statuses. A workflow containing Contacts or Jobs cannot be deleted until those records are moved elsewhere. The located docs do not clearly document deletion of one populated status. | Stage assignments feed Insights and custom reports; missing or invalid assignments impair reporting. | Workflow cloning is supported. Reset-to-default, deleted-stage restore, and maximum counts are undocumented. |
| **ServiceTitan** | In Custom Follow Up, custom opportunity statuses must belong to a protected reporting category: Not Attempted, Unreachable, Contacted, Won, or Dismissed. The chosen category determines KPI/report placement. Separately, its newer CRM Job Pipeline advances on real actions such as adding or selling/dismissing an estimate. | Custom follow-up statuses can be added in Settings and activated/deactivated/reactivated. Public documentation located for this review does not establish arbitrary pipeline-stage rename/reorder/delete behavior. | Deactivation/reactivation is documented for Custom Follow Up. Populated-status deletion/reassignment is undocumented in the located official docs. | Category choice explicitly controls KPIs/reporting. Job Pipeline system actions automatically move opportunities to Propose, Closed Won, or Closed Lost. | Reset-to-default, restore, and maximum counts are undocumented. The cited Job Pipeline feature is Early Access, so it should not anchor UCRM behavior by itself. |
| **FieldPulse** | Official product material confirms a custom-status workflow builder and status-change automation, but does not document system/custom protection rules. | Custom statuses are advertised. Detailed add/rename/reorder/delete rules were not found in accessible official help documentation. | Undocumented. | Official product material shows automations triggered by status changes, including customer notifications. Reporting consequences are undocumented. | Undocumented. |
| **Buildertrend** | Official docs describe a small fixed set of lead outcome statuses for import (Open, Lost, No Opportunity, Sold) and job statuses, but the located docs do not establish a customizable Kanban stage editor comparable to Jobber or Housecall Pro. | Lead activities and templates are highly customizable; that is not the same as customizable pipeline stages. Stage editing rules are undocumented in the located official sources. | Undocumented. | Lead activity types and lead-status reporting exist. Detailed stage-change automation/report-history behavior is undocumented in the located sources. | Undocumented. |
| **HighLevel** (general CRM contrast) | Its pipeline stages are general-purpose rather than domain-backed system states. | Stages can be added, renamed, reordered, included/excluded from reporting, or deleted. | When deleting a stage, the admin chooses another stage and all existing opportunities are transferred there. | Stage-based automations and reporting are first-class. Official documentation says existing triggers continue to work after its updated editor, but does not fully specify how references to a specifically deleted stage are handled. | Deleted whole pipelines and their stages/opportunities can be restored for up to 60 days through audit logs; stage-only restore and a maximum stage count are undocumented. |

## What the leading patterns tell us

### 1. Separate business truth from board organization

Jobber is the closest reference for UCRM because a card is a projection of a real Request or Quote. Its built-in stages are guarded by domain criteria; dragging into one launches the required action, and a system event can move an opportunity out of a custom stage. This prevents a board label from claiming that an assessment was scheduled or a quote was sent when the underlying record says otherwise.

ServiceTitan reinforces the same architectural direction: custom labels are grouped under fixed reporting categories, while estimate actions move CRM opportunities automatically. JobNimbus also separates fixed reporting stages from customizable statuses.

**UCRM implication:** retain immutable stage keys and real Request/Quote state underneath the board. Custom follow-up stages are organizational overlays, not extra document statuses.

### 2. Five columns is a defensible default; detail should be optional

Jobber says its defaults work without setup. HighLevel's official guidance says to keep pipelines simple and include only stages that matter. Housecall Pro provides visibility toggles while locking required states. Together, these support a simple default view with optional operational detail.

**UCRM implication:** the five-column collapsed board is the default. Expanding Assessment is a view choice. It must not create/delete/rewrite stages or distort reporting.

### 3. Custom insertion needs domain boundaries

Jobber allows custom stages almost anywhere but still asks the user to add them within the Request or Quote section; the initial system stage of each section stays fixed. JobNimbus similarly enforces a linear order for its reporting stages.

**UCRM implication:** when custom stages arrive, require the admin to choose **Requests** or **Quotes**. Allow reordering only within that section. Do not allow a Request follow-up stage after Draft or a Quote follow-up stage before Draft. This avoids impossible drag behavior at the record-conversion boundary.

### 4. Safe removal is a two-dependency problem

Housecall Pro will not turn off an in-use status until cards are moved and linked automations are disabled. HighLevel offers destination-stage reassignment during deletion. JobNimbus blocks deletion of a populated workflow. These are complementary pieces of the safest pattern.

**UCRM implication:** on Disable/Delete:

- Show the number of active opportunities in the stage.
- Show every automation/report/filter dependency that explicitly references it.
- Require one destination stage in the same Request/Quote section for active cards.
- Update or disable dependencies explicitly; never silently retarget an automation.
- Keep historical stage events linked to an immutable archived stage ID and retain the last label for old reports.
- Prefer **Disable** as the normal action. Offer permanent deletion only when the stage has never been used, or treat “Delete” as archived soft deletion internally.

The last two history recommendations are UCRM design judgments; vendor help pages do not fully describe their historical data storage.

### 5. Settings changes should be administrator-controlled

JobNimbus puts workflow editing in Account Settings and limits it to members with settings access. HighLevel reserves pipeline deletion/restoration for agency or account admins. Housecall Pro uses Settings → Pipeline → Customize boards. Jobber offers Edit Stages from the board and requires substantial Pipeline permissions for access.

**UCRM implication:** only owner/admin users customize the pipeline. Everyone with ordinary pipeline access may move opportunities where allowed, but cannot edit the shared workflow. A board shortcut may open Settings; configuration should not be an inline accidental-edit mode.

## Proposed UCRM settings behavior

### Launch release

**Settings → Pipeline**

- `Show detailed assessment stages` toggle.
- Off (default): Assessment is one column; cards show Needs scheduling, Scheduled with date/time, or Complete badges.
- On: Assessment expands to Assessment unscheduled, Assessment scheduled, and Assessment completed.
- A read-only preview shows the resulting board.
- Core stages carry a lock icon and a plain explanation: “This stage is connected to requests/assessments/quotes and can’t be removed.”
- No arbitrary custom-stage controls yet. Do not show disabled “coming soon” controls unless product messaging needs them.

### Custom-stage release

- **Add follow-up stage** asks for Name and Section (Requests or Quotes), then placement within that section.
- Maximum: adopt Jobber's documented ceiling of **25 custom stages per pipeline** as a hard safety cap, while recommending no more than 3–5 visible custom stages. The recommendation is ours; only the limit comes from Jobber.
- Custom stage actions: Rename, Reorder within section, Hide from board, Disable, Delete.
- Protected stages: no rename/delete/reorder; detailed Assessment changes only through its dedicated toggle.
- Disable/delete dialog: destination selector for active cards, dependency list, typed/explicit confirmation for destructive removal.
- If a system action occurs while parked in a custom stage, move the opportunity to the correct system stage and record the transition in activity history.
- Custom stages are excluded from lifecycle automations initially. If stage-based follow-up automations are later added, label them separately from lifecycle automations.

### Terms

Use **Assessment** for the site visit and **Quote** for the priced document. Avoid “Assessment/Estimate”: contractors may say “estimate appointment,” but combining the words in a column blurs the appointment with the commercial document. On cards, natural phrases such as “Estimate visit scheduled” could be tested later without changing domain terms.

## Official sources

- Jobber, [Sales Pipeline](https://help.getjobber.com/en/articles/sales-pipeline/) — default and custom stages, 25-stage limit, protected first stages, rename/reorder/delete, system criteria, drag actions, automation behavior, outcomes, and permissions.
- Jobber, [User Permissions](https://help.getjobber.com/en/articles/user-permissions/) — Pipeline permission and role context.
- Housecall Pro, [Pipeline FAQs](https://help.housecallpro.com/en/articles/6185346-pipeline-faqs) — required locked statuses, visibility, add/edit/reorder/delete, and card/automation cleanup before disabling an in-use status.
- JobNimbus, [What Are Stages?](https://support.jobnimbus.com/what-are-stages) — fixed stage names, linear ordering, and reporting consequences.
- JobNimbus, [How Do I Add or Edit a Workflow?](https://support.jobnimbus.com/how-do-i-add-or-edit-a-workflow) — settings permission, custom statuses, fixed stage sequence, Lost placement, board inclusion, and cloning.
- JobNimbus, [How Do I Hide a Workflow?](https://support.jobnimbus.com/how-do-i-hide-a-workflow) — hide behavior and prohibition on deleting populated workflows.
- JobNimbus, [How Do My Workflows Work With Insights?](https://support.jobnimbus.com/how-do-my-workflows-work-with-insights) — stage movement and Insights history consequences.
- ServiceTitan, [How to customize the Opportunity Status filter for expiring memberships](https://help-stage.servicetitan.com/how-to/customize-opportunity-status) — fixed categories, custom statuses, activation/deactivation, and KPI/report mapping.
- ServiceTitan, [Manage opportunities in Job Pipeline in CRM](https://help.servicetitan.com/shared/ef0855f1-4d8b-40fe-966f-7688f25bee8e) — system-driven movement from estimate actions and Early Access context.
- FieldPulse, [Customized Workflows for Field Service Teams](https://www.fieldpulse.com/features/custom-workflows) — first-party confirmation of custom status workflows and status-triggered automation; detailed administration rules remain undocumented.
- Buildertrend, [Data Entry Timelines and Approval Guideline](https://buildertrend.com/help-article/data-entry-timelines-and-approval-guideline/) — official import status vocabulary for leads.
- Buildertrend, [Lead Activities Overview](https://buildertrend.com/help-article/lead-activities-overview/) — customizable lead follow-up activities and reporting context.
- HighLevel, [Understanding Pipelines](https://help.gohighlevel.com/support/solutions/articles/155000001982-understanding-pipelines) — add/rename/reorder/report/delete controls, destination reassignment, automation, reporting, and keep-it-simple guidance.
- HighLevel, [Deleting and Restoring Opportunities & Pipelines](https://help.gohighlevel.com/support/solutions/articles/155000002041) — admin permissions and 60-day restoration of deleted pipelines.

## Evidence limitations

- Vendor documentation changes frequently and some features are plan-gated, early-access, or account-configured.
- Housecall Pro documents turning off an in-use status safely but is ambiguous about direct deletion of a populated custom column/status.
- Jobber documents deletion controls but does not document populated-stage reassignment or deletion consequences.
- Public official detail for FieldPulse and Buildertrend stage administration is sparse; no conclusions about unsupported operations should be inferred from that silence.
- ServiceTitan's public docs expose multiple opportunity concepts. The cited Custom Follow Up status model and Early Access CRM pipeline should not be assumed to be one universal editor.
- No located contractor-CRM source fully documents historical reporting after stage rename/deletion. UCRM's immutable event-history recommendation is therefore a design decision based on preserving reporting integrity, not a copied vendor feature.
