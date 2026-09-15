# SMS in Conversations — product proposal

Status: Approved by Jafar on 2026-09-12. Durable behavior is recorded in
`docs/unified-inbox-behavior-contract.md`. Earlier Stages 1–3 approvals remain recorded.
Planning here means features, user actions, visible results and exceptions. Coding choices belong later.

## What the contractor should be able to do

| Feature | How GHL works | Proposed UCRM experience |
| --- | --- | --- |
| One customer conversation | Texts from a contact's saved numbers stay together. [1] | Read texts alongside email and website chat in the customer's conversation, with each message's channel clearly shown. |
| Choose numbers | SMS has To and From selectors. [2] | Choose which saved customer number to text and which permitted business number sends it. Show both before sending. |
| Write a message | GHL supports reusable text snippets and estimates. [3][4] | Write a text or insert an editable saved reply. See required business/opt-out wording, message length and estimated cost before sending. |
| Pictures and files | Supported pictures can use MMS; other files can be shared as links. [5] | Send and receive pictures where supported, and share other files through approved secure links. |
| Delivery results | GHL shows message failures and their reasons. [6] | See Queued, Scheduled, Sent, Delivered or a clear failure reason. If the result is uncertain, show “Checking send status” instead of inviting a duplicate send. |
| Team handling | Opening a conversation does not clear unread; replying or marking read does. [7] | Keep assignment, followers and unread handling consistent across text, email and chat. New replies appear without refreshing. |

## A normal exchange

1. Open a customer's conversation and select SMS.
2. Check the customer number and business number.
3. Write the message, optionally insert a saved reply, and review the estimated cost.
4. Press Send. The message appears immediately with its current status.
5. When the customer replies, see it in the same conversation. Authorized teammates see the update too.
6. Read older messages without losing the conversation or the draft being written.

These steps describe the approved UCRM experience, not a claim that every detail has been observed live in GHL.

## When something prevents sending

Approved consent, balance and safety rules from Stages 1–3 still apply:

- Explain the actual problem: missing customer number, unfinished setup, customer opt-out, insufficient balance,
  spending limit, unavailable country/number, restricted SMS mode or missing staff permission.
- Offer the relevant next action only to someone allowed to take it. A staff member cannot override a customer's STOP.
- Outside permitted sending hours, show when the message will be sent, including the timezone.
- Preserve incoming replies and history while outgoing messages are paused. Notifications Only allows reading
  incoming replies but does not allow a manual SMS conversation.
- Failed messages do not suddenly resend when a restriction ends. An uncertain message must be checked first.
- Keep drafts when switching channels in the open conversation. Explain before discarding unsent work.

## Details and customer identity

A message's details should show who sent it, the customer and business numbers, time, delivery result and a useful
failure explanation. Show charges only to people allowed to see them. Never label SMS as read by the customer.

Texts from a uniquely matched saved customer number should appear with that customer. The exact handling of a
new number or a number shared by several customers still needs GHL evidence or an explicitly approved UCRM rule.
Do not silently pick a customer or lose an incoming message.

## Approved product decisions

- **Pictures:** send and receive pictures where supported; use approved secure links for other files or where
  picture messaging is unavailable.
- **Default sending number:** preserve the established conversation number. For a new conversation use the
  staff member's eligible assigned number, then the organization default. A permitted explicit choice wins and
  becomes the continuity number.
- **New/shared customer numbers:** a unique match attaches automatically; no match creates an Unassigned Lead;
  multiple matches create an Unassigned Needs identification conversation and require staff selection before
  reply. Required STOP, START and HELP handling never waits for identification.

The supporting GHL evidence and its documented gaps are in
`docs/research/ghl-sms-stage4-number-behavior.md`.

## Approval recorded

Jafar approved the feature list, normal exchange, blocked-send experience, pictures/files, number selection and
new-sender handling on 2026-09-12. Technical implementation planning and code come after the full A2 product
plan. Stage 5 covers how contractors use SMS in their automations; Stage 6 covers setup, usage and owner controls.

## Sources

1. [GHL multiple-number conversations](https://ideas.gohighlevel.com/changelog/conversation-enhancements-streamlined-multi-number-management)
2. [GHL To/From selectors](https://help.gohighlevel.com/support/solutions/articles/155000003721) and [sender defaults](https://help.gohighlevel.com/support/solutions/articles/48001152126)
3. [GHL text snippets](https://help.gohighlevel.com/support/solutions/articles/48000981405-sms-templates-snippets-overview)
4. [GHL segment and cost estimates](https://ideas.gohighlevel.com/changelog/conversations-sms-segment-count-and-cost-estimation) — cited feature covers US-to-US estimates; UCRM's approved pricing covers enabled countries.
5. [GHL SMS/MMS and file links](https://help.gohighlevel.com/support/solutions/articles/48001208913)
6. [GHL delivery errors](https://help.gohighlevel.com/support/solutions/articles/48001208912)
7. [GHL unread behavior](https://help.gohighlevel.com/support/solutions/articles/48000980858-unread-vs-read-must-manually-mark-as-read)

Previously researched official sources; no new live-product observation is claimed by this rewrite.
