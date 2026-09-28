# Memory skill upgrade — roadmap

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| 1 New skill | `SKILL.md` rebuilt around plan → parts → checkpoint, with pause/resume through part notes; `planning.md`, `setup.md`, `templates/` | — | every branch (setup, plan, split, resume, checkpoint, pause, finish, defer) is covered; `SKILL.md` is shorter than before; parallel part selection kept; merged into `main` | In progress |
| 2 Checker | a script that flags Memory files over their word limit, pointers to missing files, and `INDEX.md` rows and campaign folders that don't match; the skill's checkpoint rule runs it | 1 | it passes on clean Memory and catches each planted fault | Not started |
| 3 Move current Memory | every existing campaign in the new shape: short `INDEX.md` rows, short `NOW.md`, part notes, long roadmaps trimmed or split into stages; the skill's older-shape line removed | 1, 2 | the checker is clean on all of Memory; a campaign another session holds is moved only after that session is done | Not started |
| 4 Clean up and measure | the 5 unused planning skills removed (wayfinder, to-spec, to-tickets, implement, handoff — confirm with Jafar first); `CLAUDE.md` and `AGENTS.md` pointers updated; resume and pause tests with fresh sessions | 3 | a fresh session told only "read memory and continue" finds its exact next step within about 5 pages; a paused part resumes from its exact step | Not started |

Later, as a separate campaign: tidy old plan documents one feature at a time, invoices first.
