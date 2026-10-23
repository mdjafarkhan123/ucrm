# Data privacy and deletion — now

**Goal:** Every business, and every person whose details sit in the CRM, can see, export and permanently delete
their information the way top CRMs allow (GoHighLevel, Jobber, HubSpot), with matching tools in the Jafar control
panel. Covers all CRM data, not only Messenger.
**Core agreement — read on every resume:** none yet; the plan is written in this campaign's first session.
**Plan:** not started. Started by Jafar 2026-10-23: "we need to fix all CRM data and all necessary UI/work if
missing… we will follow what top CRMs do."
**Stage:** Planning — research first (proven-development), then plan for Jafar's approval.

**Known today (code check 2026-10-23):** clients and leads can only be archived (`src/routes/api/clients/archive`);
inbox conversations have no delete; the Jafar panel has no per-person delete; closing a whole business purges all
its data after the recovery period (`src/lib/server/jafar/organization-closure-cron.ts`), and Messenger tables
cascade with it. Deletion requests are handled by email and by hand meanwhile.

**Next part:** research how top CRMs handle permanent client/contact delete, conversation delete, data export,
a person's deletion request (GDPR/CCPA), the undo window, and records the law requires keeping (invoices,
payments). Then write the plan.

**Linked:** Messenger Part 10 (`Memory/campaigns/messenger-unified-inbox/parts/10-go-live.md`): the public Data
deletion page (`docs/marketing-site/legal-pages.md`) must be updated once in-app delete exists.

**Blockers:** none.
