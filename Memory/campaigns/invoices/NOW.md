# Invoices: Current Checkpoint

- Goal: Jobber-grounded invoicing and manual collection.
- Active part: 3c — source claims and the correction/rebill replacement chains.
- Part 3b-2 is **closed 2026-09-05**: `20260905120000` is applied to the remote database (remote version
  `20260905051805`) and `supabase/tests/database/invoices_refunds_and_closure.sql` passes 89/89.

## Exact next action

Build 3c on the 3a/3b ledger: claim each source work unit once, retain the claim after Void, let an explicit
rebill or correction create exactly one successor in the same chain without branching, and enforce the
contract's progress-invoice exclusion from ordinary Void. Installment foreign keys wait for Jobs 11c.
Produce Part 2's measured performance evidence. pgTAP goes in `supabase/tests/database/`.

## Blockers and non-obvious risks

- `invoices` already carries `predecessor_invoice_id`, `root_invoice_id`, `replacement_kind`, `replaced_at`,
  `replaced_by_invoice_id` and `frozen_status_label`, and the identity trigger already refuses rewriting a
  replaced bill's history. 3c writes the commands, it does not reshape the table.
- A voided bill accepts exactly one further change: being marked as replaced by an explicit rebill. Every
  other column is frozen by `private.invoices_guard_identity`.
- 3b-2 refuses Void on a progress invoice only by omission — there is no installment link to test yet. 3c
  must add that refusal when the link exists, not leave it implied.
- Measured 2026-09-05 on the dev project with 20,000 seeded payment events in one organization (1,000 for
  the client read): the per-receipt availability check is a nested-loop anti-join on
  `client_payment_events_original_idx`, 11 buffers, 0.13 ms. `client_account_balance` is 7.4 ms, and its
  anti-join side scans that index for the whole organization rather than one client, so it grows with the
  organization's lifetime refund and reversal count. Left as measured rather than indexed around: refunds
  are rare in this product. Revisit if an organization's correction history reaches tens of thousands.

## Essential pointers

- `docs/invoice-behavior-contract.md` — approved D1–D5 product truth, D3 and D4 for this part
- `docs/invoice-part-2-design.md` — approved foundation and implementation handoff
- `Memory/campaigns/invoices/ROADMAP.md` — the 3a/3b-1/3b-2/3c split and its completion gates

Resume command: `read memory and continue the Invoices campaign`.
