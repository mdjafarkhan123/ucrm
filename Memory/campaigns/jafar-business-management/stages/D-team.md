# Jafar Business Management — stage D: Team

Sign-in is email address and password only, with email password reset (Jafar, 2026-10-07). D1 settles and records (ADR) how teammate accounts stay separate from contractor accounts before building. Stage A left: one front-door gate in `src/hooks.server.ts` (ADR 0007) — extend it, not each route; the sidebar sections in `src/lib/components/layout/AppShell.svelte`; the Settings directory, where Team & access cards and per-teammate filtering go, in `src/lib/jafar/owner-settings.ts`.

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| D1 Invitations and teammate sign-in | Jafar invites by email with a starting role; the teammate sets a password and signs in at `/jafar/login`; removal ends sign-in at once | A1 | A test Sales teammate sees only Sales areas; removing them signs them out immediately | Done 2026-10-07 |
| D2 Areas and sensitive actions | Per-teammate area and sensitive-action switches; server enforcement; actor and time history | D1 | A revoked action is refused even by a direct request; history shows who changed what and when | Done 2026-10-07 |
| D3a Lead owners | Owner on each Lead (picker, Leads list column and filter, history line); its reminders and alerts go to the owner; calls follow the owner; a removed teammate's work returns to Jafar; teammates get their own bell | D2, C2 | A Lead assigned to Sam sends its reminder to Sam's email and bell, not Jafar's; removing Sam returns it to Jafar | Not started |
| D3b Teammates' own day | Teammate home and calendar showing only their work; their own time zone and reminder defaults in My preferences; Jafar's home Mine/Everyone switch | D3a | Sam's home and calendar show only his Lead and call; Jafar's Everyone switch shows it too | Not started |
