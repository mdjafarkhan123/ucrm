# Invoice source transitions — targeted research, 2026-09-04

Official Help review for the Invoices campaign. No live transition was executed in this pass. Jafar has
approved retaining issued Invoices through Void and preserving financial corrections through
reversal/replacement. That approval establishes traceability policy; it does not establish every
eligibility or source-work consequence below. Stop before schema design.

| Behavior                                     | Official evidence                                                                                                                                                                                                             | Confidence             | Consequence for UCRM                                                                                           |
| -------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------- | -------------------------------------------------------------------------------------------------------------- |
| Correcting upcoming progress amounts         | Update Job pricing, then upcoming payment-schedule amounts; create the updated Invoice. Direct progress line-amount editing is unavailable. [Progress Invoicing][P], updated March 31, 2026.                                  | Verified documentation | Preserve Job ownership of upcoming amounts.                                                                    |
| Correcting an already-issued progress amount | Issued installments are locked in the Job schedule. The same article directs issued changes to the Invoice, but supplies no monetary control or worked correction example that resolves its direct-line-edit prohibition. [P] | Unresolved             | Do not claim a verified Jobber monetary correction path.                                                       |
| Void of a progress installment               | Progress-schedule Invoices are expressly excluded from Void. [Invoice Basics][I], updated July 27, 2026.                                                                                                                      | Verified documentation | Extending UCRM Void to progress installments would be an additional eligibility decision, not implicit parity. |
| Source work after a non-progress Void        | Void retains the immutable Invoice and releases attached deposits. Its documented consequences do not say whether the Job, Visit, or reminder becomes billable again. [I]                                                     | Unresolved             | Deposit release does not prove source-work release. Decide rebilling explicitly.                               |
| Reminders before cancellation                | Due reminders produce Requires Invoicing; creating an Invoice marks its reminder done. A reminder may also be cleared by deletion. [Invoice Reminders][R], updated March 31, 2026.                                            | Verified documentation | Clearing and later reopening are distinct transitions.                                                         |
| Reminder after Void                          | The reminder article does not specify reopening or recreation after Void. [R]                                                                                                                                                 | Unresolved             | Do not assert automatic return to Requires Invoicing.                                                          |

## Decisions requiring Jafar's approval

1. **Issued progress corrections:** choose a permitted business action for correcting an already-issued
   installment under the approved reversal/replacement policy. Recommended proposal: preserve its original
   issued amounts and issue an explicitly linked correction/replacement; Job schedule changes alone must
   never rewrite it. Whether progress Invoices can be voided, and how their replacement affects the Job's
   remaining scheduled amount, still require approval. Jobber's exclusion prevents treating ordinary Void
   parity as the answer.
2. **Source work after Void:** choose whether voiding restores original Visit/reminder billing eligibility
   automatically or makes replacement an explicit action. Recommended proposal: explicit replacement for
   erroneous bills; cancellation does not automatically queue the work for rebilling. Otherwise a Client
   cancellation can create an unwanted replacement charge. This is a proposal, not observed Jobber behavior.

## Job contract consequences

The [Job contract](jobs-behavior-contract.md) already keeps issued installments locked from Job editing
and separates invoicing from operational Job closure. Keep those rules. Resolve the two decisions above
before adding any cross-domain cancellation behavior. Preserve the distinction between an Invoice source's
historical association and its eligibility for a replacement; the existing [Invoice contract](invoice-behavior-contract.md)
rule that a source cannot be billed twice does not define that exception.

The Job contract's Requires invoicing row also includes uninvoiced completed work, whereas its timing section
specifies a due reminder as the trigger. That broader UCRM condition must be reconciled explicitly when
deciding what a cancellation does; the official reminder rule alone does not approve automatic requeueing.

Research covered the current Progress Invoicing, Invoice Basics, and Invoice Reminders articles and targeted
official-Help searches for Void with Visits, reminders, and reinvoicing. No answer for these missing
post-Void transitions was found. Absence from the documentation is not evidence of either behavior.

[P]: https://help.getjobber.com/en/articles/progress-invoicing/
[I]: https://help.getjobber.com/en/articles/invoice-basics/
[R]: https://help.getjobber.com/en/articles/invoice-reminders/
