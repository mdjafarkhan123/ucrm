# Messenger — implementation plan

Status: **proposed 2026-10-18, waiting for Jafar's approval** (Part 2). Scope and behaviour are in
`docs/messenger-behavior-contract.md`; Meta facts are in `docs/research/messenger-transport-webhooks.md`. This plan
orders the build and fixes the technical shape. Parts 3 onward are the roadmap rows in
`Memory/campaigns/messenger-unified-inbox/ROADMAP.md`.

Followed: GoHighLevel's Facebook connect and Conversations behaviour for what users see; Meta's Messenger Platform
(Send API, signed webhooks, `subscribed_apps`, Facebook Login for Business) for how it works; the app's own Stripe
connect and Twilio/SES webhook code for the pattern.

## Database (Part 3, needs its own approval before the migration)

- `messenger_connections`: one row per connected Page per organization — Page ID, Page name, encrypted Page token
  (same crypto as `stripe-credential-crypto.ts`), status (`active`, `needs_reconnect`, `disconnected`), default flag,
  last health check, subscribed fields.
- `messenger_identities`: one row per customer per Page — PSID, display name when Meta allows it, link to client or
  lead. Unique on (connection, PSID), so the same customer on the same Page is always one thread.
- Messages reuse the existing conversation/message tables. The `channel` check constraints widen to include
  `messenger`; the `NOT NULL` on the client contact method is relaxed for Messenger rows (their address is the PSID).
  Unique on (connection, Meta `mid`) so a repeated delivery cannot create a second message.
- A raw event table saves each webhook body before processing, so nothing is lost if processing fails.
- All tables have RLS by organization, same as the SMS tables; tokens are never returned to the browser.

## Server shape

- **Connect (Part 4):** the settings card starts Facebook Login for Business; the server exchanges the code, lists
  Pages, stores the chosen Page's token encrypted, subscribes the Page via `subscribed_apps`, and sends a test
  message. Disconnect unsubscribes, marks the connection `disconnected` and keeps the history.
- **Webhook (Part 5):** `GET` handshake; `POST` reads the raw body, rejects over a size cap, verifies
  `X-Hub-Signature-256`, writes the raw event, returns 200. A worker turns raw events into messages, identities and
  delivery states, using the existing lead/client linking that SMS uses. Delivery and read events apply the
  watermark rule (everything sent at or before the watermark).
- **Reply (Part 7):** a new Messenger branch beside the SMS reply path; the CRM checks the 24-hour window itself, sends
  `RESPONSE` messages, and records Meta's `message_id` so the echo is not shown twice.
- **Health (Part 8):** a scheduled check of each connection (token valid, still subscribed). Error `190` or an empty
  `subscribed_apps` list sets `needs_reconnect`.
- Graph version pinned to `v25.0` through `MESSENGER_GRAPH_VERSION`; `MESSENGER_VERIFY_TOKEN` generated in Part 5.

## Performance design verdict (performance-review, design stage)

The inbound webhook is a write path that outside traffic drives, so it qualifies. Design: the request does only
signature check, size cap and one insert, then returns 200 (target well under Meta's 5 seconds); processing runs on
the worker, so a slow client lookup cannot make Meta disable the webhook. Message lookup is indexed on (connection,
`mid`) and (connection, PSID). Meta's own ceiling is 300 sends/second per Page, far above a contractor. Inbox lists
reuse the existing paginated conversation queries. Verify after Part 7 with a replayed burst of duplicate and
out-of-order events. No claim about how many businesses it supports until that evidence exists.

## Screens needing a Pencil design first

Settings → Communications → Messenger card (connect, Page picker, test message, reconnect state), the composer's
channel switch with the disabled-after-24-hours state, and the Messenger badge in the conversation list. Jafar approves
the design before any `.svelte` file is touched.

## Decisions waiting for Jafar

1. Replies after 24 hours: block with a plain reason now; add Meta's 7-day Human Agent option after Meta approves it.
2. Disconnect then reconnect a Page: keep old conversations visible and continue the same threads.
3. Unknown customers: always start as a new lead; never merge by name; staff can link a thread to an existing client.
