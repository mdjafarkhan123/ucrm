# Messenger in the Unified Inbox — now

**Goal:** Businesses connect Facebook Pages, receive customers' Messenger messages in Conversations and reply
there, following GoHighLevel and Meta's rules. Messenger only; Instagram later.
**Core agreement — read every resume:** `docs/messenger-behavior-contract.md` (Summary, First version, Rules,
Decided); `docs/unified-inbox-behavior-contract.md` (Messenger/Instagram and Connections sections).
**Approved plan:** `docs/messenger-implementation-plan.md`, Jafar 2026-10-23.
**Stage:** Go-live (Part 10) in progress. Parts 1–9 complete 2026-10-23.

**Facts:** Meta app Ucrm Messaging `1709471683925717`, development mode, second Facebook account. Business portfolio
Uplift Contractor `855656587107152`, verified 2026-10-18. Test Page Uplift Contractor `1121199934412688`, connected
to Raad LTD. Never use Random News. Webhook host `https://app.upliftcontractor.com`; Login configuration
`1133535439212464`. Credentials remain in `.env`. Jafar handles passwords/uploads.

**Done:** Connect/reconnect/history, signed save-first webhook, inbox, replies, Seen, hourly health checks (parts
4–8). Part 9 live proof passed every success check; fixed live Facebook-inbox replies, "Needs reply" (customer
spoke last) and real channel logos. Evidence: `docs/evidence/messenger-part9/README.md` (includes webhook
recovery runbook).

**Next:** Part 10 — `parts/10-go-live.md`. Legal page text is ready; Jafar puts it on the website, then the Meta
App Dashboard URLs and App Review. Service capacity remains unverified.
**Blockers:** real customers require Meta Advanced Access (Part 10).
