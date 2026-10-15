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

**Progress 2026-10-15 (work in progress, not yet checked or run):** new `layout/RecordCard` (shared Classic
card); `--classic2-button-surface` token + Classic secondary Button now white (Pencil `P1On1n`); header `meta`,
primary `icon`, fact `icon` props; Visits Classic rows + `completeVisitById` + `today` prop; Tabs `count` may be
text, `variant="card"`; `embedded` mode on Labor/Expenses/Checklists; new `jobs/JobWorkLog.svelte`.
Nothing is wired into the job page yet, and no svelte-check/lint/browser run has happened.

**Next:** run svelte autofixer + focused check on the changed files; wire the Classic branch in
`jobs/[id=uuid]/+page.svelte` (slice a + header facts Schedule/Crew/Time on job/Job total, meta "Multi-day ·
N visits", primary from `organization_today` visit); then slices e–h; update design-classic/recipe for the
new token; compare with Pencil exports at 1440/1100 light/dark.
