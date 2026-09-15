# HighLevel SMS number behavior — Stage 4 research

Research date: 2026-09-12  
Scope: first-party HighLevel help, changelog and API documentation only.

## 1. Manual SMS sending-number priority

HighLevel's newest general sender-selection article (modified 2026-08-10) gives this priority for an SMS:

1. a From number explicitly chosen for that message;
2. the number assigned to the user sending it;
3. the number already used for that contact's conversation;
4. the location's default outbound number.

It also says an SMS-incompatible staff-assigned number falls back to the default outbound number. A manually
chosen number must belong to the location, and the number actually used can be checked in the sent message's
Details. [HighLevel: How the “From” Number Is Chosen for SMS](https://help.gohighlevel.com/support/solutions/articles/48001152126)

That article describes SMS generally and refers to the sending user, conversation continuity, manual changes,
workflows and API sends. It does **not** publish a separate priority table for a brand-new manual conversation
versus a manual reply. Applying its stated rules literally gives:

- **New manual conversation:** explicit choice → sending user's assigned number → location default, because
  there is no existing conversation number.
- **Manual reply:** explicit choice → sending user's assigned number → conversation number → location default.

Those two lines are an interpretation of the current priority table, not separately documented HighLevel UI
flows.

### First-party documentation conflict

The composer-specific guide (modified 2024-11-01) says the From dropdown preselects the **last-used number**
for an existing contact conversation and the **default number** when there is no previous conversation. It shows
the assigned user beside each option, but does not say a staff-assigned number is automatically preselected.
[HighLevel: Select SMS To and From Numbers](https://help.gohighlevel.com/support/solutions/articles/155000003721)

The matching launch changelog says the same: last-used for an existing conversation, default for no previous
conversation. [HighLevel changelog: Select a Phone Number to Send SMS Messages](https://ideas.gohighlevel.com/changelog/conversations-select-a-phone-number-to-send-sms-messages)

Therefore, the exact current composer default for a manual reply or brand-new manual message is **not
unambiguously documented**. The newer general article places the staff-assigned number ahead of conversation
continuity/default; the older, composer-specific material does not. Live-product verification or clarification
from HighLevel would be required before claiming exact UI behavior.

There is a second wording inconsistency inside the newer general article: its summary calls priority 3 the
"last-used number," while its fallback section calls the channel number the **first** LC number ever used with
the contact. Both express continuity, but they are not the same selection rule when a contact has used several
business numbers. [HighLevel: How the “From” Number Is Chosen for SMS](https://help.gohighlevel.com/support/solutions/articles/48001152126)

## 2. Manual To and From selection

The Conversations SMS composer has a From dropdown and, when the contact has multiple saved numbers, a To
dropdown. HighLevel says the From list shows friendly names, assigned users, and tags for the default and
last-used numbers. The To control lets staff choose the recipient number; for a contact with no previous
conversation, the primary contact number is preselected. [HighLevel: Select SMS To and From Numbers](https://help.gohighlevel.com/support/solutions/articles/155000003721)

Number visibility is role-sensitive:

- admins can access every configured location number;
- ordinary users can access the location default, the last number used with that contact, their own assigned
  numbers, and unassigned numbers.

That access list is documented by the same [HighLevel composer guide](https://help.gohighlevel.com/support/solutions/articles/155000003721).
HighLevel's newer general article additionally says a message-level explicit From choice overrides staff
assignment, conversation continuity and the default, and confirms that the assigned staff number can be
changed manually. [HighLevel: How the “From” Number Is Chosen for SMS](https://help.gohighlevel.com/support/solutions/articles/48001152126)

HighLevel documents that all messages for the several phone numbers linked to **one contact** are managed in
one Conversations view, and that a primary number can be set. This does not explain how one phone number shared
by several separate contacts is routed. [HighLevel changelog: Streamlined Multi-Number Management](https://ideas.gohighlevel.com/changelog/conversation-enhancements-streamlined-multi-number-management)

## 3. Inbound SMS identity and ambiguous numbers

### Clearly documented

Inbound SMS is stored in Conversations; an optional Customer Replied workflow can create a separate internal
notification while the original message remains in the inbox. [HighLevel: Send Inbound SMS Notifications via a Workflow](https://help.gohighlevel.com/support/solutions/articles/48001156789-how-to-send-inbound-sms-notifications-via-a-workflow)

HighLevel can be configured to allow duplicate contacts, and its duplicate-management documentation explicitly
supports finding separate contacts that share a phone number and explains that duplicates can split
communication history. [HighLevel: Manage and Merge Duplicate Contacts](https://help.gohighlevel.com/support/solutions/articles/48001202210-how-to-manage-and-merge-duplicate-contacts)

HighLevel's Contact Deduplication Preferences article lists Forms, Zapier, Facebook/Instagram and CSV import
behavior. It does not state that those creation/matching rules govern native inbound SMS.
[HighLevel: Allow Duplicate Contacts](https://help.gohighlevel.com/support/solutions/articles/48001181714)

### Not documented in the reviewed first-party sources

No reviewed HighLevel help, changelog or API page clearly states:

- whether a text from a phone number that matches no contact automatically creates a contact, creates only an
  unresolved conversation, or follows another review flow;
- what name/source/assignment such a new inbound record receives;
- which contact receives an inbound SMS when the same normalized phone number exists on multiple contacts;
- whether the business number receiving the SMS, prior outbound history, contact age, assignment, primary-phone
  status or another rule breaks that tie;
- whether staff see an ambiguity warning or can manually attach/reassign the inbound message before replying.

The public Conversations API does not fill this gap. Sending a message requires a `contactId`, and the
conversation-provider documentation describes adding inbound messages in a known contact/conversation context;
neither documents native LC Phone's unknown- or duplicate-number routing decision.
[HighLevel API: Send a new message](https://marketplace.gohighlevel.com/docs/ghl/conversations/send-a-new-message/)
[HighLevel API: Conversation Providers](https://marketplace.gohighlevel.com/docs/marketplace-modules/ConversationProviders/)

## Bottom line for UCRM product planning

- HighLevel clearly offers manual To/From choice and permission-filtered business-number access.
- HighLevel currently publishes a sender-priority rule led by explicit choice and staff assignment, but its
  older composer-specific default contradicts that rule. Exact manual new-message/reply defaults should be
  treated as unverified.
- HighLevel does not clearly document safe handling for an unknown inbound SMS sender or a phone number shared
  by multiple contacts. UCRM needs an explicit product rule for both cases; calling either choice “the GHL
  behavior” would not be evidence-based.
