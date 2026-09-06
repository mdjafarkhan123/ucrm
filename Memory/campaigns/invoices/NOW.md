# Invoices: Current Checkpoint

- Goal: Jobber-grounded invoicing and manual collection.
- Parts 1–9 CLOSED + committed (7 of 8 journeys; progress invoicing is Part 5c's job). Detail in `ROADMAP.md`.
- **Part 5c is the only remaining part.** Sub-sequence 5c-1…5c-5 lives in `docs/invoice-part-5c-plan.md`.
  Jobber is the sole reference (GHL excluded).
- **5c-1, 5c-2 and 5c-3 are CLOSED and committed** (5c-3 in `337a5dc`, browser-verified 2026-09-06;
  evidence in `ROADMAP.md`). No part packet is open.

## Next action

Start **5c-4 — Progress documents and correction integration**. Read its section in
`docs/invoice-part-5c-plan.md` (that plan is the approved scope; do not re-derive it) and the shipped
`20260906133725_invoice_installment_handoff.sql` for what a progress bill already carries:
`invoice_lines.progress_original_amount_minor` and `invoice_sources.installment_id` are the two hooks the
staff and customer projections need. Load `.claude/skills/design/SKILL.md` before any Svelte, and
`supabase-postgres-best-practices` before any SQL.

## Decisions from 5c-1…5c-3 that later parts must not contradict

- A stage is locked the moment an invoice claims it. `locked_amount_minor` holds the billed amount and is
  written **before** `invoice_sources` — the guard trigger refuses the other order. It is permanent: deleting
  the Draft does not release the stage.
- Percentage schedules validate on basis points summing to 10000 and price by largest remainder (ties by
  position); fixed schedules must sum exactly to the job total. Same rule on the Quote command.
- A schedule that no longer reconciles is a real state, not an error: readers answer `reconciles: false`.
- Visit lines are a full snapshot, not a delta: no rows means the visit bills the job's lines.
- The live Quote deposit is applied to the **first** stage only (position 0, job has a `quote_id`).
- Stage status without `invoices.view` is the single word `invoiced`; with it, the live invoice status.
- Ready-to-Bill deliberately does **not** list individual stages — a job carrying any schedule is excluded
  from whole-job Ready-to-Bill, and the Job Billing card is the only place a stage is billed. Scope call made
  in 5c-3, not separately re-confirmed with Jafar.
- The composer's installment mode sends no lines: `create_installment_invoice` prices and splits the stage
  server-side, so the browser's line preview is display-only.
- `locked` means "priced into a bill, permanently"; `status` means "where that bill stands". Do not collapse
  them or re-derive `locked` from the claim.

## The stage lock, corrected 2026-09-06 (migration `20260906190000_stage_lock_matches_the_write_command`)

`job_schedule_stages.locked` now answers `stage.locked_amount_minor is not null` — the same test
`set_job_payment_schedule` uses to decide what it may rewrite. It used to answer from the invoice claim, which
disagreed after a still-Draft progress invoice was deleted: the claim cascades, the locked amount is permanent
by design, and the reader was then reporting an editable, still-to-bill stage that the write command would
silently refuse and the card would offer a doomed "Create invoice" button for. `status` is unchanged — it
answers where the *bill* stands, and 'remaining' is honest when no bill exists. The card combines them: locked
+ remaining renders as "Already billed" with no action. Covered by assertion 16 of
`invoice_installment_to_invoice_handoff.sql`.

## Verification still owed

- The stage read uses `job_payment_schedule_items_job_idx`; the two lateral lookups fall back to seq scans
  only because `invoice_sources` and `invoices` are still tiny. Re-check with `EXPLAIN (ANALYZE, BUFFERS)`
  once there is real installment data.

## Known deferrals — outside this campaign, do not treat as bugs

- The Quote screen's "Convert to job" menu item is hard-coded `disabled: true`
  (`src/routes/(app)/quotes/[id]/+page.svelte`) — the Quotes campaign's Part 8 leftover.
- **Billing-contact fan-out**: invoice + receipt email go to the client's PRIMARY email only.
  `Memory/deferred/invoice-email-sends-to-primary-only-not-billing-contact.md`.
- **Void → client cancellation email**: needs a new template (7b note).
- Payment edit/delete, one-payment-across-several-invoices, Invoices-list stat cards ("—" by design), SMS.
- Two **Jobs** reminder gaps (not ours): "On dates we pick ourselves" and "Once, when the job is finished"
  raise no reminder until a date/closure exists.
- `JobPaymentScheduleDialog` keeps its red "stages must add up" banner until save even after the numbers are
  corrected; the live "Adds up to X of Y" line is right. Jafar has seen it and has not asked for the fix.
- `npx supabase gen types` cannot run here (no access token), so new RPCs are hand-added to
  `database.types.ts`; they reorder on a real regeneration, which is fine.

## Live test-data state (Raad LTD, org 18f0d717-904e-48d8-bd99-9df7e3844cda)

- **Job #14 is now fully billed**: Deposit → Draft invoice #18 ($500, $400 deposit applied, $100 balance),
  Final → Draft invoice #19 ($376.65). Both still Draft, so 5c-4 can issue/pay/correct them.
- Unbilled schedules still available for testing: Job #1 ($20,000/$20,000/$26,500 fixed) and Job #13
  (33.33/33.33/33.34 percentage).
- Job #2 "Recurring Lawn Care Test" on `fixed_per_period`; Sept → invoice #16, Oct-31 + Nov-30 reminders
  pending, Aug → invoices #9/#10.
- Leftover Session-B drafts #16 ($75) and #17 ($200) — harmless; delete only with Jafar's OK.
- Invoice #5 "D2 refusal test" carries append-only test state ($1,000 "other" payment + extra receipts);
  remove only by reversal, with Jafar's OK.

## Notes

- Local migration filenames vs remote versions do not match — existing convention.
- Repo-wide CRLF drift on ~300 `src/` files — never stage it. Skill-dir edits never staged with features.
- pgTAP runs against the remote project in one rolled-back transaction; `finish()` is the pass/fail signal
  and emits rows only on failure. Only the last statement's output returns through MCP, so collect each
  assertion into a temp table when you need to see which one failed.
- Two pre-existing ESLint errors in `src/routes/(app)/jobs/[id]/+page.svelte` are not ours.

Resume command: `read memory and continue the Invoices campaign`.
