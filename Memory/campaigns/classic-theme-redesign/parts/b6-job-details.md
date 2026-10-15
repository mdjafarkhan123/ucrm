# B6 — Job details

**Stage:** Building 2026-10-15 on branch `claude/classic-b6` (worktree `.worktrees/classic-b6`), reservation
`e584a202764e`. B7 merged to main (`111c402e`) first.

**Agreement:** Approved `classic.pen` frame `bbWOb` "Job details · 1440": main = Job hero `mO4CI`, Visits
`V63HK`, Products and services `U2bpt` (B7), Work log `Dk3cT`; rail = Profit `UGHQz`, Close-out `qZt71`,
Billing `h2RmA`, Instructions `c801kD`, Photos `N7eBQ`, Notes `n3RqB1`. Discount and tax card (B7) stays in
the rail below Billing; the frame omits it. History still swaps in for the rail.

**Jafar's decisions, 2026-10-15** (asked because they change behaviour):
1. Add the header primary "Complete today's visit"; it opens the existing complete-visit steps and shows
   only when a visit is dated today and still open.
2. Visits keep their To be scheduled / Upcoming / Past groups; rows take the Pencil look.
3. Close-out card replaces the Signatures and Work report cards. Collect / Start open the existing dialogs;
   signed copies stay viewable from the signature row; report preview/print/link stay in More.
4. Add a read-only "invoiced so far" figure to the job payload for Billing's "$X of $Y invoiced" bar,
   shown only to readers with price and invoice view rights.

**Slices:** a frame order + rail · b header meta/facts/primary · c visit rows · d Work log tabs (Labor,
Expenses, Checklists) · e Profit card · f Close-out · g Billing (+ reminders, to-bill) + invoiced figure ·
h Instructions/Photos/Notes. Then live-vs-Pencil comparison at 1440/1100 light/dark.

**Built, not yet run in a browser (session 2, 2026-10-15):** `layout/RecordCard` (shared Classic card);
`--classic2-button-surface` token, Classic secondary Button now white (Pencil `P1On1n`); header `meta`, primary
`icon`, fact `icon`; Visits Classic rows + `completeVisitById` + `today` prop; Tabs text `count` +
`variant="card"`; `embedded` Labor/Expenses/Checklists + `jobs/JobWorkLog`; `jobs/JobProfitCard` (no margin
while open, as before); `jobs/JobCloseOutCard` hosting `variant="row"` of JobSignaturesCard and
JobWorkReportCard; Classic markup in JobBillingCard (new props `invoicedMinor`, `reminders` snippet) and
JobRemindersCard `variant="list"`. Job page: Classic header facts/meta/primary and main order (Visits,
Products, Work log) are wired; **the rail is not wired yet**. Script/markup of the new parts pass the Svelte
autofixer (it cannot parse SCSS). Full `svelte-check` runs out of memory in this worktree.

**Next:**
1. Invoiced figure, no migration: in `api/jobs/[id=uuid]/+server.ts` GET, when `canSeePrice && canSeeInvoiceStatus`,
   read distinct `invoice_id` from `invoice_sources` for the job, call `invoice_money(ids)` (definer; checks
   invoices.view / view_price) and sum `total_minor` of non-voided invoices (check invoice status column first);
   return `invoiced_minor` (null otherwise); add to `JobDetail` type.
2. Wire the Classic rail in `jobs/[id=uuid]/+page.svelte`: history (swaps for Photos + Notes) · JobProfitCard
   (when `costing`) · JobCloseOutCard (bind `workReport` to the page's `workReportCard`; it replaces Signatures,
   Work report, QuoteSummaryCard and JobCostingCard in Classic) · JobBillingCard with `reminders` =
   JobRemindersCard variant list · VisitsToBill/PeriodsToBill · RecordAdjustmentsCard · Instructions RecordCard
   (rail, pencil, one row per line from `instructionLines`, Textarea when editing; show when editable or filled)
   · RecordFilesCard · Notes. Remove unused `pointIcon`/`RecordCard` imports if left unused.
3. Classic look for Photos (RecordFilesCard grid) and Notes (NotesPanel) per Pencil `N7eBQ`/`n3RqB1`.
4. Update design-classic/recipe for `button-surface`; run the app, compare with Pencil exports at 1440/1100
   light/dark, check Botanical preview unchanged, prettier/eslint on changed files, then merge to main.

**Known differences left on purpose:** visit row keeps its ··· menu (Pencil shows chevron/pencil); Profit card
shows no margin pill while a one-off job is open; Instructions use one neutral icon per line.
