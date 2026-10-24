# Data privacy and deletion — now

**Goal:** Every business, and every person whose details sit in the CRM, can see, export and permanently delete
their information the way top CRMs allow (HighLevel, Jobber, HubSpot), with matching tools in the Jafar control
panel. Covers all CRM data, not only Messenger.
**Core agreement — read on every resume:** `docs/data-privacy-deletion-behavior-contract.md` § Summary, § First
version, § Money records after any delete, § "Don't contact me" survives deletion.
**Plan:** `docs/data-privacy-deletion-behavior-contract.md` — whole first version and the 16-part order in
`ROADMAP.md` approved by Jafar 2026-10-24. Evidence: `docs/research/data-privacy-deletion-top-crms-2026-10-23.md`.
**Stage:** Design and building. Parts 3, 4, 5, 8, 11 and 13 wait on nothing and can run side by side.

**Done:** Part 3 built 2026-10-24 (engine, stored-file cleanup, business closure closes Twilio) on branch
`claude/data-privacy-part3`, merged to main together with the planning branch. Follow-ups done the same day; only
Jafar's AWS and Twilio console checks remain (`parts/03-delete-engine.md` § Still with Jafar).

**Next part:** design sessions take 4, 5, 8, 11, 13 in Pencil (they wait on nothing). Part 6 builds after 3, 4, 5.

**Linked:** Messenger Part 10 (`Memory/campaigns/messenger-unified-inbox/parts/10-go-live.md`): public Data deletion
page text is updated once in-app delete ships.

**Blockers:** none.
