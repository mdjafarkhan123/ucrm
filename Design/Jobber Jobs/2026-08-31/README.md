# Jobs tour evidence — 2026-08-31

Private workspace research for Jafar. Screenshots contain account/client information; do not publish them without reviewing that content.

Open [the visual gallery](gallery.html) for all **72 screenshots**: 69 Jobber captures and three of UpliftContractor. Each Jobber image has a same-named `.txt` DOM snapshot. Screenshots capture the visible viewport or page at that moment; an image is not evidence of controls outside its captured area. Earlier full-page captures may not retain a transient menu; consult the paired text and the coverage below. Number 07 is intentionally absent.

Read the [proposal](../../../docs/research/jobs-discovery-and-proposal.md) for recommendations and the [official research](../../../docs/research/jobber-jobs-official-behavior-2026-08-31.md) for documented-only behavior.

## Screen coverage

| Captures | Coverage | Depth |
| --- | --- | --- |
| 01–04 | Jobs listing, status/type filters, list actions | Inspected; downstream import/booking/checklist-management flows not exercised |
| 05–16 | One-off creation, existing client picker, date-range/custom dates, independent visits, draft actions, unscheduled visit, split payment schedule, catalog, save options | Created/saved two-visit test; draft payment schedule removed with confirmation; no send action used |
| 17–27 | Detail header, More menu, signature pad, inline title editor, costing, notes, time, expense, arrival window, empty checklist attachment | Inspected; side forms canceled; no signed document, field record, or account configuration saved |
| 28–37 | Individual visit, billing settings, reminder creation, bulk selection/date moves, final completion, select-jobs invoice handoff, invoice composer | Visit title/instructions edited and both visits completed; other mutations canceled; invoice draft not saved |
| 38–45 | Recurring defaults, custom weekly/monthly dates/ordinal weekdays, as-needed, custom billing, fixed price/no reminders | As-needed recurring job saved with zero visits; end duration/date inspected, occurrence-count support not established |
| 46–52 | Edit all visits, regeneration warning, generated visits, individual recurring editor, future-update choices, completed history | Generated three Mondays, completed one; instruction-only all-incomplete edit persisted and left completed instructions unchanged; future propagation dialog canceled |
| 53–56 | Fixed/visit-based billing, discard warning, close-job consequences | Changes and closure canceled; no automatic payment configured |
| 57–61 | Deletion confirmations/results, activity history, final original-only Jobs list | Both disposable jobs deleted with their associated visits; original retained |
| 62–70 | Schedule onboarding, calendar popover, visit Info/Client/Notes and actions, month/day/map views | Read-only original visit inspection; onboarding closed without saving configuration; map opened, routing not exercised |
| our-01–03 | UpliftContractor Quotes list, approved detail, creation | Read-only comparison; shared structures retained in proposal |

## Persisted experiments and cleanup

1. One-off research job #2 used an existing client and catalog service. It had one undated visit and one dated anytime visit. Editing the first visit did not change the second. Completing the final visit showed three next-step choices; Leave as Action Required retained the open job. Invoice handoff reached an unsaved composer and was canceled.
2. Recurring research job #3 used that same client. Fixed pricing plus as-needed/no-reminder scheduling saved zero visits. Edit All Visits generated September 7, 14, and 21, 2026. September 7 was completed. A subsequent instruction-only update changed unfinished visits and preserved the completed visit's instructions. This does not establish completed-price immutability or full custom-override preservation.
3. Delete confirmations named two visits and three visits respectively. Both jobs were deleted. Capture 61 shows only the original sample job. The [ledger](test-records.json) records the deleted job URLs for audit, not as live navigation targets.

No new client was saved. No original job was edited/completed/deleted. No invoice, expense, time entry, note, checklist, or signature was saved. We did not send communications or collect payments. A client communication inspection showed no communications at that check; this is not a comprehensive delivery-system audit. Routine account activity and numbering traces can remain after deletion.

## Important distinctions found live

- Schedule later on the current one-off creator creates an undated visit; no second placeholder checkbox was observed. Recurring as-needed creates zero visits.
- One-off multi-date selection showed a 20-visit limit in the creation dialog; it is not an established lifetime job limit.
- Fixed recurring and visit-based pricing have different invoice-frequency choices. Invoice reminders are internal work, not customer payment reminders.
- Edit All Visits regeneration and Update Future Visits are separate flows. The regeneration warning says incomplete visits are deleted/recreated; the future dialog selects time, repeats, assignment, and line items.
- Last-visit completion is not automatic job closure. The recurring close preview offered removing two future visits, but closure itself was canceled.
- Arrival window is editable at job level. Recurring costing uses a labeled recent period; it is not a lifetime profit or cash measure.
- The sample account had no checklist templates and no connected automatic-payment setup, limiting safe live coverage.

## Explicit coverage limits

The core desktop tour is complete, not an exhaustive certification of every Jobber module or account entitlement. Actual close/reopen, changed-value future propagation, completed pricing changes, deletion with existing financial/field records, sent reminders/booking/follow-up, actual charges, signed PDFs, customer installment presentation, filled checklists, native mobile/offline, route optimization, bulk weather-driven dispatch, imports, and booking setup were not executed. Some have primary-source documentation; others remain open questions. Custom annual recurrence was not deeply exercised. No scale/capacity claims follow from this trial-account tour.

The proposal preserves these capabilities or names their dependencies; absence from a screenshot must not be treated as a reason to remove a feature.
