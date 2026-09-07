# Invoices Part 5c — Jobber-grounded product proposal

2026-09-06. **Direction approved for planning by Jafar; no code.** Jafar selected Jobber as the sole reference and excluded GHL after reviewing the distinction between the products. The implementation sequence is in [invoice-part-5c-plan.md](invoice-part-5c-plan.md).

## Evidence

Jobber supports a schedule on a quote or directly on a one-off job. Described percentage/fixed installments must reconcile to the total. Staff generate separate drafts from installments. Issued amounts lock on the job; progress line amounts cannot be edited independently. Invoice dates/statuses populate after issuance. Customer line columns distinguish full item value from the current portion. [Progress Invoicing, updated March 31, 2026](https://help.getjobber.com/en/articles/progress-invoicing/).

The same article conflicts on whether customer progress invoices display future installments. It also directs issued changes to the invoice without explaining how monetary corrections satisfy the line-edit prohibition. These remain unresolved, as do exact tax/discount allocation and residual-cent rules. Its quote-only wording conflicts with its explicit direct-job instructions; the separate one-off guide also confirms job schedules. [Progress Invoicing](https://help.getjobber.com/en/articles/progress-invoicing/), [Create a One-Off Job, updated July 15, 2026](https://help.getjobber.com/en/articles/create-a-one-off-job/).

Jobber documents a required first quote deposit and application of received deposits to invoices. Its general automatic deposit application description does not fully specify the worked progress-installment accounting case. [Deposits on Quotes, updated June 25, 2026](https://help.getjobber.com/en/articles/deposits-on-quotes/).

Custom visit quantities/items transfer only for the corresponding invoiced dates; fixed-rate billing does not use those visit overrides. [Visits](https://help.getjobber.com/en/articles/visits/).

**Observed live, September 6:** on Job #1, Billing → Edit Invoice Settings opens a dialog with separate closure-reminder and payment-schedule checkboxes. Selecting the schedule checkbox did not expose installment inputs in that dialog. Cancel → Discard Changes returned to the unchanged job. No schedule was saved, invoice generated, or message sent. This confirms the entry point only; customer progress display, issued corrections, and installment editing were not live-verified.

## Proposed contractor behavior

The existing [Job contract](jobs-behavior-contract.md#scope-pricing-basis-and-money), [Quote contract](quote-behavior-contract.md#deposits-and-payment-schedules), and [Invoice contract](invoice-behavior-contract.md) already establish the ownership and safeguards below. This proposal completes that workflow; it does not reopen approved D1–D5.

1. **One-off project schedule.** A contractor defines named stages using percentages or fixed amounts, reconciling to the job total. Carry the approved quote schedule into the job, or allow setup directly on the job. Example, with no tax or discount: a $10,000 project split into $3,000 mobilization, $4,000 installation, and $3,000 completion.
2. **Contractor-controlled billing.** An explicit action creates the selected stage's draft invoice. Staff review and send it through the existing invoice flow. Stage labels describe work; they do not invent automatic milestone detection. Invoice payment terms determine when an issued bill is due. Calendar-triggered installment generation is not proposed.
3. **Clear job billing position.** Show the scheduled amount, linked invoice, and collected/outstanding amounts so staff can distinguish work still to bill from issued bills still to collect. Issued installments stay locked. Schedule edits cannot silently revise an issued customer document or later installments.
4. **One stage billed once.** Reopening an existing stage leads to its bill. Draft deletion, correction, and replacement must preserve the approved source-claim rules. Ordinary Void remains unavailable for progress invoices; issued corrections use approved D3, preserving history and leaving payment moves explicit.
5. **Deposits remain actual money received.** Carry the existing quote deposit relationship through the job and apply available money once. A schedule row alone never counts as payment. Proposal for review: a funded first stage should produce no second collection request for the same amount; reconcile its invoice and the existing deposit transparently. The precise invoice treatment needs a worked example before planning, rather than a claim of Jobber parity.
6. **Per-visit quantities remain included.** Finish the transferred Jobs 11c requirement for recurring per-visit pricing: a visit's quantities determine that visit's invoice amount. Keep fixed-period charges independent of visit quantities. This is a separate pricing behavior, not a division of the project total into installments.

Online processing and automatic charging remain outside the approved manual-payment campaign.

## Choices settled for the plan

- **Customer schedule display:** the Job holds the complete schedule. A progress invoice shows its current stage, original item values, and amounts due on this invoice; it does not promise future-stage amounts on the invoice document. This is an explicit UCRM choice because Jobber's article contradicts itself.
- **Money examples:** reuse approved UCRM job/invoice arithmetic. Exact tax, discount, rounding, proportional line allocation, and funded-first-stage fixtures must pass before UI work. A changed total below already issued amounts is refused and never silently rebalances history.
- **Existing drafts and schedule changes:** an installment with any linked Invoice, including Draft, is locked on the Job. Correct or replace the Invoice through its existing lifecycle; schedule edits affect only rows with no Invoice.
- **Issued corrections:** D3 is already approved UCRM behavior. Jobber's undocumented monetary correction controls are not grounds to replace that decision.

Next action: implement the approved plan in a fresh session. This document does not authorize infrastructure or online-payment work.
