# Pipeline upgrade — stage G: final proof

Approved by Jafar 2026-10-01. Checks the whole plan
`docs/sales-pipeline-behavior-contract.md` after stages A–F.

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| G1 Speed at volume | The board, search, table, and reports measured with a large fake organization, and anything slow fixed (`performance-review` verification branch) | A–F | The measured numbers are written down with the volume they were taken at, and no capacity claim goes beyond them | Done 2026-10-02 — `docs/sales-pipeline-performance-verification.md` |
| G2 Full walk-through | Every plan rule checked with each role login on desktop and phone, then Jafar's own browser tour | G1 | Every rule in the plan is ticked or has a fix; Jafar finishes the tour with no open problem | Waiting for Jafar's tour; every other check done (`parts/G2-full-walk-through.md`) |

Carried from stage A (design in `docs/adr/0004-pipeline-custom-stages-anchor-to-protected-stages.md`):

- The custom-stage, on-hold, switch-off, Request-to-Job Won, Direct job, and `next_task_due_on` rules now
  have pgTAP files (G2, 2026-10-02), and every Pipeline pgTAP file passes on the local Docker database.
- Found in B2, for G2: the value, owner, Task, and Note commands do not refuse a closed record when called
  directly with its id (no screen offers it). A frozen Won, Lost, or Direct job value should not be editable.
- Raad LTD's test data: one enabled custom stage, "Waiting on customer" (Quotes, after Awaiting response),
  switched to on hold and holding one card with a Task due 2026-10-15; two switched-off stages remain from
  A3's check.
- From F2 (Conversion tab on `/pipeline/outcomes?view=conversion`), for G2: the phone view, and a member
  without money or without every-client access, were not checked in the browser. F2's counting rules are in the plan (Jafar,
  2026-10-02).
- From G1, for G2: two pgTAP files are stale and fail before their first test
  (`pipeline_quote_board_read_model.sql`, `pipeline_unified_board_and_presentation_setting.sql`: the board
  now needs today's date for the Task order). The browser and the phone view were not speed-profiled.
