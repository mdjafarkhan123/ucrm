---
name: campaign-memory
description: Guide multi-session work from planning through design, building, verification, and handover. Use to start, resume, checkpoint, pause, defer, or finish a campaign, or when Jafar says to read Memory and continue. Clear single-session tasks take the short path.
---

# Campaign Memory

Be the parent workflow: establish what Jafar wants, choose the necessary specialist guidance, and leave a
fresh session able to continue without this chat. A **campaign** is work that cannot finish well in one
session. Its product plan records the agreement; `Memory/` records the current position. This skill guides
each session.

## Start or resume

1. Read `Memory/INDEX.md` and the live register as the project's coordination rule directs. With no Memory,
   read [setup.md](setup.md). For a small clear task, follow the relevant project skills directly; create no
   campaign unless unfinished work needs a handover.
2. Select the campaign Jafar named, or an existing one covering his goal. For an unnamed continuation, take
   the only campaign with unclaimed work that can move now; if several qualify, ask which and mention those
   waiting on Jafar. Never select from file order, recency, or another chat.
3. For a new campaign, read [planning.md](planning.md). Otherwise read its `NOW.md` **and the plan's core
   agreement named there**: goal, scope, audience, experience or design target, and rules that govern every
   part. This is required on every resume, before choosing work; it cannot be left behind a pointer reached
   only for a specific task. Then read the named part's note or roadmap line. Without a named part, prefer a
   started, unclaimed part that is waiting on nothing, then the next part in `NOW.md`. Consult the roadmap
   only to choose or change parts. If these are claimed, or Jafar asks for any available part, choose a
   dependency-ready part whose code and services do not overlap claimed work. If none can move, explain what
   it waits for. A held claim stays held until its owner releases it or Jafar confirms that session is closed.
4. Claim before changing files or outside services. Take over only the unfinished files identified as that
   part's work under the coordination rule; unknown changes need their ownership established first. If the
   claim loses a race, choose again. Read the selected part's plan section and source pointers; the core
   agreement was already read in step 3. Read other campaign documents only when that part needs them.
5. Verify the saved position against actual code, approval records, and the outcome checks of outside
   actions. Resolve contradictory progress from evidence before following **Next**. If an outcome is unknown,
   or a correction changes agreed behavior, ask Jafar and continue independent authorized work.
6. Identify the goal, agreed behavior, current stage, completed work, blockers, next action, and done-check.
   If any necessary answer exists only in an old chat, repair the documents before dependent work. In older
   campaigns, infer the stage from the saved work and add it at the next checkpoint; do not demand migration
   or repeat valid approvals.

## Choose the next action

Choose from what is missing, rather than repeating every stage. Track the active part's stage when a
campaign has several parts in different stages. For planning actions, read the relevant section of
[planning.md](planning.md) before loading its helper. Keep control of the handover afterward.

| What is missing | Guidance to load | Completion boundary |
| --- | --- | --- |
| Facts or proven behavior | [Proven Development](../proven-development/SKILL.md); [Research](../research/SKILL.md) for substantial reading | Evidence and a recommendation for the unresolved decision |
| Product choices | [Grilling](../grilling/SKILL.md); [Grill with Docs](../grill-with-docs/SKILL.md) when terminology or lasting decisions need recording | Answers in the plan; open questions visible |
| A large planning map | [Wayfinder](../wayfinder/SKILL.md), through [planning.md](planning.md#large-planning) | Decision parts and dependencies saved |
| A readable product agreement | [To Spec](../to-spec/SKILL.md), through [planning.md](planning.md#write-the-plan) | Complete plan, fresh-reader check, scoped approval |
| A visual or interaction decision | [delivery.md](delivery.md#design) | A reviewable example and the decision recorded |
| Buildable parts | [To Tickets](../to-tickets/SKILL.md), through [planning.md](planning.md#split-the-work) | Complete slices, dependencies, checks, approved order |
| Implementation or proof | [delivery.md](delivery.md#build-and-verify) and project subject skills | The promised behavior and its appropriate verification |
| A stopping point or completed part | [handover.md](handover.md) | Consistent checkpoint, or recorded completion |

A campaign request authorizes routine skill selection, not new product decisions or outside actions.
Load helpers through the host's supported skill mechanism; where unavailable, read their referenced files
as guidance. Respect host permissions and availability. If a needed specialist is absent, use available
project guidance for the same outcome; ask for help only when a real capability is missing. Design tooling is
optional. Reuse settled research, plans, and designs; return only affected work to planning when new questions
arise. Already recorded authorization counts.

## Document homes

```text
Memory/
  INDEX.md
  campaigns/<campaign>/
    NOW.md               goal, mandatory core-agreement pointers, stage, active and next part, blockers
    ROADMAP.md           part, plan section, dependency, done-check, state
    stages/<stage>.md    parts when the roadmap needs grouping
    parts/<part>.md      unfinished work, source pointers, exact next action
  deferred/
    INDEX.md
    <task>.md
```

The plan lives where the index header says, one permanent agreement per feature, linking sub-documents
when needed. Research holds evidence. ADRs hold lasting technical choices and reasons. Code, tests,
migrations, and Git show implementation. Ordinary unfinished technical reasoning stays with its part;
larger implementation plans use a linked focused document.

Use only the relevant [template](templates/) when creating a document. Keep agreement and state in their
own homes, linked rather than copied; put a short goal and explicit core-agreement pointers in `NOW.md` so
every resuming agent reaches the campaign-wide target. Helpers use these homes instead of another tracker.
Memory points to meaningful proof and code locations instead of copying transcripts or session history.

Word limits: `NOW.md` 200 · roadmap and stage file 800 each · part 500 · deferred task 150 · index row 50.
Move excess detail to its proper source without removing necessary constraints. Before stopping, completing,
or taking a repeat-sensitive outside action, use [handover.md](handover.md).
