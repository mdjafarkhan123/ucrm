# Part 2 — Pilot

**Campaign:** memory-skill-upgrade · **Plan:** `ROADMAP.md` part 2
**Code:** worktree `.claude/worktrees/memory-skill-upgrade`, branch `memory-skill-upgrade` (the new skill)
**Done when:** every test below passes, with the six answers (goal, agreed behavior, done so far, what it
waits for, next step, done-check) matching the real project; fixes applied; skill merged into `main`.

Pilot campaign: `operations-prospects-ux` (Jafar chose it 2026-09-28 and wants the lost Prospect detail page
rebuilt). Fresh sessions are helper agents started in the worktree, plus one final window Jafar opens himself.
Helpers run with no write claim of mine held in the worktree; release mine before each run.

## Steps

- [ ] Test 1 — normal resume: a helper resumes `operations-prospects-ux` (still in the older shape); its six
      answers match the project; it moves the position into a part note, records the movement-plan approval
      question for Jafar word for word, commits only its own files, and releases its claim
- [ ] Test 2 — a helper does a test outside action (a line with a unique ID appended to
      `pilot/test-outbox.log` in this session's scratchpad), following the outside-action rule, then stops
      before recording that it happened
- [ ] Test 3 — a fresh helper finds the stopped session's claim and asks; once released, it confirms the test
      action by its ID and does not repeat it
- [ ] Test 4 — a fresh helper finds part work that exists only in a test branch and treats it as waiting to
      merge
- [ ] Test 5 — a fresh helper told only "read memory and continue" asks which campaign
- [ ] Fix the skill for each failure and rerun that test
- [ ] Jafar's own window: `read memory and continue operations-prospects-ux`
- [ ] Remove test fixtures, merge the skill into `main`, mark Part 2 done

## Next

Release claim `e1525808da0c`, then start Test 1's helper in the worktree.
