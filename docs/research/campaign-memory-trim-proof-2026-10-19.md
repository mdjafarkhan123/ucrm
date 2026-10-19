# Campaign Memory trim — verification

Checked 2026-10-19 for Part 11 of `memory-skill-upgrade`, against the
[workflow agreement](../memory-campaign-workflow-behavior-contract.md). Status: final-version trials not yet run
(Jafar paused the session); everything below was observed.

## Why

- 142 of the 201 Claude sessions since 2026-10-01 loaded the skill. They opened `planning.md` 17 times (17
  campaigns were started in that period), `handover.md` 17 times, `delivery.md` 6 times, and `setup.md` once.
  Progress was still saved far more often: 473 commits touched a campaign `NOW.md` in the same period.
- `to-spec`, `to-tickets`, and `wayfinder` were opened in 0 of 203 Claude sessions (Codex: `to-tickets` and
  `wayfinder` once each).
- 22 of 152 Memory notes broke the skill's own word limits; one roadmap had 7,524 words against 800.
- The text used vague words ("relevant" 9 times, "necessary" 5, "important" 4, "meaningful" 3), several names
  for one idea (done-check / Done when / acceptance checks; claim / reservation), "stage" for two ideas, and
  said design tools were optional while CLAUDE.md requires Pencil.

## What changed

- `SKILL.md` carries resume, start, and save rules; `handover.md` and `delivery.md` are folded in or dropped
  where CLAUDE.md already covers them; finishing and deferring moved to `finishing.md`.
- Jafar (2026-10-19): Campaign Memory is the handover memory, not a planning method. `planning.md` is removed;
  CLAUDE.md's skills table picks planning skills; `to-spec`, `to-tickets`, and `wayfinder` are back to their
  pre-2026-10-11 manual-only versions; `grill-with-docs` lost its campaign wiring.
- New `scripts/check_memory.py`: word limits, pointers to missing files, and index mismatches, for changed
  files by default or everything with `--all`.

## Reading size

`wc -w` of the saved files, not tokens.

| Reading path | Before | After |
| --- | --- | --- |
| Continue, work, save (following the rules) | 1,693 (SKILL + handover), 2,027 with delivery | 1,118 |
| What sessions actually read when continuing | 980 (save rules skipped about 9 times in 10) | 1,118, save rules included |
| Start or plan a campaign | 2,496 (SKILL + planning + handover), plus up to 3,421 in helpers | 1,118 |
| Finish a part or campaign | 1,693 | 1,383 |
| All guidance files | 2,999 | 1,547 |

Templates grew from 939 to 1,001 words because the roadmap template now holds the part rules.

## Fresh-session trials

Kit: [campaign-memory-trials](campaign-memory-trials/trial-prompt.md). One run per scenario, Claude Opus.
"Middle" is the shorter skill before `planning.md` was removed.

| Trial | Before | Middle | Final |
| --- | --- | --- | --- |
| S1 continue quote-reminders | pass: checked `QR-TEST-7`, no resend; built the opt-out skip; Part 2 done; asked about the missing business name; deferred the sorting issue | stopped part-way | not run |
| S2 bare "read memory and continue" | pass: asked which of three; 11 files read, 90k tokens | pass: same answer; 7 files, 68k tokens | not run |
| S3 start a campaign | pass: reused the deferred note and its limit; four questions | stopped part-way | not run |
| S4 continue price-book-import | Part 3 done; campaign kept open after finding two real importer gaps | stopped near the end | not run |
| S5 fix a typo | pass, no campaign | pass, no campaign | not run |
| S7 continue staff-timesheets | redid research with web searches and rewrote the saved question; 127k tokens | asked the saved question word for word, no new research; 98k tokens | not run |
| Real campaign, read-only (`jafar-business-management`) | — | correct six answers and part; found three wording gaps, since fixed | not run |

Unclear lines the agents reported were fixed in the middle and final versions: what "can move now" means,
where small tasks check for a campaign, claimed versus blocked, Jafar's answer as a blocker, when to re-check
research, where proof goes before a note is deleted, how to word a built plan, where to run the claim, a
`NOW.md` that names a group, and what "started" means.

## Checker

- Clean test notes: passed (17 files). Seven planted faults: all caught.
- Real Memory with `--all`: 154 files, no false pointer alarms, 29 word-limit problems, and two campaign
  folders without an index row (`selectable-design-experiences`, `uplift-design-refresh`).
- On this branch it caught two real problems in its own notes before commit.

## Mechanical checks

- Skill Creator's `quick_validate.py` passes for `campaign-memory` and `grill-with-docs`. For the three restored
  skills it rejects `disable-model-invocation`, a documented Claude Code field that its general format omits.
- All local links and section anchors in the changed skills and the agreement resolve; `git diff --check` is
  clean. Prettier is not applicable: `.prettierignore` excludes `.claude/skills/`, `docs/`, and `Memory/`.

## Still to do

Run the final-version trials, at least S3 and S7, which the last change touched; then merge on Jafar's word.
