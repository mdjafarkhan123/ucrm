# Invoices: Current Checkpoint

- Goal: Jobber-grounded invoicing and manual collection.
- Parts 1–9 CLOSED + committed (7 of 8 journeys; progress invoicing not built). Detail in `ROADMAP.md`.
- **Part 5c is the only remaining part.** Sub-sequence 5c-1…5c-5 lives in `docs/invoice-part-5c-plan.md`.
  Jobber is the sole reference (GHL excluded).
- **5c-1 CLOSED 2026-09-06** — records, pricing function, gated readers, Quote copy, tightened Quote rule.
- **5c-2 code complete + committed 2026-09-06** (`89ed498`, migration
  `20260906121529_job_payment_schedule_command_and_read.sql`): `public.set_job_payment_schedule`,
  `public.job_schedule_stages`, `/api/jobs/[id]/payment-schedule`, `saveJobPaymentSchedule`, the job detail
  read's `schedule` block, `JobPaymentScheduleDialog.svelte`, and the schedule section in `JobBillingCard`.
  35 pgTAP assertions pass on the remote project; advisors clean; `npm run check` 0 errors.
  **Not yet browser-verified** — see the next action.

## Next action

Finish the 5c-2 gate in the browser, then start 5c-3.

1. Browser-check on a one-off Job (contractor login): add a fixed schedule, add a percentage schedule with a
   residual cent, confirm a converted Quote's schedule appears unchanged, and confirm no amounts appear for a
   member without `jobs.view_price`. Light and dark. Then close 5c-2 in `ROADMAP.md`.
2. Implement **5c-3 — atomic installment-to-Invoice handoff** per `docs/invoice-part-5c-plan.md`.

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
  `is_deposit` travels only with the stage that already carries it; a schedule authored on the job invents
  none, so 5c-3 should apply the live Quote deposit to the **first stage**, not to an `is_deposit` flag.
- Stage status without `invoices.view` is the single word `invoiced`; with it, the live invoice status.

## Verification still owed on 5c-2

- Browser pass above.
- The stage read uses `job_payment_schedule_items_job_idx`; the two lateral lookups fall back to seq scans
  only because `invoice_sources` and `invoices` are still tiny in the dev project. Re-check with
  `EXPLAIN (ANALYZE, BUFFERS)` once there is real installment data.

## Known deferrals — outside this campaign, do not treat as bugs

- **Billing-contact fan-out**: invoice + receipt email go to the client's PRIMARY email only.
  `Memory/deferred/invoice-email-sends-to-primary-only-not-billing-contact.md`.
- **Void → client cancellation email**: needs a new template (7b note).
- Payment edit/delete, one-payment-across-several-invoices, Invoices-list stat cards ("—" by design), SMS.
- Two **Jobs** reminder gaps (not ours): "On dates we pick ourselves" and "Once, when the job is finished"
  raise no reminder until a date/closure exists — finished work can sit invisible.
- `npx supabase gen types` cannot run here (no access token), so new RPCs are hand-added to
  `database.types.ts`; they reorder on a real regeneration, which is fine.

## Live test-data state (Raad LTD, org 18f0d717-904e-48d8-bd99-9df7e3844cda)

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
