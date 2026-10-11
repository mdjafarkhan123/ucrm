# Checkpoint, pause, finish, or defer

Read before stopping, completing a part, or taking an outside action that could cause harm if repeated.
Work one focused part at a time. Continue to another small related part when context remains clear;
checkpoint and hand over when the session has been summarized or can no longer finish a coherent part.

## Checkpoint

A checkpoint saves the position in the current part note and commits it. Create a note only when unfinished
progress, an important decision, or a question would otherwise be hard to reconstruct. Checkpoint before a
handoff and whenever such information appears.

- Update **Steps**, **Stage**, and **Next**: the exact action, relevant files, and half-finished work. Save
  pending questions for Jafar word for word. A planning handover is as important as a coding handover.
- Keep unfinished technical reasoning needed by the remaining work, or link its focused implementation plan.
  Move lasting behavior into the product plan and lasting technical decisions into ADRs.
- Link meaningful proof instead of copying logs. Keep dates, identifiers, and code pointers that change the
  next action; leave session narration and test counts in evidence or Git.
- Before a repeat-sensitive outside action, save its exact identifier and how to verify the outcome; use
  the service's duplicate protection where available. After interruption, check the outcome before retrying.
  If it cannot be determined, ask Jafar. Harmless repeatable actions need no action record.
- Add discovered in-scope work to the roadmap; defer unrelated work, then continue the current part.

Before committing, confirm necessary links and source sections resolve, touched Memory files fit their
limits, and the plan's approval, roadmap, current note, and part agree about stage, dependencies, blockers,
and next action. A blocked old part must not become the next action just because it was started first.
Keep approved requirements and unfinished constraints when trimming. Use any existing project checker;
otherwise inspect the touched pointers and limits directly.

Update the campaign's index row when its state changes: Planning; In progress; Paused (available to resume,
no session working); or Blocked (an outside answer, provider, or dependency prevents all progress). A blocked
part does not block a campaign with other available work. Older record shapes can still resume: update the
current position without a forced migration of every file.

## Shared work and Git

Follow the live coordination rule. Commit only this session's changes; stage a committed copy containing
only your lines when a file also holds another session's edits. Memory lives in the main folder on `main`;
ignore stale worktree Memory. From a permitted temporary worktree, commit code there and Memory in the main
folder, naming the branch and worktree in the part. Keep it **Waiting to merge** until integrated. Edit shared
index, current-note, roadmap, and stage records in place so other sessions' lines survive.

Commit at coherent points and push under the project's rules. Release claims after safe integration and an
updated checkpoint. Report a failed push. Git preserves history; the current note need not retell it.

## Pause

When Jafar pauses or the session must stop, checkpoint, commit working steps, and name any half-done files
in **Next**. Worktree progress can be committed as work in progress. Release the claim after the checkpoint
and give the resume instruction: `read memory and continue <campaign>`.

## Finish

A part is finished when its done-check passes in the integrated project. Promote durable decisions, keep
necessary proof reachable, mark the part done with its date, delete the finished note, and point `NOW.md`
at the next available work. Commit and release or transfer the claim before continuing another part.
Reduce a fully completed stage to a roadmap line and delete its stage file.

A campaign finishes only when the agreed first version is verified and every required part is done. Open
release conditions or owner checks remain visible. Set the plan built, remove the campaign's index row and
folder, and commit; Git retains history. Later-version work already excluded from this scope may be deferred.

## Defer

Search `Memory/deferred/INDEX.md` before creating a record. Update a matching task, or add a row and note
from its template: why it waits, what brings it back, and known constraints. Remove both when done, dropped,
or taken up by a campaign. Resume deferred work only when Jafar or a relevant note names it.
