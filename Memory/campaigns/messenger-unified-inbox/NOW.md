# Messenger in the Unified Inbox — now

**Goal:** Businesses connect Facebook Pages, receive customers' Messenger messages in Conversations and reply
there, following GoHighLevel and Meta's rules. Messenger only; Instagram later.
**Core agreement — read every resume:** `docs/messenger-behavior-contract.md` (Summary, First version, Rules,
Decided); `docs/unified-inbox-behavior-contract.md` (Messenger/Instagram and Connections sections).
**Approved plan:** `docs/messenger-implementation-plan.md`, Jafar 2026-10-23.
**Stage:** Building/proving. Parts 1–8 complete 2026-10-23.

**Facts:** Meta app Ucrm Messaging `1709471683925717`, development mode, second Facebook account. Business portfolio
Uplift Contractor `855656587107152`, verified 2026-10-18. Test Page Uplift Contractor `1121199934412688`, connected
to Raad LTD. Never use Random News. Webhook host `https://app.upliftcontractor.com`; Login configuration
`1133535439212464`. Credentials remain in `.env`. Jafar handles passwords/uploads.

**Done:** Connect/reconnect/history, signed save-first webhook, inbox, replies and Seen proven live (parts 4–7).
Part 8 adds hourly connection checks, conditional claims, reconnect warnings and phone Settings repair; migration
`20270104090000_messenger_connection_health.sql` applied. Cron health wake proven 07:12 UTC, 2026-10-23.
Evidence: `docs/evidence/messenger-part8/README.md`.

**Next:** Part 9 full live walkthrough; then Part 10 Jafar-owned Meta App Review. Review the Page's own Facebook
inbox echo, closed-window UI, and app-level webhook-disable recovery. Service capacity remains unverified.
**Blockers:** none for Part 9; real customers require Meta Advanced Access.
