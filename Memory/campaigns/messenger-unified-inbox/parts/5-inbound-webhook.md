# Part 5 — Inbound webhook

**State:** code built, merged to main and pushed (8d0469cf); migration `20261228090000_messenger_inbound_webhook.sql`
applied; Vault secret `communications_messenger_worker_target_url` set; cron `communications-messenger-inbound-wake-one-minute` live.

**Built:** `src/routes/api/webhooks/messenger/+server.ts` (GET handshake, POST: 1 MiB cap → signature → save by body
hash → 200 → instant wake), `src/lib/server/communications/messenger-webhook.ts` (pure checks + parser),
`messenger-inbound-worker.ts` (SKIP LOCKED claim, records via `record_communication_messenger_inbound_message`),
`src/routes/api/internal/communications/messenger-worker/+server.ts` (cron entry).

**Proof so far (2026-10-23):** 22 unit tests pass (3 spec files beside the code). Rolled-back SQL run: repeat insert
stays one row, a held claim is not re-claimed, a 5-minute-stale claim is retaken. Live
`https://app.upliftcontractor.com/api/webhooks/messenger`: right verify token 200, wrong 403, unsigned POST 403; a
signed probe sent twice → one row, processed, answered in 0.47 s; probe row deleted.

**Next action (needs Chrome extension connected):** in Meta app 1709471683925717 → Messenger API settings / Webhooks:
callback URL above, verify token `MESSENGER_VERIFY_TOKEN` from `.env`; subscribe `messages, message_echoes,
message_deliveries, message_reads, messaging_policy_enforcement`; press Meta's "Test" for `messages` and confirm one row
in `communication_messenger_webhook_events`. Then subscribe the test Page Uplift Contractor in the same screen and have
Jafar's tester account message it → one raw row. It will not reach the inbox until Part 4 creates a connection row.

**Left for later parts:** echoes, delivered and read are saved but skipped (Part 7); attachments are counted, files not
imported (Part 6); alert when a delivery hits 10 failed attempts (Part 8).
