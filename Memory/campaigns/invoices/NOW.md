# Invoices: Current Checkpoint

- Goal: Jobber-grounded invoicing and manual collection.
- Parts 1–9 CLOSED + committed. **Part 5c is the only remaining part**; 5c-1…5c-4 CLOSED and
  browser-verified. Approved scope and performance verdict: `docs/invoice-part-5c-plan.md` — do not re-derive.
- 5c-5a (visit-line editing), 5c-5b (invoice seeding), 5c-5c (find-only browser pass) all done. The pass
  found 3 bugs. **BUG 1 fixed `863a96c`. BUG 2 fixed `7aaa5f3`. BUG 3 is the only one left.**
- Branch `schedule-5b-visits-card`. Stage named files only; never stage the repo-wide CRLF drift.

## Next action — BUG 3, and it is waiting on Jafar

**BUG 3 — "Duplicate" on a visit drops that visit's line override.** Jafar's decision: **carry the
override**, atomically in one backend op if practical, else split to its own follow-up.

Assessed 2026-09-07: **it is practical in one op.** Proposed shape, NOT yet approved —
`add_job_visits` (migration `20260901051350`, the per-visit insert loop) takes a new optional
`copy_lines_from_visit_id` per visit element and copies that visit's `job_visit_line_items` rows onto the
new visit inside the same loop, guarded to the same job and a `per_visit` job. `duplicateVisit` in
`JobVisitsSection.svelte` passes the source visit id.

**The open question Jafar must answer (CLAUDE.md: confirm before touching permissions):** duplicating is
`jobs.schedule`, but writing a visit's prices is `jobs.edit` (it is money). So either the copy requires
`jobs.edit` and a schedule-only user duplicating a customised visit gets the job's lines with a warning, or
the copy rides on `jobs.schedule` because the person is not choosing the numbers, only carrying them.
**Do not implement until Jafar picks.** If he defers it, move BUG 3 to `Memory/deferred/` and close 5c-5.

## Then, to close 5c-5 → 5c → the campaign

The parts of the plan's 5c-5 checklist the find-only pass did not cover:

- The full progress/installment journeys re-run: direct fixed schedule create→open→pay each stage,
  % schedule with residual cents, Quote-carried funded deposit, edit remaining stages after one is linked,
  correction refusal/preview. Only invoice #18's deposit-stage render was re-checked.
- The **customer-facing** frozen progress-invoice output (needs a public share link).
- Progress-invoice **print view** — still blocked; the print dialog freezes browser control.

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
  unbilled. Sep 22 is the ready-made source visit for testing BUG 3. Several orphan "Sep 7 · Due today ·
  Per visit" reminders on the job are BUG 2 residue — expected, left as evidence.
- Job #14 fully billed: Deposit → Draft #18 ($500, $400 deposit applied, $100 balance), Final → Draft #19
  ($376.65). Both still Draft.
- Unbilled schedules for testing: Job #1 ($20,000/$20,000/$26,500 fixed), Job #13 (33.33/33.33/33.34 %).
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
