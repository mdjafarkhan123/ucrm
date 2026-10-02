# Pipeline upgrade — stage E: the Opportunity Brief

Approved by Jafar 2026-10-01. Plan § Opportunity
Brief actions; audit items B3, B4, B5, B6 and section D.

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| E1 Tasks on the Schedule | A Task with a date shows on its assignee's Schedule and opens its Brief | C1 | A Task due Friday for the sales login shows on that person's Friday; clicking it opens the card's Brief; a completed Task shows as done | Done 2026-10-02 |
| E2 Task alerts | Assigning or reassigning a Task to someone else sends them one in-app alert and an email; assigning to yourself sends nothing; the customer is never told | — | The office login assigns a Task to the sales login, who gets one alert and one email; a self-assigned Task sends none | Done 2026-10-02 |
| E3 Notes with photos and mentions | A Brief Note can carry files and photos and mention a teammate, who is alerted | E2 | A photo added to a Brief Note also shows on the Request's own Notes; a mentioned teammate gets an alert that opens the card | Done 2026-10-02 |
| E3b Notes on Quote cards | A card that came from a Quote can take a Note (plan: "backing Request/Quote or the Client"); today `pipeline_create_opportunity_note` only resolves Request or Client, so the default "Request" target is refused on a Quote card, and its file upload has no Request to attach to | — | On a Quote-sourced card, a Note with a photo saves and shows on that Quote and in the Brief | Not started |
| E4 Email, Text, and Call buttons | The buttons open the existing composer or the phone's dialler; several contact details open a chooser; Call offers an optional return Note; a button shows only when the detail and permission exist; a call can be logged, and a logged call restarts the card's progress clock | — | Email opens the composer addressed to the client; a client with no phone shows no Text or Call; returning from Call offers a Note and records no automatic outcome; logging a call clears the card's inactivity warning | Not started |

Push alerts and per-person notification settings are not in this campaign (Jafar, 2026-10-01): E2 and E3 send
the in-app alert and the email only. The rest waits in
`Memory/deferred/push-alerts-and-per-person-notification-settings.md`.

From E1: `/pipeline?brief=<opportunity id>` opens that card's Brief (a card that left the board shows a
message). E2 and E3 alerts and emails should link there. Any Pipeline write already refreshes the Schedule
through `invalidatePipeline`.

Carried from stage A: the Brief shows only the real stage, not which custom stage the card is in. No
screen shows a card's move history yet; whichever part draws it must read stage names without filtering
on `disabled_at`, so a switched-off stage still shows its name.

Carried from stage C (Jafar, 2026-10-01): no call log exists yet, so "a logged call outcome is progress" moved
here. Before building it, ask Jafar how a call is logged — he was offered a "Log call" button with outcomes
(HubSpot/Pipedrive) and chose to decide with E4. Each card's progress clock is `progress_at`; the customer-reply
trigger in migration `20261002190000` is the pattern for restarting it. A card's task dates: `next_task_due_on`.

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
