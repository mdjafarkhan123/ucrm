# Communications A2 product UI — HighLevel reference

Research date: 2026-09-13  
Scope: Current first-party HighLevel product/help material for SMS conversations, workflow SMS, phone/messaging settings, usage, and agency controls. This is competitor evidence, not a UCRM product contract.

Live authenticated follow-up: Jafar's `Jk LTD` subaccount was inspected read-only on 2026-09-13. The observed
screen structure, controls and evidence gaps are indexed in
`Design/communications/live-highlevel-evidence.md`. HighLevel's `Fast 5 Lite` template was opened as an
unpublished draft to inspect its SMS action; no message was sent, phone number purchased, or workflow published.

## Executive finding

HighLevel keeps day-to-day messaging, automation design, delivery diagnosis, phone readiness, and commercial controls in separate surfaces. The conversation is the agent workbench; workflow configuration owns automated content and timing; message details and execution logs explain a particular send; Phone System owns number readiness and messaging health; billing/wallet dashboards own spend; and Agency View owns cross-account limits and rebilling. This separation is the clearest reusable UI pattern.

## 1. Conversations: manual SMS workbench

- The current Conversations workspace is a four-panel layout: inbox scope, conversation list, message history, and a right-side contact/CRM context panel. The composer stays with the selected contact and allows channel switching inside the same workspace. The history can mix messages with CRM activities, while the right panel exposes contact fields and related records. ([Getting Started with the Conversations Tab](https://help.gohighlevel.com/support/solutions/articles/155000006610-getting-started-with-the-conversations-tab))
- SMS has explicit **From** and **To** selectors. The From dropdown lists available numbers with friendly name, assigned user, and badges for default/last-used. It defaults to the last number used with that contact, or the account default for a new conversation. If the contact has several numbers, To can be changed and otherwise defaults to the primary number. Admins can access all account numbers; users get the account default, last-used, assigned, and unassigned numbers. ([Select SMS To and From Numbers](https://help.gohighlevel.com/support/solutions/articles/155000003721))
- Reusable replies are called **Snippets**. In a conversation, the agent opens the Snippets control, browses folders or searches, selects a snippet, and HighLevel inserts it into the composer for editing before send. Snippets support custom values and trigger links. The library has text/email types, folders, search, filters, preview/test, bulk move, and edit/duplicate/delete actions. Access depends on **Conversations → View & manage conversation**. ([Conversations — Snippets](https://help.gohighlevel.com/support/solutions/articles/155000003707), [HiRise Snippets redesign](https://help.gohighlevel.com/support/solutions/articles/155000006741-understanding-snippets-in-hirise-design))
- HighLevel exposes character count, SMS segment count, and approximate cost while authoring/testing a text snippet. Its cost guidance reinforces that billing is segment-based and that emoji, Unicode, and hidden pasted characters can increase segment count. Cost also varies by direction, destination, carrier fees, media, and first-message number validation. ([Message Templates/Snippets](https://help.gohighlevel.com/support/solutions/articles/155000000890-message-templates-snippets-), [How to Calculate SMS and MMS Costs](https://help.gohighlevel.com/support/solutions/articles/48001203458))
- Composer attachments are opened from the three-dot control and can be uploaded from the device or chosen from Media Library. SMS/MMS files that cannot be delivered directly because of size, type, or channel requirements can be converted into a Media Library link. ([File Size Limits for Attachments](https://help.gohighlevel.com/support/solutions/articles/48001208913))
- Conversation message details identify an automated message's workflow and deep-link directly to that contact's preselected Workflow Execution Details. This makes the visible message the starting point for diagnosis. ([Improved Execution Logs & Enrollment History](https://help.gohighlevel.com/support/solutions/articles/155000003992-execution-logs-enrolment-history-enhancements))
- A failed SMS is shown in Conversations as **Unsuccessful** with a red indicator; its error detail exposes a numeric provider/carrier code and description. HighLevel also surfaces failures in the contact timeline and workflow logs. ([Why Is My SMS Not Being Delivered?](https://help.gohighlevel.com/support/solutions/articles/48001208912), [Troubleshooting SMS Delivery](https://help.gohighlevel.com/support/solutions/articles/48000981696))
- HighLevel distinguishes human replies from workflow and AI messages: its **User Replied** trigger fires only after a human-sent conversation message is delivered, not when it is merely submitted, and does not fire for workflow or Conversation AI sends. ([Workflow Trigger — User Replied](https://help.gohighlevel.com/support/solutions/articles/155000008196-workflow-trigger-user-replied))

### Public-evidence gaps

- The reviewed public pages do not publish a complete, current visual state machine for queued, scheduled, sent, delivered, read, failed, retried, or cancelled SMS bubbles.
- Public material confirms segment/cost feedback in snippet authoring, but does not clearly prove that identical live cost feedback is always present in the ordinary conversation composer.
- Embedded screenshots show UI examples, but public documentation does not provide a stable specification for exact spacing, icon placement, responsive collapse behavior, or every empty/error state. Authenticated observation is needed before copying visual detail.

## 2. Workflow Send SMS

- The **Send SMS** action card contains an action name, message body, reusable template selection, dynamic/custom values, optional URL attachment, and **Test Phone Number**. The country picker defaults to the sub-account country; the user can change the country, enter a local-format number, and send a real test before activation. ([Workflow Action — Send SMS](https://help.gohighlevel.com/support/solutions/articles/155000002474))
- SMS sends when a contact reaches the action after the workflow's triggers, conditions, and waits. The documented launch flow is to configure content, test with sample data, then publish. ([Workflow Action — Send SMS](https://help.gohighlevel.com/support/solutions/articles/155000002474), [Getting Started with SMS Campaigns](https://help.gohighlevel.com/support/solutions/articles/155000005065))
- Workflow-level **Communication Settings** centralize timezone, a permitted sending **Time Window** with start/end time and included days, and sender defaults including From Number. If a contact reaches a communication action outside the window, the action pauses and resumes in the next allowed slot. A separate setting controls whether workflow messages mark the conversation read; the default is unread. ([Workflow Settings Overview](https://help.gohighlevel.com/support/solutions/articles/48001239875))
- Execution Logs and Enrollment History are separate tabs inside a workflow. Execution rows expose status and a **View Details** link; failed rows/details are visually highlighted, opened rows stay highlighted, and timestamps use clearer date/time display. Both areas paginate. Conversation message details can open the exact execution directly. ([Improved Execution Logs & Enrollment History](https://help.gohighlevel.com/support/solutions/articles/155000003992-execution-logs-enrolment-history-enhancements))
- An outbound SMS restriction does not pause the whole workflow. The SMS action can fail, later actions can continue according to the workflow, and HighLevel does not automatically retry the failed SMS when service returns. The recovery UI is Execution Logs → affected contact → execution details. ([LC Phone Messaging Policy](https://help.gohighlevel.com/support/solutions/articles/48001213941))

### Public-evidence gaps

- The public Send SMS page does not prove an action-local From-number selector; HighLevel documents From Number as a workflow-level sender default.
- Public docs do not fully enumerate every Send SMS validation, attachment-preview state, character/segment/cost counter location, or test-send result state in the current builder.
- The exact history-table columns, filters, and per-action payload shown can change; only the documented status/details/deep-link behavior is safe to treat as established.

## 3. Phone, SMS health, and usage settings

- Phone numbers live under **Settings → Phone System → Phone Numbers**. Number purchase exposes Voice/SMS/MMS capabilities, but purchase is separate from messaging readiness. US local messaging uses Trust Center Brand/Campaign registration; approved registration still needs the sending number linked and visibly marked **A2P Verified**. Rejections expose **View required fixes** and correction/resubmission guidance. ([Phone Number Purchase and Setup](https://help.gohighlevel.com/support/solutions/articles/155000003226), [A2P Campaign Registration](https://help.gohighlevel.com/support/solutions/articles/155000004539-campaign-registration-step-by-step-guide-and-faqs))
- **Settings → Phone System → Messaging → Messaging Analytics** shows Sent, Delivered, Failed, Received, and Opt-Out Rate cards, period comparison, date/source filters, trend charts, failure-reason breakdown, and clickable message logs. Detail rows/modals expose contact, phone, status, activity date, and error code. Default range is 30 days and maximum is 90; outbound source filters include Campaign, Workflow, and Bulk Request. ([Messaging Analytics Overview](https://help.gohighlevel.com/support/solutions/articles/155000002625))
- **Restriction History** is a read-only UTC log for messaging warnings/restrictions, with date filtering, reason, time, and measured value. Messaging Ramp separately shows current level/capacity/progress. These surfaces distinguish compliance/volume restriction from a particular delivery failure. ([SMS Restriction History](https://help.gohighlevel.com/support/solutions/articles/155000003568-sms-restriction-history), [Messaging Ramp Progress Card](https://help.gohighlevel.com/support/solutions/articles/155000005572-messaging-ramp-progress-card))
- HighLevel separates delivery analytics from money. Agency **Wallet & Transactions** shows current balance, category spend, transactions, CSV export, and transaction drill-down; Agency Wallet Summary adds cross-location spend and product detail. ([Analyze Agency Spending on LC Communications](https://help.gohighlevel.com/support/solutions/articles/48001225291-how-to-analyze-an-agency-s-spending-on-lc-communications), [Agency Wallet Summary](https://help.gohighlevel.com/support/solutions/articles/155000007776-agency-billing-wallets-transactions-summary))

## 4. Agency/owner controls

- Agency **Phone Integration → Account Creation** sets defaults for newly created sub-accounts, including LC Phone attachment, whether locations may submit A2P, Number Intelligence, and the initial messaging-limit model. ([Default Phone Preferences](https://help.gohighlevel.com/support/solutions/articles/155000004593))
- Agency Owners/Admins can set daily/monthly limits by message count or segment count and can override an eligible individual sub-account under Phone Numbers → Advanced Settings. When a limit is reached, agency and sub-account users see a banner on Phone Numbers and configured recipients receive email. Increasing beyond the allowed ceiling requires support review. ([How to Increase Messaging Limits](https://help.gohighlevel.com/support/solutions/articles/155000006385))
- HighLevel's agency billing model supports automatic wallet recharge, sub-account rebilling, and markup. The Rebilling dashboard centralizes revenue, vendor cost, profit, usage, sub-account/product/date filters, and export. This is evidence for separating owner financial controls from contractor messaging screens, not evidence that UCRM should adopt HighLevel's commercial model. ([Rebilling, Reselling, and Wallets](https://help.gohighlevel.com/support/solutions/articles/155000002095), [Agency Dashboard for Rebilling](https://help.gohighlevel.com/support/solutions/articles/155000004173))
- Agency View user management lets Owners/Admins grant users agency/sub-account scope and granular module/action permissions. ([User Access in HighLevel](https://help.gohighlevel.com/support/solutions/articles/48000982600))
- Agency controls can also decide which modules a sub-account can see, including Phone System and Conversations; these feature permissions may be attached to SaaS plans. ([Manage Feature Permissions for Sub-Accounts](https://help.gohighlevel.com/support/solutions/articles/155000008587-how-to-manage-feature-permissions-for-subaccounts))

### Public-evidence gaps

- HighLevel does not publicly expose a complete provider-state model, provider credentials/subaccount diagnostics, or a parent-account reserve-control UI comparable to UCRM's intended platform-owned Twilio structure.
- HighLevel's documented broad **Pause Sub-Account** is an access/subscription operation, not proof of a precise global SMS-only emergency control. ([Pause/Resume Sub-Accounts](https://help.gohighlevel.com/support/solutions/articles/48001230403/))
- Some agency controls depend on HighLevel plan, account age, provider, country, or eligibility. Those mutable packaging rules should not be copied into a durable UCRM contract.

## Smallest defensible UI lessons

1. Keep manual sending in the contact conversation; make channel, To, From, reusable content, media, segment impact, and send state visible near the composer.
2. Keep automated SMS configuration in the workflow action, but put sending-window and default-sender policy at workflow level.
3. Link an automated message's details directly to its exact execution record.
4. Separate number/registration readiness, delivery health, restrictions, and billing usage; each answers a different user question.
5. Put cross-organization limits, financial reconciliation, and platform controls in an owner surface with explicit role checks.

These are evidence-backed interaction patterns only. They do not alter UCRM's approved balance, consent, provider-isolation, or owner-control contracts.
