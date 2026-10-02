# Pipeline upgrade — stage F: sales reports

Approved by Jafar 2026-10-01. Plan § Outcomes,
"Sales reporting includes…". F2 reads history across many records — run the `performance-review` design
branch first.

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| F1 Outcomes report upgrade | Loss-reason breakdown; Direct jobs shown separately; missing values labelled Unvalued; days to win as median and average | B2, B6 | The report shows how many were lost to each reason, a separate Direct job line, "Unvalued" instead of zero, and both day figures | Done 2026-10-02 |
| F2 Funnel, source, and time in stage | Request-to-Quote, Request-to-Won, and per-Quote win rates by the month the work was created, with still-open work shown apart; conversion by lead source; time spent in each stage, custom stages included | F1, A3, D2 | For a chosen month the three rates are separate figures and open work is not counted as lost; one lead source shows its own win rate; each stage shows its typical days | Not started |

Carried from D1: an Undo leaves two stage events (the move and its reverse); reports should not count them.

From F1: the numbers sit above the list on `/pipeline/outcomes` (`pipeline_outcomes_report`, migration `20261005100000`, route `/api/pipeline/outcomes/report`). Days to win counts Won deals only, creation to win. F2 should reuse the same date window controls.
