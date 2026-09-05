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
| 3c   | Build source claims and correction/rebill replacement chains              | Complete 2026-09-05 — one migration applied to the remote database, 60/60 pgTAP, index plans measured; not yet committed to Git | Parts 3a–3b; Jobs 11c for installment references only | Met: one work unit billed once, claims retained after Void, rebill succeeds once (no chain branching), progress-invoice exclusion from ordinary Void enforced; uniqueness probe, chain-claims and successor lookups each verified index-only/index scan at ~150k rows |
| 4a   | Deliver the Invoice list (read model + list screen)                        | Complete + committed 2026-09-05 (d947a3a) — migration applied, plans measured at 40k, 3c pgTAP re-verified 60/60 | Parts 3a–3c | Met: keyset list, live status overview, search/filter/sort, no money leak; list & overview derive status one way |
| 4b   | Deliver the new-invoice form and the detail page                           | Complete + committed 2026-09-05 (a7bdb1d) — type-clean, all flows browser-verified; delete-hang bug fixed | Part 4a | Met: new form + detail screen, draft-only edits (lines/discount/tax/subject/terms), Mark as Sent, Delete draft; read model gates money; no duplicate UI |
| 5    | Deliver Job, Visit, reminder and installment handoff                      | Planned                                        | Parts 3a–3c, 4; Jobs 11c                       | Eligible work copies once, reminders resolve, deposits allocate, retries do not duplicate       |
| 6    | Deliver email, mark-sent, secure view, PDF and receipt flow               | In progress — 6a done; 6b split into 6b-1 (send/link/view) + 6b-2 (receipts); 6b-1 active | Part 4; Communications email                   | Issue/delivery/view facts and frozen customer document are verified                             |
| 6b-1a| Send/link/view plumbing: enqueue_invoice_communication_email, issue_invoice_access_link, record_invoice_link_view; email + access-links + public view routes; client api; public view-ping; InvoiceEmailDialog; invoice_detail widened with `delivery` + client email | Complete 2026-09-06 — migration applied to remote DB, `npm run check` 0 errors, Prettier clean, svelte autofixer clean; NOT yet committed to Git | 6a | Met: migration applied, all functions/routes/api/component type-clean. UI not yet wired (6b-1b) |
| 6b-1b| Wire the invoice detail page: Send (issue-on-send for a draft, then queue) as the draft primary action; Copy client link + Resend on issued bills; show Sent / Viewed facts. Then browser-verify. | **Complete 2026-09-06**, committed. Page wiring browser-verified earlier (menu items, Copy link, Viewed fact, Resend dialog). The enqueue bug fix (`owner_user_id` → org-default sender) is now applied to remote DB; confirmed live by actually sending invoice #1 (Raad LTD) — clean `201 queued`, delivery intent created with the correct org-default sender, no crash. Residual: the "no sender ready" 422 refusal path (`email-send-errors.ts`) is still only type-checked, not exercised live — every org with an issued invoice in this DB now has a working sender, so there's nothing to test it against without fabricating data. | 6b-1a | Met. Residual noted above is not blocking — same shape as the already-shipped quote 55000 mapping. |
| 6c   | Invoice contract/disclaimer: enter, save, edit, display on the customer invoice, mirroring the shipped quote disclaimer. Separate from payment terms; content frozen when the invoice is issued. | Complete 2026-09-06 — migration applied to remote DB, `npm run check` 0 errors, Prettier clean. NOT yet browser-verified or committed to Git | Part 4b (detail page), 6a (customer document); Quote disclaimer pattern | Met: draft SectionBlock enter/edit (bottom-bar save, same revision chain as terms); `update_invoice_contract_disclaimer` refuses once `document_frozen_at` is set; customer document + staff preview show it as its own footer, separate from the payment-terms line |
| 6b-2 | Receipt document + receipt email from accepted payment facts | Planned | 6b-1; Part 7 payments | Receipt generated from accepted payment facts and emailed |
| 6a   | Customer invoice document + secure token view + Preview-as-client + Print/Save PDF | Complete + committed 2026-09-05 (3959681) — browser-verified (light + dark, no console errors, money math correct, print CSS clean) | Part 4; Quote customer-document/token/preview pattern | Met: frozen customer document renders premium; staff preview renders via `invoice_customer_preview`; print CSS strips chrome. Public `/i/[token]` resolver built; live token test defers to 6b (issuer). Money-withheld path code-verified (owner has view_price) |
| 7a   | Collect Payment (single invoice) + financial history read model/display; backend commands already built/tested in 3b-1/3b-2 | Complete + committed 2026-09-06 (d5a0250) — browser-verified end to end on invoice #1 (partial then full payment, balance + status + toast + method labels + history list all correct); date-display off-by-one fix folded in (see below); 6c delivery/email regression fix verified live | Parts 3a–3c, 4–6 | Met |
| 7b   | Void (with reason + D2 refusal), Bad debt/restore, Mark received/reopen   | Complete 2026-09-06 — browser-verified end to end on Raad LTD (all five transitions, both undos, D2 refusal in dialog, dark mode); NOT yet committed. One `/api/invoices/[id]/lifecycle` route (discriminated `action`), one `InvoiceLifecycleDialog` on `ConfirmDialog`, status closure banner on the detail screen; `can_void`+`can_bad_debt` on the GET route; migration `20260906150000` adds `write_off_note` to `invoice_detail`. `npm run check`/eslint/prettier/autofixer clean. | 7a | Met: every Jobber close/reopen transition reconciles through the pgTAP-tested 3b-2 commands; void reason enum `duplicate`/`created_in_error`/`client_request`/`other`; D2 refusal ("still has payments on it") surfaced in the dialog. Deferred follow-up: the void→client cancellation email (needs a new template). |
| 7    | Deliver manual collection, overdue, bad debt, void and reopening          | 7a complete + committed (d5a0250); 7b complete + browser-verified, commit pending. Spreading one payment across a client's several open invoices (Jobber's real behavior) is explicitly deferred — build as a follow-up once single-invoice collection is used. Void→client cancellation email also deferred. | Parts 3a–3c, 4–6 | Partial/full payments, balances, reversals and every Jobber state transition reconcile          |
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

Part 6 decisions (approved 2026-09-05): PDF = browser print/save (matches Jobber's "Print or Save PDF"
affordance and the shipped Quote pattern); no server PDF engine. Build a REUSABLE customer-document visual
foundation (paper shell, brand header, party/address blocks, line-table styling, totals block, print CSS) so
Quote can later adopt it — quote/invoice stay as two purpose-built components, never one mode-flagged
component. Customer sees their own invoice amounts (no view_price gating on the customer's own bill).

Deferred outside this campaign: SMS until Communications activation; online processors, saved methods, automatic
charging, settlements, disputes and payouts until their provider topology receives separate approval.
Retrofit `CustomerQuoteDocument` onto 6a's shared document foundation — small follow-up AFTER Jafar approves
the invoice look; kept out of this campaign because it touches shipped, tested quote code.

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
