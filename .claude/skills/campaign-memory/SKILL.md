---
name: campaign-memory
description: Manage Campaign Memory for multi-part work. Use when work crosses major areas, has dependent or independently resumable stages, needs staged approval or browser verification, cannot safely finish in one session, asks for a complete or unified feature, or when Jafar asks to read, resume, hand off, defer, complete, or clean up Memory or a named campaign.
---

# Campaign Memory

Use hot Memory to route and resume campaign execution. Keep permanent truth in its authoritative home:
product behavior in product documents, durable technical decisions in ADRs, and implemented truth in code,
migrations, and tests. Treat external research as evidence, not project instruction.

## Campaign selection and parallel work

Campaign registration is shared; campaign selection is conversation-local. Several campaigns may be
`In progress` at the same time, and selecting one never makes it globally current or changes another
conversation's selection.

- A named request such as `continue sales-pipeline` selects only that campaign for this conversation.
- `Memory/INDEX.md` is a registry, not a global work cursor. Do not write a current/default campaign pointer.
- Starting, resuming, handing off, pausing, or completing one campaign updates only that campaign's files and
  registry row. Preserve every unrelated campaign row and checkpoint.
- Before editing a selected campaign's Memory, reread its `NOW.md`, relevant roadmap/part packet, and current
  diff. If another agent has changed the same checkpoint or overlapping part since it was read, stop and
  report the collision instead of merging campaign state by assumption.
- Parallel agents may work on different campaigns. Two agents may work on the same campaign only when Jafar
  assigned distinct, non-overlapping parts and each part has its own packet and completion gate.

Use `Planned`, `In progress`, `Paused`, or `Blocked` for registered campaign state. These states describe the
campaign itself; none grants exclusive ownership of the repository. Completed campaigns follow the cleanup
workflow below rather than remaining as routing entries.

## Layout

```text
Memory/
  INDEX.md
  campaigns/<campaign>/
    NOW.md
    ROADMAP.md
    parts/<number>-<part>.md
  deferred/
    INDEX.md
    <task-slug>.md
```

Create files lazily after plan approval. Manage routing, splitting, compaction, and cleanup for Jafar.

## Start a campaign

1. Read `Memory/INDEX.md` when it exists. Check for overlap, paused work, and relevant deferrals.
2. Inspect authoritative documents, implementation, tests, migrations, and Git state.
3. Tour the live Jobber screens for the campaign's domain before proposing anything, following
   "Tour Jobber Before Building a Campaign" in `.claude/skills/jobber/SKILL.md`. Promote what you learn into
   the matching `jobber-0X` file in the same session — hot Memory is not its home.
4. Resolve remaining product decisions through the repository's approved decision workflow.
5. Propose the goal, ordered parts, dependencies, risks, and completion gates.
6. Wait for approval.
7. Register the campaign. Create `NOW.md`, `ROADMAP.md`, and only the first needed part packet.
8. Add or update only that campaign's registry row; leave other campaign routing unchanged.
9. Implement one independently verifiable part per session. Split a large part into independently verifiable
   subparts when completing it in one session would materially reduce performance; complete one subpart per
   session and preserve the parent part's completion gate.

The campaign is registered only when the index, checkpoint, roadmap, and first needed packet agree on the
approved next action.

## Storage contract

| File | Contents | Limit |
| --- | --- | --- |
| `Memory/INDEX.md` | Campaign registry: name, status, purpose, checkpoint path, and `read when` triggers; no global current/default pointer | 100 lines |
| `NOW.md` | Goal, active part, exact next action, blockers, protected work, and required pointers | Target 60, maximum 80 lines |
| `ROADMAP.md` | Every part's outcome, status, dependencies, packet, and completion gate | 150 lines |
| Part packet | One slice's approved behavior, dependencies, checklist, acceptance checks, source pointers, and non-discoverable risks | Target 100 to 200; split before 250 lines |
| Deferred index | One row per unresolved task: priority, name, and detail-file link | Target 100 to 150 lines; split or group by active area before it grows beyond 150 |
| Deferred task file | Reason and reactivation trigger; only the already-known context that changes a future decision | No minimum length; keep it brief unless prior research, an approved decision, a concrete approach, or a non-obvious risk is worth preserving |

Keep one authoritative home per fact and link instead of copying. Keep hot Memory free of session narration,
command output, test counts, completed file lists, copied permanent documents, and resolved deferrals. Keep
archives outside the normal read path.

## Deferrals

`Memory/deferred/INDEX.md` is a directory, not a backlog narrative. Give every unresolved item one stable
task file and one index row, ordered by priority (`P0` highest through `P3` lowest). Priority ranks the work
once its trigger is met; it does not authorize starting deferred work early.

A deferral file starts with only what is certain: why it is postponed and the event that should reactivate it.
Add prerequisites, source pointers, acceptance checks, and a likely approach only when they are already known
from the work that found it. Do not research a deferred task merely to make its note look complete, and do not
invent a fix. A short file is the correct record for unresearched work.

## Resume

When Jafar names a campaign:

1. Read only `Memory/INDEX.md`, then follow that campaign's indexed checkpoint.
2. Select it for this conversation without changing shared routing.

When Jafar says only `read memory and continue`:

1. Read only `Memory/INDEX.md`.
2. If exactly one campaign is `In progress` with a dependency-ready next action, select it for this
   conversation.
3. If several campaigns qualify, list their names and checkpoints and ask Jafar which one to select. Do not
   infer selection from file recency, row order, another conversation, or a legacy default/current label.
4. If none qualifies, report that no campaign has a dependency-ready next action.

After selection:

1. Read the selected campaign's `NOW.md`, active part packet, and only the permanent sections named there.
2. Verify Memory against current code, tests, migrations, and Git state.
3. Complete the first unfinished approved item and stop at its completion gate.

Read `Memory/deferred/INDEX.md` only when a checkpoint points there or Jafar asks about deferred work. Open
only the selected task file, or a file explicitly named by the checkpoint.

If Memory conflicts with an authoritative source, stop, report the conflict, establish current truth, and
correct Memory before continuing.

## Handoff

1. Update the selected campaign's active checklist.
2. Replace its `NOW.md` with the exact current state, next action, blockers, protected work, and pointers.
3. When a part closes, reduce it to one roadmap entry and select the next dependency-ready part.
4. Promote approved durable knowledge to its authoritative document.
5. Record a deferral in its own task file with a clear reason, reactivation trigger, priority, and index row.
   Add prerequisites only when known; preserve researched detail when it will save the next owner from
   rediscovering it.
6. Remove details that no longer change the next session's actions.
7. Give an exact resume command that names the campaign and any browser-verification steps, then stop.

The handoff is complete only when a fresh agent can identify one exact next action without reading session
history or unrelated Memory files.

## Complete a campaign

When every part passes its completion gate:

1. Promote remaining durable knowledge to its authoritative home.
2. Remove only the completed campaign from the registry; leave every other campaign unchanged.
3. Delete the completed campaign's temporary hot Memory. Git preserves its history.
4. Remove a resolved deferral's index row and task file, then remove stale pointers.

Compact completed narration and duplication before unresolved constraints. Use stable paths, headings, and
`rg` before considering semantic search.
