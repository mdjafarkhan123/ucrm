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
- [ ] Test 4 — Part 2 of `pilot-test` is started in a test branch; a fresh helper treats the work as existing
      only there and marks it waiting to merge
- [ ] Test 5 — a fresh helper told only "read memory and continue" asks which campaign
- [ ] Fix the skill for each failure and rerun that test
- [ ] Jafar's own window: `read memory and continue operations-prospects-ux`
- [ ] Remove test fixtures, merge the skill into `main`, mark Part 2 done

## Next

Tests 2 and 3 passed (check recorded by exact ID before the send; after the simulated crash the new session asked about the held claim, verified the notice by its ID, sent nothing, finished part 1) and their unclear rules are fixed on the branch. Test 4's setup is committed: `pilot-test` part 2 started in worktree `.claude/worktrees/pilot-test-part2` (branch `pilot-test-part2`). Release claim `929fa6d99498`, then start Test 4's helper with `read memory and continue pilot-test`; it must not merge into `main`.

## Notes

- Test 1 findings for later parts: `Memory/deferred/prospect-detail-page.md` still tracks work the campaign has
  taken up (Part 4 should remove such records; the checker could flag a deferred record that names a live
  campaign). Another session's uncommitted Memory edits in the main folder (since 07:40) make the register
  refuse write claims there, so helpers claim from the worktree.
