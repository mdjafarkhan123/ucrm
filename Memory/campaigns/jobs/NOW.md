# Jobs: Current Checkpoint

- Goal: Build simpler contractor Jobs and Visits without losing proven Jobber behavior.
- State: 15e (Work Report) complete and committed 2026-09-08 (commit `1b442f3`). Full click-through
  browser-verified as Contractor Owner on a real job: empty state, edit dialog (toggles, signature select,
  summary, photo grid, checklist checkboxes, empty states), toggle dependency, save → "Ready to share", `···`
  menu gains Preview/Print/Copy link once `has_content`, internal preview (no chrome), public `/w/<token>`
  link (no console errors). Drawn signature image intentionally text-only on the public page.

## Exact next action

**Scope 15f** — "Deliver offline field-record queue, sync and recovery" (notes/checklist answers save
locally, photos queue, device-only vs synced state explicit, retries don't duplicate, conflicts/interrupted
uploads/reconnect verified). This is a new architectural surface (offline storage, sync, conflict handling)
with no prior design in this campaign — per CLAUDE.md rule 2/3, research how this is proven to work
(e.g. IndexedDB + background sync patterns) and present the plan to Jafar before writing any code.

## Pointers

- Roadmap: `Memory/campaigns/jobs/ROADMAP.md` — 15f depends on 15b–15e (all complete); 15g (permissions/
  journeys/mobile/performance verification) follows.
- Work Report precedents worth reusing for 15f's UI: `JobWorkReportCard.svelte`, `EditJobReportDialog.svelte`,
  `report-api.ts` (TanStack Query patterns for Job sub-resources).

Resume command: `read memory and continue the Jobs campaign`.
