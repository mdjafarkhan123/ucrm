# Data privacy and deletion — roadmap

**Plan:** `docs/data-privacy-deletion-behavior-contract.md` — plan and this part order approved by Jafar 2026-10-24.

Design parts are Pencil sessions only; a separate session builds. Performance design runs before parts 3, 10 and
14 (work grows with a business's size); verification runs in part 16.

| Part | Plan section | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- | --- |
| 1 Plan | whole plan | research and four answers | — | Jafar approved the plan | Done 2026-10-24 |
| 2 Build planning | whole plan | these parts | 1 | Jafar approved parts and order | Done 2026-10-24 |
| 3 Permanent-delete engine | § Money records; § "Don't contact me" | one customer deleted for good, keeping only money records and opt-out fingerprints; stored file copies cleaned (Twilio's log stays, as in HighLevel); audit counts | 2 | tests on a test business show nothing personal left, totals unchanged, a STOP still blocks a re-import | Done 2026-10-24 — questions in the part note |
| 4 Design: customer delete pop-ups | § Deleting a customer; § Delete permanently now; § Download one customer's data | one Pencil board: delete dialog with counts, money-open refusal, delete-now with typed name, receipt, download-ready notice | 2 | Jafar approved the board | Done 2026-10-24 — Approved B (`WEpOG`) — `parts/04-design-customer-delete-popups.md` |
| 5 Design: Recently Deleted page | § Deleting a customer | Pencil page | 2 | Jafar approved | Done 2026-10-24 — Approved B (`Wf0tP`) — `parts/05-design-recently-deleted.md` |
| 6 Delete and restore a customer | § Deleting a customer | delete one or many, hidden everywhere, Recently Deleted, restore, automatic day-30 delete | 3, 4, 5 | delete → gone from lists, search, schedule, inbox; restore on day 10 → all back; day 30 → engine ran | Not started |
| 7 Delete permanently now | § Delete permanently now | the new permission, typed-name delete, receipt | 6 | owner deletes now → receipt shown; a role without it sees nothing and the server refuses | Not started |
| 8 Design: delete conversation pop-up | § Deleting a conversation | added to the inbox pop-up board | 2 | Jafar approved | Not started |
| 9 Delete conversations | § Deleting a conversation | single and bulk (100) delete, reason, audit, owner/admin default | 8 | deleted for every member; audit has who, when, why, counts; client stays | Not started |
| 10 Download one customer's data | § Download one customer's data | background zip with readme, messages and files; 7-day link; audited | 4 | zip of a test customer holds their details, work, messages and files, no job costs | Not started |
| 11 Design: Jafar privacy requests | § Privacy requests in the Jafar panel | Pencil page: request list, find, actions | 2 | Jafar approved | Not started |
| 12 Jafar privacy requests | § Privacy requests in the Jafar panel | log, due dates and reminders, find across businesses (counts only), ask the business, delete for them, Uplift's own records | 7, 11 | a test person in two businesses is found; "Ask" reaches the owner; "Delete for them" needs reason, typed name and password | Not started |
| 13 Design: Settings Data & privacy | § Export all business data | Pencil page | 2 | Jafar approved | Not started |
| 14 Export all business data | § Export all business data | one background package with readme; offered before closure; Jafar can produce it during closure | 10, 13 | package opens with every record type and files; owner-only | Not started |
| 15 Public pages | § Public pages | new Data deletion and Privacy text for the website project; Messenger Part 10 note updated | 7, 9, 12 | text handed over; backup wording uses the real retention number | Not started |
| 16 Final check | § Success checks | performance verification at a large test business, screen checks, Jafar's browser tour | all | every success check passes on the live app | Not started |
