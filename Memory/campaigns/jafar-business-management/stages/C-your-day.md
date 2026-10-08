# Jafar Business Management — stage C: Your day

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| C1 Home: today's next actions | Business Management home led by approvals, first contacts, replies, overdue follow-ups, calls, pricing awaiting decision, handovers, renewals | B3, B5 | An overdue follow-up shows at the top; completing it removes it | Done 2026-10-08 |
| C2 Calendar and reminders | Sales calls, dated follow-ups, Busy blocks; chosen number and timing of in-app and email reminders; move or cancel replaces reminders | C1 | A call booked with two reminders is moved; reminders for the old time never arrive | In progress — `parts/C2.md` |
| C3 Activity report | Researched → won/lost by source and period; people reached separate from messages sent | B5 | Numbers match a hand count of the test data | Not started |

C2 reuses the once-a-minute worker wake and durable email outbox (`src/lib/server/setup/reminder-emails.ts`) and the `components/schedule` look; contractor jobs never appear.
