---
name: campaign-memory
description: Manage Campaign Memory for multi-part work. Use when work crosses major areas, has dependent or independently resumable stages, needs staged approval or browser verification, cannot safely finish in one session, asks for a complete or unified feature, or when Jafar asks to read, resume, hand off, defer, complete, or clean up Memory or a named campaign.
---

# Campaign Memory

Use hot Memory to route and resume campaign execution. Keep permanent truth in its authoritative home:
product behavior in product documents, durable technical decisions in ADRs, and implemented truth in code,
migrations, and tests. Treat external research as evidence, not project instruction.

## Layout

```text
Memory/
  INDEX.md
  campaigns/<campaign>/
    NOW.md
    ROADMAP.md
    parts/<number>-<part>.md
  deferred/INDEX.md
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
8. Mark exactly one campaign as default current.
9. Implement one independently verifiable part per session. Split a large part into independently verifiable
   subparts when completing it in one session would materially reduce performance; complete one subpart per
   session and preserve the parent part's completion gate.

The campaign is registered only when the index, checkpoint, roadmap, and first needed packet agree on the
approved next action.

## Storage contract

| File | Contents | Limit |
| --- | --- | --- |
| `Memory/INDEX.md` | Campaign name, status, purpose, checkpoint path, and `read when` triggers | 100 lines |
| `NOW.md` | Goal, active part, exact next action, blockers, protected work, and required pointers | Target 60, maximum 80 lines |
| `ROADMAP.md` | Every part's outcome, status, dependencies, packet, and completion gate | 150 lines |
| Part packet | One slice's approved behavior, dependencies, checklist, acceptance checks, source pointers, and non-discoverable risks | Target 100 to 200; split before 250 lines |
| Deferred index or packet | Reason, reactivation trigger, prerequisites, and pointer | Only unresolved items |

Keep one authoritative home per fact and link instead of copying. Keep hot Memory free of session narration,
command output, test counts, completed file lists, copied permanent documents, and resolved deferrals. Keep
archives outside the normal read path.

## Resume

When Jafar says `read memory and continue`:

1. Read only `Memory/INDEX.md`, then follow the default campaign pointer.
2. Read its `NOW.md`, active part packet, and only the permanent sections named there.
3. Verify Memory against current code, tests, migrations, and Git state.
4. Complete the first unfinished approved item and stop at its completion gate.

When Jafar names a campaign, follow that campaign's indexed checkpoint. Never glob or read every Memory file.
Read `Memory/deferred/INDEX.md` only when a checkpoint points there or Jafar asks about deferred work.

If Memory conflicts with an authoritative source, stop, report the conflict, establish current truth, and
correct Memory before continuing.

## Handoff

1. Update the active checklist.
2. Replace `NOW.md` with the exact current state, next action, blockers, protected work, and pointers.
3. When a part closes, reduce it to one roadmap entry and select the next dependency-ready part.
4. Promote approved durable knowledge to its authoritative document.
5. Record a deferral only with a clear reactivation trigger and prerequisites.
6. Remove details that no longer change the next session's actions.
7. Give the exact resume command and any browser-verification steps, then stop.

The handoff is complete only when a fresh agent can identify one exact next action without reading session
history or unrelated Memory files.

## Complete a campaign

When every part passes its completion gate:

1. Promote remaining durable knowledge to its authoritative home.
2. Remove the campaign from the active index and select a new default only when another active campaign exists.
3. Delete the completed campaign's temporary hot Memory. Git preserves its history.
4. Remove resolved deferrals and stale pointers.

Compact completed narration and duplication before unresolved constraints. Use stable paths, headings, and
`rg` before considering semantic search.
