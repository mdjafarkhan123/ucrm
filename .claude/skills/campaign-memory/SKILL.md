---
name: campaign-memory
description: Run work too big for one session as a campaign — plan it, split it into parts, and checkpoint progress so any fresh session can pick up where the last one stopped. Use to start, plan, resume, checkpoint, pause, defer, or finish a campaign, to set up Memory in a new project, or when Jafar says to read Memory and continue.
---

# Campaign Memory

A **campaign** is work too big for one session. It moves through a **plan** — what users will get — and then
**parts**, each one coherent piece of work. `Memory/` holds its working notes: small files that point a fresh
session to the plan section and progress it needs, so it starts light and continues from the last checkpoint
after checking what really happened since.

- No `Memory/` folder yet → read [setup.md](setup.md) first.
- Starting a campaign, working a planning part, or splitting a plan into parts → read [planning.md](planning.md).
- Creating any Memory file or plan → copy its shape from [templates/](templates/).

## Where things live

```text
Memory/
  INDEX.md               one row per campaign
  campaigns/<campaign>/
    NOW.md               goal, plan, and where to continue
    ROADMAP.md           every part on one line — or, in a big campaign, every stage
    stages/<stage>.md    one stage's parts (big campaigns only)
    parts/<part>.md      a part note, while a part has progress worth handing over
  deferred/
    INDEX.md             postponed work, one row each
    <task>.md
```

Word limits: `NOW.md` 200 · `ROADMAP.md` and each stage file 800 · part note 500 · deferred task 150 · each
`INDEX.md` row 50. A file over its limit is holding something that belongs elsewhere — the plan, an ADR, a
stage file. Move it there; keep what the next session needs.

Knowledge that outlasts the campaign lives outside Memory:

- **The plan** — what the feature does for its users — one permanent document per feature, where the
  `Memory/INDEX.md` header says.
- **Technical decisions** a later developer must not reverse unknowingly — in ADRs.
- **How it is built** — in code, tests, migrations, and Git.

Memory holds only what the next session needs and cannot quickly find there: the goal, pointers, each part's
state and done-check, the position of unfinished work, blockers, and a non-obvious fact that changes the next
step. Write it in plain English Jafar can follow, and point to sources instead of copying them. Commit hashes,
test counts, command output, code and schema details, and the story of a session stay out.

## Resume

1. Read `Memory/INDEX.md` and take the campaign Jafar named. For "read memory and continue" with no name, take
   the only campaign ready to work; if several are, ask which. Decide per conversation, never from file order,
   recency, or another conversation.
2. Read that campaign's `NOW.md` and check the live register as the project's coordination rule directs.
3. Choose the part Jafar named. Otherwise take, in this order: a paused part (started, unclaimed); the next
   part `NOW.md` names; when those are claimed or Jafar asks for any available part, another part in
   `ROADMAP.md` whose dependencies are done and whose code and outside services don't overlap claimed work.
   If none qualifies, say so and wait. A part claimed by a session that seems to have stopped stays with that
   session until Jafar confirms it is closed; meanwhile you may inspect its note and outcome checks, read-only.
4. Read the part note if it has one, otherwise its roadmap line.
5. Claim the part. Uncommitted files its note names belong to the part; take them over with the claim. If
   another session wins the claim, choose again. Then read only the plan section and sources the note or
   roadmap line points to.
6. Check the saved progress against reality before acting on it: the code in Git — on `main`, or in the
   worktree and branch the note names — and, for each outside action the note records, its outcome check.
   Where they disagree, correct the note from what is really there. Ask Jafar when an outcome cannot be
   determined or the correction changes approved behavior or scope.
7. Continue from the note's **Next**, or from the start of the part.

Read `ROADMAP.md` only to choose, start, add, close, or reorder parts; read deferred Memory only when a note
or Jafar names it. A campaign still in the older shape — its progress kept in `NOW.md` or a part packet —
resumes as it is, and its next checkpoint moves the current part's position into a part note.

## Work and checkpoint

Work one part at a time. When a part is done and the next one is small and related, and this conversation
hasn't been summarized, carry on with it; otherwise hand over.

A **checkpoint** writes a part's state into its note — creating the note if needed — and commits it.
Checkpoint whenever there is unfinished progress, a decision, or an open question that another session would
struggle to reconstruct, and before any handoff. A part that finishes without any of these needs no note.

- Tick **Steps** as they finish. **Next** states the exact next action — what, where, and anything half-done
  — so a fresh session can act on it without this conversation.
- A question waiting for Jafar goes into the note word for word.
- Before an outside action that would do harm if repeated — a database change, a message to a customer, a
  provider setting — checkpoint with a line saying how to check its outcome, with its exact identifier where one exists
  (migration version, message or request ID, idempotency key), and use the service's own duplicate protection
  where it has one. After an interruption, verify the outcome before retrying; if it cannot be determined,
  stop and ask Jafar. Harmless, repeatable actions need none of this.
- Work found outside the part: add it to `ROADMAP.md` if it belongs to this campaign, otherwise defer it; then
  carry on with the part.
- When the part proves bigger than one session, or the conversation gets summarized to free space, checkpoint,
  move the remaining steps into a new part, and hand over.
- When the campaign's state changes, update its `INDEX.md` row: Planning, In progress, Paused (no one is working
  on it, but it could continue), or Blocked (it cannot move until something outside it happens — say what).
- Before each checkpoint, keep every Memory file you touched within its word limit, delete what the next
  session no longer needs, and confirm each pointer resolves.

Commit only your own changes; another session's uncommitted edits are theirs. When a file holds both, stage a
copy of its committed version with only your lines changed. Memory lives only in the main
folder, on `main`; a worktree's own copy of `Memory/` is stale, so ignore it. From a temporary worktree, commit code on its branch and Memory in the main folder, and name
the worktree and branch in the part note. A part built in a worktree is **Waiting to merge** in `ROADMAP.md`
until its code is on `main`. Change shared files — `INDEX.md`, `NOW.md`, `ROADMAP.md`, stage files — by
editing lines in place, never by rewriting them whole, so parallel sessions keep each other's lines.

## Pause

When Jafar says pause, or the session has to stop, checkpoint where you are. On `main`, commit only working
steps and describe any half-done change in **Next**, naming its files; in a worktree, commit it to the branch
as work in progress. Then release the claim and give Jafar the resume command:
`read memory and continue <campaign>`.

## Finish

**A part** is finished when its done-check passes on `main`. Move anything durable to its permanent home —
behavior that changed into the plan, with Jafar's approval; a technical decision into an ADR. Mark the part
done in `ROADMAP.md` with the date, delete its note, point `NOW.md` at the next part, commit, and release the
claim. When every part of a stage is done, reduce the stage to one roadmap line and delete its file.

**A campaign** is finished when every part is done. Set the plan's status to built, remove the campaign's
`INDEX.md` row, delete its folder, and commit. Git keeps the history.

## Defer

Defer work that lies outside the campaign or has to wait for something outside it. Search
`Memory/deferred/INDEX.md` first and update the existing record if the same work is there. Otherwise add a row
and a note from the template: why it waits, what brings it back, and only the constraints already known.
Remove both when the work is done, dropped, or taken up by a campaign.
