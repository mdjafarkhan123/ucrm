# Part 6A: Deposit schema and calculation

Approved 2026-08-21 (Jafar: "lets go... We follow jobber"). Schema and calculation only — no staff UI, no
API route, no offline recording. Part 6B builds the `QuoteDepositCard` configuration dialog and offline
deposit recording; Part 6C builds readiness gating and the customer-facing display.

## Approved behavior

- A quote has either no deposit requirement (`deposit_type is null`) or one payment schedule
  (`deposit_type in ('deposit_only', 'schedule')`), carried on `quote_versions`.
- `quote_version_schedule_items` holds a version's own ordered installments: `value_type` (`fixed` or
  `percentage`) and `value` (minor units or basis points, mirroring `discount_type`/`discount_value`). At
  most one row per version may have `is_deposit = true`, enforced by a partial unique index.
- The calculator prices the deposit exactly like it prices tax: a percentage deposit is a share of
  `total_amount` for the *current* selected add-ons (matches Jobber — the client toggles add-ons in Client
  Hub and the total, and therefore the deposit, recalculates live before they approve). A fixed deposit is
  capped at the total, the same way a fixed discount is capped at the subtotal.
- `deposit_type` set with no `is_deposit` row is refused by the calculator (`check_violation`), not silently
  priced as zero.
- `deposit_required_minor` is a stored, database-owned column on `quote_versions` (same treatment as
  `subtotal_minor`/`discount_minor`/`tax_minor`/`total_minor`), refreshed by `refresh_quote_draft_totals` and
  frozen by `freeze_quote_version`. A `quote_versions_totals_check` constraint keeps it between 0 and the
  version's own total.
- `clone_quote_version_to_draft` (Revise) and `create_similar_quote` (Create Similar) both copy `deposit_type`
  and the schedule items, the same way they already copy discount and tax — a revised or duplicated quote
  does not silently lose its deposit configuration.

## Dependencies

Parts 2, 4-5: the calculation function, `quote_versions`' discount/tax columns, and the freeze/clone/publish
lifecycle all exist and follow the pattern this part extends.

## Checklist

- [x] Migration `20260822160000_quote_deposit_schema_and_calculation.sql`: `quote_version_schedule_items`
      table (RLS gated on `quotes.view`, no write grant), `deposit_type`/`deposit_required_minor` on
      `quote_versions`, `calculate_quote_version` extended, `refresh_quote_draft_totals` and
      `freeze_quote_version` persist the new column and hash the schedule items, `clone_quote_version_to_draft`
      and `create_similar_quote` copy the deposit shape.
- [x] Same migration also fixed a deferred, already-diagnosed bug in `clone_quote_version_to_draft`: its line
      and attachment copy queries named only `quote_version_id`, missing the index prefix
      `quote_version_lines_version_idx` needed (`organization_id, quote_id, quote_version_id, ...`), so they
      seq-scanned. Fixed while every line of the function was being touched anyway; verified by `EXPLAIN` now
      showing `Index Only Scan`. Deferred entry removed.
- [x] `supabase-postgres-best-practices` read before writing the migration.
- [x] `supabase/tests/database/quote_deposit_schema_and_calculation.sql` — plan 35, all 35 passing, run as a
      rolled-back transaction against the linked remote project (no local Docker/Supabase stack, per the
      standing deferred note on database test execution).
- [x] `performance-review`: `EXPLAIN` confirms the deposit-item lookup uses
      `quote_version_schedule_items_one_deposit_idx`, and both the schedule-item and line copy queries in
      `clone_quote_version_to_draft`/`create_similar_quote` use `quote_version_schedule_items_version_idx` /
      `quote_version_lines_version_idx`. `get_advisors` (security + performance) shows nothing new for the
      added table beyond the expected "unused index" info notice on a brand-new, still-empty table.
- [x] New deferred finding logged, not fixed (out of 6A's approved scope):
      `preview_quote_version_totals` / `POST /api/quotes/[id]/preview` gate on `quotes.view` only, not
      `quotes.view_price` — a reader without price visibility can see subtotal/discount/tax/total/deposit.
      See `Memory/deferred/INDEX.md`.

## Acceptance checks

- No deposit prices as zero; a fixed deposit prices its exact amount and is capped at the total; a percentage
  deposit recalculates when the add-on selection changes the total.
- Exactly one `is_deposit` row per version; a second one is refused (unique violation).
- Publish, Revise, and Create Similar all carry the deposit shape forward untouched.
- Another organization's members see zero rows (RLS).

## Non-discoverable risks

- Milestone-schedule "installments sum to the total" validation is explicitly **not** enforced here — it is
  a save-time command concern (Part 6B), not a schema or calculator concern, because the total itself moves
  with add-on selection.
- `deposit_required_minor` rides into the frozen document hash via the `calculation` key and via
  `quote_version_schedule_items` in the canonical JSON; `deposit_type` is not excluded from the version's own
  hashed fields, so changing it (or its installment) after approval invalidates the signature the same way a
  discount or tax edit already does — untested here because signature invalidation is Part 5C's concern, not
  6A's, but worth re-confirming in 6B/6C once a real deposit edit UI exists.

## Source pointers

- `docs/quote-behavior-contract.md` § Deposits and payment schedules, § Proposed database architecture.
- `.claude/skills/jobber/jobber-03-quotes.md` §4, §7 — deposit/payment-schedule behavior and the "client
  toggles add-ons, total (and therefore deposit) recalculates live" note that resolved the one open question
  from the Part 6 proposal.
- `supabase/migrations/20260822160000_quote_deposit_schema_and_calculation.sql`.
- `supabase/tests/database/quote_deposit_schema_and_calculation.sql`.
