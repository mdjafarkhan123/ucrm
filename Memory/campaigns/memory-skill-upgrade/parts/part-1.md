# Part 1 — New skill

**Campaign:** memory-skill-upgrade · **Plan:** `ROADMAP.md` part 1
**Code:** worktree `.claude/worktrees/memory-skill-upgrade`, branch `memory-skill-upgrade`
**Done when:** every branch (setup, plan, split, resume, checkpoint, pause, finish, defer) is covered;
`SKILL.md` is shorter than before; parallel part selection kept; merged into `main`.

## Steps

- [x] Write `SKILL.md`: layout and word limits, resume, checkpoint, pause, finish, defer
- [x] Write `planning.md` and `setup.md`
- [x] Write `templates/` (INDEX, deferred INDEX, NOW, ROADMAP, stage, part, plan, deferred task); update
      `agents/openai.yaml`
- [ ] Review against the `writing-for-agents` skill; Prettier check
- [ ] Commit on the branch, merge into `main`, mark part 1 done, release the claim, remove the worktree

## Next

Review `SKILL.md`, `planning.md`, `setup.md`, and `templates/` in the worktree against the `writing-for-agents` skill: duplication, no-op sentences, negations, leading words, and one term per concept.

## Notes

- Agreed design: one note per started part; checkpoint after every working step; Memory only in the main
  folder; word limits instead of line limits; one plan per feature with **Still unclear** and **Not doing**;
  build parts are thin complete pieces with observable done-checks; big roadmaps split into stages.
- The main folder holds another session's uncommitted edits (`Memory/INDEX.md`, `deferred-launch-sweep/NOW.md`)
  and an unknown `design-previews/` folder. Commit only this campaign's files and its own `INDEX.md` row.
