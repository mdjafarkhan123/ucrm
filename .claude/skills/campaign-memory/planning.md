# Planning a campaign

For a new campaign, unfinished planning, writing the plan, or splitting approved work into parts. Recorded
answers and approvals stay valid; a plan may grow over several planning parts.

## Start

1. Search `Memory/INDEX.md` and `Memory/deferred/INDEX.md` for the same work and open only the matches.
   Continue a matching campaign rather than starting another. A matching deferred note brings its constraints;
   delete its row and note once the campaign takes it up.
2. Agree a short goal with Jafar: what the user actually wants, who gains what ability, and why it matters.
   Work earns a campaign when it has several separately checkable outcomes or would crowd one conversation, not
   because it touches many files.
3. Claim the first part. Create the plan, `NOW.md`, and `ROADMAP.md` from the [templates](templates/); `NOW.md`
   and the roadmap point at the first planning part (an approved plan can start at a later stage). Add the
   campaign's row to `Memory/INDEX.md`.
4. For unsettled behaviour, follow the `proven-development` skill: research facts yourself and label each one
   verified, inferred, or our proposal. Put the remaining choices to Jafar with the `grilling` skill, in
   everyday English with a recommendation; use `grill-with-docs` when terms or lasting decisions need recording
   (its glossary is not the plan). Ask only what saved sources don't answer; routine technical details are
   yours to decide.
5. Write each answer into the plan at once, and keep open questions under **Still unclear**. If the interview
   stops, save the exact pending question in the part's note.

## Specialist contract

When this workflow sends you to `grill-with-docs`, `wayfinder`, `to-spec`, or `to-tickets`, use their method but
keep their output in the plan, the roadmap, and the part notes: no `.scratch` tickets, no issue-tracker
statuses, nothing published to an outside tracker. Give the helper the saved sources instead of the old
conversation; recorded approvals and order still count. Then record its output and return to Campaign Memory to
check and save. Called on its own, outside a campaign, a helper keeps its own workflow.

## Large planning

Use the `wayfinder` skill when the decisions themselves need more than one session. The roadmap becomes the
map: the planning goal, small decision parts, what each waits for, and links to the plan sections that hold the
answers. Questions not yet precise go under **Still unclear**, deliberate exclusions under **Not doing**.
Research and prototypes settle facts, never Jafar's approval. Load only the active decision's detail. When the
map is clear, write the full plan before splitting build parts.

## Write the plan

The `to-spec` skill writes up what is already understood; it does not replace unfinished planning. Fill the
plan template in plain English, starting from what the user actually wants, and keep proposals and assumptions
apart from agreed behaviour. Write promises as behaviour, such as "retrying does not send the customer a second
copy." Link research and design decisions instead of copying them; technical detail belongs to a build part or
an ADR.

Before asking Jafar to approve:

1. Check the plan against the real stack and providers, and write any limit users will notice into it.
2. **Fresh-reader check:** give a fresh agent the plan and its named sources, without this chat, and ask which
   important questions it still needs answered before planning the build, and what a wrong guess would cost.
   If you can't start one, read the plan that way yourself and tell Jafar so.
3. Settle facts and routine technical questions yourself; bring Jafar the remaining product choices together.

Planning is done when no first-version question is open and Jafar approves the scope. Record the scope and
approval date in Memory; the plan stays the current agreement. Later-version questions may stay open once
explicitly moved to later. Changing one part of the scope leaves the other approvals standing.

## Split the work

Use the `to-tickets` skill to draft parts from the approved plan, reusing approved parts. Each part delivers a
thin, complete result that can be shown or checked, fits one focused session, points to its plan section, names
what it waits for, and has an observable done-check. Put the riskiest unknowns first. A technical foundation may
be proved technically; say which user result it enables.

Show Jafar each part's name, result, and dependencies, and settle size and order before recording his approval.
Re-splitting interrupted work keeps its approved scope and order unless something really changed. Every
first-version requirement needs a part, and every part a requirement; fix conflicts, missing checks, vague
claims, and mismatched names. Save the parts in `ROADMAP.md`, moving them into group files under `stages/` once
it outgrows its word limit. An approved design can come before this split or be its first part.
