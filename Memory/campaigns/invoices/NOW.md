# Invoices: Current Checkpoint

- Goal: Jobber-grounded invoicing and manual collection.
- Active part: 3b-2 — refunds, receipt reversal, and the payment-dependent lifecycle commands.
- Part 3b-1 is **closed 2026-09-05**: `20260905100000` and `20260905110000` are applied to the remote
  database and `supabase/tests/database/invoices_payments_ledger.sql` passes 80/80.

## Exact next action

Build 3b-2 on top of the 3b-1 ledger: record an actual external refund against exactly one original receipt
(manual or reused quote deposit), reverse/replace an erroneous receipt, then Void with D2's refusal and its
deposit release, Bad debt/unmark, and Mark received/reopen. All under `private.begin_invoice_command`.
pgTAP goes in `supabase/tests/database/`.

## Blockers and non-obvious risks

- `client_payment_events` already carries the `refunded` and `reversed` shapes and their foreign keys; 3b-2
  writes the commands, it does not reshape the table.
- Refund caps read `private.payment_event_available_minor` / `private.deposit_event_available_minor`, which
  already subtract refunds and net allocations. Lock the receipt row; lock order is settings → invoice → receipt.
- Void must refuse while ordinary allocations remain (D2) and release deposits in the same transaction.
  `private.lock_invoice_for_payment` already refuses a voided invoice in both directions.
- Bad debt sets `written_off_at`, which flips `invoices.is_effective_receivable` to false automatically. Do
  not also subtract write-offs by hand anywhere.
- Recognition is irreversible (3a), so a settled draft's money is reachable only through a refund.
- Repo/remote drift: the two 3b-1 migration files carry explanatory comments inside seven function bodies
  that the applied versions do not. Logic is identical, verified by hashing the comment-stripped bodies.

## Essential pointers

- `docs/invoice-behavior-contract.md` — approved D1–D5 product truth
- `docs/invoice-part-2-design.md` — approved foundation and implementation handoff
- `Memory/campaigns/invoices/ROADMAP.md` — the 3a/3b-1/3b-2/3c split and its completion gates

Resume command: `read memory and continue the Invoices campaign`.
