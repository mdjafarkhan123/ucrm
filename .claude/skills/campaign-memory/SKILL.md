---
name: campaign-memory
description: Run work too big for one session as a campaign — plan it, split it into session-sized parts, and checkpoint every step so any fresh session resumes exactly where the last one stopped. Use to start, plan, resume, checkpoint, pause, defer, or finish a campaign, to set up Memory in a new project, or when Jafar says to read Memory and continue.
---

# Campaign Memory

A **campaign** is work too big for one session. It moves through a **plan** — what users will get — and then
**parts**, one session-sized piece each. `Memory/` holds the campaign's working notes: small files that point
each fresh session to the one plan section and the one step it needs. Every session starts light, knows where
the work stands, and can stop at any step for the next session to resume from exactly there.

- No `Memory/` folder yet → read [setup.md](setup.md) first.
- Starting a campaign, working a planning part, or splitting a plan into parts → read [planning.md](planning.md).
- Creating any Memory file or plan → copy its shape from [templates/](templates/).

## Where things live

```text
Memory/
  INDEX.md               one row per campaign
  campaigns/<campaign>/
    NOW.md               goal, plan, parts in progress, next part
    ROADMAP.md           every part on one line — or, in a big campaign, every stage
    stages/<stage>.md    one stage's parts (big campaigns only)
    parts/<part>.md      one part note per started part: its steps and exact next step
  deferred/
    INDEX.md             postponed work, one row each
    <task>.md
```

Word limits: `NOW.md` 200 · `ROADMAP.md` and each stage file 800 · part note 500 · deferred task 150 · each
`INDEX.md` row 50.

Knowledge that outlasts the campaign lives outside Memory:

- **The plan** — what the feature does for its users — in one product document per feature, at the location
  the `Memory/INDEX.md` header names. It stays after the campaign ends.
- **Technical decisions** a later developer must not reverse unknowingly — in ADRs.
- **How it is built** — in code, tests, migrations, and Git.

Memory holds only what the next session needs and cannot quickly find there: the goal, pointers, each part's
state and done-check, each started part's exact position, blockers, and a non-obvious fact that changes the
next step. Write it in plain English Jafar can follow, and point to sources instead of copying them. Commit
hashes, test counts, command output, code and schema details, and the story of a session stay out.

## Resume

1. Read `Memory/INDEX.md` and take the campaign Jafar named. For "read memory and continue" with no name, take
   the only campaign ready to work; if several are, ask which. The choice holds for this conversation only —
   file order, recency, and other conversations never decide it.
2. Read that campaign's `NOW.md` and check the live register as the project's coordination rule directs.
3. Choose the part Jafar named. Otherwise take, in this order: a paused part (started, unclaimed); the next
   part `NOW.md` names; when those are claimed or Jafar asks for any available part, another part in
   `ROADMAP.md` whose dependencies are done and whose code and outside services don't overlap claimed work.
   If none qualifies, say so and wait.
4. Claim the part. Uncommitted files its note names belong to the part; take them over with the claim. If
   another session wins the claim, choose again.
5. Read the part note — for a part not yet started, create it from its roadmap line and the template. Then read
   only the plan section and sources the note points to.
6. Check the note against Git: its ticked steps are committed, and its half-done work shows up as the
   uncommitted files it names. Where they disagree, correct the note from what is really there; ask Jafar only
   when the correction changes approved behavior or scope.
7. Continue from the note's **Next**.

Read `ROADMAP.md` only to choose, add, close, or reorder parts; read deferred Memory only when a note or Jafar
names it. A campaign still in the older shape — its progress kept in `NOW.md` or a part packet — resumes as it
is, and its next checkpoint moves the current part's position into a part note.

## Work and checkpoint

Work one part per session, one step at a time. A **checkpoint** makes the part note match reality, so any
session could take over from that point:

- After each step that works: tick it, rewrite **Next**, and commit the step's files and the note.
- **Next** states the exact next action — what, where, and anything half-done — so a fresh session can act on
  it without this conversation.
- A question waiting for Jafar goes into the note word for word, so the next session can ask it again.
- Work found outside the part: add it to `ROADMAP.md` if it belongs to this campaign, otherwise defer it; then
  carry on with the part.
- When the part proves bigger than one session, or the conversation gets summarized to free space, checkpoint
  at the next working step, move the remaining steps into a new part, and hand over.
- When the campaign's state changes — Planning, In progress, Paused, or Blocked — update its `INDEX.md` row.
- Before each checkpoint, keep every Memory file you touched within its word limit, delete what the next
  session no longer needs, and confirm each pointer resolves.

Commit only your own changes; another session's uncommitted edits are theirs. Memory lives only in the main
folder, on `main`. From a temporary worktree, commit code on its branch and the part note in the main folder;
the note names the worktree and branch. Change shared files — `INDEX.md`, `NOW.md`, `ROADMAP.md`, stage files
— by editing lines in place, never by rewriting them whole, so parallel sessions keep each other's lines.

## Pause

When Jafar says pause, or the session has to stop, checkpoint where you are. On `main`, commit only working
steps and describe any half-done change in **Next**, naming its files; in a worktree, commit it to the branch
as work in progress. Then release the claim and give Jafar the resume command:
`read memory and continue <campaign>`.

A session that stops without warning resumes from its last checkpoint, at most one step back. Its claim stays
until Jafar confirms that session is closed.

## Finish

**A part** is finished when its done-check passes on `main`. Move anything durable to its permanent home — behavior that
changed into the plan, with Jafar's approval; a technical decision into an ADR. Mark the part done in
`ROADMAP.md` with the date, delete its note, point `NOW.md` at the next part, commit, and release the claim.
When every part of a stage is done, reduce the stage to one roadmap line and delete its file.

**A campaign** is finished when every part is done. Set the plan's status to built, remove the campaign's
`INDEX.md` row, delete its folder, and commit. Git keeps the history.

## Defer

Defer work that lies outside the campaign or has to wait for something outside it. Search `Memory/deferred/INDEX.md` first and
update the existing record if the same work is there. Otherwise add a row and a note from the template: why it
waits, what brings it back, and only the constraints already known. Remove both when the work is done or
dropped.
