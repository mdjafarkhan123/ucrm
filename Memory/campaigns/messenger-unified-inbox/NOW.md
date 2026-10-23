# Messenger in the Unified Inbox — now

**Goal:** A business connects its Facebook Page; customers' Messenger messages arrive in the Conversations inbox
like GoHighLevel does; staff reply from there; Meta's rules are respected. Messenger only (Instagram later).
**Core agreement — read on every resume:** `docs/messenger-behavior-contract.md` (Summary, First version, Rules, Decided) and the Messenger/Instagram + Connections sections of `docs/unified-inbox-behavior-contract.md`.
**Plan:** `docs/messenger-behavior-contract.md` and `docs/messenger-implementation-plan.md` — approved 2026-10-23, including the three product choices.
**Stage:** Building. Part 3 done; Part 5 built and live 2026-10-23, Meta dashboard step left.

**Facts a new session needs:** Meta app "Ucrm Messaging", App ID `1709471683925717` (2nd Facebook account; old 1419027217062214 abandoned), development mode, portfolio Uplift Contractor 855656587107152, Business Verification **Verified** 2026-10-18. Webhook host `https://app.upliftcontractor.com`. Test Page **Uplift Contractor** (Random News is another account — never use it). Jafar logs in, types passwords and uploads; Claude drives Chrome.

**Done:** Parts 1, 1b, 2, 3 (2026-10-23). Tables `communication_messenger_{connections,identities,webhook_events}`; save function `record_communication_messenger_inbound_message`; key `MESSENGER_CREDENTIAL_KEYRING` in `.env`. Login configuration ID `1133535439212464`.

**Next part:** finish 5 — Meta dashboard webhook setup and a real test message (`parts/5-inbound-webhook.md`); needs the Chrome extension connected. Parts 4 (connect card) and 6 (inbox) need Pencil drawings approved by Jafar first — drawing happens in a design session, building in another.

**Blockers:** none. `META_APP_SECRET` checked against Facebook 2026-10-23: matches the new app.
