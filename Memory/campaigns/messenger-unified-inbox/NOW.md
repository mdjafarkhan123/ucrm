# Messenger in the Unified Inbox — now

**Goal:** A business connects its Facebook Page; customers' Messenger messages arrive in the Conversations inbox
like GoHighLevel does; staff reply from there; Meta's rules are respected. Messenger only (Instagram later).
**Core agreement — read on every resume:** `docs/messenger-behavior-contract.md` (Summary, First version, Rules, Still unclear) and the Messenger/Instagram + Connections sections of `docs/unified-inbox-behavior-contract.md`.
**Plan:** `docs/messenger-behavior-contract.md` — first-version scope approved 2026-10-18; open product choices listed in it.
**Stage:** Planning. Parts 1, 1b and 2 can run side by side.

**Facts a new session needs:** Meta app "Ucrm Messaging", App ID `1709471683925717` (new, 2nd account, 2026-10-18; the old 1419027217062214 is abandoned), development mode, portfolio Uplift Contractor 855656587107152 (verification in review). `META_APP_ID`, `PUBLIC_META_APP_ID`, `META_APP_SECRET` are set in `.env`; `MESSENGER_VERIFY_TOKEN` is not.
Webhook host `https://app.upliftcontractor.com`. Jafar tests with his own Facebook Page "Random News".
Jafar has his Bangladesh **trade license in hand** (2026-10-18). Claude cannot type passwords or upload his legal
documents; Jafar logs in, uploads and confirms submits while Claude drives Chrome. Use Opus for Parts 2–3.

**In progress:**

- 1b Business portfolio + Meta Business Verification — `parts/1b-business-verification.md` (start first: review takes days)
- 1 Meta app dashboard setup — `parts/1-meta-app-dashboard-setup.md`
- 2 Plan: research done 2026-10-18, plan written; waits for Jafar's answers to three choices — `parts/2-plan-messenger.md`

**Next part:** 3 Database foundation — waits for Part 2 approval.

**Paused 2026-10-18:** Part 2 research and plan done and waiting on Jafar's three answers (replies after 24h, reconnect history, customer matching). Part 1b blocked by his main account's ad restriction; second account plan in `parts/1b-business-verification.md`. Random News admin confirmed.

**Part 1b 2026-10-18 later:** portfolio exists on Jafar's 2nd account (details in the part note); verification SUBMITTED 2026-10-18, status In review (~2 business days). Next: admin access for the 2nd account on app Ucrm Messaging, link app to portfolio.

**Open 2026-10-18:** `META_APP_SECRET` in `.env` is still the OLD app's; Jafar must paste the new secret. Test Page needs to belong to / be accessible by the 2nd account.

**Blockers:** Part 1b needs from Jafar: the exact business name, address and phone printed on the license. Merged into `main` 2026-10-18.
