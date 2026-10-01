# A3 — Switch a stage off safely

**Campaign:** pipeline-upgrade · **Plan:** `docs/sales-pipeline-behavior-contract.md` § First-release board, "Disable is the normal removal action"
**Code:** `main`
**Done when:** Disabling a stage holding three cards asks where they go, moves all three, and removes the
column; an earlier move still shows the old stage name.

## Steps

- [x] Migration written and rehearsed on the live database in a rolled-back run (20,000 cards)
- [ ] Apply the migration and regenerate `src/lib/database.types.ts` (`npm run db:types`)
- [ ] API: card-count read and switch-off route under `src/routes/api/settings/pipeline/stages/[id]/`
- [ ] Settings → Pipeline: a remove button on each saved stage opens a dialog that asks where its cards go
- [ ] Tests, browser check of the done-check, ADR 0004 gets the A3 decisions; close the part

## Next

Apply `supabase/migrations/20261001230000_pipeline_custom_stage_disable.sql` if the outcome check below
says it is not applied, then build the API step.

## Outside actions

- Apply migration `20261001230000` — check: function `public.disable_pipeline_custom_stage` exists and
  `supabase migration list --linked` shows 20261001230000 on the remote side — pending

## Notes

- Cards can go to another custom stage of the same section, or "back to their built-in stage". A stage
  holding cards is never switched off without one of the two being chosen (`needs_destination`).
- Switching off is its own immediate action, not part of Save. The button is offered only while the form
  has no unsaved changes, because it reloads the form afterwards.
- Moving 20,000 cards took about 10 seconds in rehearsal; a logged-in request is cut off at 8, and then
  nothing moves. Tell Jafar the honest ceiling (about 15,000 cards in one stage) in the report.
