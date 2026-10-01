# A4 — On hold

**Campaign:** pipeline-upgrade · **Plan:** `docs/sales-pipeline-behavior-contract.md` § First-release board, "On hold is an ordinary custom follow-up stage"
**Code:** `main`
**Done when:** Moving a card to On hold with no future Task is refused and offers to add one; with one it moves and the Open count is unchanged

## Steps

- [x] Jafar chose how a stage becomes on hold: a switch on any custom stage (HubSpot's per-stage rule), not one ready-made stage
- [x] Migration written: `supabase/migrations/20261001234000_pipeline_on_hold_stages.sql`
- [ ] Apply the migration and prove the rules in a rolled-back run
- [ ] Settings → Pipeline: the switch on each custom stage, saved with the list
- [ ] Board: a refused move opens the Task dialog, then finishes the move once a future Task is saved
- [ ] Browser check of the done-check, then close the part

## Next

Apply the migration, then build the Settings switch (`PipelineStageList.svelte`, the settings page payload,
`settings.schema.ts`, `enabledCustomStages`) and the board prompt (`PipelineColumn.svelte` `performPlace`,
`TaskDialog.svelte`, the placement route).

## Outside actions

- Apply migration `20261001234000` — check: `supabase migration list --linked` shows 20261001234000 on the
  remote, and `pipeline_custom_stages` has a `requires_future_task` column — pending

## Notes

- "Future" means an open Task due after today on the organization's own calendar; a Task due today does not
  count. The rule is checked only on the way in.
- The refusal is a `check_violation` carrying the hint `needs_future_task`; the board reads that hint to
  offer the Task dialog.
