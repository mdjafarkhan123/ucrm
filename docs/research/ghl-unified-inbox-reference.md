# GoHighLevel unified inbox reference

Research date: 2026-08-23  
Scope: HighLevel's current Conversations behavior, workflows, channel/data semantics, permissions, automation, integrations, and edge cases, limited to first-party HighLevel Help and Developer documentation. UI structure is recorded only where it explains behavior; UCRM's approved visual blueprint remains authoritative.  
Evidence labels: **Fact** is stated in a cited first-party source; **Inference** is a product conclusion drawn from facts; **Unverified** means the reviewed sources do not establish the behavior.

## Executive summary

HighLevel's Conversations product is a contact-centered work surface rather than five separate inboxes. A four-panel desktop layout combines inbox scope, a conversation list, a mixed-channel history, and an editable CRM context panel. Agents select a conversation and then choose the reply channel in the composer without leaving the timeline. The right panel exposes contact fields and operational records such as opportunities, appointments, invoices, and payments. ([Getting Started with the Conversations Tab](https://help.gohighlevel.com/support/solutions/articles/155000006610-getting-started-with-the-conversations-tab))

The model is unified but not channel-naive. SMS, Facebook Messenger, and Instagram DM append to one ongoing channel conversation, while email can have several subject-based threads for one contact. Live/Web Chat is session-led and visitor-initiated. ([User Replied workflow trigger](https://help.gohighlevel.com/support/solutions/articles/155000008196-workflow-trigger-user-replied))

**Inference:** The strongest pattern to adopt is one contact workspace with a chronological cross-channel timeline, while preserving channel-native identifiers and threading rules underneath. “Unified” should not mean storing every message as one undifferentiated thread.

## 1. Information architecture and layout

- **Fact:** The redesigned experience uses four collapsible panels: Inbox, Chat List, Message History, and a Right Panel for contact context. ([Getting Started](https://help.gohighlevel.com/support/solutions/articles/155000006610-getting-started-with-the-conversations-tab))
- **Fact:** Inbox scope includes **My Inbox** (assigned to or followed by the user), **Team Inbox** (all account conversations, requiring full data access), and **Internal Chat**, which is separate from customer threads. ([Getting Started](https://help.gohighlevel.com/support/solutions/articles/155000006610-getting-started-with-the-conversations-tab))
- **Fact:** The chat list supports bulk selection, sorting, filters, unread counts, and list-level conversation actions. The message-history panel shows messages and CRM activities. The right panel supports viewing/editing contact fields, custom fields, tags, owner, documents, and related operational records. ([Getting Started](https://help.gohighlevel.com/support/solutions/articles/155000006610-getting-started-with-the-conversations-tab))
- **Fact:** Right-panel actions include creating/viewing opportunities, appointments, invoices, and payments, without leaving the thread. ([Getting Started](https://help.gohighlevel.com/support/solutions/articles/155000006610-getting-started-with-the-conversations-tab))
- **Fact:** Timeline filters include all messages, direct conversations, activities, email, internal comments, contacts, opportunities, payments, invoices, and AI action logs. ([Getting Started](https://help.gohighlevel.com/support/solutions/articles/155000006610-getting-started-with-the-conversations-tab))

**Inference:** GHL treats the conversation as the primary workbench and embeds compact CRM operations alongside it. For a contractor CRM, the equivalent right-side context should likely emphasize client, property, request, quote/job, invoice, and payment rather than sending staff to separate pages.

## 2. Conversation, contact, and thread model

- **Fact:** A conversation is associated with a contact and has its own conversation ID. The API can create, retrieve, update, and delete conversations; message endpoints generally accept either a `conversationId` or `contactId`. ([Conversations API](https://marketplace.gohighlevel.com/docs/ghl/conversations/conversations/index.html), [Messages API](https://marketplace.gohighlevel.com/docs/ghl/conversations/messages/index.html))
- **Fact:** SMS, Facebook Messenger, and Instagram DM are described as single-thread channels: after the first exchange, later messages append to the ongoing thread. Email can maintain multiple threads with the same contact, distinguished by a new subject versus a reply. Live Chat is visitor-started and session-oriented. ([User Replied trigger](https://help.gohighlevel.com/support/solutions/articles/155000008196-workflow-trigger-user-replied))
- **Fact:** HighLevel renders Email, SMS, WhatsApp, Facebook/Instagram messages, internal comments, and CRM activities in one message-history panel, and the composer can switch channels inside the same conversation workspace. ([Getting Started](https://help.gohighlevel.com/support/solutions/articles/155000006610-getting-started-with-the-conversations-tab))
- **Fact:** When an anonymous live-chat conversation is later identified as an existing contact, HighLevel exposes a `ConversationUpdate` webhook containing old and new conversation IDs, indicating that it merges the visitor conversation into the identified contact conversation. ([ConversationUpdate webhook](https://marketplace.gohighlevel.com/docs/webhook/ConversationUpdate/index.html))

**Inference:** The domain needs separate concepts for Contact, Conversation/Inbox item, Channel identity, Channel thread/session, and Message. Contact identification may require a merge operation with a durable audit trail and idempotent reassociation.

## 3. Channel behavior

### SMS and email

- **Fact:** Agents can switch between SMS and email from the same composer. Updating a contact's email in the right panel immediately updates channel availability without refreshing. ([Getting Started](https://help.gohighlevel.com/support/solutions/articles/155000006610-getting-started-with-the-conversations-tab))
- **Fact:** Email supports inline replies and a full-screen composer for longer drafts, formatting, attachments, and review. ([Getting Started](https://help.gohighlevel.com/support/solutions/articles/155000006610-getting-started-with-the-conversations-tab))
- **Fact:** HighLevel can manually forward an individual inbound email to external recipients; the forward is recorded in the timeline. Replies return to the connected mailbox and appear in Conversations when two-way sync is enabled. ([Forward emails from Conversations](https://help.gohighlevel.com/support/solutions/articles/155000007241-forward-emails-from-conversations-in-highlevel))
- **Fact:** Cold inbound email support varies by provider. Dedicated LC Email/Mailgun domains can capture it, while Gmail/Outlook two-way sync, shared domains, and some SMTP setups have narrower behavior and may only capture replies or known contacts. ([Inbound Email trigger](https://help.gohighlevel.com/support/solutions/articles/155000007650-workflow-trigger-inbound-email))
- **Fact:** HighLevel documents a 20 MB email-attachment threshold in the UI; oversized email files and SMS files that exceed channel limits are placed in the media library and shared as links. ([Attachments in Conversations](https://help.gohighlevel.com/support/solutions/articles/155000001323-attachments-made-easy-in-conversations))

### Facebook Messenger and Instagram

- **Fact:** Facebook Pages and Instagram accounts are connected under Settings → Integrations; test inbound messages should create or reach contacts and appear in Conversations. ([Facebook and Instagram setup](https://help.gohighlevel.com/support/solutions/articles/155000005068))
- **Fact:** Facebook Messenger and Instagram DM behave as continuous channel threads after the initial message. ([User Replied trigger](https://help.gohighlevel.com/support/solutions/articles/155000008196-workflow-trigger-user-replied))
- **Fact:** Automated Messenger and Instagram messages are subject to Meta's 24-hour window after the contact's last interaction. Instagram interactive messages cannot combine quick replies with attachments. ([Facebook Interactive Messenger](https://help.gohighlevel.com/support/solutions/articles/155000004661-workflow-action-facebook-interactive-messenger), [Instagram Interactive Messenger](https://help.gohighlevel.com/support/solutions/articles/155000004662-workflow-action-instagram-interactive-messenger))

**Unverified:** The reviewed first-party pages do not fully specify manual-agent exceptions, message tags, every supported Instagram attachment/reaction type, or behavior when a Facebook/Instagram account is disconnected mid-thread. These need live-product observation and current Meta documentation before implementation.

### Web Chat / Live Chat

- **Fact:** Website chat messages route into Conversations in real time and can be opened, replied to, assigned, and filtered like other channels. The setup UI currently labels the widget type “Live chat,” while the inbox channel is documented as Web Chat; HighLevel explicitly warns that naming is inconsistent. ([Web Chat inside Conversations](https://help.gohighlevel.com/support/solutions/articles/155000007355-web-chat-inside-conversations))
- **Fact:** Widget configuration includes intro message, avatar/branding, inactivity fallback, and timeout message. A chat may be ended manually or automatically on inactivity; an unanswered visitor can be prompted to leave contact details for later follow-up. ([Web Chat inside Conversations](https://help.gohighlevel.com/support/solutions/articles/155000007355-web-chat-inside-conversations))
- **Fact:** HighLevel's All-in-One widget can expose Live Chat, SMS/Email, Facebook, Instagram, WhatsApp, and Voice AI choices in one website surface. ([All-in-One Chat Widget](https://help.gohighlevel.com/support/solutions/articles/155000004779))

**Inference:** UCRM should choose one stable customer-facing term (probably “Web chat”) and keep session state, anonymous visitor identity, and later contact merge explicit.

## 4. Triage: inboxes, unread, status, filters, search, and bulk actions

- **Fact:** Opening a conversation does not mark it read. It stays unread until a user replies, explicitly marks it read, or a workflow changes it. Opening an unread conversation jumps to the first unread message and shows a persistent **New** divider. ([Mark a Conversation as Read](https://help.gohighlevel.com/support/solutions/articles/48000980858-unread-vs-read-must-manually-mark-as-read), [Getting Started](https://help.gohighlevel.com/support/solutions/articles/155000006610-getting-started-with-the-conversations-tab))
- **Fact:** Unread counts update in real time. Conversations can be archived without deleting history; archived items remain in All, and new inbound messages surface them in Unread but do not restore them to Recents. ([Getting Started](https://help.gohighlevel.com/support/solutions/articles/155000006610-getting-started-with-the-conversations-tab))
- **Fact:** Filters include assigned owner, follower, mention, last-message direction, manual-versus-automated outbound type, last-message channel, tags, and SLA. Rules support nested AND/OR groups and multi-value selection. ([Conversation Filters](https://help.gohighlevel.com/support/solutions/articles/48001222121-overview-of-conversation-filters))
- **Fact:** Bulk actions include read/unread, star/unstar, and permanent delete. Starred conversations have their own inbox tab. Sorting includes latest/oldest all messages, latest/oldest manual messages, and SLA urgency. ([Conversation Filters](https://help.gohighlevel.com/support/solutions/articles/48001222121-overview-of-conversation-filters))
- **Fact:** The help page says ad-hoc filters are session-based, while the redesigned overview separately describes saved views. This appears to mean saved views are a distinct feature rather than automatic persistence of an ad-hoc filter. ([Conversation Filters](https://help.gohighlevel.com/support/solutions/articles/48001222121-overview-of-conversation-filters), [Getting Started](https://help.gohighlevel.com/support/solutions/articles/155000006610-getting-started-with-the-conversations-tab))
- **Fact:** The Conversations API search endpoint supports text query, contact, assigned users (including unassigned), followers, mentions, sort order, and cursor-like continuation using `startAfterDate` plus an ID. ([Search Conversations API](https://marketplace.gohighlevel.com/docs/ghl/conversations/search-conversation/index.html))

**Inference:** Unread is an intentional “needs handling” signal, not a passive seen/unseen receipt. Archive and read are orthogonal. Automated traffic must remain distinguishable so it does not bury human replies.

## 5. Team collaboration

- **Fact:** A conversation has one primary assigned owner and may have followers who gain visibility without ownership. My Inbox includes both assigned and followed conversations. ([Conversation Filters](https://help.gohighlevel.com/support/solutions/articles/48001222121-overview-of-conversation-filters), [Getting Started](https://help.gohighlevel.com/support/solutions/articles/155000006610-getting-started-with-the-conversations-tab))
- **Fact:** Internal comments are private timeline entries that contacts never see. `@mentions` can notify teammates; mentions and internal comments can be filtered. Draft internal comments persist across channel switches, composer collapse, and conversation changes. ([Internal comments and mentions](https://help.gohighlevel.com/support/solutions/articles/155000003877-conversations-adding-internal-comments-and-mentioning-users))
- **Fact:** Posted internal comments cannot be edited or deleted and do not support attachments. Mention notifications follow each user's notification preferences. ([Internal comments and mentions](https://help.gohighlevel.com/support/solutions/articles/155000003877-conversations-adding-internal-comments-and-mentioning-users))
- **Fact:** Internal Chat is a distinct team-only space, separate from customer conversation comments. ([Getting Started](https://help.gohighlevel.com/support/solutions/articles/155000006610-getting-started-with-the-conversations-tab))

## 6. Composer, snippets, attachments, scheduling, and delivery state

- **Fact:** The composer provides channel selection, formatting, inline or full-screen email drafting, links, file uploads, clipboard paste, and internal-comment mode. Selected channel persists when collapsing/reopening within a conversation. ([Getting Started](https://help.gohighlevel.com/support/solutions/articles/155000006610-getting-started-with-the-conversations-tab))
- **Fact:** Snippets are reusable text or email content, can contain custom values/placeholders, live in folders, support search/type filters, and populate the composer for editing before send. Access requires Conversations → View & manage conversation permission. ([Conversations Snippets](https://help.gohighlevel.com/support/solutions/articles/155000003707-conversations-snippets))
- **Fact:** UI attachments can come from the device, media library, or clipboard. Oversized/channel-incompatible files may become media-library links. ([Attachments in Conversations](https://help.gohighlevel.com/support/solutions/articles/155000001323-attachments-made-easy-in-conversations))
- **Fact:** The API attachment uploader documents a different integration limit: at most five files per upload and 5 MB per file, across an enumerated set of image, video, audio, document, archive, contact, and calendar types. ([Messages API](https://marketplace.gohighlevel.com/docs/ghl/conversations/messages/index.html))
- **Fact:** The Messages API includes sending a new message, cancelling a scheduled message, updating message status, and fetching messages by conversation with `lastMessageId` pagination and type filters. ([Messages API](https://marketplace.gohighlevel.com/docs/ghl/conversations/messages/index.html), [Get messages](https://marketplace.gohighlevel.com/docs/ghl/conversations/get-messages/index.html))
- **Fact:** Forwarded-email failures can expose banners/status; HighLevel tells users to check DNS, sender reputation, and provider limits. Message details can identify the Marketplace app or provider that originated a message. ([Forward emails](https://help.gohighlevel.com/support/solutions/articles/155000007241-forward-emails-from-conversations-in-highlevel), [Getting Started](https://help.gohighlevel.com/support/solutions/articles/155000006610-getting-started-with-the-conversations-tab))

**Unverified:** Public pages reviewed here do not define the complete UI state machine for queued, scheduled, sent, delivered, read, failed, retried, bounced, or cancelled messages across every requested channel. The API proves scheduled cancellation and status updates exist, but not all user-facing semantics.

## 7. Automation, notifications, SLAs, and missed calls

- **Fact:** Workflows can route/assign conversations, send messages, and edit conversation state including read/unread and archive/unarchive. By default, workflow-sent messages can mark a conversation unread; a workflow setting can instead mark it read. ([Workflow Settings](https://help.gohighlevel.com/support/solutions/articles/48001239875-workflow-settings-overview/), [Mark as Read](https://help.gohighlevel.com/support/solutions/articles/48000980858-unread-vs-read-must-manually-mark-as-read))
- **Fact:** Notification events include all new conversations/messages, assignment to me, new messages on assigned conversations, follower activity, mentions, and continued activity after a mention. Delivery options include in-app/web/desktop, email, mobile, and SMS depending on the event. ([Live Chat notifications](https://help.gohighlevel.com/support/solutions/articles/155000005924-how-to-enable-and-customize-live-chat-notifications), [Custom notifications](https://help.gohighlevel.com/support/solutions/articles/48001224427-how-to-set-up-custom-notifications-as-a-user-in-a-sub-account))
- **Fact:** Optional channel-specific or common SLAs start on inbound messages, display on the conversation list, change from on-track to due-soon to overdue, and stop on an agent reply or manual mark-read. Admins can decide whether workflow/AI replies satisfy the SLA. ([Conversation SLAs](https://help.gohighlevel.com/support/solutions/articles/155000006745-conversations-how-to-setup-track-slas))
- **Fact:** Missed Call Text Back automatically sends an SMS from the default number after each missed call. Repeated calls can cause repeated texts, and HighLevel recommends workflow logic such as a wait/tag guard when deduplication is desired. ([Missed Call Text Back](https://help.gohighlevel.com/support/solutions/articles/48001239140-where-and-how-to-configure-the-missed-call-text-back-feature))

**Inference:** Automation and humans share the timeline, so every message should retain an origin (human, workflow, campaign, AI, provider/app) and automation should not silently imply human handling.

## 8. Permissions, settings, and onboarding

- **Fact:** Team Inbox requires full data access; snippet visibility/use requires Conversations → View & manage conversation. ([Getting Started](https://help.gohighlevel.com/support/solutions/articles/155000006610-getting-started-with-the-conversations-tab), [Conversations Snippets](https://help.gohighlevel.com/support/solutions/articles/155000003707-conversations-snippets))
- **Fact:** Facebook/Instagram onboarding requires connecting the appropriate Page/account in Settings → Integrations, linking Instagram to Facebook where required, and testing inbound and outbound messages. ([Facebook and Instagram setup](https://help.gohighlevel.com/support/solutions/articles/155000005068))
- **Fact:** Web Chat onboarding requires creating a widget, customizing it, and installing a script (or the LeadConnector WordPress plugin). ([Web Chat inside Conversations](https://help.gohighlevel.com/support/solutions/articles/155000007355-web-chat-inside-conversations))
- **Fact:** Email capabilities depend on the connected provider and sync mode; operational onboarding therefore includes validating cold inbound capture, reply threading, sender address, and two-way sync rather than merely marking email “connected.” ([Inbound Email trigger](https://help.gohighlevel.com/support/solutions/articles/155000007650-workflow-trigger-inbound-email), [Forward emails](https://help.gohighlevel.com/support/solutions/articles/155000007241-forward-emails-from-conversations-in-highlevel))

**Unverified:** The reviewed sources do not provide a complete role/permission matrix for viewing, sending, deleting, exporting, reassigning, or accessing specific channels and contacts. This must be established before adopting GHL's behavior “totally.”

## 9. Mobile

- **Fact:** The current mobile app groups Conversations, Email, SMS, and messaging channels under Communication; its homepage can show unread messages, Universal Search can search Conversations/Contacts/Opportunities, and quick actions include creating messages. ([HighLevel Mobile App Experience](https://help.gohighlevel.com/support/solutions/articles/155000008398-highlevel-mobile-app-experience))
- **Fact:** Conversation AI on mobile can show suggested replies or send automatically, and users can pause/activate/schedule bot reactivation per conversation; core bot setup remains desktop-only. ([Conversation AI mobile](https://help.gohighlevel.com/support/solutions/articles/155000002669))
- **Fact:** Mobile users can apply contact DND from Conversations, call screens, or call logs. ([Mobile DND](https://help.gohighlevel.com/support/solutions/articles/155000005437-how-to-use-mobile-app-dnd-in-contacts))

**Unverified:** First-party pages reviewed do not document full mobile parity for advanced inbox filters, internal comments, followers, bulk actions, saved views, or all composer functions.

## 10. APIs, webhooks, and integration shape

- **Fact:** Public v3 endpoints cover conversation CRUD, search, message retrieval/sending, inbound-message insertion, external outbound-call insertion, scheduled-message cancellation, file upload, and message-status update. ([Conversations API](https://marketplace.gohighlevel.com/docs/ghl/conversations/conversations/index.html), [Messages API](https://marketplace.gohighlevel.com/docs/ghl/conversations/messages/index.html))
- **Fact:** Message retrieval supports cursor-like pagination using `lastMessageId` and filtering by types including SMS, email, Facebook, Instagram, WhatsApp, calls, and CRM activity types. ([Get messages](https://marketplace.gohighlevel.com/docs/ghl/conversations/get-messages/index.html))
- **Fact:** Search supports assigned owner, followers, mentions, free-text query, sort, and continuation fields. ([Search Conversations](https://marketplace.gohighlevel.com/docs/ghl/conversations/search-conversation/index.html))
- **Fact:** Custom conversation providers can receive signed outbound-message webhooks for SMS and email initiated from web, mobile, workflows, or bulk actions. HighLevel explicitly tells providers to verify webhook signatures against the raw request body. ([Conversation Provider outbound webhook](https://marketplace.gohighlevel.com/docs/webhook/ProviderOutboundMessage/))
- **Fact:** Contact-identification merges for live chat emit a webhook with old/new conversation IDs and the contact ID. ([ConversationUpdate webhook](https://marketplace.gohighlevel.com/docs/webhook/ConversationUpdate/index.html))

**Inference:** Provider adapters should normalize into a stable internal message model while retaining raw provider IDs/payload references, delivery transitions, threading keys, and signed-webhook idempotency keys.

## 11. Edge cases and provider limitations to carry into design

1. **Meta windows:** automated Facebook/Instagram replies may become unavailable after 24 hours without user interaction. The composer must explain why a channel is unavailable rather than failing silently. ([Facebook Interactive Messenger](https://help.gohighlevel.com/support/solutions/articles/155000004661-workflow-action-facebook-interactive-messenger), [Instagram Interactive Messenger](https://help.gohighlevel.com/support/solutions/articles/155000004662-workflow-action-instagram-interactive-messenger))
2. **Email is not one endless thread:** multiple email subjects can coexist for a contact. Replying must preserve provider headers/thread identity. ([User Replied trigger](https://help.gohighlevel.com/support/solutions/articles/155000008196-workflow-trigger-user-replied))
3. **Anonymous chat becomes identified:** merging must preserve history and references, and downstream consumers need a merge event. ([ConversationUpdate webhook](https://marketplace.gohighlevel.com/docs/webhook/ConversationUpdate/index.html))
4. **Read is intentional work state:** viewing alone does not clear it; reply/manual action does. Automation can alter it, so source-aware rules matter. ([Mark as Read](https://help.gohighlevel.com/support/solutions/articles/48000980858-unread-vs-read-must-manually-mark-as-read))
5. **Archive does not reopen on inbound:** the item remains archived but appears in Unread. This is a non-obvious interaction to decide deliberately. ([Getting Started](https://help.gohighlevel.com/support/solutions/articles/155000006610-getting-started-with-the-conversations-tab))
6. **Attachment limits differ by surface/provider:** UI email threshold and API upload constraints are not the same. Store capability/limit metadata per channel and entry point. ([Attachments](https://help.gohighlevel.com/support/solutions/articles/155000001323-attachments-made-easy-in-conversations), [Messages API](https://marketplace.gohighlevel.com/docs/ghl/conversations/messages/index.html))
7. **Cold inbound email is provider-dependent:** “email connected” is insufficient as a capability flag. ([Inbound Email trigger](https://help.gohighlevel.com/support/solutions/articles/155000007650-workflow-trigger-inbound-email))
8. **Missed-call auto-replies can duplicate:** every missed attempt can trigger another SMS unless guarded. ([Missed Call Text Back](https://help.gohighlevel.com/support/solutions/articles/48001239140-where-and-how-to-configure-the-missed-call-text-back-feature))
9. **Internal notes are immutable and attachment-free in GHL:** adopting this exactly is a product choice, not a technical necessity. ([Internal comments](https://help.gohighlevel.com/support/solutions/articles/155000003877-conversations-adding-internal-comments-and-mentioning-users))
10. **Deletion is permanent:** GHL's bulk delete is unrecoverable. This deserves explicit confirmation rather than automatic imitation. ([Conversation Filters](https://help.gohighlevel.com/support/solutions/articles/48001222121-overview-of-conversation-filters))

## 12. Candidate adoption decisions for grilling

These are proposals/inferences, not observed GHL facts:

1. Make the contact/client conversation workspace primary and expose contractor-specific context: property, active request, quote/job, invoice, payment. Placement and visual treatment follow UCRM's blueprint, not GHL's layout.
2. Preserve channel-native threading beneath one chronological activity view.
3. Treat unread as “needs attention”; separately model archive, star/priority, assignment, followers, and SLA.
4. Distinguish human, workflow, campaign, AI, and integration-originated messages everywhere.
5. Use channel capability checks in the composer (identity present, provider connected, consent/DND, reply window, attachment limits) with an actionable reason when disabled.
6. Keep internal comments in the customer timeline but unmistakable and never externally deliverable; their visual treatment comes from the UCRM blueprint.
7. Require an explicit decision on destructive delete versus archive-only retention.
8. Treat anonymous Web Chat identification and contact merge as a first-class lifecycle.
9. Verify mobile behavior independently rather than assuming desktop parity.

## 13. Known research gaps

- Keyboard shortcuts and non-visual productivity behaviors not fully documented in help text. GHL's visual design itself is intentionally outside this research scope.
- Complete permissions matrix and record-level visibility behavior.
- Complete per-channel delivery/read/failed/retry state machines.
- Manual social messaging behavior outside Meta's response window and all supported rich-message types.
- Contact deduplication rules beyond the documented live-chat identification merge.
- Exact search scope (contact fields versus message bodies versus attachments) in the web UI.
- Retention, export, legal hold, audit, and tenant-admin controls.
- SMS consent, opt-out, registration, country/provider constraints; these should be researched against the actual provider and applicable rules, not inferred from GHL UI.
- Mobile parity across every collaboration and triage feature.

These gaps should be resolved through a read-only live-product walkthrough and provider-specific primary documentation before a final UCRM contract is approved.
