# Invoice payment research — 2026-09-04

Research only. Current official Help pages were checked against the completed live notes in
`.claude/skills/jobber/jobber-05-invoices-payments.md`. No live interaction, financial transition,
application change, or schema proposal occurred in this pass. Public behavior does not establish
Jobber's internal storage. This note does not approve UCRM departures or amend the Invoice contract.

## Verified evidence

| Behavior                                                                                                                                                                                                 | Official source and confidence                                                                                                        | Consequence for later contract decisions                                                                     |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Drafts accept payments; covering the full balance produces Paid. Multiple partial payments reduce the amount owing; partial payment alone does not mean Paid.                                            | [Collect Payment](https://help.getjobber.com/en/articles/how-to-collect-payment-on-an-invoice/), updated August 6, 2026; high         | Do not prohibit draft payments as claimed Jobber parity. Exact partial-draft transition remains below.       |
| Close Invoice offers payment collection, Bad Debt, and closure without payment. The last sets Paid without settling the amount owing.                                                                    | [Collect Payment](https://help.getjobber.com/en/articles/how-to-collect-payment-on-an-invoice/); high, corroborated live              | Status alone cannot establish financial settlement.                                                          |
| Manual payment records acknowledge money received elsewhere; the manual card option does not charge a card. Account collection requires an invoice; an account deposit is the alternative.               | [Collect Payment](https://help.getjobber.com/en/articles/how-to-collect-payment-on-an-invoice/); high                                 | Keep recording distinct from processing.                                                                     |
| Bad Debt writes off only the unpaid remainder, removes that amount from Client balance and chase lists, and retains the Invoice. Unmark as bad debt reopens it.                                          | [Bad Debt](https://help.getjobber.com/en/articles/bad-debt/), updated March 31, 2026; high                                            | Write-off is distinct from receipt of money and can be undone.                                               |
| Bad Debt is hidden in Client Hub, including partially paid invoices. Jobber offers no email/text invoice action in this state; its downloadable PDF shows zero owed without exposing the Bad Debt label. | [Bad Debt](https://help.getjobber.com/en/articles/bad-debt/); high                                                                    | Do not treat Bad Debt like a customer cancellation notification.                                             |
| Void retains an immutable Invoice: no editing, sending, or payment. It applies to unpaid invoices, excluding progress schedules and consumer financing; franchise availability may vary.                 | [Invoice Basics](https://help.getjobber.com/en/articles/invoice-basics/), updated July 27, 2026; high                                 | Void is permanent cancellation, not write-off or payment.                                                    |
| Void releases attached deposits back to the Client account and sends email and SMS cancellation notifications.                                                                                           | [Invoice Basics](https://help.getjobber.com/en/articles/invoice-basics/); high documentation confidence; transition not executed live | Deposit reuse and customer communication are part of documented Jobber behavior.                             |
| Documentation lists Duplicate, Created in error, Client request. Completed live observation additionally verified Other, an internal reason, and an irreversible-action warning.                         | [Invoice Basics](https://help.getjobber.com/en/articles/invoice-basics/) plus dated live notes; high for account observed             | Preserve all four verified choices; do not silently discard live evidence because documentation lists three. |
| Delete is listed for non-draft invoices.                                                                                                                                                                 | [Invoice Basics](https://help.getjobber.com/en/articles/invoice-basics/); high, also visible on issued Invoice live                   | Draft-only deletion is a UCRM departure.                                                                     |
| Invoice deletion is permanent and unrecoverable.                                                                                                                                                         | [Invoices in the Jobber App](https://help.getjobber.com/en/articles/invoices-in-the-jobber-app/); high                                | Retention through Void is now explicitly approved UCRM policy.                                               |

## Client balance and payment corrections

[Client Billing History](https://help.getjobber.com/en/articles/client-billing-history/), updated August
11, 2026, documents the following (high confidence):

- Positive balance means debt; negative means credit/overpayment. Tips are excluded. Statements include
  issued invoices even before their due dates.
- Editable manual-payment/deposit fields include date, method, reference/details and Applied to.
  However, invoice-applied payments cannot simply move to another invoice. Deleting the invoice releases
  its payment to Client credit for subsequent application. Unallocated deposits can cover outstanding
  invoices for that Client.
- Payments, deposits and initial balances can be deleted; deleted payments cannot be recovered.
- Processed Jobber Payments transactions cannot be edited; reassignment requires support.

[Jobber Payments Refunds](https://help.getjobber.com/en/articles/jobber-payments-refunds/), updated June
9, 2026, explicitly distinguishes external/manual refunds (high confidence): return money outside
Jobber, then change the original payment to zero and annotate it. This verifies amount editing despite
the Billing History field list omitting amount. Documentation does not establish a general manual
reversal/replacement command.

The same refund article uses _reversal_ for a card issuer's treatment of an early processor refund:
the charge disappears from the bank statement. This is unrelated to UCRM's proposed retained correction
history. Processor refunds may require reopening the Invoice to restore an amount owed; refund receipts
are sent manually. These facts clarify vocabulary only and do not add processor infrastructure to scope.

## Account observations and approved departures

Initial manual methods remain the six verified live: Other, Bank transfer, Cash, Check, Credit/debit
card, PayPal. Broader Help examples or public API enums do not expand this implementation scope.

UCRM's approved issued-Invoice retention through Void prevents losing the original request for payment.
Approved reversal/replacement corrections preserve the original entry and explain its correction.
Both are product choices departing from Jobber's documented Delete/edit workflows, not evidence about
Jobber's underlying database. Jafar explicitly approved both in the subsequent redline approval. That approval does not
settle unresolved transitions or authorize design. No processor, failed-ACH, dispute, payout, saved-card or automatic-payment work follows.

## Genuine limits of current evidence

- “Unpaid” in the Void documentation does not explicitly decide eligibility after a **partial payment**.
  An attached deposit is expressly supported; do not equate deposit attachment with partial payment.
- Draft collection and full settlement are explicit; the exact displayed status/issue-date effect of a
  **partial payment on an unsent draft** is not explicit in these pages or completed observations.
- Delete availability on issued invoices and release of payments are documented; a complete eligibility
  matrix for every paid, partial, Bad Debt and Voided case is not. Do not claim universal eligibility.
- General Client balance semantics are documented; the exact treatment of a partially paid unsent draft
  versus the composer’s “including this draft” preview is not established here.
- Manual **partial external refund** editing semantics and status consequences are not expressly
  documented by the instruction to zero an externally refunded payment.
- Void notification intent is documented; missing contact channels and failed delivery behavior are not.

These limits must remain visible instead of being filled with API/storage inference. Part 2 remains stopped.

Targeted follow-through and decisions: [transition decisions](invoice-transition-decisions.md).
