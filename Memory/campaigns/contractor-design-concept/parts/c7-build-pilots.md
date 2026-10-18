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

## Job details — in progress

Built and partly reviewed; the open differences and the next steps are in `parts/c7b-job-details-build.md`.

## Next

Finish Job details (`parts/c7b-job-details-build.md`), merge to main, then build New job (`parts/c5-new-job.md`).
