# Invoices: Current Checkpoint

- Goal: Jobber-grounded invoicing and manual collection.
- Active part: 3b — the manual money ledger, the three balances, and every payment-dependent lifecycle rule.
- Part 3a is **closed 2026-09-05**: all three migration files are applied to the remote database and its
  pgTAP suite passes (72/72, `supabase/tests/database/invoices_document_and_commands.sql`).
- One approved-scope decision needs Jafar's confirmation: Void, Bad debt and Mark received are **built in 3b**
  rather than 3a, because each one's rule depends on the ledger that does not exist until 3b. 3a wired the
  seams they need instead. Nothing else moved.

## Exact next action

Build 3b: `client_payment_events`, `invoice_payment_allocations`, the three balance reads, the money commands
(record receipt, apply/unapply/move, refund, reverse/replace) under `private.begin_invoice_command`, and then
the payment-dependent lifecycle commands (Void with D2's refusal, Bad debt/unmark, Mark received/reopen).
Replace the two seam bodies as part of it. pgTAP goes in `supabase/tests/database/`.

## Blockers and non-obvious risks

- Two seams in `20260904190000` must be replaced, not bypassed: `private.invoice_allocated_minor` (answers 0
  today) and `private.recognize_invoice_if_settled` (D1, already correct once the seam is real). Delete-draft
  and refresh-snapshot already refuse on the first one.
- Currency lock: extend `private.organization_currency_lock_reason` with a money-received branch. It reads
  retained history on purpose, so a refund or deletion never unlocks.
- Deposits reuse `quote_deposit_events`; do not copy that money into a second receipt table, and do not widen
  its payment methods.
- Lock order is settings (`for share`) → invoice (`for update`) → receipt; keep it.
- Remote migration versions differ from repo filenames; that drift is the established practice here.
- The client-edit permission key is `customers.edit`, not `clients.edit`.

## Essential pointers

- `docs/invoice-behavior-contract.md` — approved D1–D5 product truth
- `docs/invoice-part-2-design.md` — approved foundation and implementation handoff
- `Memory/campaigns/invoices/ROADMAP.md` — the 3a/3b/3c split and its completion gates

Resume command: `read memory and continue the Invoices campaign`.
