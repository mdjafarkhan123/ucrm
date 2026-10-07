# Jafar Business Management — stage D: Team

Sign-in is email address and password only, with email password reset (Jafar, 2026-10-07). D1 settles and records (ADR) how teammate accounts stay separate from contractor accounts before building.

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| D1 Invitations and teammate sign-in | Jafar invites by email with a starting role; the teammate sets a password and signs in at `/jafar/login`; removal ends sign-in at once | A1 | A test Sales teammate sees only Sales areas; removing them signs them out immediately | Not started |
| D2 Areas and sensitive actions | Per-teammate area and sensitive-action switches; server enforcement; actor and time history | D1 | A revoked action is refused even by a direct request; history shows who changed what and when | Not started |
| D3 Teammates in daily work | Owner pickers include teammates; assigned reminders and "my work" go to them; unassigned stays Jafar's | D2, C2 | A Lead assigned to the teammate shows on their home and their reminder reaches them, not Jafar | Not started |
