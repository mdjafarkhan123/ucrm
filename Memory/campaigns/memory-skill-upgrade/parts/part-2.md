# Part 2 — Pilot

**Campaign:** memory-skill-upgrade · **Plan:** `ROADMAP.md` part 2
**Code:** worktree `.claude/worktrees/memory-skill-upgrade`, branch `memory-skill-upgrade` (the new skill)
**Done when:** every test below passes, with the six answers (goal, agreed behavior, done so far, what it
waits for, next step, done-check) matching the real project; fixes applied; skill merged into `main`.

Pilot campaign: `operations-prospects-ux` (Jafar chose it 2026-09-28 and wants the lost Prospect detail page
rebuilt). Fresh sessions are helper agents started in the worktree, plus one final window Jafar opens himself.
Helpers run with no write claim of mine held in the worktree; release mine before each run.

## Steps

- [x] Test 1 — normal resume: a helper resumes `operations-prospects-ux` (still in the older shape); its six
      answers match the project; it moves the position into a part note, records the movement-plan approval
      question for Jafar word for word, commits only its own files, and releases its claim
- [x] Tests 2–5 moved to the temporary `pilot-test` campaign (Jafar, 2026-09-28: no prospect decisions needed);
      the prospect campaign waits for his page-plan answers
- [x] Test 2 — a helper resumes `pilot-test` Part 1 and stops right before its first outside action; its note
      must already say how to check the action's outcome, by an exact ID; the claim stays held
- [x] Test 3 — I append the notice line with that ID (the send succeeded, then the power cut). A fresh helper
      must find the held claim and ask; told the session is closed, it confirms the notice by its ID and does
      not send it again
- [x] Test 4 — Part 2 of `pilot-test` is started in a test branch; a fresh helper treats the work as existing
      only there and marks it waiting to merge
- [x] Test 5 — a fresh helper told only "read memory and continue" asks which campaign
- [x] Fix the skill for each failure and rerun that test
- [ ] Jafar's own window, in the normal project folder: `read memory and continue operations-prospects-ux` —
      then mark Part 2 done
- [x] Remove test fixtures and merge the skill into `main` (2026-09-28, with the `Plans live in` line added
      to `Memory/INDEX.md`)

## Next

The new skill is on `main`. Wait for Jafar's report from his own window test: a fresh session in the normal folder, told `read memory and continue operations-prospects-ux`, should show him the saved page plan with its two questions. If it goes as expected, mark Part 2 done and start Part 3 (checker); if not, fix the skill first.

## Notes

- Test 1 findings for later parts: `Memory/deferred/prospect-detail-page.md` still tracks work the campaign has
  taken up (Part 4 should remove such records; the checker could flag a deferred record that names a live
  campaign). Another session's uncommitted Memory edits in the main folder (since 07:40) make the register
  refuse write claims there, so helpers claim from the worktree.
