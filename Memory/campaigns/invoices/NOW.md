# Invoices: Current Checkpoint

- Goal: Jobber-grounded invoicing and manual collection.
- Parts 1–9 CLOSED + committed. **Part 5c is the only remaining part**; 5c-1…5c-4 CLOSED and
  browser-verified. Approved scope and performance verdict: `docs/invoice-part-5c-plan.md` — do not re-derive.
- 5c-5a (visit-line editing), 5c-5b (invoice seeding), 5c-5c (find-only browser pass) all done. The 5c-5c
  pass found 3 bugs, all fixed and committed: BUG 1 `863a96c`, BUG 2 `7aaa5f3`, BUG 3 `83fd891`.
- **5c-5's second find-only pass (J1,J2,J2b,J3,J6,J8) is done and triaged.** Findings and their verdicts
  are in `Memory/campaigns/invoices/parts/5c-5-browser-pass.md`:
  - BUG 1 **FIXED + browser-verified** — the schedule dialog rounded each percentage stage on its own, so
    the live preview total sat a cent off the job's. It now prices the stages as a set, mirroring
    `private.price_job_payment_schedule`. Dead `lockedAmountMinor` draft field removed with it.
  - BUG 2 **NOT A BUG** — the "red square" on Job #14 is a real line photo (`line-photo-test.png`, 178
    bytes), rendered decorative (`<img alt="">`), which is why it had no a11y or text node.
  - J6 confirmed as expected (no correction UI exists).
  - **J4/J5 still unrun and blocked on test data:** Job #1 no longer matches the tick sheet — real total
    is $66,500.00 (not $665.00), it already carries a linked 3-stage schedule, and Invoice #6 already
    bills the whole job. The app correctly refused a stage invoice as already-billed. Needs a fresh rig
    job (or a Job #1 reset) before J4/J5 can run.
- Branch `schedule-5b-visits-card`. Stage named files only; never stage the repo-wide CRLF drift.

## Next action — seed a clean rig, then run J4 and J5

Everything the second pass found is closed. **J4 and J5 are the only unrun journeys left in
`5c-5-browser-pass.md`, and they are the last thing standing between 5c-5 and Part 5c closing.**

Ask Jafar whether to reset Job #1 or seed a new job, then run:
- **J4** — create / open / pay each fixed stage in order; expect Remaining -> Draft -> Awaiting payment ->
  Paid, the invoice number and total on the Job Billing card, and a created stage locked even while Draft.
- **J5** — after J4's first stage only: the linked stage is not editable, the two unlinked ones may be
  edited or reordered only if the whole schedule still reconciles with the locked amount preserved, and a
  set that does not reconcile is refused whole.

The rig needs a job with priced lines, a fixed multi-stage schedule, nothing linked, and **no whole-job
invoice** — that last one is what disqualified Job #1.

BUG 3 (first pass) closed `83fd891`: `add_job_visits` takes an optional `copy_lines_from_visit_id`, copies
the source visit's lines in the same transaction, refuses a source outside the job with P0404. pgTAP
`plan(37)` passes.

## Owed

- `EXPLAIN (ANALYZE, BUFFERS)` on the stage reads and the visit-line reads once there is real data — the
  planner picks seq scans on a dozen rows today.

## Known deferrals — outside this campaign, do not treat as bugs

- Quote screen's "Convert to job" menu item is hard-coded `disabled: true` (Quotes Part 8 leftover).
- Invoice + receipt email go to the client's PRIMARY email only —
  `Memory/deferred/invoice-email-sends-to-primary-only-not-billing-contact.md`.
- Void → client cancellation email needs a new template.
- No correction UI —
  `Memory/deferred/issued-invoices-cannot-be-corrected-from-the-browser.md`.
- Payment edit/delete, one-payment-across-several-invoices, Invoices-list stat cards ("—" by design), SMS.
- Two Jobs reminder gaps: "On dates we pick ourselves" and "Once, when the job is finished" raise no
  reminder until a date or closure exists.
- `JobPaymentScheduleDialog` keeps its red "stages must add up" banner until save even after the numbers
  are corrected; the live "Adds up to X of Y" line is right. Jafar has seen it and not asked for the fix.
- `npx supabase gen types` cannot run here, so new RPCs are hand-added to `database.types.ts`.

## Live test data (Raad LTD, org `18f0d717-904e-48d8-bd99-9df7e3844cda`)

- **"5b-4 Per-Visit Verify"** `138844e5-a1cf-41e6-8f35-b09e3bd2bf86` — the per-visit rig. All 6 visits
  completed. Sep 15 (`28e5f732-…`) billed to Draft #20 at its $100 override; Sep 22 (`3b319a7b-…`, a
  2-line override incl. a visit-only "Edging") and Sep 29 (`67bfca37-…`, qty 2 = $100) completed and
  unbilled. One extra upcoming Sep 22 visit is the BUG 3 duplicate ($165 copy) — evidence, delete only
  with Jafar's OK. Several orphan "Sep 7 · Due today · Per visit" reminders are BUG 2 residue, likewise.
- Job #14 fully billed: Deposit → Draft #18 ($500, $400 deposit applied, $100 balance), Final → Draft #19
  ($376.65). Both still Draft.
- Job #1 is **no longer the J4/J5 rig** — see the J4/J5 blocked note above; it's now a $66,500.00 job with
  a linked schedule and a whole-job invoice (#6). Job #13 (33.33/33.33/33.34 % on $200) **divides evenly
  and does NOT exercise residual cents** — it is not the percentage rig.
- Percentage/fixed preview rigs, schedules now SAVED and confirmed by query: **Job #15 "5c-5 Residual
  Cents Rig"** (`64b313b8-…`, $100.01, 3333/3333/3334 bp -> $33.33/$33.33/$33.35), **Job #16 "5c-5
  Tie-Break Rig"** (`45437d90-…`, $100.01, 5000/5000 -> $50.01/$50.00), **Job #17 "5c-5 Fixed Schedule
  Rig"** (`ed14da3e-…`, $600.00, 20000/20000/20000). None has a linked invoice, so #17 is the closest
  thing to a ready J4 rig — but confirm it carries no whole-job invoice before using it.
- **Job #2 "Recurring Lawn Care Test" is `fixed_per_period`** — it shows no per-visit pricing section.
- Leftover drafts #16 ($75), #17 ($200), #20 ($100) — harmless; delete only with Jafar's OK.
- Invoice #5 "D2 refusal test" carries append-only test state; remove only by reversal, with Jafar's OK.

## Notes

- The dev app over the Cloudflare tunnel is slow: most actions need a ~4 s wait before a screenshot
  succeeds, and job-detail cold loads take 8–12 s.
- Local migration filenames vs remote versions do not match — existing convention.
- pgTAP runs against the remote project as one rolled-back transaction. `finish()` emits rows only on
  failure, and MCP returns the last statement that produced rows — so a run that comes back with the last
  `is` row instead of a `finish` row passed.

Resume command: `read memory and continue the Invoices campaign`.
