# Contractor design concept — roadmap

**Plan:** `docs/contractor-design-concept-behavior-contract.md` — two phases; Phase B starts only after Phase A.

| Part | Plan section | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- | --- |
| A1 Shell, lists, Job details | First version A | New shell, 5 lists, Job details built | — | Pushed on branch; checked at 1440/1100 light+dark | Merged 2026-10-16; list gaps listed in NOW |
| A2 Other designed screens | First version A | Quote, Invoice, Request, Client, Payment details; Home; Inbox; Settings | A1 | Each matches its Pencil frame; no new behaviour | Built and on main except Settings |
| A3 Schedule | First version A | Schedule month/day/states, drawers, new-item dialogs | A1 | Matches Pencil frames | In progress, paused (branch `claude/a3-schedule`) |
| A4 Undesigned screens | First version A | Timesheets, Pipeline, Files, Marketing, Reviews, Reports designed in Pencil, approved, built | A1 | Jafar approves each design; built | Not started |
| A5 Cleanup | First version A | Shared parts are the only look; old styles/options deleted; docs and design skills match | A2–A4 | Every page checked; lint and unused-code scan clean; merged to main | Not started |
| B1 Research | First version B | Cited file of what top products show and omit | A5 | `docs/research/` saved; Jafar read it | Not started |
| B2 Concept | Experience target | Colour, type, spacing, shell, core parts in Pencil | B1 | Jafar approves | Not started |
| B3 Pilot screens | First version B | Home, Jobs list, Job details designed | B2 | Jafar approves each | Not started |
| B4 Build and rollout | First version B | Pilots built, then whole app on the new look | B3 | Every page checked; no old code | Not started |
