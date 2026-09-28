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

Paused mid-review. Jafar shared a Codex review of the design (measure understanding rather than pages; checkpoint at meaningful points; verify outside effects before repeating a step; part notes only when progress must be handed over; keep technical planning; pilot before migrating). Agree the revisions with Jafar, then apply them to the files on the branch before continuing the review step.

## Notes

- Agreed design: one note per started part; checkpoint after every working step; Memory only in the main
  folder; word limits instead of line limits; one plan per feature with **Still unclear** and **Not doing**;
  build parts are thin complete pieces with observable done-checks; big roadmaps split into stages.
- The main folder holds another session's uncommitted edits (`Memory/INDEX.md`, `deferred-launch-sweep/NOW.md`)
  and an unknown `design-previews/` folder. Commit only this campaign's files and its own `INDEX.md` row.
