# Invoices: Current Checkpoint

- Goal: Jobber-grounded invoicing and manual collection.
- Parts 1–9 CLOSED + committed (7 of 8 journeys; progress invoicing not built). Detail in `ROADMAP.md`.
- **Part 5c is the only remaining part.** Sub-sequence 5c-1…5c-5 lives in `docs/invoice-part-5c-plan.md`.
  Jobber is the sole reference (GHL excluded).
- **5c-1 CLOSED 2026-09-06** (migration `20260906113542_job_payment_schedules_and_visit_lines.sql`, 50
  pgTAP assertions passing on the remote project in a rolled-back transaction, advisors clean). It shipped
  `job_payment_schedule_items` (+ `locked_amount_minor`, locked-row guard trigger),
  `job_visit_line_items`, `invoice_sources.installment_id` with a strict shape check,
  `private.price_job_payment_schedule`, the gated readers `public.job_schedule_money` /
  `public.visit_line_money`, the Quote-to-Job schedule copy, and the tightened
  `public.set_quote_draft_deposit` rule.

## Next action

Implement **5c-2 — Job schedule commands and read model** per `docs/invoice-part-5c-plan.md`. One validated
`/api/jobs/[id]/payment-schedule` write route + Job API method; the command replaces only unlocked stages
under an expected Job revision and calls `private.price_job_payment_schedule` for validation; extend the Job
detail read model with a price-gated schedule projection and derived Invoice/payment status (do not store
status). Extend Billing setup rather than adding a settings surface; reuse the Quote schedule editor
behavior and existing Dialog/money controls. Invalidate Job detail, Job history, Job lists/counts,
billable-work and ready-to-bill queries on save. Stop at the 5c-2 completion gate.

Before SQL: reload the Supabase + Postgres skills and check the Supabase changelog. Migrations go through
`mcp__supabase__apply_migration`, NOT `supabase db push`
(`Memory/deferred/two-migration-ledger-rows-do-not-match-the-repo.md`); base `create or replace` on
`pg_get_functiondef`, then rename the local migration file to the version the ledger records. Regenerate
`database.types.ts` when the browser first calls the new RPCs (5c-1 skipped it deliberately).

## 5c-1 decisions later parts must not contradict

- A stage is locked the moment an invoice claims it. `locked_amount_minor` holds the amount it was billed
  at and the 5c-3 claim command must write it **before** inserting `invoice_sources`, or the guard trigger
  refuses the write.
- Percentage schedules are validated on basis points summing to 10000 and priced by largest remainder
  (ties by position); fixed schedules must sum exactly to the job total. Same rule on the Quote command.
- A schedule that no longer reconciles is a real state, not an error: `job_schedule_money` returns
  `reconciles: false` with the stored stages instead of throwing.
- Visit lines are a full snapshot, not a delta: no rows means the visit bills the job's lines; rows mean
  that visit's complete billable set.

## Known deferrals — outside this campaign, do not treat as bugs

- **Billing-contact fan-out**: invoice + receipt email go to the client's PRIMARY email only.
  `Memory/deferred/invoice-email-sends-to-primary-only-not-billing-contact.md`.
- **Void → client cancellation email**: needs a new template (7b note).
- Payment edit/delete, one-payment-across-several-invoices, Invoices-list stat cards ("—" by design), SMS.
- Two **Jobs** reminder gaps (not ours): "On dates we pick ourselves" and "Once, when the job is finished"
  raise no reminder until a date/closure exists — finished work can sit invisible.

## Live test-data state (Raad LTD, org 18f0d717-904e-48d8-bd99-9df7e3844cda)

- Job #2 "Recurring Lawn Care Test" on `fixed_per_period`; Sept → invoice #16, Oct-31 + Nov-30 reminders
  pending, Aug → invoices #9/#10.
- Leftover Session-B drafts #16 ($75) and #17 ($200) — harmless; delete only with Jafar's OK.
- Invoice #5 "D2 refusal test" carries append-only test state ($1,000 "other" payment + extra receipts);
  remove only by reversal, with Jafar's OK.

## Notes

- `database.types.ts` hand-added RPCs reorder on regeneration — fine.
- Local migration filenames vs remote versions do not match — existing convention.
- Repo-wide CRLF drift on ~300 `src/` files — never stage it. Skill-dir edits never staged with features.
- pgTAP runs against the remote project in one rolled-back transaction; `finish()` is the pass/fail signal.

Resume command: `read memory and continue the Invoices campaign`.
