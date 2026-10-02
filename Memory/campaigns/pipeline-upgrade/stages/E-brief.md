# Pipeline upgrade — stage E: the Opportunity Brief

Approved by Jafar 2026-10-01. Plan § Opportunity
Brief actions; audit items B3, B4, B5, B6 and section D.

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| E1 Tasks on the Schedule | A Task with a date shows on its assignee's Schedule and opens its Brief | C1 | A Task due Friday for the sales login shows on that person's Friday; clicking it opens the card's Brief; a completed Task shows as done | Done 2026-10-02 |
| E2 Task alerts | Assigning or reassigning a Task to someone else sends them one in-app alert and an email; assigning to yourself sends nothing; the customer is never told | — | The office login assigns a Task to the sales login, who gets one alert and one email; a self-assigned Task sends none | Done 2026-10-02 |
| E3 Notes with photos and mentions | A Brief Note can carry files and photos and mention a teammate, who is alerted | E2 | A photo added to a Brief Note also shows on the Request's own Notes; a mentioned teammate gets an alert that opens the card | Done 2026-10-02 |
| E3b Notes on Quote cards | A Quote card's Brief writes Notes and photos onto its Quote or Client, and still shows the Notes of the Request the Quote came from | — | On a Quote-sourced card, a Note with a photo saves and shows on that Quote and in the Brief | Done 2026-10-02 |
| E4 Email, Text, and Call buttons | Quick buttons on the Brief; a person logs a call with one of five outcomes | — | Email opens the client's composer; no phone shows no Text or Call; only Connected and Left voicemail clear the inactivity warning | Done 2026-10-02 |

Push alerts and per-person notification settings are not in this campaign (Jafar, 2026-10-01): E2 and E3 send
the in-app alert and the email only. The rest waits in
`Memory/deferred/push-alerts-and-per-person-notification-settings.md`.

From E1: `/pipeline?brief=<opportunity id>` opens that card's Brief (a card that left the board shows a
message). E2 and E3 alerts and emails should link there. Any Pipeline write already refreshes the Schedule
through `invalidatePipeline`.

Carried from stage A: the Brief shows only the real stage, not which custom stage the card is in. No
screen shows a card's move history yet; whichever part draws it must read stage names without filtering
on `disabled_at`, so a switched-off stage still shows its name.

From E4: `progress_at` is restarted by `pipeline_log_opportunity_call` (migration `20261004130000`). Calls show on
the Brief only, not yet on the Client record. Email and Text go to the client's primary address or number; the
composer has no recipient picker. Tapping Call on a desktop was not tried, so check it on a phone.

Carried from D6 (bulk tools): a bulk Task given to someone else must send them one combined alert and email
("5 new Tasks"), not one per card. Bulk Tasks are created by `pipeline_bulk_update` (migration `20261003140000`).

From E2: Task alerts are made by `private.alert_task_assignment` (migration `20261003220000`). The email
worker decides who is emailed per alert kind in `claim_team_notification_emails`; the old inquiry rule
would drop a salesperson, so E3's mention alert needs its own kind added there, and its own email footer
in `buildAlertEmail`. Unconfirmed: in the browser check, picking the sales login in the Brief's Add task
owner picker saved the Task unassigned. Rechecked in E3 by clicking like a person: the owner saves — not a bug.

From E3: on this machine uploaded files stay "Still being checked" because the file checker is not switched on
(`Memory/deferred/background-jobs-have-no-production-scheduler-decision.md`). A teammate with no profile name
is mentioned by email, and that mention is not highlighted in the Note's text.

From E3b: a card with neither a Request nor a Quote (a direct Job card) can take Notes on its Client only.
