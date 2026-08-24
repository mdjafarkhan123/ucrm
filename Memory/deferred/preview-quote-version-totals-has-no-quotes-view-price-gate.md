# `preview_quote_version_totals` has no `quotes.view_price` gate

- **Priority:** P0


- **Campaign:** found during `quotes` Part 6A, 2026-08-21. Out of 6A's own scope — the preview endpoint is
  Part 4B work, already in production, and touching a second permission boundary wasn't part of the approved
  6A schema/calculation packet.
- **Reason:** `POST /api/quotes/[id]/preview` and the `public.preview_quote_version_totals` function it calls
  check only `quotes.view` (`src/routes/api/quotes/[id]/preview/+server.ts` line 13; the RPC itself calls
  `private.member_has_permission(..., 'quotes.view')`). `private.quote_customer_totals()` strips cost,
  profit, and margin for a reader without `quotes.view_cost`, but nothing strips subtotal, discount, tax,
  total, or (as of Part 6A) `deposit_required_minor` for a reader without `quotes.view_price`. The contract's
  own permission table (`docs/quote-behavior-contract.md` § Staff permissions) lists exactly those fields as
  what `quotes.view_price` is supposed to gate.
- **What is at risk:** the proposed default role matrix gives Field only `quotes.view` (no `view_price`), so
  a Field member could call this endpoint directly and see every dollar figure on a quote the UI never shows
  them. No default roles are seeded yet (Part 6A's fixtures use `admin`, which holds every key), so nothing
  is exploitable in the live product today.
- **The likely fix:** either gate the route on `quotes.view_price` the way `quotes.view_cost` is already
  gated inside the RPC, or have `preview_quote_version_totals` also strip subtotal/discount/tax/total/deposit
  for a caller without `quotes.view_price`, mirroring `quote_customer_totals`.
- **Reactivation trigger:** the Field/Office/Sales default role matrix is actually seeded and enforced
  (`docs/quote-behavior-contract.md` § Staff permissions says this needs Jafar's separate schema/RLS
  approval), or any campaign next touches `preview_quote_version_totals` or the preview route.
- **Checkpoint:** `src/routes/api/quotes/[id]/preview/+server.ts`,
  `supabase/migrations/20260822140000_quotes_drop_packages.sql` (current body of
  `preview_quote_version_totals`).

