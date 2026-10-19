# Contractor design concept — roadmap

**Plan:** `docs/contractor-design-concept-behavior-contract.md`. Every screen: research → Pencil (`concept.pen`, 1440) → Jafar approves → build.
**Note:** Read the SKILL.md file of design skill to know design preferences before designing in pencil app. Research jobber and other industry to see what the made, what works and not, research is not for copying the ui.

| Part | Plan section | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- | --- |
| C1 Foundation | First version 1 | Colour map, icon rule, core parts, sidebar, top bar | — | Jafar approves | Approved 2026-10-17 |
| C2 Home | First version 2 | Home in the concept | C1 | Jafar approves | Approved 2026-10-18 (`parts/c2-home.md`) |
| C3 Jobs list | First version 2 | Jobs list in the concept | C1 | Jafar approves | Approved and built 2026-10-18 (`parts/c3-jobs-list.md`) |
| C4 Job details | First version 2 | Job details in the concept | C1 | Jafar approves | Approved 2026-10-18 (`parts/c4-job-details.md`) |
| C5 New job | First version 3 | New job in the concept | C4 | Jafar approves | Approved 2026-10-18 (`parts/c5-new-job.md`) |
| C5 Everything else | First version 3 | Every page and component on the redesign checklist, most necessary first, Jafar's admin panel last | C5a checklist; C2–C4 pattern | Jafar approves each; coverage check clean | Checklist made 2026-10-18 from the code (`stages/list-index.md`); waits for Jafar to read it and confirm the order |
| C6 Rollout decision | First version 4 | All at once or screen by screen | C2–C4 | Jafar decides | Decided 2026-10-18: screen by screen |
| C7 Build | First version 4 | Approved screens built; variables in code and skill | C6 | Each screen matches its frame; full screen check | Jobs list built; next Home → Job details → New job, one per session (`parts/c7-build-pilots.md`) |
| C8 Old look removed | First version 4 | Old styles and unused code deleted | C7 | Every page on the concept; lint and unused-code scan clean | Not started |

**Earlier Phase A (App look):** A1, A2, A2b, Settings (25 pages) and A3 Schedule built and on main (`parts/a3-schedule.md` lists its open Pencil differences); A4 and A5 folded into C5 and C8 on 2026-10-17.
