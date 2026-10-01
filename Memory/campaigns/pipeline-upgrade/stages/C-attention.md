# Pipeline upgrade — stage C: what needs attention today

Approved by Jafar 2026-10-01. Plan § First-release
board (priority order, inactivity warning) and § Ownership and visibility; audit items A3, C2, C3.

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| C1 Tasks are the only follow-up | Existing next-follow-up dates become open Tasks and the duplicate field goes; the default board order is overdue Task, due today, no Task, future Task; Expected close is an alternate sort | — | A card that had a follow-up date now shows a Task on that date; "Next follow-up" appears nowhere; in one column the default order is overdue, due today, no Task, future | Not started |
| C2 Inactivity warning replaces the red 24-hour rule | Time in stage shows as plain context; a warning appears after the default days for that stage; the clock resets only for real progress on the Request, Assessment, Quote, or a completed Task | B3 | A New request untouched for two days shows the warning; completing its Task clears it; changing its value, owner, or adding a Note does not | Not started |
| C3 Replies, calls, own day counts, and On hold | A customer reply or a logged call outcome resets the clock; the owner sets the warning days for each stage; an on-hold card stays quiet until its Task is due | C2, A4 | A customer's email reply clears a warning; the owner sets Awaiting response to 3 days and the board follows; an on-hold card shows no warning until its Task date arrives | Not started |

Trap for C1: an Opportunity may already hold five open Tasks, so the move from follow-up date to Task needs a
rule for that case before any data is changed.
