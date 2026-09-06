# Invoices Part 5c — implementation plan

Status: **Planning complete 2026-09-06. 5c-1 and 5c-2 built and committed; 5c-2 awaits its browser pass. 5c-3 is next.**

This closes the last unplanned Invoice campaign part: one-off Job payment schedules, progress Invoices created from one installment, and recurring per-visit quantities. Jobber is the sole product reference. Existing Quote, Job, Invoice, ledger, correction-chain, and source-claim rules remain authoritative.

## Final behavior

### One-off Job payment schedules

- A one-off Job has either whole-job billing or one ordered payment schedule, never both.
- The schedule uses one mode across all rows: fixed minor-unit amounts or percentage basis points. It contains 2–12 named installments and reconciles exactly to the current Job total. **Confirmed by Jafar 2026-09-06: Jobber is the source of truth — a payment schedule is one mode and represents several invoices; the strict rule stands.**
- **Fixed schedules must reconcile exactly to the Job total or the whole save is refused. Largest-remainder reconciliation applies only to percentage schedules**, spreading residual minor units across rows by descending remainder, ties by position.
- **Quote schedule validation is aligned to the same strict rule as part of 5c-1** (Jafar authorized the shipped-code change 2026-09-06): a Quote `deposit_type = 'schedule'` needs 2–12 installments in one mode. `deposit_type = 'deposit_only'` is unchanged — it stays a single required deposit and is not a payment schedule. Data check 2026-09-06 (Raad LTD, the only org with schedule data): no mixed-mode rows exist; every single-stage row is `deposit_only`; the one real `schedule` Quote (#1) is already 2-stage single-mode. Aligning the rule reinterprets no existing row.
- A converted approved Quote copies its frozen schedule, descriptions, order, value mode, values, and first-installment deposit identity into the Job. A Job created without a Quote can add the same schedule directly.
- A schedule row has no due date. It is a contractor-named work stage. Staff explicitly create its Invoice when the stage is ready; the Invoice's existing payment term produces its due date.
- The Job Billing area shows every stage as Remaining, Draft, Awaiting payment, or Paid, plus Invoice number, total, balance, and an action to create or open the linked Invoice. Full schedule truth stays on the Job.
- Any installment with a linked Invoice is locked, including Draft. Unlinked rows may be added, reordered, edited, or removed only if the complete remaining schedule still reconciles with the Job total after preserving every locked amount.
- Switching a Job away from a payment schedule is allowed only before any installment has a linked Invoice. Editing Job scope never rewrites an Invoice or automatically redistributes remaining stages.

### Progress Invoice

- Create opens the existing Invoice composer with the selected installment, Job, Client, Property, description, and progress-priced lines already seeded.
- The installment amount is fixed by the Job. The composer allows subject, payment terms, issue date, message, attachments, and other non-money fields; line quantities, unit prices, discount, tax, add/remove, and reorder are read-only for this Invoice.
- Each progress line retains the Job line's full customer value in `progress_original_amount_minor` and stores its allocated amount due in the normal Invoice line total. Allocate the installment total proportionally across the Job's final priced line totals with a deterministic largest-remainder pass, breaking equal remainders by Job line position. This preserves the exact installment total without inventing fractional cents.
- The customer document labels the two figures **Item total** and **Due this invoice**. It identifies the current stage. It does not show future installment values because Jobber's official article conflicts on that point.
- The create command locks the Job and installment, checks the current amount, creates the Draft, and claims the installment in one transaction. A retry returns the first Invoice; a competing request cannot create a second one.
- Link `invoice_sources` to the installment row while retaining installment number in the frozen source identity. Ordinary Void remains excluded. Issued corrections use the approved D3 retained replacement chain; later installments and allocations do not move implicitly.

### Deposit treatment

- A required first Quote deposit remains an immutable receipt linked to the approved Quote version. Copying the schedule to the Job does not create money.
- When the matching first-stage Invoice is created, apply the available live deposit to that Invoice once, up to the stage amount, in the same transaction. A fully funded first-stage Draft shows zero due; a partial available deposit reduces its balance without changing the scheduled amount.
- Reversal, movement, refund, correction, and Void consequences continue through the existing ledger commands. No second receipt is created and no automatic charge is attempted.

### Per-visit quantities

- This applies only to recurring Jobs with `price_basis = 'per_visit'`.
- Each Visit starts with the Job line quantities and can override a quantity, omit a Job line, or add a Visit-only priced line. Unit customer price, cost, taxability, name, and description snapshot from the Job/catalog at the time the Visit line is saved; later Job changes do not rewrite a completed Visit.
- A Visit Invoice uses that Visit's effective lines and quantities. Fixed-per-period Jobs continue using Job lines and ignore Visit overrides for billing.
- Once a Visit is completed or invoiced, its priced lines are locked. Uncompleting an uninvoiced Visit restores editing; an invoiced Visit keeps its historical billing snapshot.

## Delivery sequence

### 5c-1 — Money fixtures and Job-owned records

Add tenant-owned Job installment and Visit-line records, using existing Job money types and organization-scoped foreign keys. Add the installment foreign key to `invoice_sources` (0 existing `installment` claims, so a strict shape check is safe). Extend Quote-to-Job conversion to copy the approved schedule atomically and idempotently.

One database function owns schedule pricing and validation. It must prove fixed and percentage totals, deterministic residual cents (percentage schedules only), discounts, taxable/non-taxable mixtures, a fully/partially funded first stage, changed totals with locked rows, and totals too small to cover locked installments. Direct table writes stay unavailable to browser roles; public commands enforce membership, permission, Job type/basis, revision, and organization ownership. Money columns get no `authenticated` SELECT grant — a `jobs.view_price`-gated reader exposes amounts, matching the Job contract.

Also in 5c-1: align the shipped Quote schedule command (`public.set_quote_draft_deposit` in `20260821104331_...`) and its pgTAP so a `schedule` deposit type enforces one mode across 2–12 installments. Leave `deposit_only` untouched.

Completion gate: pgTAP proves tenant isolation, valid shapes, Quote copying, exact conservation, deposit reuse, stale-write refusal, immutable linked rows, no cross-organization references, and the tightened Quote schedule rule with `deposit_only` unaffected.

### 5c-2 — Job schedule commands and read model

Add one validated `/api/jobs/[id]/payment-schedule` write route and matching Job API method. The command replaces only the editable part of the schedule under an expected Job revision while preserving linked rows. Extend the existing Job detail read model with a price-gated schedule projection and derived Invoice/payment status; do not store duplicate status.

Extend Billing setup rather than creating another settings surface. Reuse the Quote schedule editor behavior and existing Dialog, inputs, money controls, Job Billing card, and TanStack Job detail key. Saving invalidates Job detail, Job history, Job lists/counts, billable-work, and ready-to-bill queries affected by the change.

Completion gate: fixed and percentage schedules can be created and edited on an eligible one-off Job, converted schedules appear unchanged, linked rows are visibly locked, and no money leaks without `jobs.view_price`.

### 5c-3 — Atomic installment-to-Invoice handoff

Extend the billable-work read model and Invoice seed route with installment identity and server-calculated progress lines. Add an installment-specific create command or extend the existing source-aware create command only where the invariant can remain clear: lock Job → installment → Quote deposit receipt/allocation → Invoice in the established order, then create and claim once.

The existing Invoice composer renders its money controls read-only for an installment seed and explains that the Job schedule owns the amount. Saving creates a normal Draft. After save, invalidate the Job, Invoice detail/list/counts, billable-work, and ready-to-bill keys.

Completion gate: two concurrent creates yield one Draft; retries return it; every installment bills once; the correct deposit is applied once; Draft deletion does not make the installment independently billable; and opening a linked row reaches its Invoice.

### 5c-4 — Progress documents and correction integration

Extend staff and customer Invoice projections/components to show current-stage context, Item total, and Due this invoice only for progress bills. Keep ordinary Invoice rendering unchanged. Finish the existing progress-Void exclusion with the installment foreign key and verify D3 preview/activation against a real schedule difference.

Completion gate: frozen customer output survives later Job edits; price-withheld staff reads contain no progress amounts; ordinary Void refuses progress bills; correction retains the original, activates one replacement, preserves allocations, and does not alter later stages.

### 5c-5 — Per-visit quantities and integrated verification

Add validated Visit-line read/write commands and extend the existing Visit editor. Keep the interaction inside the existing Visit dialog and use the shared products/services controls where their behavior matches. Update Visit invoice seeding to use effective Visit lines rather than copying Job lines.

Browser-verify the complete journeys in light and dark mode: direct fixed schedule, percentage schedule with residual cents, Quote-carried funded deposit, create/open/pay each stage, edit remaining stages after one is linked, correction refusal/preview, customized Visit quantities, and fixed-period non-regression. Verify keyboard/focus behavior for dialogs and no console errors.

Completion gate: the Invoice campaign's eighth journey—progress invoicing—passes end to end, plus a per-visit override reaches exactly its Visit Invoice.

## Performance design verdict

**Growth path:** installments per Job, Visit lines per Visit, and lookup of linked Invoice/payment facts. All interactive reads are scoped to one Job or one selected Visit; writes replace a bounded user-edited collection.

**Workload contract:** preserve existing product bounds of 2–12 installments, up to 100 Job lines, and one selected Job/Visit per editor action. Traffic and simultaneous sessions do not justify a cache, queue, materialized view, or new service. Correctness requires short transactions, stable lock order, revision checks, idempotency, and tenant isolation.

**Chosen shape:** normalized child rows, organization-scoped foreign keys, indexes supporting Job/detail order and installment-to-Invoice lookup, live derived statuses, and bounded JSON projections through existing Supabase RPC/API patterns. TanStack Query remains the only browser server-state cache.

**Failure behavior:** stale edits return conflict and require refresh; invalid totals refuse the whole save; concurrent invoice creation queues on the same Job/installment and returns the winning Invoice on replay; every command commits fully or rolls back.

**Verification required:** `EXPLAIN (ANALYZE, BUFFERS)` for Job schedule detail, installment uniqueness/linked-Invoice lookup, and Visit effective-line reads using representative skew; confirm indexed plans and bounded returned bytes. Record concurrent-create latency and lock waits. This establishes only these bounded paths, not 40,000-user capacity.

**Overall:** ready to implement. No added cache, queue, dependency, Realtime subscription, or infrastructure change.

## Required checks during implementation

- Follow the imperative migration workflow and create migration files through the Supabase CLI; review current Supabase changelog items again before SQL starts.
- Run database advisors and all relevant pgTAP suites after each coherent database part.
- Validate every new `POST`/`PATCH` body with Zod before database access.
- Run Svelte autofixer on every changed Svelte file, then `npm run check`, targeted ESLint/Prettier, and meaningful unit/browser checks.
- Do not commit or stage unrelated existing worktree changes.

## Explicit exclusions

Automatic milestone detection, installment calendar dates, automatic charging, saved payment methods, online processors, arbitrary customer partial payments, batch progress invoicing, future-stage values on the customer Invoice, new Invoice statuses, and GHL behavior are outside Part 5c.
