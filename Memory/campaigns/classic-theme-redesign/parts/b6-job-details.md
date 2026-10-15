# B6 — Job details

**Stage:** Done 2026-10-15 on branch `claude/classic-b6` (worktree `.worktrees/classic-b6`), reservation
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

**Built and verified 2026-10-15 (session 3).** Classic job page now follows `bbWOb` top to bottom. Main: header
(meta, four facts with their own icons, "Complete today's visit"), Visits, Products and services, Work log. Rail:
Profit (`costing` only) · Close-out (signature row shows the newest signature plus "N earlier", expandable) ·
Billing with "$X of $Y invoiced" and its reminders list · visits/periods to bill · Discount and tax · Instructions
(one row per line, pencil edits in place) · Photos and files · Notes. History swaps in at the top and hides
Photos and Notes. `GET /api/jobs/[id]` returns `invoiced_minor`: live invoices only (current in each replacement
chain, not voided), drafts included, null without jobs.view_price + invoices.view (+ invoices.create).
NotesPanel and RecordFilesCard take `look="record"` for the Classic card; only the job page opts in, so other
pages and dialogs are unchanged until their own step.

**Fixed on the way:** Add visits styles never applied (scoped parent was in RecordCard); RecordFactsList showed
a calendar for every fact that had its own icon (operator precedence); job Save never refreshed the notes list
(also on main); the composer placeholder was pushed down by the global floating-label placeholder padding.

**Proof:** Playwright at 1440 and 1100, light and dark, owner of Raad LTD, jobs #20 and "Testing job"; compared
with the Pencil export of `bbWOb`. Live journey in Chrome: edit Instructions + stage a note with Enter → save bar
→ Save changes → both stored (note `d669b057…`, test data in the test business) and shown; Cancel discards a
staged note. `svelte-check`: only the pre-existing dev-preview error. Prettier clean. ESLint: three errors left that are
identical on main (two `goto` without resolve, unused `addSaving`). Vitest jobs/work/api: 156 passed. At 1100px
the rail stacks under the main column (existing RecordDetailLayout rule).

**Known differences left on purpose:** visit row keeps its ··· menu and the existing Start timer button (Pencil
shows chevron/pencil); Profit card shows no margin pill while a one-off job is open; Instructions use one neutral
icon per line; a document row keeps its ··· menu instead of a download icon; the Billing pill wraps under the
figure when the amount is long.
