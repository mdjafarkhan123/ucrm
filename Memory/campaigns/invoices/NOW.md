# Invoices: Current Checkpoint

- Goal: Jobber-grounded invoicing and manual collection.
- Parts 1–9 CLOSED + committed. **Part 5c is the only remaining part**; 5c-1…5c-4 are CLOSED and
  browser-verified. Approved scope and performance verdict: `docs/invoice-part-5c-plan.md` — do not re-derive.
- **5c-5 is split across sessions on Jafar's instruction (2026-09-07):**
  - **5c-5a — visit-line editing. BUILT.**
  - **5c-5b — invoice seeding from visit lines. BUILT 2026-09-07.**
  - **5c-5c — the integrated browser pass for the whole 5c journey set. NOT STARTED — next action.**
- 5c-5a and 5c-5b are **committed** (`Invoices 5c-5: a visit bills what that visit did`) on branch
  `schedule-5b-visits-card`. Stage named files only; never stage the repo-wide CRLF drift.

## Next action

Run **5c-5c**: the browser pass listed in the plan's 5c-5 section, light and dark, no console errors.
Needs a recurring job on `per_visit` — Job #2 is `fixed_per_period` and will NOT show the pricing section, so
check for another or set one up. Verify the campaign's completion gate: a per-visit override reaches exactly
its Visit Invoice, and the visits-to-bill card, the "Invoice now" prompt and the created invoice all agree.

### 5c-5c is a FIND-ONLY session — Jafar's instruction, 2026-09-07

This pass observes and records. **Do not fix anything you find.** Append each finding to the bug log below
with the exact steps, what you expected, and what happened, then carry on with the rest of the checklist so
one bug does not cost the whole pass. A separate session fixes them.

The only writes this session may make are the ones the test itself requires (creating the per-visit test job,
its visits, the invoices under test) plus this checkpoint file. No source changes, no migrations.

Report at the end: which journeys passed, which failed, and what is in the bug log.

## 5c-5c bug log

Empty — the pass has not run yet. Findings go here, newest last.

## What 5c-5b changed

Three places used to show or bill one copy of the JOB's lines per visit. All three now ask the visit:

- `src/routes/(app)/invoices/new/+page.svelte` — the visit seed fetches `fetchJobVisitLines(jobId, visitIds)`
  and seeds each visit's own effective priced lines, dated from the read itself. A failed read toasts and
  returns to the job rather than leaving a blank invoice looking finished.
- `JobVisitsSection.svelte` — the "Invoice now / later" prompt takes its figure from the prompted visit's own
  `subtotal_minor`; the `visitAmountMinor` prop is gone. The row hover already warmed that exact key.
- `JobVisitsToBillCard.svelte` — each row and the selected total use per-visit subtotals (one gated read for
  up to 100 billable visits). Prop `subtotalMinor` replaced by `canSeePrice`. **This third path was not in the
  previous checkpoint's next action; it is the same lie in the same journey and would have failed the gate.**

Green: `npm run check` 0 errors, Prettier clean, `JobVisitsSection.svelte.spec.ts` 5/5. The Svelte autofixer
pass owed on the 5c-5a files is DONE — every remaining complaint is a false positive (it cannot parse SCSS
nesting or `//` comments) or the page's established seed-effect pattern. ESLint reports only pre-existing
errors in those files.

## What 5c-5a built (all applied and green)

- Migrations `20260908130000_job_visit_line_commands.sql` and
  `20260908140000_job_batch_billing_uses_visit_lines.sql` — both **applied to the remote project**.
  - `private.job_visit_effective_lines` is the single answer to "what does this visit bill": its own rows if
    it has any, otherwise the job's. Editor, composer, card and batch planner all ask it, so they cannot disagree.
  - `public.job_visit_lines(org, job, visit_ids[])` — gated read for up to 100 visits, with each visit's
    `subtotal_minor`, `has_override`, `locked` and `lock_reason`. Prices need jobs.view_price.
  - `public.replace_job_visit_line_items` — jobs.edit, refuses a non-`per_visit` job, a closed job, a
    completed or invoiced visit (P0410) and a stale visit revision (P0409). **An empty list is not "bill
    nothing" — it clears the override and puts the visit back on the job's lines.**
- `supabase/tests/database/invoice_visit_line_commands.sql` — **31 pgTAP assertions, all passing** remotely.
- Routes: `PATCH /api/jobs/[id]/visits/[visitId]/lines`, `GET /api/jobs/[id]/visit-lines?visits=`.
  Zod: `replaceVisitLinesSchema`. Client API: `fetchJobVisitLines`, `saveJobVisitLines`, `jobVisitLinesKey`.
- UI: a pricing section inside `JobVisitDialog` (recurring + per_visit only), using the shared
  `ProductsAndServicesBlock` with a new `carrySourceLine` prop; the dialog goes `size="large"` when it shows.

## Non-obvious decisions 5c-5c must not contradict

- **The visit dialog saves pricing FIRST, then the schedule** (`savePricingFirst`), threading the revision the
  pricing write hands back. Saving lines bumps `job_visits.revision`. If pricing succeeds and the schedule
  save then fails, the lines are saved and the dialog stays open with the error — deliberate.
- Pricing is only written when it really changed (`pricingFingerprint`), so reopening a dialog and changing
  nothing does not turn a plain visit into a customised one.
- `source_job_line_item_id` is provenance, never a price source.
- Editing a visit's lines is `jobs.edit` (it is money), not `jobs.schedule`.
- A figure is never shown before its visit's own subtotal arrives — the alternative was showing the job's
  number and taking it back.

## Owed

- `EXPLAIN (ANALYZE, BUFFERS)` on the stage reads and the visit-line reads once there is real data — the
  planner picks seq scans on a dozen rows today.

## Known deferrals — outside this campaign, do not treat as bugs

- Quote screen's "Convert to job" menu item is hard-coded `disabled: true` (Quotes Part 8 leftover).
- Invoice + receipt email go to the client's PRIMARY email only —
  `Memory/deferred/invoice-email-sends-to-primary-only-not-billing-contact.md`.
- Void → client cancellation email needs a new template.
- No correction UI: `prepare_invoice_correction` / `activate_invoice_replacement` / `rebill_voided_invoice`
  work and are tested, but nothing in `src/` calls them —
  `Memory/deferred/issued-invoices-cannot-be-corrected-from-the-browser.md`.
- Payment edit/delete, one-payment-across-several-invoices, Invoices-list stat cards ("—" by design), SMS.
- Two Jobs reminder gaps: "On dates we pick ourselves" and "Once, when the job is finished" raise no reminder
  until a date or closure exists.
- `JobPaymentScheduleDialog` keeps its red "stages must add up" banner until save even after the numbers are
  corrected; the live "Adds up to X of Y" line is right. Jafar has seen it and has not asked for the fix.
- The progress-invoice **print view** was never verified: the print dialog freezes browser control.
- `npx supabase gen types` cannot run here, so new RPCs are hand-added to `database.types.ts`.

## Live test data (Raad LTD, org 18f0d717-904e-48d8-bd99-9df7e3844cda)

- Job #14 fully billed: Deposit → Draft #18 ($500, $400 deposit applied, $100 balance), Final → Draft #19
  ($376.65). Both still Draft.
- Unbilled schedules for testing: Job #1 ($20,000/$20,000/$26,500 fixed), Job #13 (33.33/33.33/33.34 %).
- **Job #2 "Recurring Lawn Care Test" is `fixed_per_period`**, so it will NOT show the per-visit pricing section.
- Leftover Session-B drafts #16 ($75) and #17 ($200) — harmless; delete only with Jafar's OK.
- Invoice #5 "D2 refusal test" carries append-only test state; remove only by reversal, with Jafar's OK.

## Notes

- Local migration filenames vs remote versions do not match — existing convention.
- Repo-wide CRLF drift on ~300 `src/` files — never stage it. Skill-dir edits never staged with features.
- pgTAP runs against the remote project as one rolled-back transaction. `finish()` emits rows only on
  failure, and MCP returns the last statement that produced rows — so a run that comes back with the last
  `is` row instead of a `finish` row passed.

Resume command: `read memory and continue the Invoices campaign`.
