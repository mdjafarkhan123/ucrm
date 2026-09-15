# HighLevel SMS UI — live evidence

Observed live in Jafar's `Jk LTD` subaccount on 2026-09-13. Read-only except for opening HighLevel's
`Fast 5 Lite` workflow template as an unpublished draft so its SMS action could be inspected. No message was
sent, no number was purchased, and no workflow was published.

The screenshots captured during the browser walkthrough cover the states below. This note preserves what each
capture proves; the approved UCRM contracts remain authoritative when HighLevel differs.

## Conversations

- Desktop is a four-part workspace: compact inbox navigation, conversation list, active timeline/composer, and
  a contact-details rail.
- The list header keeps Unread, All, Recent and Starred together, with filter and sort beside the inbox title.
- The thread header carries message filter, star, read/unread and delete actions.
- The contact rail keeps owner, followers and tags above All fields, DND and Actions tabs.
- The composer keeps its channel selector at the left edge and send plus send-options at the right edge.
- This subaccount has no phone number and the selected contact has no phone, so the live channel menu offered
  Email and Internal Comment only. HighLevel correctly hid SMS instead of showing a fake-ready channel.

## Workflow SMS

- The builder is a node canvas with one selected node opening a right-side action editor. UCRM will keep its
  approved linear builder rather than copy the canvas.
- The SMS editor contains Action name, Templates, Message, custom values, undo/redo, character and word count,
  device upload, URL attachments, Test phone number, Send test SMS, and Cancel/Save action controls.
- HighLevel offers AI writing here; A2 explicitly excludes it.
- Workflow Settings separates Contact behavior from Communication behavior. Communication owns timezone,
  optional time window, default From number and whether workflow activity marks Conversations read.
- Enrollment history columns are Contact, Enrollment reason, Date enrolled, Current action, Current status,
  Next execution and Actions, with date/event/contact filters and a 60-day empty state.
- Execution logs columns are Contact, Action, Status, Executed on and Actions, with date/action/status/contact
  filters and a 60-day empty state.

## Phone System / Messaging

- Phone System uses top-level tabs for Phone numbers, Regulatory Bundles, Messaging, Voice, Trust Center and
  Additional Settings.
- Messaging uses secondary tabs for Messaging Compliance, Messaging Limits, Messaging Analytics and
  Restriction History.
- Compliance keeps opt-out text, sender identification, periodic opt-out interval and regional blocking in
  separate saveable cards.
- Messaging Limits presents a progressive ramp/cap ladder. UCRM should show its own approved cap and hold truth,
  not copy HighLevel's ladder.
- Analytics leads with a date range and Filters, then separates outbound Sent/Delivered/Failed from inbound
  Received/Opt-out rate. Failure-rate and opt-out-rate trends sit below. UCRM A2 keeps only the approved lean
  health summary rather than duplicating this analytics suite.

## Evidence limitations

- There was no configured HighLevel phone number, SMS conversation, delivery failure, restriction-history row,
  registration submission or usage transaction to inspect.
- No purchase, test SMS or published workflow was created merely to manufacture those states.
- Exact SMS bubble statuses, To/From menus and message-detail failures therefore continue to rely on the cited
  first-party HighLevel documentation in `docs/research/communications-a2-product-ui-highlevel.md` plus UCRM's
  approved product contracts.

