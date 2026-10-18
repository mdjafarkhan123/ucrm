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

## Next

Start Home: read `parts/c2-home.md`, screenshot `rKrbu`, read the live dashboard components, build, compare.
