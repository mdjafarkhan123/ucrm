# Part 6C: Readiness gating and customer-facing deposit display — closed, browser-verified

Approved 2026-08-22 (Jafar: "lets go", after reviewing the DB/API/UI plan). Built end-to-end, covered by
pgTAP, and browser-verified 2026-08-22 on live Quote #36 — see Checklist.

## Approved behavior

- `ready_for_job` is a derived fact, never stored: `quote.status = 'approved'` and (no deposit required, or
  the published version's required deposit has a live, non-reversed `received` event). Approval and deposit
  satisfaction stay separate — a required deposit never blocks the customer's Approve.
- `public.quote_ready_for_job(target_quote_id)`: new `security definer` function, callable by anyone with
  `quotes.view` (not gated on `quotes.view_price` — it is a status fact, not money). Reuses the exact
  live-receipt-exists subquery `record_quote_deposit_event`/`private.quote_customer_document` already use.
  Part 8's real Convert-to-Job route should call this rather than re-deriving the same fact.
- `private.quote_customer_document` gains a `deposit` field: `{ required_minor, satisfied } | null`, gated
  behind `include_money` exactly like `totals` — a viewer without price permission sees neither. `satisfied`
  uses the same live-receipt-exists check. Flows automatically to every reader of the one builder: the real
  customer link, staff "Preview as client", and PDF.
- Staff quote detail page: a "Ready for job" (success) / "Deposit due" (warning) badge appears next to the
  status badge once a quote is `approved`, via a new optional `badges` snippet on the shared
  `WorkRecordHeader` (additive — Request/Job/Invoice headers are unaffected).
- Customer document: when a deposit is required, the right rail shows the amount and, if unsatisfied,
  "Arrange this deposit directly with {business} — this page does not take payment"; if satisfied, a
  "Received" badge. Never a payment control, per the contract's pre-Payments rule.
- Convert-to-Job menu entry itself is untouched — it is already honestly dependency-gated on Jobs (Part 5D),
  and Jobs doesn't exist yet for this part to wire a second reason into.

## Dependencies

Part 6B (deposit ledger, `record_quote_deposit_event`/`reverse_quote_deposit_event`), Part 5B1
(`private.quote_customer_document`, the one customer-document builder), Part 5D (`WorkRecordHeader`,
status-aware header menu).

## Checklist

- [x] Migration `20260823100000_quote_readiness_and_customer_deposit_display.sql`: extends
      `private.quote_customer_document` with the `deposit` field. Applied to remote.
- [x] Migration `20260823100100_quote_ready_for_job.sql`: new `public.quote_ready_for_job(uuid)`. Applied to
      remote.
- [x] `supabase-postgres-best-practices` read before writing both migrations.
- [x] `supabase/tests/database/quote_readiness_and_customer_deposit_display.sql` — plan 17, all 17 passing,
      run as a rolled-back transaction against the linked remote project. Covers: no-deposit quote shows no
      deposit fact; a required deposit shows unpaid, then satisfied after recording, then unpaid again after
      reversal; the fact is withheld from a viewer without price permission and shown to one with it.
- [x] `performance-review` for the database layer: `EXPLAIN ANALYZE` on the new deposit subquery — 1.57ms,
      index-only scans on `quote_deposit_events_version_idx`/`_reversed_idx`, identical proven pattern from
      6B. `quote_ready_for_job`'s common case (non-approved quote) short-circuits after one PK read. No new
      indexes needed.
- [x] `GET /api/quotes/[id]`: added `ready_for_job` to the response, computed via the new RPC inside the
      existing `Promise.all` batch (parallel, no added latency). First attempt computed this in TypeScript
      from the already price-gated `deposit_events`/`version` selects — caught in review as wrong for a
      viewer with `quotes.view` but not `quotes.view_price` (a real per-member-override combination), fixed
      by moving the computation into the database function instead.
- [x] Regenerated `src/lib/database.types.ts` via the Supabase MCP after both migrations.
- [x] `QuoteDetail.ready_for_job: boolean` in `src/lib/quotes/api.ts`.
- [x] `WorkRecordHeader.svelte`: new optional `badges` snippet, rendered beside the main `StatusBadge`.
- [x] `src/routes/(app)/quotes/[id]/+page.svelte`: `readinessBadge` derived (only while `status === 'approved'`),
      passed into the header's `badges` snippet.
- [x] `CustomerQuoteDeposit` type in `src/lib/quotes/customer-document.ts`; `deposit` added to
      `CustomerQuoteDocument`.
- [x] `CustomerQuoteDocument.svelte`: deposit block in the right rail, below the total, above the decision
      buttons. Fixed the rail's outer visibility guard (`doc.totals || showDecisions`) to also include
      `doc.deposit`, so a deposit still shows when staff have hidden the totals breakdown for this quote.
- [x] `performance-review` for the API and Svelte layers.
- [x] `npx prettier --check` the new/changed files (one file needed `--write`, re-checked clean after).
- [x] `npm run check` — 0 errors, same 2 pre-existing unrelated warnings.
- [x] Browser-verified live on Quote #36 (approved, $17,550 total, $3,510 deposit): pre-record showed
      "Deposit due" on the staff header and, on both the real `/q/{token}` customer link and staff "Preview
      as client", "Deposit Required $3,510.00 — Arrange this deposit directly with Raad LTD — this page does
      not take payment", no payment control. Recording the deposit (Cash) flipped the header to "Ready for
      job" and both customer-facing views to a green "Received" badge. The no-`quotes.view_price`-viewer case
      was not clicked through live (no restricted test member exists yet); Jafar accepted the pgTAP coverage
      (plan 17, checked directly against the database function) plus the shared `include_money` gate already
      proven for `totals` as sufficient and closed 6C without it, 2026-08-22.

## Acceptance checks

- An approved quote with no deposit required, or a satisfied one, is `ready_for_job = true` immediately.
- An approved quote with an unsatisfied required deposit is `ready_for_job = false`; reversing a recorded
  deposit flips it back to `false` without any explicit "un-ready" action.
- The deposit fact (amount and satisfied state) never appears for a reader without `quotes.view_price`, in
  either the staff detail payload or the customer document — checked directly against the database function
  in pgTAP, not just through the permission layer that happens to call it today.
- The customer page never renders anything that looks like a payment control.

## Non-discoverable risks

- `ready_for_job` is deliberately not cached or stored anywhere; every read recomputes it from the deposit
  ledger. This is intentional (contract calls it a "derived label"), but a future high-traffic Convert-to-Job
  check should call `quote_ready_for_job` directly rather than re-deriving the logic a third time.
- The customer-facing deposit message hardcodes "this page does not take payment" — when Payments ships and
  online collection becomes real, this copy and the `satisfied`-only-offline assumption both need revisiting
  together, not just the payment control itself.

## Source pointers

- `docs/quote-behavior-contract.md` § Deposits and payment schedules.
- `supabase/migrations/20260823100000_quote_readiness_and_customer_deposit_display.sql`,
  `20260823100100_quote_ready_for_job.sql`.
- `supabase/tests/database/quote_readiness_and_customer_deposit_display.sql`.
- `parts/06b-deposit-configuration-and-recording.md` — the deposit ledger and permission split this part
  reads from.
- `src/lib/components/work/WorkRecordHeader.svelte` — shared header now used by Request/Job/Invoice/Quote.
