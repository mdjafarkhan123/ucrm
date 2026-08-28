# HighLevel Website Chat Automation Reference

Research date: 2026-08-26  
Status: Planning input only; not approved UCRM behavior or implementation scope  
Sources: Official HighLevel Support documentation only

## Executive finding

HighLevel does not treat every website inquiry as the same kind of chat. It offers a real-time **Web Chat**
(labelled "Live Chat" in setup), an **Email/SMS Chat** that captures details for later off-widget follow-up,
and an All-in-One launcher that can expose several connected channels. Website auto-replies are built by
combining a channel/widget-scoped `Customer Replied` trigger with workflow actions such as send message,
assignment, notification, tags, tasks, and waits. This is the useful reference for UCRM's website-widget
acknowledgement preset; HighLevel's separate Missed Call Text Back switch is a phone-call feature, not the
website-chat engine.

## Documented behavior

### Widget types and visitor identity

- HighLevel lists All-in-One Chat, Email/SMS Chat, Web Chat (shown as Live Chat during setup), Facebook,
  Instagram, WhatsApp, and Voice AI widget types. Email/SMS Chat collects visitor information so the business
  can reply later by email or SMS; Web Chat is a real-time two-way channel routed into Conversations.
  ([Getting Started with Chat Widget](https://help.gohighlevel.com/support/solutions/articles/155000004102))
- Live Chat can require a pre-chat contact form. The minimum documented identity is name plus at least one of
  phone or email; an active returning visitor can skip the form and resume the chat, while an ended or expired
  session gets the form again.
  ([Collect Visitor Details Before Live Chat Starts](https://help.gohighlevel.com/support/solutions/articles/155000005415-collect-visitor-details-before-live-chat-starts))
- Non-Live-Chat widgets can include a required, visitor-editable opening message (maximum 255 characters) so
  CRM identity fields stay out of the public conversation body.
  ([Customizable Message Field](https://help.gohighlevel.com/support/solutions/articles/155000006967-customizable-message-field-in-chat-widgets))

### Trigger, immediate acknowledgement, and follow-up

- The workflow event is `Customer Replied`. It can be filtered by channel, phrases, tags, intent, or the
  workflow being answered. For All-in-One Chat, it can be narrowed further to Chat Widget versus Live Chat and
  then to one exact widget configuration.
  ([Customer Replied trigger](https://help.gohighlevel.com/support/solutions/articles/155000002677))
- HighLevel explicitly documents an acknowledgement recipe: on a reply from a selected website widget, send
  an immediate confirmation, assign the contact/conversation, add a tag, and optionally create an internal
  task. It also documents waits and escalation when no teammate responds.
  ([Automating customer replies from an All-in-One widget](https://help.gohighlevel.com/support/solutions/articles/155000007454-automating-customer-replies-from-an-all-in-one-chat-widget))
- HighLevel's first-party example for after-hours lead capture combines a form/chat submission with an instant
  thank-you text and email, later timed follow-ups, and an internal alert. This shows that SMS and email can be
  parallel workflow actions after capture; the documentation does **not** describe automatic channel fallback
  as an inherent property of the widget.
  ([Never Miss a Lead Again—Even After Hours](https://help.gohighlevel.com/support/solutions/articles/155000005117-never-miss-a-lead-again-even-after-hours))

### Business hours and after-hours handling

- Live Chat business hours use the location timezone and allow multiple non-overlapping ranges per day. Outside
  those hours, HighLevel shows configurable offline copy and a contact-details form; after that form is
  submitted, HighLevel automatically closes the chat.
  ([Business Office Hours in Live Chat](https://help.gohighlevel.com/support/solutions/articles/155000004104-chat-widget-business-office-hours-in-live-chat))
- If nobody answers within the configured inactivity period, Web Chat can show a fallback asking the visitor
  for contact details so follow-up can continue later. Chats can be ended manually or automatically for
  inactivity.
  ([Web Chat inside Conversations](https://help.gohighlevel.com/support/solutions/articles/155000007355-web-chat-inside-conversations))

### Inbox continuity, assignment, and notifications

- Website messages arrive in the shared Conversations inbox in real time alongside other channels. Staff can
  respond in the thread, filter Web Chat conversations, and assign them manually or through workflows and
  ownership rules.
  ([Web Chat inside Conversations](https://help.gohighlevel.com/support/solutions/articles/155000007355-web-chat-inside-conversations))
- The official installation guide recommends a `Customer Replied` trigger filtered to Chat Widget, followed by
  an internal email, in-app, or SMS notification; the visitor's message body can be included in that alert.
  ([Install HighLevel's Chat Widget](https://help.gohighlevel.com/support/solutions/articles/48000984860-how-to-install-highlevel-s-chat-widget))
- HighLevel documents using a separate `User Replied` trigger to stop or change an automation once a teammate
  personally responds, avoiding simultaneous human and automated messages. Workflow- and AI-sent messages do
  not fire that user trigger.
  ([User Replied trigger](https://help.gohighlevel.com/support/solutions/articles/155000008196-workflow-trigger-user-replied))

### Consent, opt-out, and delivery protection

- Entering a phone number and consenting to messages are separate decisions. HighLevel's A2P guidance says a
  widget/form cannot require SMS consent merely because the phone field is required, and marketing versus
  non-marketing consent must be separate; post-submit communication must follow the selected consent choices.
  ([HighLevel A2P Opt-In Compliance](https://help.gohighlevel.com/support/solutions/articles/155000007237))
- Initial outbound SMS—including workflow sends, missed-call replies, and review requests—receives sender
  identification and opt-out language. STOP and related keywords block further SMS, and workflow SMS steps
  skip contacts whose channel DND conflicts with the send.
  ([SMS Compliance Settings](https://help.gohighlevel.com/support/solutions/articles/155000004684/),
  [DND Contact trigger](https://help.gohighlevel.com/support/solutions/articles/155000002673-workflow-trigger-contact-dnd))

### Separate missed-call text-back behavior

- Missed Call Text Back immediately sends a customizable SMS from the default number after an inbound call is
  missed and can be test-sent before activation. It works after hours and counts toward messaging usage.
  ([Configure Missed Call Text Back](https://help.gohighlevel.com/support/solutions/articles/48001239140-where-and-how-to-configure-the-missed-call-text-back-feature))
- The simple switch sends an SMS for **every** missed call, including repeated calls close together. HighLevel
  itself recommends replacing/customizing that behavior with a workflow, wait, or tags to prevent duplicates.
  The feature is SMS-only; WhatsApp text-back is separate.
  ([Configure Missed Call Text Back](https://help.gohighlevel.com/support/solutions/articles/48001239140-where-and-how-to-configure-the-missed-call-text-back-feature))

## Documented limitations and gaps

- Widget messaging cannot be dynamically customized per page in the standard configuration, although multiple
  widgets may exist in one sub-account.
  ([Install HighLevel's Chat Widget](https://help.gohighlevel.com/support/solutions/articles/48000984860-how-to-install-highlevel-s-chat-widget))
- HighLevel's outside-hours Live Chat flow closes after contact-form submission rather than preserving an open
  durable website conversation.
  ([Business Office Hours in Live Chat](https://help.gohighlevel.com/support/solutions/articles/155000004104-chat-widget-business-office-hours-in-live-chat))
- All-in-One Chat scoping is documented only for the `Customer Replied` trigger, not every workflow trigger.
  ([Customer Replied trigger](https://help.gohighlevel.com/support/solutions/articles/155000002677))
- The reviewed official documentation does not define native SMS-to-email fallback ordering, duplicate
  suppression for website acknowledgements, a reply-frequency ceiling, or retroactive enrollment. Those must
  be explicit UCRM automation-engine decisions rather than assumed HighLevel behavior.

## Planning implications for UCRM

These are recommendations inferred from the documented behavior above, not HighLevel facts:

1. Model `Website chat message received` as a first-class automation trigger with optional widget, hours,
   availability, intent, and contact-state conditions.
2. Offer an editable preset that can immediately acknowledge in the same widget, route/assign the conversation,
   notify staff, wait for a human reply, and then use an approved SMS/email follow-up only when identity and
   consent allow it.
3. Keep website-chat acknowledgement and missed-call text-back as separate presets sharing the same automation
   builder and safeguards.
4. Preserve one Conversations thread across website, SMS, and email where the contact identity is safely
   matched; visibly label each message's channel rather than pretending a channel switch did not happen.
5. Beat the reference by keeping after-hours website conversations durable, suppressing duplicate acknowledgements,
   stopping/escalating when a teammate responds, and making channel fallback visible in the recipe and activation
   review.
6. Treat consent/DND, legal quiet hours, tenant isolation, idempotency, and provider limits as hard enforcement;
   contractor warnings and `/jafar` organization allowances cannot override them.

