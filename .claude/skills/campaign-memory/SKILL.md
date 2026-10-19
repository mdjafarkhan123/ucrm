---
name: campaign-memory
description: Continues, saves, and finishes multi-session work (campaigns) kept in Memory/, and starts new ones. Use when Jafar says "read memory and continue", names a campaign, or asks for work that will not finish in one session.
---

# Campaign Memory

A **campaign** is work that needs more than one session. Its **plan** (`docs/<feature>-behavior-contract.md`)
holds what Jafar agreed; its `Memory/` folder holds where the work stands and, in plain English, what it is
for, so a fresh session can carry on without old chats.

**Small task** (it will finish in this session and no campaign covers it): follow CLAUDE.md and skip the rest
of this file. If it grows past one session, give it a campaign before you stop.

## Continue a campaign

1. **Campaign.** Read `Memory/INDEX.md` (no `Memory/` folder: follow [setup.md](setup.md)). Take the campaign
   Jafar named, or the one whose purpose covers his request; a new one starts in [planning.md](planning.md).
   For a bare "read memory and continue", find the campaigns whose next work is unclaimed and not blocked (their
   `NOW.md` and the register show this): continue the only one, or ask Jafar which and say what the blocked ones
   wait for. Never choose by file order, date, or another chat.
2. **Core agreement.** Read the campaign's `NOW.md`, then the plan sections it lists as the core agreement
   (goal, scope, audience, design target, rules for every part), on every resume and before choosing work.
3. **Part.** Take the part Jafar named; otherwise a started, unclaimed part that waits on nothing; otherwise
   `NOW.md`'s next part. Open `ROADMAP.md` only to choose a part or update its state. If those are claimed, or
   Jafar wants any free part, take one whose dependencies are done and whose files no claim covers. If none can
   move, tell Jafar what each one waits for.
4. **Claim** the part with CLAUDE.md's register command before changing files or outside services; if refused,
   pick again. Another session's claim holds until its owner releases it or Jafar says that session is closed.
   Take over only unfinished files the part's note names. Read the note, its plan section, and the files it
   points to.
5. **Evidence.** Check the note against the code (in the part's branch, if it names one), Git, approvals, and
   the results of outside actions; where they disagree, trust the evidence and correct the note before
   following **Next**. If an outside action's result is unknown, or a correction would change agreed behaviour,
   ask Jafar and carry on with other approved work.
6. **Six answers.** The notes must give the goal, the agreed behaviour, what is done, what it waits for, the
   next action, and the done-check; write in anything that lives only in an old chat. Older campaigns keep their
   file layout and their approvals.

## Do the next action

Do what is missing, not every stage in turn:

- **Facts, or how proven products behave:** [proven-development](../proven-development/SKILL.md), plus
  [research](../research/SKILL.md) for long reading.
- **Jafar's product choices:** [grilling](../grilling/SKILL.md), plus
  [grill-with-docs](../grill-with-docs/SKILL.md) when terms or lasting decisions need recording.
- **A planning map, a written plan, or buildable parts:** [planning.md](planning.md).
- **A look or an interaction:** CLAUDE.md's design rules, and [prototype](../prototype/SKILL.md) when trying
  something beats discussing it, until Jafar approves an example.
- **Building or proving:** CLAUDE.md and the subject skills, until the part's done-check passes. Skills and
  documents are proved by a fresh-session trial.

A campaign request lets you pick these helpers; product decisions and outside actions still need Jafar. Reuse
recorded research, plans, designs, and approvals, and re-check a fact only when evidence contradicts it. An
approval covers only what Jafar saw. When something new comes up, send only the affected work back to planning.
Work on one part at a time; take another small related part only while your context is still clear.

## Save progress

Save before you stop, before an outside action, after your context is summarized, and whenever a decision, a
question, or half-done work would be hard to rebuild. Before a part has started, there is nothing to save.

1. **Note:** update the part's note, or create it from [the template](templates/part.md): **Steps**,
   **Stage**, and **Next** (the exact action, its files, anything half-done), and any question for Jafar word
   for word.
2. **Outside actions** do harm if repeated: sending a message, charging a card, submitting a form. Before one,
   save its exact ID and how to check whether it happened. After an interruption, check before repeating it;
   if you can't tell, ask Jafar.
3. **Agreement:** `NOW.md`, the roadmap, and the note agree on stage, dependencies, blockers, and next action;
   a blocked part never becomes next just because it started first. `NOW.md` links every rule for all parts.
   Update the campaign's index row when its state changes.
4. **Homes:** agreed behaviour → the plan; lasting technical choices → an ADR; design approvals (what was shown,
   and where) → the note; in-scope discoveries → the roadmap, as parts proposed to Jafar; unrelated work →
   [deferred](finishing.md#put-work-aside). Link proof instead of copying it. Built but unchecked work stays
   unfinished.
5. **Check:** run `python3 .claude/skills/campaign-memory/scripts/check_memory.py` and fix all it lists. To
   shorten a note, move detail to its proper home and keep every requirement.
6. **Commit.** Pushing, branches, and claims follow CLAUDE.md and `docs/agent-concurrency.md`. Tell Jafar how to
   continue: `read memory and continue <campaign>`.

To finish a part or the campaign, follow [finishing.md](finishing.md).

## Where things live

`Memory/INDEX.md` lists the campaigns. A campaign's folder holds `NOW.md`, `ROADMAP.md`, notes for unfinished
parts in `parts/`, and, for a long roadmap, group files in `stages/`. Put-aside work lives in `Memory/deferred/`.
New files start from the [templates](templates/).

- A part's **stage** is Planning, Design, Build planning, Building, or Verifying.
- A campaign's **state** is Planning; In progress; Paused (work is available, no session is on it); or Blocked
  (Jafar, an outside answer, or a dependency stops all of its work).
