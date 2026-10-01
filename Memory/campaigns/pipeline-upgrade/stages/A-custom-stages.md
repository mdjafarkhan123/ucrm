# Pipeline upgrade — stage A: custom follow-up stages

Approved by Jafar 2026-10-01. Plan § First-release
board, "Revision 3 adds section-bound custom follow-up stages". Riskiest stage: it changes how a card's column
is decided, which every later board part builds on. A1 and A2 change the board's read path — run the
`performance-review` design branch first.

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| A1 Add custom stages in Settings | Owner or admin adds, renames, and reorders custom stages under Requests or Quotes; the seven protected stages are locked; the new columns show on the board | — | The owner adds "Waiting on customer" under Quotes and it appears as an empty column for everyone; a 26th stage and a repeated name in the same section are refused with a clear message; a sales login cannot change stages | Done 2026-10-01 |
| A2 Move cards in and out | A card moves by drag or menu among custom stages of its own section, in either direction; it cannot cross the Request/Quote line; a real action pulls it to the protected stage; each move is kept in history | A1 | A Draft quote card goes into "Waiting on customer" and back; publishing that quote lands it in Awaiting response by itself; a Request card dropped on a Quote-side stage is refused and says why | Done 2026-10-01 |
| A3 Switch a stage off safely | Disable asks for a destination in the same section and moves every open card; the old name stays in history and reports | A2 | Disabling a stage holding three cards asks where they go, moves all three, and removes the column; an earlier move still shows the old stage name | Done 2026-10-01 |
| A4 On hold | Moving a card to an on-hold stage needs a future Task; the card stays Open and never counts as Lost | A2 | Moving a card to On hold with no future Task is refused and offers to add one; with one it moves and the Open count is unchanged | Not started |

Open for A4, to settle with Jafar when it starts: how a stage becomes "on hold" — a ready-made optional On hold
stage, or a switch on any custom stage.

Carried from A1 and A2 (design in `docs/adr/0004-pipeline-custom-stages-anchor-to-protected-stages.md`):

- No screen shows a card's move history yet, so "an earlier move still shows the old stage name" was
  proven in the database only (the switched-off row keeps its name and its events). Whichever part draws
  that history must read stage names without filtering on `disabled_at`.
- A3's database rules were proven on the live database in a rolled-back run, with no pgTAP file. Stage G
  should add one, with A2's.
- A4: placing goes through `pipeline_place_opportunity` and the board's `performPlace` in
  `PipelineColumn.svelte`; the future-Task rule belongs in that command.
- A card's menu lists every custom stage of its section in one flat list. Stage D's Move button replaces it.
- The Brief still shows only the real stage; it does not say which custom stage the card is in.
- A2's database rules were proven on the live database in rolled-back runs (20,000 cards). No pgTAP file
  covers them, and the pgTAP edit in `pipeline_unified_board_and_presentation_setting.sql` has not been
  run on a fresh rebuild. Stage G should close both.
- Raad LTD has one enabled custom stage, "Waiting on customer" (Quotes, after Awaiting response), holding
  no cards, plus two switched-off ones left by A3's browser check.
