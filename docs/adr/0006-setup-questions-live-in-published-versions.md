# ADR 0006: Setup stages and questions live in published database versions; built-in answer rules stay in code

## Status

Accepted 2026-10-03, with client onboarding part A3. Describes the current implementation. Jafar approved a
future change on 2026-10-07: a business already filling Setup will stay on its started program version until
an owner-reviewed move. That change remains to be designed and built; do not treat this ADR's live-update
rule as the target behavior for the industry expansion. Follows plan §2.1 of the
[client onboarding and delivery plan](../client-onboarding-delivery-behavior-contract.md) (Jafar writes the
setup). Revises [ADR 0005](0005-client-setup-answers-draft-snapshot-accepted.md) decision 3; the rest of
ADR 0005 stands.

## Context

ADR 0005 kept the list of setup questions in `src/lib/setup/catalogue.ts`, so every new question was a code
change. Plan §2.1 now has Jafar adding, rewording, reordering and removing stages and questions himself,
editing a draft and publishing it. Clients still filling in setup must see a published change at once.
Some questions feed CRM settings or provider registration, and the app depends on what their answers look
like.

## Decision

1. **Three tables, versioned like package editions (ADR 0003).** `setup_versions` holds at most one draft
   and one published version; publishing freezes a version and the previous one becomes superseded. A
   trigger refuses any change to a published version's stages and items. `setup_stages` lists a version's
   stages in order, each optionally tied to one service from `package_services` (A2). `setup_items` lists
   each stage's items in order.
2. **A heading is an item, not a separate level.** An item is a heading or a question. Questions sit under
   the heading before them, the way Google Forms, Jotform and Tally place section titles inside a page. One
   ordered list per stage keeps reordering to one operation, and today's grouped cards render unchanged.
3. **Keys stay the identity.** A stage's `stage_key` and a question's `fact_key` never change across
   versions, because answers (`organization_setup_answers`), sections marked done and support chats refer
   to them. A fact key is unique within a version, so a fact is still asked once.
4. **Built-in questions take their rules from code.** `BUILT_IN_FACTS` in `src/lib/setup/catalogue.ts`
   holds each built-in question's answer type, choices and size limits. The database stores only its
   wording, position, required and "don't have it / need help" flags, so editing setup can never change
   what a built-in answer looks like. A built-in row the code has no rules for is left out. Every other
   question stores its own answer type in the row.
5. **Read fresh, never cached.** Every setup read and save loads the published version through
   `public.setup_published_catalogue()`, a single small read. Answers to a question removed from the
   version stay stored; nothing reads them.

## Rejected

- **A separate groups table.** A third level Jafar would have to manage, for nothing a heading item
  cannot do.
- **Storing every rule in the database, including built-in ones.** A wrong edit could change the answer
  type of a fact that feeds CRM settings or a texting registration.
- **Editing the published version in place.** A client halfway through a stage could see a half-edited
  question, and B13's snapshot could not name what the client was shown.

## Consequences

- A4 adds draft creation, publish and the stage editor; A5 adds custom answer types (yes/no, date, file),
  the "show only if" rule, and the limits on built-in questions.
- B13's snapshot should record the setup version it was taken against.
- A new built-in question needs both a `BUILT_IN_FACTS` entry and a published row.
