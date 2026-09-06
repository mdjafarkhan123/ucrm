# Invoices: Current Checkpoint

- Goal: Jobber-grounded invoicing and manual collection.
- **6b-2a CLOSED + committed** (`e1cf299`). Customer payment receipt: `private.payment_receipt_document`,
  `/r/[token]` hosted page, `enqueue_payment_receipt_email` (link, not PDF), "Save and email receipt" on
  CollectPaymentDialog. Browser-verified. Behavior/content follow Jobber; full findings in
  `.claude/skills/jobber/jobber-05-invoices-payments.md` § "Payment receipts".
- **Part 7 CLOSED + committed** (7a d5a0250, 7b d324946).

## Next action — build 6b-2b (payment detail page)

Roadmap 6b-2b: read-only `/(app)/payments/[id]` page — amount, method, transaction date, reference, details,
"Applied to: Invoice #N" (link) — with **Send receipt** and **Print / Save PDF** (reuse
`CustomerPaymentReceiptDocument` with its `notice` snippet for the staff render). Then wire the invoice
detail financial-history rows to link to it. Follow the Working Procedure: state understanding, inspect
relevant files, present the plan, wait for approval. Load `svelte` before writing the page, `design` before
the UI, `supabase-postgres-best-practices` only if a read-model migration is needed (a payment detail read
model may already exist from Part 7 — check first).

## Known issues (not blockers for 6b-2b)

- **Email send blocked for Raad LTD**: `private.resolve_communication_email_allowance` returns
  `essential_limit_state: not_included` for org `18f0d717-904e-48d8-bd99-9df7e3844cda`. Every operational
  email (invoice + receipt) queues fine but the worker defers it with a 15-min backoff. This is a package
  entitlement gap owned by **communications-activation** (Paused), not invoices. The receipt path itself is
  correct.
- **Leftover test payment**: a $1,000 "other" payment (ref "6b-2a receipt browser test") is on invoice #5
  "D2 refusal test" (Raad LTD), dropping its balance to $39,000. `client_payment_events` /
  `invoice_payment_allocations` are **append-only** (DB trigger `payment_history_is_append_only`) — it cannot
  be plain-deleted. Left in place; remove it only with Jafar's OK (temporarily disabling the trigger) or via
  a proper reversal.

## Notes

- `database.types.ts`: regenerate with the Supabase MCP tool, then `npx prettier --write` it — that collapses
  the whole-file reformat to just the real schema delta (6b-2a was +143 lines, receipt-only). No
  `supabase login` needed.
- Repo-wide CRLF drift on ~300 `src/` files + migration files nobody touched — unrelated, never stage it.
  `.env` is also CRLF: strip `\r` when reading secrets in a shell.
- Skill-dir edits (`.claude/`, `.agents/`, `.codex/`, `.opencode/`) are never staged with feature commits —
  prior invoice parts all left the jobber-05 research promotion uncommitted in the working tree.
- Deferred: payment edit/delete, void→client cancellation email (needs template), bulk payment, Invoices
  list stat cards still unwired.
- Email worker manual drain: `POST http://localhost:5173/api/internal/communications/email-worker` with
  `authorization: Bearer $COMMUNICATIONS_WORKER_SECRET`.

Resume command: `read memory and continue the Invoices campaign`.
