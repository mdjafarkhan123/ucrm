# Jafar Business Management — stage B: Leads to client

Jafar alone uses these first; owner fields default to Jafar and accept teammates once stage D lands. Uplift needs its own records — contractor opportunities, tasks, and schedule tables are organization-scoped — while reusing `components/pipeline` screens.

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| B1 Leads list and adding a Lead | One business relationship record; Leads list with status, country, trade, source, owner, next action; add form with contact source and fit notes; possible-duplicate warning | A1 | Jafar adds "Smith Plumbing, UK"; adding the same website again shows the possible duplicate; filters by status and country work on a large test list | Done 2026-10-07 |
| B2 Lead page and history | Notes, logged outside contact (email, call, message) and replies, next action; Applications labelled as such and linkable to the relationship | B1 | Jafar logs "emailed from Gmail" and a reply, links an existing Application, and sees one history | Done 2026-10-07 |
| B2b Editing a Lead's details | Change the business, contact details (with where found), source and fit notes from the Lead page | B2 | Jafar fixes a typo in a Lead's email; its history and any logged contact keep pointing to that detail | Done 2026-10-07 |
| B3 Approving who to contact | Review queue with reasons, sources, exclusions; approve per contact method or send back; personal contact tasks; opt-out stops everything; nothing sends | B2 | Jafar approves 3 of 5; the opted-out one shows excluded with its reason; approved ones get a contact task | Done 2026-10-07 |
| B4 Deals board | Deal from an interested Lead or booked call; stages, Later with date, lost reason, pricing link (`/packages/[slug]`) with price snapshot, follow-up due | B2 | Jafar shares the Pro link; a later price change leaves the Deal's shared price unchanged; dragging stays instant on phone | Done 2026-10-07 |
| B5 Won and handover | Won only after payment confirmation on the linked Application; handover with first onboarding action owner; Client view linking organization, onboarding, support, package, payments | B4 | Won is blocked until payment is confirmed; afterwards the business shows as Client with its onboarding stage | Not started |
