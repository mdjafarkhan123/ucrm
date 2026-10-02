# Pipeline upgrade — stage G: final proof

Approved by Jafar 2026-10-01. Checks the whole plan
`docs/sales-pipeline-behavior-contract.md` after stages A–F.

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| G1 Speed at volume | The board, search, table, and reports measured with a large fake organization, and anything slow fixed (`performance-review` verification branch) | A–F | The measured numbers are written down with the volume they were taken at, and no capacity claim goes beyond them | Done 2026-10-02 — `docs/sales-pipeline-performance-verification.md` |
| G2 Full walk-through | Every plan rule checked with each role login on desktop and phone, then Jafar's own browser tour | G1 | Every rule in the plan is ticked or has a fix; Jafar finishes the tour with no open problem | Not started |

Carried from stage A (design in `docs/adr/0004-pipeline-custom-stages-anchor-to-protected-stages.md`):

- The database rules for moving cards among custom stages (A2), switching a stage off (A3), and on-hold
  stages (A4) were proven on the live database in rolled-back runs only. G1 or G2 should add pgTAP files
  for them, and run the pgTAP edit in `pipeline_unified_board_and_presentation_setting.sql` on a fresh
  rebuild — it has never been run there.
- Found in B2, for G2: the value, owner, Task, and Note commands do not refuse a closed record when called
  directly with its id (no screen offers it). A frozen Won, Lost, or Direct job value should not be editable.
- B1 and B2's database rules (Request-to-Job Won, Direct job) were proven on the live database and in the
  browser only; they need pgTAP files too.
- From C1: the `next_task_due_on` trigger needs a pgTAP file.
- Raad LTD's test data: one enabled custom stage, "Waiting on customer" (Quotes, after Awaiting response),
  switched to on hold and holding one card with a Task due 2026-10-15; two switched-off stages remain from
  A3's check.
- From F2 (Conversion tab on `/pipeline/outcomes?view=conversion`), for G2: the phone view, and a member
  without money or without every-client access, were not checked in the browser. Waiting on Jafar: approve
  adding F2's counting rules to the plan (rates divide closed work only; a Request and its Quote count once;
  archived-without-Lost counts as not won).
- From G1, for G2: two pgTAP files are stale and fail before their first test
  (`pipeline_quote_board_read_model.sql`, `pipeline_unified_board_and_presentation_setting.sql`: the board
  now needs today's date for the Task order). The browser and the phone view were not speed-profiled.
