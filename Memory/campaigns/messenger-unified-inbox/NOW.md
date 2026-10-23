# Messenger in the Unified Inbox — now

**Goal:** A business connects its Facebook Page; customers' Messenger messages arrive in the Conversations inbox
like GoHighLevel does; staff reply from there; Meta's rules are respected. Messenger only (Instagram later).
**Core agreement — read on every resume:** `docs/messenger-behavior-contract.md` (Summary, First version, Rules, Decided) and the Messenger/Instagram + Connections sections of `docs/unified-inbox-behavior-contract.md`.
**Plan:** `docs/messenger-behavior-contract.md` and `docs/messenger-implementation-plan.md` — approved 2026-10-23, including the three product choices.
**Stage:** Building. Parts 3–6 done; Part 7 built and merged 2026-10-23, live proof pending.

**Facts a new session needs:** Meta app "Ucrm Messaging", App ID `1709471683925717` (2nd Facebook account), development mode, portfolio Uplift Contractor 855656587107152, Business Verification **Verified** 2026-10-18. Webhook host `https://app.upliftcontractor.com`. Test Page **Uplift Contractor** (Random News is another account — never use it). Jafar logs in, types passwords and uploads; Claude drives Chrome.

**Done:** Parts 1, 1b, 2, 3, 4, 5 (2026-10-23). Uplift Contractor connected to Raad LTD in the live app. Webhook live; test Page 1121199934412688 subscribed (see `parts/5-inbound-webhook.md`). Tables `communication_messenger_{connections,identities,webhook_events}`; save function `record_communication_messenger_inbound_message`; key `MESSENGER_CREDENTIAL_KEYRING` in `.env`. Login configuration ID `1133535439212464`.

**Active part:** 7 Reply (`parts/7-reply.md`) — built, migration applied, merged; next: live send to Jafar's tester account (needs his yes + Chrome).

**Blockers:** none.
