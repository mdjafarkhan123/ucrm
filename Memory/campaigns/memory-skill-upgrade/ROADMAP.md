# Memory skill upgrade — roadmap

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| 1 Revised skill | `SKILL.md` rebuilt around plan → parts → checkpoints, with Codex's review applied (checkpoint on meaningful progress, verify outside actions before retrying, keep technical planning); `planning.md`, `setup.md`, `templates/` | — | every branch (setup, plan, split, resume, checkpoint, pause, finish, defer) covered; `SKILL.md` no longer than before; parallel part selection kept; committed on its branch, kept off `main` until the pilot passes | Done 2026-09-28 |
| 2 Pilot | the new skill tried on one campaign, from the branch; fresh-session tests using safe test actions: normal resume; interruption after an outside test action succeeds but before it is recorded; work that exists only in another branch; two equally ready campaigns | 1 | every test passes; the six answers (goal, agreed behavior, done so far, what it waits for, next step, done-check) match the real project, not only the notes; fixes applied; skill merged into `main` | Not started |
| 3 Checker | a script that flags pointers to missing files, `INDEX.md` rows and campaign folders that don't match, and notes over their word limit as a prompt to review; the skill's checkpoint rule runs it | 2 | it passes on clean Memory and catches each planted fault | Not started |
| 4 Move the other campaigns | every existing campaign in the new shape; the skill's older-shape line removed | 2, 3 | the checker is clean on all of Memory; a campaign another session holds is moved only after that session is done | Not started |
| 5 Tidy and measure | everything a fresh session reads measured — `CLAUDE.md`, skills, and Memory — and trimmed while the six answers stay right; `CLAUDE.md` and `AGENTS.md` pointers updated; the 5 unused planning skills removed only with Jafar's separate approval | 4 | the measurement is reported to Jafar, and a fresh session still answers the six questions correctly | Not started |

Later, as a separate campaign: tidy old plan documents one feature at a time, invoices first.
