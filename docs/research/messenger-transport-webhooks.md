# Messenger transport, webhooks, tokens and approval — research

Researched 2026-10-18 for the `messenger-unified-inbox` campaign (Part 2). Sources are Meta's own developer docs, fetched
that day. Each statement is tagged **Verified** (read in Meta's docs), **Inference** (our reading of the docs), or
**Proposal** (our recommendation). Source pages are listed at the end.

## 1. Graph API version

- **Verified:** v26.0 is the newest (released 2026-07-29, expiry "TBD"). v25.0 was released 2026-02-18 and expires
  2028-07-29. Meta's current Messenger examples use `v25.0`.
- **Proposal:** pin `v25.0` in `MESSENGER_GRAPH_VERSION`. It is the version the examples were written against and has
  almost two years of life; move to v26.0 deliberately later.

## 2. Sending

- **Verified:** `POST https://graph.facebook.com/v25.0/{PAGE-ID}/messages?access_token={PAGE-TOKEN}` with JSON
  `{ "recipient": {"id": "<PSID>"}, "messaging_type": "RESPONSE", "message": {"text": "..."} }`. Success returns
  `{ "recipient_id": "...", "message_id": "..." }`. Attachments use `message.attachment {type, payload.url}`.
  `reply_to.mid` replies to a specific earlier message.
- **Verified:** `messaging_type` is `RESPONSE` (reply, in window), `UPDATE` (proactive, in window) or `MESSAGE_TAG`
  (outside the window, needs an allowed tag, non-promotional content only).
- **Verified:** rate limit is 300 calls/second/Page for text, 10/second for audio/video. A Page doing more than 40
  messages/second hits a "high-volume" state. Contractors are far below this.
- **Verified:** a recipient is a Page-scoped ID (PSID); IDs from Facebook Login are app-scoped and do not work.

## 3. The 24-hour window and the Human Agent tag

- **Verified:** the window is 24 hours from the person's last message (also opened by Get Started or a Click-to-Messenger
  ad reply). Promotional content is allowed inside it, never in tagged messages.
- **Verified:** the `HUMAN_AGENT` tag lets a person at the business answer manually up to **7 days** after the customer's
  message. It is for issues that cannot be solved in 24 hours (for example after-hours support). Automated messages
  and unrelated content are disallowed. The app must be approved for the **Human Agent** feature through App Review
  (it is available in Facebook Login for Business).
- **Verified:** tags `CONFIRMED_EVENT_UPDATE`, `ACCOUNT_UPDATE`, `POST_PURCHASE_UPDATE` return error 100 since
  2026-04-27. `HUMAN_AGENT` is not on that list.
- **Verified error codes when outside the window:** `10 / 2534022`, `10 / 2018278` ("sent outside of allowed window").
  Meta's two pages disagree on `200 / 1545041` (one calls it "messaging window closed", the other "person isn't
  available right now"), so treat it as "cannot send now" and show the reason from our own window check first.
- **Unverified:** the exact JSON field for the tag. Meta's reference describes `HUMAN_AGENT` with
  `messaging_type: "MESSAGE_TAG"` (expected `"tag": "HUMAN_AGENT"`). Confirm with a real call in Part 7.
- **Proposal:** the CRM works out the window itself from the last inbound message time, disables the Messenger option
  after 24 hours with a plain reason, and treats Meta's rejection as the backstop. First version does not send
  `HUMAN_AGENT`; it becomes a small follow-up once Meta approves the feature (needs App Review anyway).

## 4. Webhooks

- **Verified:** GET handshake carries `hub.mode=subscribe`, `hub.verify_token`, `hub.challenge`; answer 200 with the
  challenge, else 403.
- **Verified:** POST is signed with `X-Hub-Signature-256: sha256=<hex>`, HMAC-SHA256 over the body with the App Secret.
  Meta's note: the signature is computed over the *escaped-unicode* form of the payload with lowercase hex, so the
  **raw body bytes must be hashed before any JSON parsing** and the comparison must be constant-time.
- **Verified:** answer `200 OK` in 5 seconds (webhooks page) — App Review text says 20 seconds. We target the 5.
  Failed deliveries retry a few times immediately; after 15 minutes of failure the developer gets an alert; after
  **1 hour** the app is unsubscribed from that Page ("Webhooks Disabled") and must resubscribe. Events can arrive out
  of order after failures: sort by `timestamp`.
- **Verified inbound shape:** `{object:"page", entry:[{id:<PAGE_ID>, time, messaging:[{sender:{id:<PSID>},
  recipient:{id:<PAGE_ID>}, timestamp, message:{mid, text? , attachments?[{type,payload.url}], reply_to?}}]}]}`.
  Attachment types: image, audio, video, file, sticker, reel, ig_reel, post, ig_post, appointment_booking, fallback.
  Since 2026-08-30 stickers arrive only as `sticker` (not also `image`).
- **Verified delivered/read:** `message_deliveries` → `delivery.watermark` (always) and `delivery.mids` (sometimes);
  `message_reads` → `read.watermark` only. A watermark means "everything sent at or before this time".
- **Verified echoes:** `message_echoes` fires when the *Page* sends a message; carries `is_echo: true`, `app_id`, `mid`,
  `sender.id = PAGE_ID`, `recipient.id = PSID`.
- **Inference:** echoes include messages staff type in Facebook's own Page inbox or Meta Business Suite (different
  `app_id`), so subscribing keeps the CRM thread complete, and our own sends echo back (deduplicate on `mid` with
  the `message_id` the Send API returned).
- **Proposal:** subscribe `messages`, `message_echoes`, `message_deliveries`, `message_reads`, plus
  `messaging_policy_enforcement`. Skip postbacks, referrals, reactions for the first version.
- **Verified:** Page subscription: `POST /{PAGE_ID}/subscribed_apps?subscribed_fields=messages,...` with a Page token from
  someone holding the `MODERATE` task; needs `pages_messaging` and `pages_manage_metadata`. `GET` on the same edge
  lists subscribed apps/fields; empty `data` means not subscribed.
- **Proposal (health):** after Meta auto-disables a webhook the GET list comes back empty, so a periodic check of
  `subscribed_apps` is the "reconnect needed" signal for that case.

## 5. Page tokens and the connect flow

- **Verified:** a long-lived Page token "does not have an expiration date and only expires or is invalidated under
  certain conditions." It comes from a long-lived *user* token via `GET /{app-scoped-user-id}/accounts`; the Page
  token is in each item's `access_token`.
- **Inference (third-party sources, not Meta):** invalidation happens on password change, app removal, or loss of the
  Page role. Error `190` ("Invalid OAuth access token") is the signal; show "reconnect".
- **Verified:** Facebook Login for Business needs a business-type app, lets us define a *configuration* (permissions
  plus a User access token), and requires **Advanced Access via App Review** to serve businesses we do not own. Its
  settings need a redirect URI, a **deauthorize callback URL** and a **data deletion URL**. Messenger's required
  permissions: `pages_messaging`, `pages_manage_metadata`, `pages_show_list`, `business_management`, `public_profile`.
  `pages_read_engagement` optional.
- **Verified:** in development mode only people with a role on the app can message, and Meta returns error
  `200` ("Cannot message users who are not admins, developers or testers…") for anyone else. This matches the
  test plan with Jafar's own Page and a tester account.
- **Proposal:** store the encrypted Page token per connection (Stripe pattern), run `debug`-style health checks on a
  schedule, and treat any `190` or subscription loss as a "reconnect" state.

## 6. Going live — who must be verified

- **Verified:** an app that accesses business data owned by *other* businesses must become a **Tech Provider**, which
  needs a verified business portfolio plus App Review before publishing.
- **Inference (answers an open question):** the verification belongs to the **app owner (Uplift)**. Nothing in Meta's
  docs requires each contractor to be verified; a contractor only grants the app access to their Page. Re-confirm
  when submitting in Part 10, because Meta's pages do not state it for clients in so many words.
- **Verified for publishing:** app icon (512–1024 px), privacy policy URL, data deletion URL or callback, published
  Page, reviewer instructions with test login, webhook answering 200 inside 20 seconds.
- **Verified:** the *Business Asset User Profile Access* feature (Advanced Access, via App Review) is required to read a
  customer's name and photo. Without it the profile call returns an empty object. Accounts made with a phone number
  return error `2018218` ("No profile available").
- **Inference:** until that approval, a new Messenger customer has only a PSID and no name.

## 7. Policy that touches the product

- **Verified:** a CRM where staff type every reply is a "manual reply" bot: responsiveness and disclosure rules apply
  only to automated experiences. If automation is added later the 30-second response rule and automation disclosure
  apply.
- **Verified:** tagged messages may not carry promotions; misuse can restrict the Page's sending (error `10 / 1893063`).
- **Verified:** subscribe to `messaging_policy_enforcement` to hear about violations.

## 8. What stays unknown until a real call

- Exact `tag` field for Human Agent; whether the Human Agent feature can be exercised in development mode.
- How long an attachment URL stays valid (assume short: copy files to R2 when received — **Proposal**, same as MMS).
- Whether a PSID stays the same after a Page is disconnected and reconnected (it is Page-scoped, so **Inference**: yes).

## Sources

- Send a message: developers.facebook.com/documentation/business-messaging/messenger-platform/send-messages
- Webhooks: …/messenger-platform/webhooks and …/webhooks/webhook-events/{messages,message-deliveries,message-reads,message-echoes}
- Policy: …/messenger-platform/policy; error codes: …/messenger-platform/error-codes; rate limits: …/overview/rate-limiting
- App review and use-case setup: …/messenger-platform/app-review and …/messenger-platform/create-an-app
- User profile: …/messenger-platform/identity/user-profile
- Facebook Login for Business: developers.facebook.com/documentation/facebook-login/facebook-login-for-business
- Long-lived tokens: developers.facebook.com/docs/facebook-login/guides/access-tokens/get-long-lived
- Graph API versions: developers.facebook.com/docs/graph-api/changelog/versions
