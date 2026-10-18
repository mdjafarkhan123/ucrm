# Messenger in the Unified Inbox

Status: first-version scope approved by Jafar 2026-10-18 (Messenger only, GoHighLevel-style behaviour). Product
details under **Still unclear** are not approved. Inbox-wide behaviour lives in
`docs/unified-inbox-behavior-contract.md` (Messenger and Instagram section, Connections section); this file adds
the Messenger-specific agreement and does not repeat it.

## Summary

A contractor connects their business's Facebook Page to the CRM. When a customer messages that Page on Messenger,
the message appears in the same Conversations inbox as SMS and email, under the right client or lead, and staff
reply from there. This is how GoHighLevel works and Jafar wants the same experience. Instagram is a separate, later
campaign. Real customers can only reach us after Meta approves the app; until then only people with a role on our
Meta app can test.

## Problem and audience

Contractors get customer messages on their Facebook Page and miss them or answer in a separate app. Contractor
staff (owner, office, sales) gain one inbox for every channel.

## First version

- **Connect:** Settings → Communications → Messenger. Log in to Facebook, choose one or more Pages, connect, run a
  test message. Disconnect safely. Several Pages per business, one default.
- **Receive:** a customer's message becomes a conversation under a client or lead (new Lead if unknown, as SMS does).
  Messenger is one continuous thread per customer. Repeated deliveries from Meta never create duplicates.
- **Reply:** staff reply from the composer, which switches channel inside the same conversation. Delivered and read
  states show when Meta reports them.
- **Meta's 24-hour window:** when closed, the Messenger option is disabled with a plain reason, never a silent failure.
- **Health:** expired token, revoked permission or a webhook Meta switched off shows as a clear "reconnect" state.

## Experience target

Match GoHighLevel's Facebook connect and Conversations behaviour (evidence:
`docs/research/ghl-unified-inbox-reference.md`, "Facebook Messenger and Instagram"). Visual design follows the
current Pencil concept and the design skill; Jafar approves designs before the inbox or settings screens are built.

## Rules that govern every part

- App Secret and Page tokens stay server-side; tokens are stored encrypted per organization (Stripe pattern).
- Webhooks verify Meta's signature, cap body size, save the event before processing, and answer within 5 seconds.
- Meta's rules are checked when sending (window, permissions), as the inbox contract requires.
- Messenger-only: no Instagram code or screens in this campaign.

## Success checks

- A test Facebook account messages the test Page → the message shows in the live inbox under a lead → staff reply →
  the account receives it in Messenger.
- Meta sends the same event twice → one message in the inbox.
- Customer's last message is over 24 hours old → composer disables Messenger and says why.
- Token revoked on Facebook → the Settings card shows "reconnect needed" and sends do not silently fail.

## Assumptions

- Meta facts confirmed from official docs (2026-10-18): GET handshake with verify token; POST signed with
  `X-Hub-Signature-256` using the App Secret; reply 200 within 5 seconds; Meta disables a webhook after about an hour
  of failures; in development mode only app-role people receive events; real customers need Advanced Access
  (App Review) and Business Verification.
- Unverified: Human Agent 7-day tag for manual replies, exact Send API shape, Page token lifetime, whether
  Facebook Login for Business needs extra app configuration for the Page picker.
- Going live needs Meta Business Verification of the business that owns the app (Uplift). Jafar has a Bangladesh trade
  license (2026-10-18); Meta's own accepted-document list for Bangladesh is unverified, so Part 1b tries it.
- Webhook host `https://app.upliftcontractor.com` (Jafar confirmed); Meta app "Ucrm Messaging", App ID
  `1419027217062214`; the three Meta values are set in `.env`.

## Still unclear

- Manual replies after 24 hours (use Meta's Human Agent tag or block) — recommendation needed in Part 2.
- What happens to old conversations when a Page is disconnected and reconnected — GHL does not document it.
- Whether contractors who connect their own Page must also be verified by Meta — settle in Part 2.
- Duplicate-contact rule when a Messenger customer matches an existing client by name only.

## Not doing

- Instagram, WhatsApp — separate campaigns; Instagram needs Jafar's choice between its two login paths.
- Automation triggers, bulk Messenger marketing, message tags for promotional content — Meta forbids promotion
  outside the window.
- Going live for real customers (business portfolio, Business Verification, App Review) — last part, Jafar-owned.

## Sources and design decisions

- `docs/unified-inbox-behavior-contract.md` — Messenger/Instagram and Connections sections.
- `docs/research/ghl-unified-inbox-reference.md`; GHL setup article 155000005068 — connect and inbox behaviour.
- Meta Messenger Platform docs: webhooks and overview (developers.facebook.com/documentation/business-messaging/messenger-platform).
- Code patterns to reuse are listed in the campaign roadmap.
