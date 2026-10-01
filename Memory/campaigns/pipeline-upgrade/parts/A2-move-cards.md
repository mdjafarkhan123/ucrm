# A2 — Move cards in and out

**Campaign:** pipeline-upgrade · **Plan:** `docs/sales-pipeline-behavior-contract.md` § First-release board, "Revision 3 adds section-bound custom follow-up stages"
**Code:** `main`
**Done when:** A Draft quote card goes into "Waiting on customer" and back; publishing that quote lands it in
Awaiting response by itself; a Request card dropped on a Quote-side stage is refused and says why.

## Steps

- [x] Performance design: one `board_column` value per card, the six board indexes re-keyed on it
- [x] Migration written and rehearsed on the live database inside a rolled-back run (20,000 cards)
- [ ] Apply the migration and regenerate `src/lib/database.types.ts` (`npm run db:types`)
- [ ] API: column page accepts a custom stage id; summary counts custom columns; new placement route
- [ ] Board: custom columns load cards, take drops, card menu "Move to…", real-stage badge on placed cards
- [ ] Tests, `performance-review` verification branch, browser check of the done-check
- [ ] ADR 0004 gets the A2 decisions; close the part

## Next

Apply `supabase/migrations/20261001220000_pipeline_custom_stage_placement.sql` if the outcome check below
says it is not applied, then build the API step.

## Outside actions

- Apply migration `20261001220000` — check: `opportunities.custom_stage_id` exists and
  `supabase migration list --linked` shows 20261001220000 on the remote side — pending

## Notes

- A card's age chip restarts when it enters or leaves a custom stage (`stage_entered_at` means "arrived in
  the column it is drawn in"). Tell Jafar in the report.
- Dragging a placed card onto a protected column: its own real stage puts it back; any other runs the usual
  real action from its real stage.
