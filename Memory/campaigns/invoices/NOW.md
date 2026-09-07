# Invoices: Current Checkpoint

- Goal: Jobber-grounded invoicing and manual collection.
- Parts 1–9 CLOSED + committed. **Part 5c is the only remaining part**; 5c-1…5c-4 are CLOSED and
  browser-verified. Approved scope and performance verdict: `docs/invoice-part-5c-plan.md` — do not re-derive.
- **5c-5 is split across sessions on Jafar's instruction (2026-09-07):**
  - **5c-5a — visit-line editing. BUILT + committed.**
  - **5c-5b — invoice seeding from visit lines. BUILT + committed 2026-09-07.**
  - **5c-5c — the integrated find-only browser pass. RAN 2026-09-07; 3 findings (bug log below).**
- 5c-5a and 5c-5b are **committed** (`Invoices 5c-5: a visit bills what that visit did`) on branch
  `schedule-5b-visits-card`. Stage named files only; never stage the repo-wide CRLF drift.

## Next action

**BUG 1 is DONE + committed. BUG 2 and BUG 3 are a fresh session (Jafar, 2026-09-07).** Resume with
`read memory and continue the Invoices campaign`.

**BUG 1 (money) — DONE, committed `863a96c`, browser-verified.** `refreshAll()` in `JobVisitsSection.svelte`
now `removeQueries` the `['jobs','visit-lines',jobId]` keyset instead of invalidating, so the "Invoice now"
prompt / ready-to-bill card / composer cold-fetch the visit's real subtotal. Verified warm on "5b-4
Per-Visit Verify": edit a visit to qty 2 ($100) → complete → prompt, card and composer all $100, no reload.
No console errors.

### Next session — BUG 2, then BUG 3

Jafar's decisions: BUG 2 = **block**, backend-authoritative; BUG 3 = **carry the override**, atomically in
one backend op if practical, else split to its own follow-up (do not keep current behaviour).

**BUG 2 — block "Mark Incomplete" on a visit that is on an invoice.**
- New migration `20260908150000_job_visit_uncomplete_blocks_invoiced.sql`: `create or replace
  public.uncomplete_job_visit` (currently in `20260903120000_jobs_visit_completion_and_lifecycle.sql`,
  §3) adding, right after the visit is fetched, a refusal `using errcode = 'P0410'` when
  `exists (select 1 from public.invoice_sources where organization_id = target_organization_id and
  visit_id = target_visit_id and source_kind = 'visit')` — the exact predicate
  `replace_job_visit_line_items` uses (migration `20260908130000` ~line 298). Indexed already
  (`invoice_sources_visit_unique_idx`). D4 keeps the claim through void, so any claim row = locked.
- No route/error-map change: `uncomplete/+server.ts` already routes through `scheduleVisitError`, which
  already maps `P0410` → `{ error: message, reason: 'locked' }` (409).
- Client (`JobVisitsSection.svelte`): in `rowMenuItems`, only push "Mark Incomplete" when
  `!(canInvoiceVisits && visit.invoiced)` (`visit.invoiced` is only trustworthy when `canInvoiceVisits`).
  In `handleUncomplete`, add `await refreshAll()` when `err.reason === 'locked'` (it does not refresh on
  error today).
- pgTAP: extend `supabase/tests/database/invoice_visit_line_commands.sql` (currently `plan(31)`). Mark
  fixture visit `d5600000-…-03` completed (`completed_at = now()`), which is safe — `job_visit_lines`
  lock_reason stays `invoiced`, `replace_job_visit_line_items` still throws `P0410`, and
  `job_batch_billing_payload` excludes claimed visits (`…140000` line 72) so the "2 sources" assertion
  holds. Add, just before `select * from finish()`: `throws_ok` `P0410` for `uncomplete_job_visit` on
  `…-03` (billed) and a positive `uncomplete_job_visit` on `…-02` (completed, not billed).
- Run `get_advisors` + this suite after applying.

**BUG 3 — Duplicate drops the source visit's line override.** `duplicateVisit` in `JobVisitsSection.svelte`
builds an `AddVisitInput` (schedule fields only); `addJobVisits` returns `visit_ids`. No dedicated duplicate
command today — decide atomic backend duplicate vs a scoped follow-up. Assess after BUG 2.

## 5c-5c test residue on "5b-4 Per-Visit Verify" (`138844e5-…`, org Raad LTD, `18f0d717-…`)

- Sep 15 visit: override $100, completed, billed to **Draft #20**.
- Sep 22 visit: override qty 3 = $165, **completed**, not billed — on the ready-to-bill list.
- Sep 29 visit: override qty 2 = $100, **completed**, not billed — added + used for the BUG 1 warm re-test.
- Several orphan "Sep 7 · Due today · Per visit" reminders on the job (BUG 2 side-effect + completions).
- No invoice was created from either uncompleted-visit prompt. Draft #20 left in place (delete needs
  Jafar's OK).

Then finish the parts of the plan's 5c-5 checklist that 5c-5c did not cover (see bug log "Not done this
pass"): the full progress/installment journeys re-run and the customer-facing frozen progress output.

When BUG 1 is fixed and the completion gate passes on the **warm** path too, 5c-5 → 5c → the Invoices
campaign can close.

## 5c-5c bug log

Pass started 2026-09-07. Test job: **"5b-4 Per-Visit Verify"** (`138844e5-…`, org Raad LTD),
`recurring` / `per_visit`, job line "Lawn mowing" 1 × $50. Added visits Sep 15 + Sep 22. Sep 15 given a
per-visit override qty 2 = $100, completed, and billed to Draft invoice **#20** ($100, source_kind=visit).
Backend verified correct end to end (`private.job_visit_effective_lines`, `/api/jobs/[id]/visit-lines`,
`invoice_sources` all report $100).

### BUG 1 — stale cache: a just-saved visit override does not reach the "Invoice now" prompt / ready-to-bill card / composer until reload (MONEY)

Steps: on a `per_visit` job, open a future visit → Edit → change a line qty (dialog fetched
`jobVisitLinesKey` while it still held the job's lines) → Save visit → immediately kebab → Mark Complete.
Expected: the "Visit completed" prompt, the "Visits ready to bill" card and (after "Invoice now") the
composer all show the visit's new subtotal. Actual: all three showed the **pre-override** figure ($50, not
$100). "Invoice now" → composer seeded qty 1 / $50; clicking Save Invoice would have billed $50 for a $100
visit. A hard reload of any of those surfaces then shows the correct $100 (cold fetch is right; only the
warm in-session path is wrong). Re-completing the visit *after* the Edit dialog had refreshed the cache
showed the correct $100 — confirms it is purely the TanStack entry, not the backend.
Likely cause: `JobVisitsSection.refreshAll()` invalidates `['jobs','visit-lines',jobId]` but at
`saveEdit` time `editVisit` is already null so that query has no active observer → it is marked stale but
not refetched; the prompt query (`staleTime 60s`) and the ready-to-bill card then serve the stale entry,
and the composer's `visitLinesQuery` (`staleTime 30_000`) does the same when reached by in-app `goto`.

### BUG 2 (minor) — an already-billed visit can be uncompleted, then re-offers invoicing + raises a duplicate reminder

Steps: Sep 15 visit already on Draft invoice #20 → kebab → Mark Incomplete (allowed, no warning) → visit
returns to UPCOMING with a full menu incl. Delete → kebab → Mark Complete again. Actual: a **new** "Sep 7
Due today · Per visit" invoice reminder is raised (now shows next to the one already there) and the "Invoice
now" prompt reappears for a visit that is already billed. Saving from that prompt is correctly blocked
("That work has already been billed on another invoice") — so no double invoice — but the flow lets the
user walk all the way to the composer + Save before saying so, and leaves an orphan reminder. Line-pricing
lock is correct: the Edit dialog for the uncompleted-but-invoiced visit shows the pricing table read-only
with "This visit is already on an invoice, so its pricing is fixed."

### BUG 3 (minor) — Duplicate does not carry the visit-line override

Duplicating the Sep 22 visit (which had a 2-line override incl. a visit-only "Edging" line) produced a new
visit with 0 override rows — it falls back to the job's lines. Arguably correct (fresh copy) but worth a
decision; recorded so the fix session decides rather than discovers.

### Passed

- Pricing section appears in the visit Edit dialog **only** for `recurring` + `per_visit`; dialog grows to
  `size="large"` when shown; a `fixed_per_period` recurring job ("Recurring Lawn Care Test" `b6229fd7-…`)
  shows **no** pricing section and stays default size — non-regression holds.
- Qty edit recomputes line total + dialog subtotal live. "Add line item" adds a visit-only priced line
  (`source_job_line_item_id` null); carried job lines keep their provenance id. Subtotal $50→$65 correct.
- Override saved to the one visit only (Sep 22 untouched by the Sep 15 edit, and vice-versa).
- Editing an already-invoiced visit shows the pricing table **read-only** with "This visit is already on an
  invoice, so its pricing is fixed." — 5c-5a lock works.
- Cold-path completion gate (per-visit): ready-to-bill card ($100) → "Create invoice" ($100 selected) →
  composer (qty 2 / $100) → saved **Draft #20** (qty 2, $50 unit, $100 total, `invoice_sources.source_kind
  = visit`). The override reaches exactly its Visit Invoice; card, prompt and invoice agree — **on a cold
  cache** (see BUG 1 for the warm-cache failure).
- Double-bill prevented: re-invoicing an already-billed visit is refused ("That work has already been
  billed on another invoice").
- Progress invoice #18 "Panel upgrade quote — Deposit" renders correctly in **light and dark**: "Payment
  stage: Payment 1 · Deposit", Item total / Due this invoice columns, "$500.00 Due this invoice", the
  schedule-owns-amounts note; balance $100 after deposit. No console errors.
- Dialog keyboard: Escape closes the visit dialog and returns focus to the row's kebab.
- Console: only `[vite] connecting/connected` debug lines on every page checked (job detail, visit dialog,
  invoice composer, invoice detail, invoices list) — **zero errors or warnings**.

### Not done this pass (lower priority — 5c-1…5c-4 already CLOSED + browser-verified)

- The full progress/installment journeys re-run (direct fixed schedule create→open→pay each stage,
  % schedule with residual cents, Quote-carried funded deposit, edit remaining stages after one is linked,
  correction refusal/preview). Only the #18 deposit-stage **render** was re-checked here.
- The **customer-facing** frozen progress-invoice output (needs a public share link).
- Progress-invoice **print view** — still blocked (print dialog freezes browser control), unchanged from
  earlier checkpoints.

### Test data left on "5b-4 Per-Visit Verify" (`138844e5-…`) for the fix session

- Sep 15 visit: override qty 2 ($100), completed, billed to **Draft #20**. Consistent.
- Sep 22 visit: override (Lawn mowing $50 + visit-only "Edging" $15 = $65), **not** completed/billed —
  ready-made for re-testing BUG 1's cold vs warm path.
- One orphan "Sep 7 · Due today · Per visit" invoice reminder on the job (BUG 2 side-effect) — left as
  evidence.
- Draft #20 left in place (delete needs Jafar's OK per house rule).

### Environment note (not a product bug)

The dev app over the Cloudflare tunnel is slow: nearly every action needs a ~4 s wait before a screenshot
succeeds ("renderer may be frozen"), and job-detail cold loads take 8–12 s. Consistent with the plan's
"planner picks seq scans on a dozen rows" — real data / `EXPLAIN` still owed.

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
