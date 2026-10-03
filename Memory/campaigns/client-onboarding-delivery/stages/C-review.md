# Client onboarding and delivery — stage C: Uplift review

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| C1 Client list | §8 list of paid clients with setup progress and state | B1 | Jafar sees each client's progress and next action | Done 2026-10-03 — `/jafar/onboarding`; a paid client is one with a succeeded provision; blockers, provider waits and build target columns arrive with C4/E1/E2 |
| C2 Client page | §8 client page with submitted sections, original beside accepted values; a Pause reminders control (sets `organization_setup_reminders.paused_at`, plan §5 human deferral) | C1, B13 | Jafar reads a submitted client's answers by section | Not started |
| C3 Review a section | §4 accept, ask, return one section; help-needed becomes an Uplift task; returning a section restarts setup reminders (C6 timer stops once every task is done) | C2 | Returned section links the client straight to it; other sections stay accepted | Not started |
| C4 Ready for Uplift | §4–5 blocker list, Ready action, 7–10 business-day range shown to client | C3 | Ready refused while a named blocker remains; client sees start date and range | Not started |
| C5 Fill CRM settings | Accepted facts seed matching CRM settings safely | C4 | Repeating it creates no duplicates and keeps the owner's later edits | Not started |
| C6 Reminders | §5 emails at about 24h, 3d, 7d of inactivity, linking to the exact task | B1 | Reminder stops after Send to Uplift | Not started |
