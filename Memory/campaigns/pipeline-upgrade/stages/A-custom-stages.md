# Pipeline upgrade — stage A: custom follow-up stages

DRAFT — waiting for Jafar's approval of the build split (see `parts/3-build-split.md`). Plan § First-release
board, "Revision 3 adds section-bound custom follow-up stages". Riskiest stage: it changes how a card's column
is decided, which every later board part builds on. A1 and A2 change the board's read path — run the
`performance-review` design branch first.

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| A1 Add custom stages in Settings | Owner or admin adds, renames, and reorders custom stages under Requests or Quotes; the seven protected stages are locked; the new columns show on the board | — | The owner adds "Waiting on customer" under Quotes and it appears as an empty column for everyone; a 26th stage and a repeated name in the same section are refused with a clear message; a sales login cannot change stages | Not started |
| A2 Move cards in and out | A card moves by drag or menu among custom stages of its own section, in either direction; it cannot cross the Request/Quote line; a real action pulls it to the protected stage; each move is kept in history | A1 | A Draft quote card goes into "Waiting on customer" and back; publishing that quote lands it in Awaiting response by itself; a Request card dropped on a Quote-side stage is refused and says why | Not started |
| A3 Switch a stage off safely | Disable asks for a destination in the same section and moves every open card; the old name stays in history and reports | A2 | Disabling a stage holding three cards asks where they go, moves all three, and removes the column; an earlier move still shows the old stage name | Not started |
| A4 On hold | Moving a card to an on-hold stage needs a future Task; the card stays Open and never counts as Lost | A2 | Moving a card to On hold with no future Task is refused and offers to add one; with one it moves and the Open count is unchanged | Not started |

Open for A4, to settle with Jafar when it starts: how a stage becomes "on hold" — a ready-made optional On hold
stage, or a switch on any custom stage.
