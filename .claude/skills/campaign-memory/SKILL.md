---
name: campaign-memory
description: Manage lightweight roadmaps and checkpoints for work that spans sessions, has independently resumable stages, or is likely to need a fresh session to stay reliable. Use for campaign start, resume, checkpoint, handoff, pause, deferral, completion, cleanup, or when Jafar asks to read Memory and continue.
---

# Campaign Memory

Memory is temporary feature-delivery storage. It helps a fresh agent answer three questions: what are we
building, where did we stop, and what is the next approved action?

The skill is the operating contract. `Memory/` only stores campaign state created under this contract.

## Minimal-memory rule

Save a fact only when both are true:

1. A future session needs it to continue safely.
2. It cannot be quickly rediscovered from the authoritative source.

Keep product truth in product documents, durable technical decisions in ADRs, and implementation truth in
code, migrations, tests, and Git. Link to an authoritative source when a pointer is enough.

Memory may hold the feature goal, approved product decisions not yet promoted, current part, exact next
action, dependencies, blockers, completion gate, and a non-obvious risk that changes the next action. Write
each once, in the smallest file that needs it.

Keep session narration, implementation explanations, code or schema inventories, command output, test
counts, completed-file lists, research copies, and facts visible in the repository out of Memory.

## Storage

```text
Memory/
  INDEX.md
  campaigns/<campaign>/
    NOW.md
    ROADMAP.md
    parts/<active-part>.md
  deferred/
    INDEX.md
    <task>.md
```

- `INDEX.md` is a small campaign registry: name, state, purpose, checkpoint, and read trigger. It has no
  global current campaign. Target 50 lines.
- `NOW.md` is the only normal resume checkpoint: goal, active part, exact next action, blockers, and only the
  pointers required for that action. Target 20 lines; maximum 30.
- `ROADMAP.md` is the approved feature sequence: one concise entry per part with outcome, state,
  dependencies, and completion gate. Target 60 lines; maximum 100.
- An active part packet holds only approved behavior, acceptance checks, unresolved decisions, and
  non-discoverable risks for the current part. Target 40 lines; maximum 80. Create it only when the roadmap
  entry is insufficient to execute the part.
- A deferred task holds only why it is postponed, what reactivates it, and any already-known constraint that
  changes the future decision. Target 10 lines; maximum 20.

Closed parts need only their roadmap entry. Delete their packets and archives after recording the outcome and
completion state. Git is the history.

## Session sizing

Before registration, decide whether the task should remain one session. Use a campaign when it has multiple
independently verifiable outcomes, cannot finish safely in one session, or carrying the whole working context
would materially reduce reliable implementation or verification. File count, step count, and guessed token
count are signals, not thresholds.

Make each part one coherent, independently verifiable outcome likely to fit a focused session. If a part grows
beyond reliable context, split it at the nearest safe, verified boundary without changing approved behavior.
Stabilize any atomic change before stopping, update `ROADMAP.md` and `NOW.md`, and hand off. Continue in the
same session when restarting would cost more rediscovery than it saves.

## Start

1. Read `Memory/INDEX.md` if it exists to check overlap.
2. If `Memory/deferred/INDEX.md` exists, search it for terms that overlap the proposed campaign; open only
   matching tasks.
3. Inspect only the authoritative product and implementation sources needed to establish the starting state.
4. Follow the project's applicable research and approval rules; promote durable findings to their
   authoritative home.
5. Propose the campaign goal, ordered parts, dependencies, risks, and completion gates; wait for approval.
6. Register the campaign, create its concise roadmap and `NOW.md`, and create only the first needed packet.

The campaign is ready when the registry, roadmap, checkpoint, and optional active packet name the same next
action.

## Resume

When Jafar names a campaign, read only `Memory/INDEX.md` and that campaign's `NOW.md`. When Jafar says only
`read memory and continue`, use the index to identify the single dependency-ready campaign; if several
qualify, ask which one to select.

After selection:

1. Follow the pointers in `NOW.md`. Read the active part packet only when `NOW.md` points to it.
2. Read only the authoritative sections named by the checkpoint.
3. Verify the checkpoint against current code and Git state. If they disagree, repair Memory from the
   authoritative state before acting; ask Jafar only when the correction changes approved scope or behavior.
4. Perform the exact next approved action and stop at its completion gate.

Do not read `ROADMAP.md` during an ordinary resume. Read it only to plan a campaign, change scope, close or
select a part, resolve a dependency, or repair inconsistent Memory. Read deferred Memory only when the
checkpoint or Jafar names it.

Campaign selection is conversation-local. Several campaigns may be in progress. Never infer a global current
campaign from file order, recency, or another conversation.

## Checkpoint and handoff

After any turn that changes a campaign's state, refresh its checkpoint before the final response. Discussion
and review turns with no campaign-state change do not write Memory.

1. Promote durable knowledge to its authoritative home.
2. If a part closed, reduce it to its roadmap entry, delete its packet after promotion, and select the next
   dependency-ready part. Read the roadmap for this transition only.
3. Replace `NOW.md` with the current goal, active part, exact next action, blockers, and essential pointers.
4. Keep only unresolved context that changes the next session's action.
5. When handing off or pausing, give Jafar an exact resume command naming the campaign.

A checkpoint is complete when a fresh agent can identify one exact next action from the index and `NOW.md`,
then load no more than the explicitly required active packet and source sections.

## Pause, defer, and complete

Use `Planned`, `In progress`, `Paused`, or `Blocked` in the registry. Update only the selected campaign.

Before creating a deferral, search the deferred index and task names for the same underlying work. Update an
existing record instead of creating a duplicate. If the work remains owned by an active campaign, keep it in
that campaign's roadmap; use global deferred Memory when it must remain discoverable independently.

For a global deferral, add one short index row and one short task file containing the reason, reactivation
trigger, and only already-known constraints that change future work. Leave unresearched detail absent rather
than investigating merely to fill the note. Remove the row and file when the task is resolved.

When every part passes its completion gate, promote remaining durable knowledge, remove that campaign's
registry row, and delete its temporary campaign folder. Preserve unrelated campaigns and deferrals.

Before every checkpoint, deferral, pause, or completion, prune Memory against the minimal-memory rule and
verify that all remaining pointers resolve.
