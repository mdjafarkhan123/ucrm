# Pipeline upgrade — stage C: what needs attention today

Approved by Jafar 2026-10-01. Plan § First-release
board (priority order, inactivity warning) and § Ownership and visibility; audit items A3, C2, C3.

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| C1 Tasks are the only follow-up | Existing next-follow-up dates become open Tasks and the duplicate field goes; the default board order is overdue Task, due today, no Task, future Task; Expected close is an alternate sort | — | A card that had a follow-up date now shows a Task on that date; "Next follow-up" appears nowhere; in one column the default order is overdue, due today, no Task, future | Done 2026-10-01 |
| C2 Inactivity warning replaces the red 24-hour rule | Time in stage shows as plain context; a warning appears after the default days for that stage; the clock resets only for real progress on the Request, Assessment, Quote, or a completed Task | B3 | A New request untouched for two days shows the warning; completing its Task clears it; changing its value, owner, or adding a Note does not | Done 2026-10-01 |
| C3 Replies, calls, own day counts, and On hold | A customer reply or a logged call outcome resets the clock; the owner sets the warning days for each stage; an on-hold card stays quiet until its Task is due | C2, A4 | A customer's email reply clears a warning; the owner sets Awaiting response to 3 days and the board follows; an on-hold card shows no warning until its Task date arrives | Not started |

Carried from stage A: an on-hold stage is a custom stage with `requires_future_task` on. The plan says its
inactivity warning pauses only until the card's future Task becomes due; the part that builds the warning
owns that. The warning needs its own progress clock — `stage_entered_at` restarts on every custom move
(ADR 0004, point 8).

From C1: each card keeps `next_task_due_on` (its earliest open Task date, kept by a trigger on `tasks`);
C3's "quiet until its Task is due" can read it.

From C2: each card keeps `progress_at`, its own progress clock (migration `20261002180000`), restarted by
a real stage change, an assessment booked/moved/completed, a quote version sent, or a Task completed. The
warning is worked out in the browser from it (`src/lib/pipeline/freshness.ts`, `INACTIVITY_DAYS`). A card in
a custom stage uses its real stage's days for now; C3 replaces the fixed days with the owner's setting and
adds replies and calls as progress.
