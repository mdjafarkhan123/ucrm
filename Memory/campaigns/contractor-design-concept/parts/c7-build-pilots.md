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

Matches `rKrbu` at 1440 light, dark and 1100; Clock in/out proven live. New shared `ui/CardHeader`, `StatusBadge`
`size="small"`. Field-worker Home keeps today's look. **Left out, need data the app lacks** (Jafar decides when):
"In progress" and money on schedule rows, money on Quotes/Jobs To do lines, "Upcoming work"; Money owed shows
not-due/overdue only.

## Job details — view page built 2026-10-18

Matches `tNdkX` side by side at 1440 light and dark (commits `783458bc`, `0988d05f`; checked on Raad LTD jobs
#20, #1, #25, #29, browser clock set to a visit day for the "today" row). Pricing save proven live ($150 → $300
and back). Shared parts given the concept look: `WorkRecordHeader`, `ClientSummaryCard`, `RecordFactsList`,
`LifecycleTrack`, `RecordDetailLayout` (`header` + `concept`), `SectionBlock` flush body, `WorkTimerControl`
`concept`, `ProductsAndServicesBlock` `concept`. No checks run (Jafar: none until the campaign ends).

**Jafar 2026-10-18:** the header card stays inside the scrolling main column with the rail beside it (as the
live app always had), not full width as in `tNdkX`; the rail stays 336px so the step strip fits. Update `tNdkX`
to match at the Pencil tidy-up.
**Left out, need data the app lacks:** "Client since · jobs", "Started Oct 14", "next today 9:00 AM",
"From quote #318", the line under each payment stage, the expense receipt photo (a receipt tile shows).
**Not done yet:** edit mode `jFBRB` (labels above fields, no box per line, kind pill, discount/tax panel in the
totals, card footer Cancel / Save changes; the line editor is shared with Quotes and Requests, so concept-only),
then the Pencil tidy-up. **Decided (Jafar left it to Claude):** row menus switch to "…" app-wide
(`DropdownMenu`); `Avatar` darkens in dark mode.

## Next

Build Job details edit mode (`jFBRB`), do the Pencil tidy-up, then build New job (`parts/c5-new-job.md`).
