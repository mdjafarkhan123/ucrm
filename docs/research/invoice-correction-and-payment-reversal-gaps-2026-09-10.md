# Invoice correction, payment reversal, and void-notice gaps

**Date:** 2026-09-10
**Campaign:** paid-launch-trust, Part 10 (investigation only — no correction made)
**Scope:** every command that can change an issued invoice's money or status, whether staff can actually
reach it today, and whether a customer is ever told when it happens.

---

## Part A — The database already has the right shape

This is not a from-scratch design problem. Three earlier sessions (3b-1, 3b-2, 3c) built a complete,
append-only financial ledger in the database:

| Layer | Commands |
| --- | --- |
| Record & apply money | `record_client_payment`, `apply_client_payment`, `unapply_client_payment`, `move_client_payment` |
| Undo money that shouldn't count | `refund_client_payment` (money actually sent back), `reverse_client_payment` (an entry that never should have existed) |
| Close a bill | `void_invoice`, `write_off_invoice` / `restore_invoice_from_write_off`, `mark_invoice_received` / `reopen_invoice` |
| The approved money-correction path | `prepare_invoice_correction`, `activate_invoice_replacement`, `rebill_voided_invoice` |

Every one of these is a single transaction that locks in the design's fixed order, claims an idempotency key,
and writes an appended event rather than overwriting anything. `void_invoice` even resolves quote deposits
on the caller's behalf in the same transaction. This is the proven correction-ledger pattern (append a
correcting entry, never rewrite the original) and it is already built correctly.

**The gap is not the database. It is what the app can reach.**

---

## Part B — Five money-correction commands exist only in the database

Checked every route under `src/routes/api/invoices`, `src/routes/api/payments`, and every `.svelte`/`.ts`
file under `src/routes` and `src/lib` for a call to each command (`grep` for the function name, excluding the
generated `database.types.ts`):

| Command | Called from a route or screen? |
| --- | --- |
| `record_client_payment` | Yes — `POST /api/invoices/[id]/payments` |
| `void_invoice`, `write_off_invoice`, `restore_invoice_from_write_off`, `mark_invoice_received`, `reopen_invoice` | Yes — `POST /api/invoices/[id]/lifecycle` |
| `apply_client_payment` | **No** |
| `unapply_client_payment` | **No** |
| `move_client_payment` | **No** |
| `refund_client_payment` | **No** |
| `reverse_client_payment` | **No** |
| `prepare_invoice_correction` | **No** |
| `activate_invoice_replacement` | **No** |
| `rebill_voided_invoice` | **No** |

Only recording a brand-new payment and the five status-closure transitions are reachable. Everything that
*corrects* money already recorded — taking a payment off a bill, moving it to another bill, giving money
back, cancelling a mistaken entry, or replacing an invoice's money the approved way — has no button, no
screen, and no API route. A staff member cannot do any of these five things through the product today, no
matter what permission they hold.

### This is why void quietly dead-ends on any paid bill

`void_invoice` refuses outright while ordinary (non-deposit) payments are still applied, and its own error
message says exactly what to do first:

> "Take the payment back to client credit, move it to another invoice, or refund it first."

All three of those are `unapply_client_payment`, `move_client_payment`, and `refund_client_payment` — the
three commands with no route. So today, voiding any invoice that has a real payment on it (not just a
deposit) is impossible from the product, even though the database fully supports it. The only invoices that
can actually be voided right now are ones that were issued and never paid.

### This is why the approved money redline isn't enforced either

Part 6/7 recorded the approved departure from Jobber: money corrections to an issued invoice should go
through reversal/replacement (`prepare_invoice_correction` → `activate_invoice_replacement`), not a silent
in-place rewrite. That chain is built and has no route. Meanwhile the four in-place edit commands
(`replace_invoice_lines`, `set_invoice_discount`, `set_invoice_tax`, `update_invoice_details`) *are* wired up
and reachable — confirmed by re-reading `private.lock_invoice_for_edit`
(`supabase/migrations/20260904190000_invoice_draft_and_issue_commands.sql:350`), which still refuses only a
voided or replaced invoice or a stale revision, exactly as Part 6 found it. Nothing added an issued-invoice
refusal for money fields after Part 6/7; Part 7's own follow-up only added the read side (surfacing
`document_history` in `invoice_detail`, `supabase/migrations/20260910160000`), not a write-side gate. So the
one path staff can actually use for a money correction on an issued invoice is the exact one the approved
decision said not to rely on. History is still kept (`retain_prior_invoice_document` appends the prior
document to `invoice_events` on every edit), so nothing is silently lost from an audit standpoint — but
nothing stops staff from quietly rewriting what a customer's live link shows, and the built alternative that
was supposed to be the sanctioned path sits unreachable.

---

## Part C — No customer notice on any lifecycle change

Checked `src/lib/server/communications/*` for any reference to the five lifecycle event types
(`invoice.voided`, `invoice.written_off`, `invoice.marked_received`, `invoice.reopened`) or to
`refund_client_payment` / `reverse_client_payment`: none exist. The only invoice-related sends are
`invoice-email.ts` (the original issue) and `receipt-email.ts` (a payment receipt). There is no template, no
enqueue call, and no UI action anywhere that tells a customer their bill was voided, written off, reopened,
or refunded.

`void_invoice`'s own migration comment says this was deliberate sequencing, not an oversight:

> "The cancellation notice to the client is a Communications send, queued after the state is secured. That
> seam belongs to Part 6 with the rest of invoice delivery; nothing is sent from inside these locks."

That seam was never picked up. Live state confirms nobody has hit it yet — Part 6's doc recorded 0
`invoice.document_edited` events, and the same is true here: no void/write-off/refund has ever been recorded
in this pilot's data, so this is a latent gap, not damage already done.

**This one may not be a blocker.** The Jobber live check (`jobber-05-invoices-payments.md:374-377`) found a
Void confirmation modal that warns staff internally but could not establish that Jobber notifies the client
either — "Deposit release and notification behavior were not established by this modal." So silence on void
may be Jobber parity, not a departure. Worth Jafar's call rather than an assumed fix.

---

## Summary for Part 11

| # | Finding | Severity | Blocked on |
| --- | --- | --- | --- |
| E1 | `unapply_client_payment`, `move_client_payment`, `refund_client_payment` have no route — void cannot be completed on any invoice that has a real (non-deposit) payment applied | High | Nothing — wire the three existing commands to routes + a small correction UI on the invoice/payment screens |
| E2 | `reverse_client_payment` has no route — a payment entered against the wrong client or recorded by mistake cannot be corrected away at all | High | Nothing — same shape as E1 |
| E3 | `prepare_invoice_correction` / `activate_invoice_replacement` (the approved money-correction path) have no route, so the only reachable way to change an issued invoice's money is the in-place edit the redline says to avoid | High | Product call: build the correction-chain UI, or accept in-place editing and drop the redline |
| E4 | No customer notice on void, write-off, mark-received, reopen, or refund | Medium | Jafar's call — may already be Jobber parity |

Nothing here was corrected. Correction and verification are Part 11.

---

## Open question for Jafar before scoping Part 11

E1–E3 all point at the same missing layer: a "Correct a payment" surface (take a payment off a bill, move it
to another bill, refund it, or reverse a mistaken entry) and a "Correct this invoice's money" surface (the
reversal/replacement chain), neither of which exist in the UI yet. Building both is real screen work, not a
small patch — closer in size to Part 3b/3c's original database session than to a one-file fix.

Two ways to scope Part 11:

1. **Minimum to unblock void:** wire up `unapply_client_payment`, `move_client_payment`, and
   `refund_client_payment` behind the smallest possible UI (buttons on the payment/invoice detail screens),
   so void stops dead-ending. Leave the full correction-chain UI (E3) and reversal (E2) for a later part.
2. **Full financial-correction surface:** build all five missing routes plus the screens for them in one part,
   since they share the same permission (`invoices.correct_payment`) and the same invoice/payment detail
   screens.

Recommend option 1 for Part 11 — it directly unblocks the one broken workflow (void on a paid bill) with the
smallest surface, and leaves reversal/correction-chain UI as a follow-up once Jafar has seen the shape of the
first one.
