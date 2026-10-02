# D6 Bulk tools — part note

**Done when:** five selected Table rows are reassigned to one person at once; no bulk send, convert, close, or
protected-stage move exists. Roadmap line: `stages/D-move-find-volume.md`.

## Steps

- [x] Database function `pipeline_bulk_update` (migration `20261003140000`, applied — check with
  `supabase migration list --linked`). Each card goes through its own single-card function, up to 50 at once.
- [x] Route `POST /api/pipeline/opportunities/bulk`, `$lib/pipeline/bulk.ts`, tests
- [x] Table: tick boxes, bar with Change owner / Add task / Move to stage (`PipelineTable.svelte`);
  `TaskDialog` takes `submit` for bulk
- [ ] Browser check as the contractor owner on the Table view, then commit and close the part

**Next:** open `/pipeline?view=table` on the local dev server, tick five rows, Change owner, confirm all five
change; try Move to stage on request cards and see the refusal toast; then commit and finish.

For E2 (Task alerts): a bulk Task to someone else must send them one combined alert, not one per card.
