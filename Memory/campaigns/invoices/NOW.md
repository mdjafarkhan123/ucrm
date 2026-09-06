# Invoices: Current Checkpoint

- Goal: Jobber-grounded invoicing and manual collection.
- Parts 1–9 CLOSED + committed (7 of 8 journeys; progress invoicing not built). Detail in `ROADMAP.md`.
- **Part 5c is the only remaining part.** Sub-sequence 5c-1…5c-5 lives in `docs/invoice-part-5c-plan.md`.
  Jobber is the sole reference (GHL excluded).
- **5c-1 and 5c-2 are CLOSED** (5c-2 browser-verified 2026-09-06; evidence in `ROADMAP.md`).

## Next action

Implement **5c-3 — atomic installment-to-Invoice handoff** per `docs/invoice-part-5c-plan.md`.

Before SQL: reload the Supabase + Postgres skills and check the Supabase changelog. Migrations go through
`mcp__supabase__apply_migration`, NOT `supabase db push`
(`Memory/deferred/two-migration-ledger-rows-do-not-match-the-repo.md`); base `create or replace` on
`pg_get_functiondef`, then rename the local migration file to the version the ledger records.

## 5c-1/5c-2 decisions later parts must not contradict

- A stage is locked the moment an invoice claims it. `locked_amount_minor` holds the amount it was billed
  at and the 5c-3 claim command must write it **before** inserting `invoice_sources`, or the guard trigger
  refuses the write.
- Percentage schedules are validated on basis points summing to 10000 and priced by largest remainder
  (ties by position); fixed schedules must sum exactly to the job total. Same rule on the Quote command.
- A schedule that no longer reconciles is a real state, not an error: the readers answer `reconciles: false`
  with the stored stages instead of throwing, and the billing card explains it.
- Visit lines are a full snapshot, not a delta: no rows means the visit bills the job's lines.
- **Proposed schedule items reach the database as `{id?, description, type, value}`** — `id`, not
  `installment_id`, is what `private.price_job_payment_schedule` reads. The API body uses `installment_id`
  and the route maps it.
- `set_job_payment_schedule` rewrites every unlocked stage (new row ids) and leaves locked ones untouched.
  `is_deposit` travels only with the stage that already carries it (verified: survives a job-side edit); a
  schedule authored on the job invents none, so 5c-3 applies the live Quote deposit to the **first stage**.
- Stage status without `invoices.view` is the single word `invoiced`; with it, the live invoice status.

## Open UI nit found in the 5c-2 pass (not blocking)

`JobPaymentScheduleDialog` keeps the red "stages must add up" banner on screen after the numbers are
corrected; it only clears on save. The live "Adds up to X of Y" line below is correct. Jafar has seen it and
has not asked for the fix yet.

## Verification still owed

- The stage read uses `job_payment_schedule_items_job_idx`; the two lateral lookups fall back to seq scans
  only because `invoice_sources` and `invoices` are still tiny in the dev project. Re-check with
  `EXPLAIN (ANALYZE, BUFFERS)` once there is real installment data.

## Known deferrals — outside this campaign, do not treat as bugs

- The Quote screen's "Convert to job" menu item is hard-coded `disabled: true`
  (`src/routes/(app)/quotes/[id]/+page.svelte`). The command and `/api/quotes/[id]/convert-to-job` work; the
  entry point is the Quotes campaign's Part 8 leftover.
- **Billing-contact fan-out**: invoice + receipt email go to the client's PRIMARY email only.
  `Memory/deferred/invoice-email-sends-to-primary-only-not-billing-contact.md`.
- **Void → client cancellation email**: needs a new template (7b note).
- Payment edit/delete, one-payment-across-several-invoices, Invoices-list stat cards ("—" by design), SMS.
- Two **Jobs** reminder gaps (not ours): "On dates we pick ourselves" and "Once, when the job is finished"
  raise no reminder until a date/closure exists — finished work can sit invisible.
- `npx supabase gen types` cannot run here (no access token), so new RPCs are hand-added to
  `database.types.ts`; they reorder on a real regeneration, which is fine.

## Live test-data state (Raad LTD, org 18f0d717-904e-48d8-bd99-9df7e3844cda)

- Schedules now exist on Job #1 ($20,000/$20,000/$26,500 fixed), Job #13 (33.33/33.33/33.34 percentage) and
  Job #14 (Deposit $500 `is_deposit` / Final $376.65) — all created for the 5c-2 pass, all unbilled.
- **Quote #1 is now `converted` and produced Job #14** (Jafar approved this on 2026-09-06 so the
  quote-carried schedule could be verified). Its $400 cash deposit receipt is still attached to the quote.
- Job #2 "Recurring Lawn Care Test" on `fixed_per_period`; Sept → invoice #16, Oct-31 + Nov-30 reminders
  pending, Aug → invoices #9/#10.
- Leftover Session-B drafts #16 ($75) and #17 ($200) — harmless; delete only with Jafar's OK.
- Invoice #5 "D2 refusal test" carries append-only test state ($1,000 "other" payment + extra receipts);
  remove only by reversal, with Jafar's OK.

## Notes

- Local migration filenames vs remote versions do not match — existing convention.
- Repo-wide CRLF drift on ~300 `src/` files — never stage it. Skill-dir edits never staged with features.
- pgTAP runs against the remote project in one rolled-back transaction; `finish()` is the pass/fail signal.
  Only the last statement's output comes back through MCP, so collect each assertion into a temp table when
  you need to see which one failed.
- Two pre-existing ESLint errors in `src/routes/(app)/jobs/[id]/+page.svelte` (`dateFormat` unused, a `goto`
  with a query string) are not ours.

Resume command: `read memory and continue the Invoices campaign`.
