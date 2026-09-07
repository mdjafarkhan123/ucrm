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
  - **J4 and J5 both PASS** on a purpose-built rig, **Job #18 "5c-5 Stage Billing Rig"**
    (`02780a53-1668-44f0-8e59-73ba67b28c0c`, Tester Account, $665.00, fixed Deposit $200 / Mid build $200
    / Final $265) created through the UI on 2026-09-07. Job #1 was retired from this role rather than
    reset, because resetting it meant voiding its real $66,500 Invoice #6; Job #17 was rejected because
    three identical $200 stages cannot reveal a stage billed out of order. Each stage carried its own
    amount to its own invoice (#21/#22/#23), walked Still To Bill -> Draft -> Awaiting payment -> Paid,
    and locked as soon as its draft saved — before issue or payment. A linked stage refused edits, a
    non-reconciling set was refused whole, and a reconciling one saved with the locked $200 preserved.
  - BUG 3 **FIXED + browser-verified** (`fa07c5a`) — "Add stage" stayed enabled on a fully-invoiced
    schedule where every outcome is a refusal. Now disabled via an `allStagesBilled` derived. The
    over-reach risk was checked head-on: a partly-billed schedule still offers it and still saves a
    rebalanced set, and the 12-stage cap still trips independently.
- Branch `schedule-5b-visits-card`. Stage named files only; never stage the repo-wide CRLF drift.

## Next action — Jafar's call on closing the campaign

**5c-5 is done. Every journey in `5c-5-browser-pass.md` has run and passed, and all three bugs it found
are fixed, browser-verified and committed** (`cdd12bf`, `fa07c5a`). That closes 5c-5, which closes Part
5c, and **Part 5c was the last open part of this campaign.**

Nothing is left to implement. The only item still owed is the `EXPLAIN (ANALYZE, BUFFERS)` evidence under
`## Owed` — it needs realistic data volume, which this org does not have. **Put the choice to Jafar:**
either the campaign completes now and the EXPLAIN moves to `Memory/deferred/` with "reactivates when the
stage/visit-line reads run against production-like data" as its trigger, or it stays open until that
evidence exists. Do not close the campaign without his answer — completion deletes this folder.

Standing instruction from Jafar 2026-09-07: the browser is driven by an agent, never by the main session.

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
- Schedule rigs, all schedules saved and confirmed by query. Preview rounding: **Job #15 "5c-5 Residual
  Cents Rig"** (`64b313b8-…`, $100.01 -> $33.33/$33.33/$33.35) and **Job #16 "5c-5 Tie-Break Rig"**
  (`45437d90-…`, $100.01 -> $50.01/$50.00). Fixed mode: **Job #17 "5c-5 Fixed Schedule Rig"**
  (`ed14da3e-…`, $600.00, three $200 stages, unbilled). Stage billing: **Job #18 "5c-5 Stage Billing
  Rig"** (`02780a53-…`, $665.00, $200/$200/$265, all three billed and Paid via invoices #21/#22/#23).
  **Job #19 "5c-5 Partial Lock Check"** (`69759daa-…`, $300.00, stage one billed to draft Invoice #24)
  is the ONLY partly-billed schedule in the org and the only fixture that can catch a lock guard
  over-reaching — keep it.
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
