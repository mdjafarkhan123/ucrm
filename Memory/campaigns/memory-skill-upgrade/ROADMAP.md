# Memory skill upgrade — roadmap

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| 1 Revised skill | `.claude/skills/campaign-memory/SKILL.md` rebuilt around plan → parts → checkpoints, with planning guidance and templates | — | setup, plan, split, resume, checkpoint, pause, finish, defer covered; original pilot constraints recorded in Part 2 | Done 2026-09-28 |
| 2 Earlier pilot | safe resume, outside-action interruption, branch-only work, and ambiguous-campaign checks; see `parts/part-2.md` | 1 | automated pilot checks and Jafar's own window check pass; skill integrated | In progress — skill integrated; owner-window result unreported |
| 3 Checker | missing-pointer, registry, and note-size checks | 2, 10 | passes on clean Memory and catches planted faults | Done 2026-10-19 in Part 11, ahead of Part 2 with Jafar's go-ahead |
| 4 Move the other campaigns | existing campaigns moved to the proven shape, only when unclaimed | 3, 10 | checker clean; fresh sessions find correct work | Not started — next; Jafar names which waiting campaigns to close |
| 5 Tidy and measure | wider instruction cleanup; removal of unused skills requires separate approval | 4 | reading measured and six resume answers remain correct | Not started — after migration |
| 6 Agree parent workflow | `docs/memory-campaign-workflow-behavior-contract.md`; current direction and build order written independently of old chats | — | fresh-reader review addressed; Jafar reviews and approves plan and order | Done 2026-10-11 |
| 7 Parent guidance | stage selection, specialist routing, usable invocation, and existing resume safeguards | 6 | a session can select and follow the appropriate guidance without extra skill commands | Done 2026-10-11 |
| 8 Templates | clear purpose, first version, success checks, stage, and proof pointers in existing homes | 7 | sample campaign saves all necessary context without duplicate truth | Done 2026-10-11 |
| 9 Fresh-start proof | safe examples for planning, design, building, conflicts, and a small task | 8 | fresh sessions choose correct next actions from saved sources | Done 2026-10-11 |
| 10 Pilot and measure | one campaign trial, reading measurements, fixes from observed failures | 9 | evidence reported; workflow works across a fresh session; follow-on work reviewed | Done 2026-10-11 |
| 11 Trim and clarify | resume and save rules in one shorter skill file, a finishing guide, plain wording, and `.claude/skills/campaign-memory/scripts/check_memory.py` | 10 | fresh-session trials match the old skill; reading measured | Paused — final trials and merge wait for Jafar; `parts/part-11-trim.md` |

Later, as a separate campaign: tidy old plan documents one feature at a time, invoices first.

Parent-upgrade proof: `docs/research/campaign-memory-parent-proof-2026-10-11.md`. Trim proof:
`docs/research/campaign-memory-trim-proof-2026-10-19.md`.
