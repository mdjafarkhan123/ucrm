# Invoices campaign roadmap

Jafar authorized Jobber as the behavior baseline and approved the campaign direction on 2026-09-05. Reuse shipped
Quote/Job patterns; add only Invoice-specific truth. Part 2's corrected design is approved and Part 3
implementation is under way, split into 3a/3b/3c on Jafar's 2026-09-04 approval.

| Part | Outcome                                                                   | State                                          | Dependency                                     | Completion gate                                                                                 |
| ---- | ------------------------------------------------------------------------- | ---------------------------------------------- | ---------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| 1    | Verify Jobber and approve the Invoice behavior contract                   | Complete — redline and concrete D1–D5 approved | Live Jobber, official docs, existing contracts | Status, source, snapshot, money, delivery and scope boundaries are explicit                     |
| 2    | Design Invoice foundation and billing-address seam                        | Complete — corrected design redline approved | Part 1; corrected design approval           | Smallest tenant-safe model, commands, permissions and test matrix approved                      |
| 3a   | Build Invoice identity, terms, numbering, snapshots, arithmetic, draft and issued-document commands, plus private command receipts and retry protection | Complete 2026-09-05 — three migrations applied to the remote database, 72/72 pgTAP | Part 2                    | Met: isolation, numbering, calculation, snapshot freezing, issued edits retaining prior snapshots and replay safety are verified. Void/Bad debt/Mark received moved to 3b with the ledger their rules depend on; their seams are wired here |
| 3b-1 | Build the money ledger, the three balances, and the commands that record, apply, unapply and move money | Complete 2026-09-05 — two migrations applied to the remote database, 80/80 pgTAP, balance plans measured | Part 3a | Met: receipts, allocation, unapplication, movement, the three balances, D1 draft rules, deposit reuse, append-only privilege, isolation and replay verified |
| 3b-2 | Build refunds, receipt reversal, and the payment-dependent lifecycle commands (Void, Bad debt, Mark received) | Complete 2026-09-05 — one migration applied to the remote database, 89/89 pgTAP, plans measured | Part 3b-1 | Met: refund caps against the original receipt, reversal of a receipt or an erroneous refund, D2's Void refusal with its deposit release, bad debt/unmark, mark received/reopen, permissions, isolation and replay verified |
| 3c   | Build source claims and correction/rebill replacement chains              | Next                                           | Parts 3a–3b; Jobs 11c for installment references only | One work unit billed once, claims retained after Void, rebill succeeds once, chain has no branching, the contract's progress-invoice exclusion from ordinary Void is enforced, and Part 2's measured performance evidence is produced |
| 4    | Deliver direct Invoice list, new form and detail                          | Planned                                        | Parts 3a–3c                                    | Shared Quote patterns plus Invoice-only fields/actions work without duplicate UI                |
| 5    | Deliver Job, Visit, reminder and installment handoff                      | Planned                                        | Parts 3a–3c, 4; Jobs 11c                       | Eligible work copies once, reminders resolve, deposits allocate, retries do not duplicate       |
| 6    | Deliver email, mark-sent, secure view, PDF and receipt flow               | Planned                                        | Part 4; Communications email                   | Issue/delivery/view facts and frozen customer document are verified                             |
| 7    | Deliver manual collection, overdue, bad debt, void and reopening          | Planned                                        | Parts 3a–3c, 4–6                               | Partial/full payments, balances, reversals and every Jobber state transition reconcile          |
| 8    | Deliver batch create and batch deliver                                    | Planned                                        | Parts 5–7                                      | Reviewed drafts group compatible Client work; completion atomic with creation; sending separate |
| 9    | Verify integrated billing journeys and measured performance               | Planned                                        | Parts 2–8                                      | Direct, Job, recurring, progress, delivery, payment, exception and batch journeys pass          |

Approved behavior: `docs/invoice-behavior-contract.md`, including D1–D5. Part 2 corrected design:
`docs/invoice-part-2-design.md`. Part 2 is complete, including all seven corrections. Jafar approved the
3a/3b/3c split on 2026-09-04 with these boundaries: private command receipts and retry protection are built in
3a and applied to money commands in 3b; permitted issued-document edits with retained prior snapshots belong to
3a; payment-dependent lifecycle rules are verified in 3b, never declared complete in 3a; source claims and
replacement chains stay in 3c with Jobs 11c dependencies explicit. The split changes build order only, not
approved behavior. Batch groups compatible tax rates, and incomplete Visit completion follows the approved
atomic, previewed permission boundary.

Deferred outside this campaign: SMS until Communications activation; online processors, saved methods, automatic
charging, settlements, disputes and payouts until their provider topology receives separate approval.

Build order (confirmed by Jafar 2026-09-05): Void, Bad debt and Mark received are built with the ledger their
rules read, not in 3a. Jafar also approved splitting 3b into 3b-1 (ledger, balances, money movement) and 3b-2
(refunds, reversal, payment-dependent lifecycle), and approved storing the effective-receivable predicate once
as a calculated column on `invoices` rather than restating it in each caller. Approved behavior is unchanged.

Three facts the ledger parts established that later parts must not contradict:

- Unapplying the money that settled a never-issued draft is refused, because 3a made recognition
  irreversible. 3b-2's refund path must reach that money through a refund of the receipt, not an unapply.
- Money can still be unapplied or moved off a *replaced* invoice, per D3; only a voided one is closed to
  both directions.
- 3b-2 refuses Void on a draft, a replaced bill, a written-off or by-hand-closed bill, and a fully paid one,
  and it cannot yet exclude progress invoices because no installment link exists until Jobs 11c. 3c owns that
  exclusion. Mark received deliberately leaves `is_effective_receivable` true and is gated on
  `invoices.record_payment`.
