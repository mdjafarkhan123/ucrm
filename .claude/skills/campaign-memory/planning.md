# Planning a campaign

Read this to start a campaign, to work a planning part, or to split an approved plan into parts.

## Is it a campaign?

Make it a campaign when the work cannot finish well in one session: it has several outcomes that can each be
checked on their own, or holding all of it in one conversation would crowd out careful building and checking.
File count, step count, and guessed size are hints, not rules. Anything smaller is an ordinary task.

## Start

1. Read `Memory/INDEX.md` for a campaign that already covers this work, and search `Memory/deferred/INDEX.md`
   for matching postponed tasks; open only the matches.
2. Agree the **goal** with Jafar in a sentence or two: what users can do when the campaign is done.
3. If an approved plan already covers the goal, go to [Split](#split). Otherwise the campaign opens with
   planning parts.
4. Register it: add the `INDEX.md` row; create `NOW.md` and `ROADMAP.md` from the templates with the parts
   known so far; and when no plan exists yet, create the plan from its template.

The campaign is ready when its `INDEX.md` row, `NOW.md`, and `ROADMAP.md` all point to the same next part.

## The plan

One plan per feature, in plain English, describing what its users see and do: the workflow, screens, states,
rules, permissions, and edge cases. Guarantees users rely on belong here too, stated as behavior — "sending twice
never sends the customer two messages"; how the system keeps them is technical planning, done during the
build. A very large feature keeps one main plan that links its sub-documents. The plan opens with a summary
Jafar can read in a minute and closes with two lists:

- **Still unclear** — questions not settled yet.
- **Not doing** — what is ruled out of this feature, and why.

The body holds only settled behavior. Research goes in its own files, linked from the plan.

## Planning parts

Planning moves in parts, like building. Each planning part settles a group of related questions from **Still
unclear**, and its note lists them as steps. For each question:

1. Research how mature products handle it, as the project's research rules direct.
2. Put the choice to Jafar in everyday words with your recommendation. Ask every question that doesn't depend
   on another open one in the same round.
3. Write the answer into the plan body, remove the question from **Still unclear**, and checkpoint.

A new question that surfaces joins **Still unclear**. Before asking for approval, check that every behavior can
be built with the project's technology and outside services, and write any limit the check uncovers into the
plan as behavior. Planning is done when **Still unclear** is empty — or holds only what Jafar chose to leave for
later — and Jafar approves the plan. Write the approval and its date into the plan's status line.

## Split

Turn the approved plan into build parts, working out the technical approach as you go under the project's
engineering rules; record lasting technical decisions in ADRs. Each part:

- delivers a thin but complete piece Jafar can try — screen, server, data, and tests together, rather than one
  layer at a time;
- fits one focused session;
- has a done-check anyone can observe, such as "the owner voids a paid invoice and the client's credit goes
  up";
- names the parts it waits for.

Put the riskiest or least certain piece in the earliest parts. Show Jafar the list — each part's name, what it
delivers, and what it waits for — and ask whether any part is too big or too small and whether the order is
right. Revise until he approves, then write the parts into `ROADMAP.md`.

When the parts would push `ROADMAP.md` past its word limit, group them into stages: `ROADMAP.md` lists the
stages, one line each, and each stage's parts live in `stages/<stage>.md`.
