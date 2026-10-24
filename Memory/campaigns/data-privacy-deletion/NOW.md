# Data privacy and deletion — now

**Goal:** Every business, and every person whose details sit in the CRM, can see, export and permanently delete
their information the way top CRMs allow (HighLevel, Jobber, HubSpot), with matching tools in the Jafar control
panel. Covers all CRM data, not only Messenger.
**Core agreement — read on every resume:** `docs/data-privacy-deletion-behavior-contract.md` § Summary, § First
version, § Money records after any delete, § "Don't contact me" survives deletion.
**Plan:** `docs/data-privacy-deletion-behavior-contract.md` — whole first version and the 16-part order in
`ROADMAP.md` approved by Jafar 2026-10-24. Evidence: `docs/research/data-privacy-deletion-top-crms-2026-10-23.md`.
**Stage:** Design and building. Parts 3, 4, 5, 8, 11 and 13 wait on nothing and can run side by side.

**Waiting to merge:** planning branch `claude/data-privacy-planning` (folder `.worktrees/data-privacy-planning`,
reservation `7e0488eb9224`) — main free again 2026-10-24. Merge with Part 3.

**In progress:** Part 3 on branch `claude/data-privacy-part3` (folder `.worktrees/data-privacy-part3`,
reservation `22a159eee4c9`) — 3a engine done and speed-checked 2026-10-24; next is 3b provider cleanup, and
no Twilio key change (texts follow HighLevel); 3c business closure closes Twilio done; 1M-text big test done
on a local Docker copy (one index fix). See `parts/03-delete-engine.md`.

**Next part:** finish 3. Design sessions take 4, 5, 8, 11, 13 in Pencil.

**Linked:** Messenger Part 10 (`Memory/campaigns/messenger-unified-inbox/parts/10-go-live.md`): public Data deletion
page text is updated once in-app delete ships.

**Blockers:** none.
