# Recurring schedule editing: field-service industry practice

Researched 2026-09-01 from official Jobber, Housecall Pro, and ServiceTitan documentation plus RFC 5545. This note separates documented product behavior from UCRM design choices. Silence in a vendor's public documentation is not evidence that the vendor lacks a feature.

## Short answer

The proposed Part 10b has a sound **industry-standard core**, but the full proposal is not all established field-service practice.

- **Established and worth shipping:** edit one occurrence separately from the series; edit the current/future series; propagate operational fields such as time and assigned team; protect completed/past work from schedule regeneration; warn before replacing incomplete future visits; support recurring contracts whose visits are created only as needed.
- **Useful but UCRM-specific:** preserving every customized future visit through an arbitrary recurrence rebuild, treating it as an extra appointment, detecting collisions, and previewing exact delete/create/retain counts. RFC 5545 provides a standard identity model for modified occurrences, but it does not prescribe that product behavior.
- **Likely overengineering for the first slice:** collision-resolution UI, field-by-field preservation/merge rules for customized occurrences, and scheduled-to-as-needed conversion unless a confirmed contractor workflow requires conversion rather than creating/ending service periods. These can follow observed demand.

The smallest mature-product-shaped release is therefore: **Edit all incomplete/future visits** with a destructive warning, plus **Save and update future visits** for time and assigned team. Add line-item propagation when per-visit line items exist. Keep recurrence changes in the full-series editor. Do not claim customized-occurrence preservation is an industry norm.

## What mature products document

| Behavior | Official evidence | Conclusion for UCRM |
| --- | --- | --- |
| Edit one occurrence independently | Housecall Pro offers **Only this job** versus **This job and all future jobs**. Jobber documents that editing a visit changes only that visit. | Proven field-service pattern. |
| Edit current and future occurrences | Housecall Pro applies series edits to the current job and all future jobs. ServiceTitan recalculates all future recurring-service dates from an edited From date. RFC 5545 defines `RECURRENCE-ID;RANGE=THISANDFUTURE`. | Proven pattern, though each product's storage model differs. |
| Protect completed work | Jobber's Edit All Visits action applies to **all incomplete visits** and its schedule warning says incomplete visits are cleared and recreated. Housecall Pro tells users deleting future occurrences to begin with the first occurrence that will not be completed. | Completed/past visits should remain historical records. |
| Propagate time and assignment | Jobber's future-update fields include time of day and assigned team. Housecall Pro series edits propagate date, time, technician, and arrival window. | Time and assigned team are a defensible initial set. |
| Propagate recurrence | Jobber exposes repeating schedule in Save and update future visits. Housecall Pro permits recurrence changes from the current job forward. | This is documented industry behavior. Omitting it from the small dialog is a UCRM safety simplification, not proof that Jobber overengineered it. Keep recurrence editable in the warned full-series flow. |
| Propagate line items | Jobber permits line-item changes on one visit and includes line items among future-update choices. | Useful for per-visit pricing, but defer until UCRM has working per-visit line items. |
| Propagate instructions/notes | Jobber says job instructions carry to visits and its Edit All Visits flow can update visit instructions. ServiceTitan recurring-service records include a memo that carries to recurring events/upcoming appointments. | Instructions are operationally legitimate. Defer if scope demands, but do not classify them as inherently job-only. |
| Destructive recurrence warning | Jobber explicitly warns that editing a job schedule creates new visits and overwrites customized visit details; confirmation is required before updating. | A consequences warning is proven and necessary. Exact before/after counts are a UCRM enhancement. |
| Preserve customized occurrences during rebuild | Jobber explicitly documents the opposite: regenerated visits overwrite customized visit details. RFC 5545 identifies an exception using the original occurrence time in `RECURRENCE-ID`, even when moved, but does not define how an application must reconcile exceptions after replacing an arbitrary recurrence rule. | Preservation may differentiate UCRM, but it adds material rules and UI. It is not needed to match mature field-service practice. |
| As-needed recurring contracts | Jobber documents an **As needed - we won't prompt you** recurring schedule for snow removal, irrigation startups, seasonal maintenance, and other on-demand contracted work; it creates no visits until users add them. | As-needed is a proven contractor workflow. |
| Convert scheduled recurrence to/from as-needed | The reviewed official sources document creating and using as-needed recurring jobs, but do not clearly document converting an existing scheduled series in both directions. | This conversion remains an evidence gap. Do not call it industry standard. |

## Assessment of the current proposal

### Not overengineering

1. **A separate series editor.** Jobber and Housecall Pro both distinguish a single occurrence from series/future changes.
2. **Completed-visit protection.** Rewriting completed work would damage operational and billing history; Jobber scopes bulk changes to incomplete visits.
3. **Time and assigned-team propagation.** Both Jobber and Housecall Pro document these bulk/future changes.
4. **An explicit destructive warning.** Jobber warns that incomplete visits will be regenerated and customized details overwritten.
5. **As-needed jobs themselves.** Jobber documents specific contractor use cases, especially weather-triggered work.

### Potential overengineering now

1. **Preserve customized visits automatically.** This sounds safer but creates unresolved semantics when the new recurrence no longer contains the original occurrence. Keeping each exception as an extra visit, merging it with a same-day generated visit, or mapping it to a new recurrence are distinct business decisions. Neither reviewed field-service vendors nor RFC 5545 supplies the proposed rule.
2. **Same-day collision resolution.** This is required only if automatic exception preservation is chosen. It is avoidable in the first release by following Jobber's clear regenerate-with-warning behavior.
3. **Exact consequences accounting.** “Remove 8, create 11, retain 3” is helpful and safer than a generic warning, but it is an enhancement rather than a documented baseline. It is reasonable if the schedule preview already computes these values cheaply; otherwise ship a clear warning first.
4. **Scheduled-to-as-needed conversion as pause/resume.** The official Jobber material supports as-needed contracts, not using as-needed as a seasonal pause. Pause/resume should preserve recurrence and is a separate mental model.
5. **Future instructions in Part 10b.** Instructions are valid in mature products, but adding another propagation/override dimension is optional. Time and team deliver the clearest immediate value.

## Recommended minimum for Part 10b

1. Add **Edit all visits** for recurrence, time, and assignment changes.
2. Apply it only to incomplete future visits; completed visits remain untouched.
3. Before recurrence regeneration, clearly state that incomplete visits are replaced and customized visit details will be lost, then require confirmation.
4. Add **Save and update future visits** for time of day and assigned team.
5. Add line items there only after per-visit line items ship.
6. Retain as-needed recurring-job support. Allow as-needed-to-scheduled conversion only if it naturally falls out of the same safe editor; defer scheduled-to-as-needed conversion until a contractor use case is confirmed.
7. Defer customized-occurrence preservation and collision handling to a later, separately approved enhancement backed by user evidence.

This is slightly less ambitious than the current proposal, but it aligns more directly with documented mature field-service behavior and avoids inventing a calendar exception policy before contractors have demonstrated the need.

## Official sources

- Jobber, [Visits](https://help.getjobber.com/en/articles/visits/) — single-visit edits, regeneration warning, customized details being overwritten, and future-update fields.
- Jobber, [Job Basics](https://help.getjobber.com/en/articles/job-basics/) — Edit All Visits and application to incomplete visits.
- Jobber, [Create New Visits for Existing Recurring Jobs (Snow Removal Workflow)](https://help.getjobber.com/en/articles/create-new-visits-for-existing-recurring-jobs-snow-removal-workflow-new-schedule/) — contractor use cases for as-needed recurring jobs.
- Jobber, [Create a Recurring Job](https://help.getjobber.com/en/articles/create-a-recurring-job/) — as-needed creates no visits and job instructions carry to visits.
- Housecall Pro, [Manage Recurring Jobs](https://help.housecallpro.com/en/articles/2845351-manage-recurring-jobs) — only-this-job versus this-and-future edits, propagated schedule/team fields, recurrence edits, and future deletion behavior.
- ServiceTitan, [Manage recurring services](https://help.servicetitan.com/residential-s-r/docs/manage-recurring-services) — recurring service editing, generated events, editable booked-job details, and recurring-service memo.
- ServiceTitan, [What is the process for pushing the dates of membership recurring visits?](https://help.servicetitan.com/docs/what-is-the-process-for-pushing-the-dates-of-membership) — recalculation of future dates without retroactive changes.
- IETF, [RFC 5545: Internet Calendaring and Scheduling Core Object Specification](https://www.rfc-editor.org/rfc/rfc5545.html#section-3.8.4.4) — occurrence identity and `THISANDFUTURE` semantics.

## Evidence gaps

- The reviewed official field-service sources do not establish automatic preservation of customized occurrences through arbitrary recurrence replacement.
- They do not establish exact create/delete/retain previews as a common field-service convention.
- They do not clearly document bidirectional conversion between scheduled and as-needed recurring jobs.
- Public documentation does not fully describe every product's collision, transaction, audit, or rollback behavior.
