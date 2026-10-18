# C7 — Build Home, Job details and New job

**Campaign:** contractor-design-concept · **Plan:** `docs/contractor-design-concept-behavior-contract.md` § First version 4
**Decision (Jafar, 2026-10-18):** build approved screens now, screen by screen, before drawing more. Order and one
session each: **Home → Job details → New job**; then back to drawing Schedule (C5).
**Done when (each screen):** the live page matches its Pencil frame side by side (`docs/screen-check.md`, memory
"compare live with Pencil"), its main journey works once on the live app, the checklist Built tick is ✅, and
the Pencil tidy-up in `docs/pencil-workflow.md` step 6 is done.

## Screens

| Screen | Pencil frame | Approval note | Live code |
| --- | --- | --- | --- |
| Home | `rKrbu` | `parts/c2-home.md` | `src/routes/(app)/dashboard/+page.svelte`, `src/lib/components/dashboard/*` |
| Job details | `tNdkX`, edit mode `jFBRB` | `parts/c4-job-details.md` | `src/routes/(app)/jobs/[id=uuid]/+page.svelte`, `src/lib/components/jobs/*` |
| New job | `zUFDO`, states `TVQzs` | `parts/c5-new-job.md` | `src/routes/(app)/jobs/new/+page.svelte`, `jobs/JobForm`, `jobs/JobVisitsBlock`, `jobs/RecurrenceFields` |

## Carry into each build

- Restyle only; keep every live field and behaviour. The one approved behaviour change: Job details products,
  discount and tax edit together with one Save (`parts/c4-job-details.md`).
- Shared parts first: one CardHeader replaces the Card / RailCard / SectionBlock headers (Job details build).
  New job adds the segmented switch, checkbox, people pick chips and floating save bar to the Parts board, the
  design modules and code together.
- Home: Today schedule "In progress" and the other "asked, not yet answered" points in `parts/c2-home.md` stay as
  drawn unless Jafar says otherwise.
- New tokens go into `_variables.scss`, Pencil and the design skill in one commit.
- Work in a temporary branch and worktree, claimed (`docs/agent-concurrency.md`); type check once at the end.

## Home — built 2026-10-18

Matches `rKrbu` side by side at 1440 light, dark and 1100; Clock in/out pressed live (loading, no double
press). New shared part `ui/CardHeader`; `ui/StatusBadge` gained `size="small"` (the concept pill);
`--radius-circle` is 999px like Pencil. Field-worker Home keeps today's look (not drawn).

**Left out, need data the app lacks** (all in the approved Home plan; Jafar to decide when to build):
"In progress" on the schedule, money per schedule row and in the schedule hint, money on Quotes and Jobs To do
lines and their card hints, "Upcoming work" in Business performance. Also: Money owed shows not-due/overdue
only (the 1–30… buckets stay in the bar's spoken label); the setup strip keeps today's delivery line.

## Job details — built 2026-10-18 (claude, taking over Codex's branch `codex/concept-job-details`)

Page matches `tNdkX` side by side at desktop width on Raad LTD jobs #25 and #29: header (job tile, status,
"Job #· Type", boxed client with call/text/email, facts column, step strip), Visits → Instructions →
Checklists → Products → Billing (with invoice reminders inside) → Labor → Expenses, and the rail (Job total
card with profit bar, Notes, Photos and files, Signatures, Work report). Main journey proven live: edit the
quantity, one "Save job pricing", total went $150 → $300 and back. New shared parts: concept look on
`WorkRecordHeader`, `ClientSummaryCard`, `RecordFactsList`, `LifecycleTrack`; rail and main columns no longer
squeeze their cards (`RecordDetailLayout`).

**Left out, need data the app lacks:** "Client since 2024 · 3 jobs" under the client name, "Started Oct 14" in
the header line, "next today 9:00 AM" in the Visits hint, "From quote #318" (live says "From a quote").
**Review 2026-10-18 (second session, branch `claude/job-details-review`):** the first build did not match `tNdkX`
side by side. Fixed to match on job #20 (visits, labor, expense) at 1440 light and dark: header spans both
columns (History · More · green Create invoice with icon; quiet title pencil; long track lines), Visits rows
(day tile, title under the time, grey crew initials, white Start timer, today tint, Past hint), Money divider,
Products table (40 thumb or kind tile, Product/Service pill, bold totals, discount and tax rows), Billing
(flush sections, card-tiled stages, bell-tiled reminders), Labor and Expenses rows with grey footer totals,
"•••" row menus, rail button overflow. Expense rows show a receipt tile, not the receipt photo (photo needs
data the list lacks).

**Still not matching / not done:** edit mode `jFBRB` (live is the old editor: floating labels, discount and
tax as pencil rows, no in-card Save bar) — its own session; empty states (Instructions, Checklists, Work
report) are big dashed boxes not drawn in Pencil; Notes shows the live inline composer, the drawing a "+"
button; the pop-ups; Pencil tidy-up (`docs/pencil-workflow.md` step 6).

**Jafar 2026-10-18: "fix all", then pause; the next session does the rest and pushes to main.** Branch
`claude/job-details-review` (worktree `.worktrees/job-details-review`, pushed) holds 2 commits not yet on main.
Its quick test run found 2 failures in `JobVisitsSection.svelte.spec.ts` ("recurrence summary with count",
"running timer with Stop … no Start on the others") — likely the new team-names query / row layout; unconfirmed.
Jafar: no long tests (no svelte-check, no browser-mode spec runs) until the campaign ends.

## Next

In the worktree: (1) fix the 2 failing visit checks (read the spec; don't run long suites); (2) rebuild the
Products edit mode to `jFBRB`; (3) "fix all" covers the open points too — draw compact empty states in Pencil for
Instructions, Checklists and Work report for Jafar's yes, and match Notes to the drawing's "+" (confirm with
Jafar if keeping the inline composer seems better); (4) screen check against `tNdkX`/`jFBRB`; (5) merge to main
and push. Then build New job (`parts/c5-new-job.md`).
