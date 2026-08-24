# Part 6B: Staff deposit configuration and offline recording — CLOSED (2026-08-21)

Approved 2026-08-21 (Jafar: "go", after confirming the record/reverse UI folds into `QuoteDepositCard`
itself rather than a separate card). Built end-to-end and browser-verified; see Closing verification below.

## Approved behavior

- `quotes.record_deposit` permission, granted by default to owner/admin/office/finance (not sales, not
  field) — mirrors `finance` already holding `quotes.view_cost`.
- `set_quote_draft_deposit(target_quote_id, expected_revision, new_deposit_type, new_items)`: replaces a
  draft's whole deposit shape in one call, following the exact `lock_quote_draft` → mutate → `bump_quote_draft`
  pattern `set_quote_draft_tax`/`set_quote_draft_discount` already use. `new_deposit_type` is `null`,
  `'deposit_only'`, or `'schedule'`; `new_items` is the ordered installment list (`description`, `type`,
  `value`). Deposit-only accepts exactly one item; a schedule accepts 1-12 and its installments' priced
  amounts (fixed value, or `round(total * value / 10000)` for percentage — same formula the calculator uses)
  must sum to the draft's current `total_minor` exactly, or the save is refused naming the mismatch. A
  schedule cannot be saved against a zero-total draft. Removing the deposit (`null`) clears every
  installment with it.
- `quote_deposit_events`: new immutable ledger table (`received`/`reversed` rows), RLS-gated on `quotes.view`
  only (matching 6A's own choice for `quote_version_schedule_items` — price-sensitive columns are withheld at
  the API/read-model layer, not by a second RLS permission, everywhere else in this campaign). No
  INSERT/UPDATE/DELETE grants; only the two commands below may write it.
- `record_quote_deposit_event(target_quote_id, idempotency_key, method, reference, note)`: binds to the
  quote's `current_published_version_id` (there is no partial/cumulative recording this campaign — the
  contract's "no partial deposit" rule means exactly one live, non-reversed `received` row per version, for
  the version's exact frozen `deposit_required_minor`). Refuses with a plain `check_violation` when there is
  no sent version, no deposit configured, or a live receipt already exists. Idempotency-key replay returns
  the first result untouched, following Pipeline's `pipeline_mark_opportunity_lost` pattern exactly (key
  length ≥ 8, replay check runs before every other guard).
- `reverse_quote_deposit_event(target_quote_id, target_event_id, idempotency_key, reason)`: inserts a new
  `reversed` row naming the receipt it corrects; never edits or deletes the original. Requires a reason,
  refuses a second reversal of the same receipt, and is itself idempotency-key replay-safe. Once reversed, a
  fresh `record_quote_deposit_event` call can record again (a new idempotency key, a new live receipt).

## Dependencies

Part 6A (deposit schema/calculator), Part 5A (`publish_quote`, `lock_quote_draft`/`bump_quote_draft` shared
preamble), Pipeline's `pipeline_mark_opportunity_lost`/`pipeline_reopen_opportunity` (idempotency-key ledger
pattern this part copies).

## Checklist

- [x] Migration `20260823090000_quote_deposit_configuration_and_recording.sql`: permission seed,
      `set_quote_draft_deposit`, `quote_deposit_events` table + RLS + indexes, `record_quote_deposit_event`,
      `reverse_quote_deposit_event`. Applied to remote.
- [x] Migration `20260823093000_quote_deposit_events_actor_index.sql`: `actor_user_id` index the advisor
      flagged (same fix `quote_decisions` already carries).
- [x] `supabase-postgres-best-practices` read before writing the migration.
- [x] `supabase/tests/database/quote_deposit_configuration_and_recording.sql` — plan 58, all 58 passing, run
      as a rolled-back transaction against the linked remote project.
- [x] `performance-review` for the database layer: `get_advisors` (security + performance) showed only the
      actor-index finding (fixed) and the expected "unused index" info notices on a brand-new, empty table.
      `EXPLAIN` on the "already reversed" anti-join confirms both sides use index scans
      (`quote_deposit_events_reversed_idx` index-only on the inner side).
- [x] `PATCH /api/quotes/:id/deposit` (via `runQuoteCommand`, gated `quotes.edit`) → `set_quote_draft_deposit`.
- [x] `POST /api/quotes/:id/deposit-events` (gated `quotes.record_deposit`) → `record_quote_deposit_event`.
- [x] `POST /api/quotes/:id/deposit-events/:eventId/reverse` (gated `quotes.record_deposit`) →
      `reverse_quote_deposit_event`.
- [x] `quoteDepositSchema` / `recordQuoteDepositEventSchema` / `reverseQuoteDepositEventSchema` in
      `src/lib/server/validation/quotes.schema.ts`.
- [x] `saveQuoteDeposit` / `recordQuoteDepositEvent` / `reverseQuoteDepositEvent` client functions in
      `src/lib/quotes/api.ts`; `QuoteDetail.version` carries `deposit_type`/`deposit_required_minor`
      directly rather than widening the unrelated `QuoteTotals` shape.
- [x] Extended `GET /api/quotes/[id]`: `deposit_type` on `VERSION_SELECT` (ungated), `deposit_required_minor`
      on `VERSION_PRICE_COLUMNS` (`canSeePrice`-gated), `quote_version_schedule_items` for the visible version
      and `quote_deposit_events` for `current_published_version_id` (both fetched only when `canSeePrice`),
      `can_record_deposit`.
- [x] `QuoteDepositCard.svelte`: `RailCard` following `QuoteTaxCard`/`QuoteDiscountCard`'s Add/Edit-dialog
      shape for configuration, folding deposit status (required vs. received) and the Record/Reverse actions
      into the same card. Dialog: Deposit only vs. Payment schedule; schedule rows add/remove in insertion
      order (no drag-reorder, keyed by a minted id so removing a middle row doesn't misattribute focus);
      deposit-only's single installment's description is hardcoded `'Deposit'`, no field shown for it. A
      live running-total line ("Adds up to $X of $Y") helps hit the schedule's exact-sum requirement before
      the save round-trip.
- [x] Mounted `QuoteDepositCard` in `src/routes/(app)/quotes/[id]/+page.svelte`'s right rail, alongside
      `QuoteDiscountCard`/`QuoteTaxCard`.
- [x] `performance-review` for the API route and Svelte layers: pass (see report in session — both new GET
      queries reuse 6A/6B indexes exactly, no new migration needed; fixed a real each-block keying bug on the
      schedule-row editor during the review).
- [x] `npx prettier --check` the new/changed files.
- [x] `npm run check` — 0 errors.
- [x] Browser-verify live: configure a deposit-only and a schedule deposit, publish, record an offline
      deposit, reverse it, record again — as different role members to confirm the permission split.

## Closing verification (2026-08-21)

- Deposit-only (50% of $285.00 → $142.50) and payment-schedule (two installments summing exactly to
  $876.65, with the live running-total line updating correctly) both configured, saved, and published
  cleanly. The published deposit-required amount for a schedule is the first installment ($400.00 of
  $876.65), matching the milestone-first-installment design.
- Record → Reverse → Record again cycled correctly on both quotes: reference/note round-tripped, reversal
  required a reason, and a fresh record after reversal created a new live receipt.
- Role split verified live with temporary `sales`/`field` test members added to the org (not just pgTAP):
  `sales` could open "Add deposit" and save a configuration on a draft, but the published quote showed no
  Record/Reverse control. `field` was refused at the API layer entirely (`GET /api/quotes` and
  `GET /api/quotes/:id` both 403) — stronger than the acceptance check asked for, since `field` has no
  `quotes.view` at all.
- Test members were removed from `organization_members` after verification (their `auth.users` rows are
  orphaned and harmless — deleting them outright is blocked by design, since they authored immutable
  published-version and deposit-event rows).

## Acceptance checks

- A deposit-only save prices its exact amount; a schedule save is refused unless its installments sum to
  the current total; removing the deposit clears price and installments together.
- Exactly one live receipt may exist per published version; recording twice without a reversal in between is
  refused; the same idempotency key replays instead of duplicating, for both record and reverse.
- `sales` (has `quotes.edit`) can configure a deposit but cannot record or reverse one; `field` (has neither)
  is refused both.
- Another organization's members see zero rows in `quote_deposit_events` (RLS).

## Non-discoverable risks

- Recording is deliberately all-or-nothing against the version's frozen `deposit_required_minor` — there is
  no outstanding-balance tracking. If Jafar later wants partial offline deposits, that is explicitly a later
  Payments-approved extension per the contract, not a gap in this part.
- The actor's display name is not surfaced on the deposit ledger (no `profiles`/member-name join was added
  for this part, to avoid pulling in collaboration-profile machinery for one line of UI); the card should
  show date + method + reference/note, not "recorded by X". Revisit only if Jafar asks for it live.
- `quote_deposit_events` RLS is gated on `quotes.view` only, same as `quote_version_schedule_items` in 6A —
  a reader without `quotes.view_price` must not see `amount_minor` at the API layer (the GET route change
  above must actually withhold it, not just rely on RLS).

## Source pointers

- `docs/quote-behavior-contract.md` § Deposits and payment schedules, § Staff permissions.
- `.claude/skills/jobber/jobber-03-quotes.md` §4, §7.
- `supabase/migrations/20260823090000_quote_deposit_configuration_and_recording.sql`,
  `20260823093000_quote_deposit_events_actor_index.sql`.
- `supabase/tests/database/quote_deposit_configuration_and_recording.sql`.
- `supabase/migrations/20260819083832_pipeline_outcome_engine.sql` — the idempotency-key ledger pattern
  (`pipeline_mark_opportunity_lost`) `record_quote_deposit_event`/`reverse_quote_deposit_event` copy.
- `src/lib/components/quotes/QuoteTaxCard.svelte`, `QuoteDiscountCard.svelte` — the dialog pattern
  `QuoteDepositCard` extends.
- `src/lib/components/pipeline/MarkOpportunityLostDialog.svelte` — the "mint the idempotency key once per
  dialog open, not per submit" pattern to copy for Record/Reverse.
