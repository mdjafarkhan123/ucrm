# Messenger live proof — 2026-10-23

Full journey on the live app (`https://app.upliftcontractor.com`), Chrome signed in as the Raad LTD owner, desktop
width. Test Page Uplift Contractor `1121199934412688`; customer = Jafar's tester Facebook account. Success checks
from `docs/messenger-behavior-contract.md`.

| Check | Result | Evidence |
| --- | --- | --- |
| Customer message → inbox → staff reply → received | Pass. "hi there" saved 09:07:49 UTC, processed in 0.6 s, one webhook row; CRM reply loaded with spinner, delivered, then Seen after Jafar opened it | `1-reply-delivered.jpg` |
| Reply typed in the Page's Facebook inbox | Pass after fix A. Saved once as a foreign echo; now appears in an open inbox without reload | `2-live-customer-and-facebook-reply.jpg` |
| Needs reply | Pass after fix B. Customer's new message moves the chat to Needs reply live; any person's answer moves it to Earlier | `2-answered-moves-to-earlier.jpg` |
| Same event twice → one message | Covered by Part 5 (signed probe sent twice → one row); not repeated | `Memory/campaigns/messenger-unified-inbox/parts/5-inbound-webhook.md` |
| 24-hour window closed | Pass. Page clock moved +25 h in the browser only: "Reply window closed", Meta's reason, Send disabled, "Reply by text". Database refusal proven in Part 7 | `3-window-closed.jpg` |
| Access revoked on Facebook | Pass. Jafar removed Ucrm Messaging from Business integrations; the Page was made due (`last_checked_at = null`) and the next one-minute wake set `needs_reconnect / token_invalid` at 09:39:00 UTC. Settings shows Reconnect needed + Reconnect; composer shows Page disconnected, Send disabled | `4-settings-reconnect-needed.jpg`, `4-inbox-page-disconnected.jpg` |
| Reconnect | Pass. Jafar reconnected; the same connection row returned to active, Receiving, history kept, no duplicate | `4-reconnected-receiving.jpg` |
| Meta webhook (app level) | Pass. Page object callback `https://app.upliftcontractor.com/api/webhooks/messenger`; subscribed: messages, message_echoes, message_deliveries, message_reads, messaging_policy_enforcement (v26.0) | `5-meta-webhook-page.jpg` |

## Fixed during this proof

- **A. Facebook-inbox replies needed a reload.** `communication_delivery_intents_publish_activity` fired on status
  updates only; a foreign echo is inserted already sent. Migration `20270105090000_inbox_activity_on_new_send.sql`
  (applied and recorded atomically) also broadcasts on insert of non-automated sends. Automated bulk sends are
  excluded because their status change broadcasts moments later; the inbox already coalesces bursts to one refetch
  per 500 ms per open tab.
- **B. "Needs reply" meant unread.** Now `ConversationGroup.awaitingReply`: the newest person-to-person message is
  the customer's (Front "Unreplied", Intercom "waiting on you"). Automated sends, forwards, chat system/automation
  lines and auto-responders are ignored. Unread stays its own green count. `npx vitest run
  src/lib/communications/inbox.spec.ts`: 33 passed.
- **C. Channel logos.** Jafar's PNGs in `src/lib/assets/channels/`, imported so a replaced file gets a new hashed
  URL (a same-name file in `static/` stayed cached). Green bubbles keep the white mark.

## Webhook recovery (owner runbook)

Meta disables an app's callback after roughly an hour of failed deliveries and notifies the app admins (email and
the dashboard Alert Inbox). The Page subscription health check cannot see that state. Recovery: fix the server,
open Meta for Developers → Ucrm Messaging → Use cases → Messenger from Meta → Webhooks → Page, and press
**Verify and save** with the same callback URL and verify token from `.env`; then send a tester message and confirm
it reaches Conversations.

## Limits

Development mode: only app-role accounts can message the Page; real customers need Part 10 (App Review, Advanced
Access). Service capacity remains unverified (Part 8 verdict). Desktop light only, per Jafar's screen-check rules.
