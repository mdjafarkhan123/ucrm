# ADR 0004: Pipeline custom stages are anchored to protected stages

## Status

Accepted 2026-10-01, with Pipeline upgrade part A1. Follows the approved
[Pipeline plan](../sales-pipeline-behavior-contract.md), revision 3, and Jobber's Sales Pipeline: up to 25
custom stages, placed inside the Request or the Quote section, built-in stages locked.

## Context

Custom follow-up stages may sit between the seven protected stages, but a protected stage must never be
renamed, reordered, or removed, and a custom stage must never cross the Request/Quote line or go ahead of
its section's first stage. The board also has a collapsed mode in which three protected assessment stages
are drawn as one column.

## Decision

1. **Protected stages stay in code; only custom stages are rows.** `pipeline_custom_stages` holds custom
   stages only. The protected vocabulary and its order remain in `src/lib/pipeline/stages.ts` and the
   database's stage checks. No write to the stage table can reorder or remove a protected stage, because
   there is no row to change.
2. **A custom stage stores the protected stage it follows** (`after_stage`) plus a `position` among custom
   stages. A check ties `after_stage` to the stage's section. The board and Settings both build their
   order from this with `sectionColumns`; on the collapsed board, a stage anchored to any assessment stage
   is drawn after the one Assessment column.
3. **The whole list is saved in one command under the Pipeline settings revision.**
   `save_pipeline_settings` takes every enabled stage in board order with the Assessment toggle. It refuses
   a list that leaves an enabled stage out, so a stale page can never drop a stage by omission; switching a
   stage off is its own action (part A3) using `disabled_at`.
4. **Name uniqueness is an exclusion constraint**, partial on enabled stages and deferrable, so two stages
   can swap names in one save.
5. **A card's custom placement is not part of this table.** It is `opportunities.custom_stage_id` (part
   A2), a reference to a custom stage that sits beside the real `stage`, never in place of it: `stage`
   stays the projection of Request and Quote truth.
6. **The board reads one value, `board_column`.** A stored generated column: the custom stage id as text
   when the card is placed, the real stage otherwise. Every board index and both board readers
   (`pipeline_board_page`, `pipeline_stage_counts`) key on it, so a custom column pages, sorts, filters,
   and counts through the same access paths as a protected one, and a placed card is never also drawn or
   counted under its real stage. Rejected: keeping the indexes on `stage` and adding a second set for
   custom columns — twice the indexes, and a protected column would skip over its placed cards row by row.
7. **A real action wins inside the stage trigger.** `opportunity_apply_stage` clears the placement
   whenever the derived `stage` changes, so no Request, Assessment, or Quote command has to know custom
   stages exist. `pipeline_place_opportunity` is the only writer of a placement; it refuses a stage from
   the other section and does nothing when the card is already there.
8. **`stage_entered_at` means "arrived in the column it is drawn in".** It restarts on a real stage change
   and on a move into, out of, or between custom stages, so the card's age and the default sort stay
   true to the column. The inactivity warning (stage C) must use its own progress clock, because the plan
   says a manual custom move does not reset it.
9. **History is one table.** `opportunity_stage_events` gains `from_custom_stage_id` and
   `to_custom_stage_id`; a custom move is a row whose `from_stage` and `to_stage` are equal.

## Consequences

- Reordering in Settings while the board is collapsed re-anchors that section's stages to the columns
  shown, so a stage that sat between two assessment stages moves to after Assessment completed.
- A custom stage may not take the name of a built-in column in its section; that rule lives in the API
  validation, where the built-in names are.
- Each custom column is one more page request when the board opens, the same as a protected column: up
  to 25 more at the stage limit.
- Anything that reads `opportunity_stage_events` for time in stage must treat a row with equal stages as
  a custom move, not a stage change.
- Switching a stage off (A3) must take the stage row `for update`: `pipeline_place_opportunity` holds it
  `for share`, so the two cannot interleave.
