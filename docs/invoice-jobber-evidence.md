# Invoice Jobber evidence — 2026-09-04

Research-only reconciliation of the Invoice contract and Invoice-related Client behavior. Official Help was
read current to this session; live evidence is the completed 2026-09-04 tour. **High** means explicit official
behavior or a directly observed control, not an executed financial transition. **Limited** identifies a
specific gap. **UCRM** means a product/engineering rule, not a discovered Jobber fact. No internal storage
is inferred from screens, GraphQL names, or returned connections. The research redline is now approved and applied to the contract; additional transitions remain undecided.

## Evidence matrix

| Behavior                                                                                                                                                             | Jobber source                                                                 | Confidence                                      | Implementation consequence (no design approval)                                                                  |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- | ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| One effective Client billing address: matching Property or custom Client billing address                                                                             | [Client app][CA], [Import Clients][IC], completed property-dialog observation | High                                            | Correct the per-Property billing-storage claim; preserve Client billing independently of service location.       |
| Job-derived invoices show service properties; direct invoices need not                                                                                               | [Properties][P], [Invoice Basics][I]                                          | High                                            | Keep billing and work locations distinct.                                                                        |
| Invoice displayed statuses: Draft, Awaiting Payment, Past Due, Paid, Bad Debt, Voided                                                                                | [List metrics][L]                                                             | High                                            | Six display labels; future-due issued invoices are Awaiting Payment. Basics' count of five is stale.             |
| Overview uses Sent but not due; filters split Awaiting payment into past due / not yet due / all                                                                     | [Completed live notes][LIVE]                                                  | High for observed account                       | Tiles and groups are not additional detail statuses. Historical API `sent_not_due` is not a display requirement. |
| Terms: receipt, Net 7/15/30/45/60, month-end/next-month-end; Custom date observed                                                                                    | [Terms][T], [LIVE]                                                            | High                                            | Use verified choices; no arbitrary term invention.                                                               |
| Invoice override → Client term → residential/commercial default                                                                                                      | [Terms][T]                                                                    | High                                            | Replace the undifferentiated organization fallback.                                                              |
| Commercial uses company-name identity; unspecified type uses residential                                                                                             | [Terms][T]                                                                    | High documented rule                            | No invented residential/commercial field or selector. Labels remain internal.                                    |
| Terms can be named/managed; fixed receipt/month-end terms protected; deleting a default term falls back to receipt; invoice change can optionally update Client term | [Terms][T]                                                                    | High                                            | Name capability explicitly in redline; do not silently broaden implementation.                                   |
| Draft collection, full/partial allocation, Close Invoice and payment-versus-status distinction                                                                       | [Collect Payment][C], [financial evidence][F], [LIVE]                         | High core; partial-draft effects limited        | Drafts can accept payments; Paid does not prove Client settlement. See limits below.                             |
| Only six initial manual methods: Other, Bank transfer, Cash, Check, Credit/debit card, PayPal                                                                        | [LIVE]                                                                        | High account observation + explicit Jafar scope | External recording only; no all-15-method/provider infrastructure.                                               |
| Bad Debt removes unpaid remainder from Client debt, is reversible, hides Invoice in Client Hub                                                                       | [Bad Debt][B], [F]                                                            | High                                            | Separate write-off from payment; no cancellation-message assumption.                                             |
| Void is irreversible/immutable, unpaid-only; progress/financing excluded                                                                                             | [Invoice Basics][I], [F]                                                      | High core; partial-payment eligibility limited  | Eligibility must be explicit; provider exclusions do not authorize building providers.                           |
| Void releases deposits and notifies by email/SMS; live adds Other to documented reasons                                                                              | [I], [LIVE], [F]                                                              | High core; delivery edge cases limited          | Four internal reasons; UCRM email-first boundary must be explicit.                                               |
| Issued Delete and deletion with attached payment exist; payment returns to Client account                                                                            | [Client Billing History][H], [F], [LIVE]                                      | High supported cases                            | Issued retention through Void is an approved UCRM departure, not parity.                                         |
| Manual payment/deposit edits and permanent payment deletion exist                                                                                                    | [H], [F]                                                                      | High                                            | Reversal/replacement preservation is explicitly approved; transition details remain open.                        |
| External refund happens outside Jobber; documented full-refund record is edited to zero with a note                                                                  | [Refunds][R], [F]                                                             | High                                            | No invented Jobber manual reversal command; partial refund remains limited.                                      |
| Client balance may be debt or credit, excludes tips; issued-not-due invoices matter                                                                                  | [H], [F]                                                                      | High                                            | Invoice status, Invoice balance and Client account balance are different facts.                                  |
| Direct, Client, Job, reminder, installment and batch creation                                                                                                        | [I], [Progress][G], [Batch create][BC]                                        | High                                            | No evidence of direct Quote→Invoice conversion; preserve existing UCRM Job boundary.                             |
| Save creates Draft; Save-and actions can send or collect; updating and re-sending separate                                                                           | [I], [LIVE]                                                                   | High                                            | Add draft collection to acceptance behavior. Database transaction boundaries are UCRM decisions.                 |
| Batch normally groups by Client, but splits different property tax rates                                                                                             | [BC]                                                                          | High                                            | Correct “one invoice per Client” absolute claim.                                                                 |
| Batch requires due reminders; incomplete visits excluded by default, selecting them marks complete                                                                   | [BC]                                                                          | High                                            | Explicitly disclose Visit consequence before implementing parity; reconcile Job contract later.                  |
| Batch delivery is separate; email primary + billing contacts, optional PDF; standard-mail PDF/labels also exist                                                      | [Batch deliver][BD]                                                           | High                                            | Email-first campaign is a scoped subset; do not claim complete delivery parity.                                  |
| Progress amounts follow Job schedule; issued installments locked in schedule                                                                                         | [G]                                                                           | High                                            | No independent line-amount editing. Exact correction path for issued progress amounts is ambiguous in docs.      |
| Job invoice reminders prompt creation; invoice follow-ups chase overdue bills                                                                                        | [Reminders][IR], [Messages][M]                                                | High                                            | Different workflows. Follow-up settings moved to Automations; old fixed limits not reverified.                   |
| Invoice form/detail fields, service dates, client-view toggles and edit controls                                                                                     | [LIVE], preserved screenshots                                                 | High for observed screens                       | Reuse behavior; blueprint placement and UCRM appearance remain our choices.                                      |
| Stable snapshots; non-reused numbering; single billing claim; atomic calculation; revision/idempotency/tenant enforcement                                            | Contract; historical API is not proof                                         | UCRM                                            | Preserve as stated safeguards, not Jobber internal facts. No schema is designed here.                            |
| Communications ownership, secure recipient links, cache rules, permissions layout, shared money arithmetic                                                           | Contract/UCRM architecture                                                    | UCRM                                            | These are our boundaries, not verified Jobber storage or security mechanisms.                                    |
| Retain issued Invoice through Void; retain financial corrections through reversal/replacement                                                                        | [Proposed redline](invoice-contract-proposed-redline.md)                      | Proposal                                        | Explicitly approved by Jafar; no transition details implied.                                                     |

## Remaining behavior gaps

The documented core questions are reconciled. Research is **not exhaustive transition verification**:

1. Partial payment on an unsent Draft: exact displayed status, issue-date effect, and account-balance treatment.
2. Void after a partial payment: “unpaid” does not specify that case; deposits are expressly different.
3. Full Delete eligibility across Paid, partial, Bad Debt and Voided states. Issued deletion itself is verified.
4. Partial external refund: manual editing and subsequent status/balance consequences.
5. Void notification behavior with missing contact channels or delivery failure.
6. Issued progress-invoice amount correction: docs prohibit independent line amounts yet say issued changes
   must be made on the Invoice, without explaining the permitted monetary correction controls.

These require targeted test evidence or Jobber clarification before claiming exact parity. No implementation
may silently choose an answer. Processor behavior, fee schedules, all public API types, and unrelated Client
features are outside this research scope and are not claimed newly verified.

## Source and artifact authority

The [financial evidence][F] owns detailed financial findings and source dates. The Jobber skill's Invoice and
Client references link here. Archived API signatures remain historical reference only. The contract now includes the explicitly approved redline. Four original temporary screenshots are preserved with
provenance in [Design/Jobber Invoices/2026-09-04](../Design/Jobber%20Invoices/2026-09-04/README.md).

[CA]: https://help.getjobber.com/en/articles/client-information-in-the-jobber-app/
[IC]: https://help.getjobber.com/en/articles/import-clients/
[P]: https://help.getjobber.com/en/articles/properties/
[I]: https://help.getjobber.com/en/articles/invoice-basics/
[L]: https://help.getjobber.com/en/articles/invoices-list-page-and-key-metrics/
[T]: https://help.getjobber.com/en/articles/set-invoice-payment-terms/
[C]: https://help.getjobber.com/en/articles/how-to-collect-payment-on-an-invoice/
[B]: https://help.getjobber.com/en/articles/bad-debt/
[H]: https://help.getjobber.com/en/articles/client-billing-history/
[R]: https://help.getjobber.com/en/articles/jobber-payments-refunds/
[G]: https://help.getjobber.com/en/articles/progress-invoicing/
[BC]: https://help.getjobber.com/en/articles/batch-create-invoices/
[BD]: https://help.getjobber.com/en/articles/batch-deliver-invoices/
[IR]: https://help.getjobber.com/en/articles/invoice-reminders/
[M]: https://help.getjobber.com/en/articles/emails-and-text-messages-settings/
[LIVE]: ../.claude/skills/jobber/jobber-05-invoices-payments.md
[F]: invoice-payment-research.md

Current decisions and Job consequences: [transition decisions](invoice-transition-decisions.md).

## UCRM decisions now approved

Jafar supplied concrete D1–D5 and authorized Part 2 design for review. The remaining evidence gaps above
are gaps in Jobber documentation, not unresolved UCRM decisions for those cases. The
[Invoice contract](invoice-behavior-contract.md) owns approved behavior; the
[Part 2 proposal](invoice-part-2-design.md) is unimplemented and awaits review.
