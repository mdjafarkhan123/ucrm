# GHL and Jobber SMS onboarding reference

Research date: 2026-08-30  
Scope: Current first-party HighLevel, Jobber, and Twilio documentation for a US contractor-CRM SMS launch: number provisioning, A2P 10DLC onboarding, two-way conversations, consent and opt-out, operational messages, delivery/failure handling, billing, permissions, monitoring, and number exit. Marketing campaigns, MMS, voice implementation, and final UCRM product decisions are outside this note.  
Evidence labels: **Fact** is stated in a cited first-party source; **Inference** is a product conclusion drawn from facts; **Proposal** requires Jafar's approval.

## Executive answer

The thing being acquired is a cloud business phone number, not a SIM. Buying a number, registering it, and proving one outbound text works is only the provider-onboarding spine. A production-complete SMS slice also needs:

1. a per-contractor provider account and sender model;
2. business and campaign registration with visible, recoverable statuses;
3. verifiable consent, STOP/START/HELP enforcement, and retained consent evidence;
4. inbound replies in the shared conversation workspace;
5. message lifecycle and actionable delivery failures;
6. approved contractor-workflow sends such as reminders, reschedules, and On My Way;
7. staff permissions and conversation ownership;
8. segment-based usage metering, fees, limits, and billing;
9. delivery/compliance monitoring and webhook reconciliation; and
10. port-in, port-out, release, closure, and history-retention behavior.

**Proposal:** UCRM's first US SMS slice should use one local 10DLC number per contractor organization, one Twilio subaccount per organization, and one Messaging Service per registered campaign/use case. Start with non-marketing operational messaging: manual two-way SMS, appointment/visit reminders and changes, and On My Way. Do not include promotional blasts in the first campaign. HighLevel's missed-call text-back is attractive, but it depends on inbound voice routing and deduplication, so it should be a later voice-enabled slice rather than being smuggled into an SMS-only launch.

## 1. The mature product shape

### HighLevel

- **Fact:** A phone number is purchased inside a specific sub-account, may require one-time Persona identity verification, carries a recurring rental cost, and may still need registration/configuration before messaging can be relied on. HighLevel also supports porting an existing number. ([How to Purchase a Phone Number](https://help.gohighlevel.com/support/solutions/articles/155000003226), [Porting Options](https://help.gohighlevel.com/support/solutions/articles/48001211919))
- **Fact:** HighLevel exposes A2P onboarding in a Trust Center. The user registers a Brand (business identity), then a Campaign (messaging purpose and consent flow), then confirms each local number has the green `A2P Verified` label. Campaign submission can be pending, approved, or rejected with required fixes; carrier propagation can continue after approval. ([A2P overview](https://help.gohighlevel.com/support/solutions/articles/155000002380-what-is-a2p-10-dlc-brand-and-campaign-registration), [Campaign registration](https://help.gohighlevel.com/support/solutions/articles/155000004539), [Campaign rejection fixes](https://help.gohighlevel.com/support/solutions/articles/155000007572-understanding-a2p-campaign-rejection-reasons-required-fixes), [Link a number](https://help.gohighlevel.com/support/solutions/articles/155000008316-error-30034-how-to-link-a-phone-number-to-an-approved-a2p-campaign))
- **Fact:** SMS lives in a contact-centered Conversations inbox with assignment, followers, channel filters, human-versus-automated outbound filters, unread state, and SLA-oriented sorting. Users choose an eligible From number; admins see all account numbers while ordinary users see the default, last-used, assigned, and unassigned numbers. ([Conversation filters](https://help.gohighlevel.com/support/solutions/articles/48001222121-overview-of-conversation-filters), [Select SMS To and From numbers](https://help.gohighlevel.com/support/solutions/articles/155000003721))
- **Fact:** Contact DND and provider opt-out block even a manual reply. The first SMS conversation message includes sender identity and opt-out language; STOP-family keywords block subsequent sending and START-family keywords restore it. ([LC Phone Messaging Policy](https://help.gohighlevel.com/support/solutions/articles/48001213941), [SMS compliance settings](https://help.gohighlevel.com/support/solutions/articles/155000004684/), [Twilio error 21610](https://help.gohighlevel.com/support/solutions/articles/48001186075/))
- **Fact:** HighLevel supports appointment booked/confirmed, canceled, rescheduled, reminder, and follow-up notifications over SMS, with templates, test sends, recipients, and timing. It also offers missed-call text-back, but every missed attempt can emit another SMS unless a workflow guard is added. ([Calendar notifications](https://help.gohighlevel.com/support/solutions/articles/155000003441-calendar-email-in-app-appointment-notifications), [Missed Call Text Back](https://help.gohighlevel.com/support/solutions/articles/48001239140-where-and-how-to-configure-the-missed-call-text-back-feature))
- **Fact:** Failed messages show an error badge/code in Conversations. HighLevel does not blindly retry them; a workflow can react to a delivery error by alerting staff or switching channel. Its Messaging Analytics exposes delivery, failure reasons, inbound volume, and opt-out trends and can be filtered by campaigns, workflows, and bulk sends. ([Troubleshooting SMS Delivery](https://help.gohighlevel.com/support/solutions/articles/48000981696-troubleshooting-sms-delivery), [Messaging Error workflow trigger](https://help.gohighlevel.com/support/solutions/articles/155000003201-workflow-trigger-messaging-error-code-sms), [Messaging Analytics](https://help.gohighlevel.com/support/solutions/articles/155000007596-messaging-analytics-new-experience-in-phone-settings))
- **Fact:** Phone charges include number rental, message segments, A2P fees, and carrier pass-through fees. Delivery attempts can be billable even when ultimately undelivered. HighLevel's agency/sub-account wallet and rebilling model lets the platform expose usage and pass through or mark up costs. ([Phone System Pricing and Billing](https://help.gohighlevel.com/support/solutions/articles/48001223556-lc-phone-pricing-structure), [Wallets, Charges, and Rebilling](https://help.gohighlevel.com/support/solutions/articles/155000001156))
- **Fact:** Port-in is an explicit, tracked workflow using ownership evidence and an LOA. Moving numbers between sub-accounts requires rechecking A2P association, assignments, workflows, and call/SMS settings. ([Porting Options](https://help.gohighlevel.com/support/solutions/articles/48001211919), [Moving Numbers Between Sub-Accounts](https://help.gohighlevel.com/support/solutions/articles/48001203968-moving-numbers-across-sub-accounts))

### Jobber

- **Fact:** Jobber asks an admin to choose one local dedicated number, then register it. All manual and automated texts use that stable business number rather than employee personal numbers. Before setup, some automated texts can use a non-reply shared pool; successful registration unlocks two-way messaging. ([Dedicated Phone Number](https://help.getjobber.com/en/articles/dedicated-phone-number/), [Two-Way Text Messaging](https://help.getjobber.com/en/articles/two-way-text-messaging/))
- **Fact:** Jobber normalizes registration into user-facing states: `Not started`, `Processing`, `Failed`, `Verification Expired`, and `Successful`. During processing, two-way messaging is disabled; failed submissions give a correction/resubmission path. Registration can take up to three weeks. ([Register Your Number](https://help.getjobber.com/en/articles/register-your-number/))
- **Fact:** Jobber's message center is a searchable, client-centered two-way inbox. Unread is account-wide rather than per-user; manual messages identify the sending staff member. Admins see all messages. Non-admin access is permission-gated and also constrained by permissions on requests, quotes, jobs, invoices, and pricing. ([Two-Way Text Messaging](https://help.getjobber.com/en/articles/two-way-text-messaging/), [Two-Way Text Messaging FAQ](https://help.getjobber.com/en/articles/two-way-text-messaging-faq/), [User Permissions](https://help.getjobber.com/en/articles/user-permissions/))
- **Fact:** Jobber provides lifecycle-native SMS rather than treating texting as a standalone blast tool: booking confirmations, assessment/visit reminders, reschedule notifications, quote and invoice sends/follow-ups, review requests, and a fieldworker-triggered On My Way message. Rescheduling cancels old reminders, and staff can review the reschedule message. ([Emails and Text Messages Settings](https://help.getjobber.com/en/articles/emails-and-text-messages-settings/), [Assessment and Visit Reminders](https://help.getjobber.com/en/articles/assessment-and-visit-reminders/), [On My Way Text Messages](https://help.getjobber.com/en/articles/on-my-way-text-messages-in-the-jobber-app/), [Automations](https://help.getjobber.com/en/articles/automations/))
- **Fact:** A client's phone must be text-capable and enabled to receive messages. Automated communication categories have separate contact-level preferences. STOP causes an opt-out notification and blocks future SMS until the client texts START. ([Client Basics](https://help.getjobber.com/en/articles/client-basics/), [Two-Way Text Messaging](https://help.getjobber.com/en/articles/two-way-text-messaging/))
- **Fact:** A failed outbound is red in the thread and Jobber requires a manual copy/resend; a merely `sent` message may still be filtered at carrier/device level. The Client Communications report covers outbound operational texts, while back-and-forth message-center replies remain in the message center. New inbound texts can send push notifications to admins and SMS-enabled users. ([Two-Way Text Messaging](https://help.getjobber.com/en/articles/two-way-text-messaging/), [Push Notifications](https://help.getjobber.com/en/articles/push-notifications-from-the-jobber-app/))
- **Fact:** Two-way SMS has no separate per-message price on eligible Jobber subscriptions; the cost is packaged into the plan. This is a product-pricing choice, not evidence that provider usage is free. ([Two-Way Text Messaging](https://help.getjobber.com/en/articles/two-way-text-messaging/))
- **Fact:** Jobber's provisioned number is owned by Jobber, cannot be changed after selection, is non-transferable, and may be reclaimed when the qualifying subscription ends. Jobber has no obligation to port it out. ([Dedicated Phone Number](https://help.getjobber.com/en/articles/dedicated-phone-number/), [Jobber Terms of Service](https://www.getjobber.com/terms-of-service/))

### Decision-relevant comparison

| Concern | HighLevel pattern | Jobber pattern | Implication for UCRM |
| --- | --- | --- | --- |
| Tenant isolation | Number and telephony resources live per sub-account | One Jobber-managed dedicated number per business | Use one provider subaccount and stable number per contractor organization. |
| Onboarding | Full Trust Center with granular Brand/Campaign/number visibility | Small guided status model with banners and correction steps | Keep Jobber's plain-language UX over Twilio's detailed provider state machine. |
| Conversation work | Rich unified inbox, assignment, followers, filters, SLA | Simple shared message center with domain permission gates | Preserve UCRM's unified inbox and assignment model; require underlying work-item permission before exposing linked documents/pricing. |
| Operational SMS | Flexible workflows and calendar notifications | Opinionated contractor presets and On My Way | Default to Jobber's contractor workflow presets; add a GHL-style builder later. |
| Failures/monitoring | Message error codes plus aggregate analytics | Red thread failure plus outbound report | Offer both an actionable thread state and an admin operations dashboard. |
| Commercial model | Metered wallet/rebilling | Bundled into plan | Meter accurately underneath; packaging as allowance, overage, or pass-through remains a pricing decision. |
| Number exit | Porting and provider migration are supported workflows | Provisioned number is deliberately non-transferable | Do not copy Jobber's lock-in. Make number ownership and port-out expectations explicit before sale. |

## 2. Twilio constraints that validate the platform design

- **Fact:** UCRM is an ISV because contractor customers send under their own brands. Twilio's preferred architecture is one subaccount per customer plus Messaging Services. Each customer gets a Secondary Customer Profile, Brand, and Campaign(s); each use case maps to a Messaging Service. This isolates analytics and reduces the impact of one customer's noncompliant traffic on others. ([ISV A2P 10DLC Onboarding](https://www.twilio.com/docs/messaging/compliance/a2p-10dlc/onboarding-isv))
- **Fact:** Brand registration states include `PENDING`, `IN_REVIEW`, `APPROVED`, and `FAILED`. Campaign API states include `PENDING`, `IN_PROGRESS`, `FAILED`, and `VERIFIED`; failures carry structured errors. Twilio Event Streams emits Brand, Campaign, and phone-number registration/deregistration events. ([Brand troubleshooting](https://www.twilio.com/docs/messaging/compliance/a2p-10dlc/troubleshooting-a2p-brands/troubleshooting-and-rectifying-a2p-standardlvs-brands), [UsAppToPerson resource](https://www.twilio.com/docs/messaging/api/usapptoperson-resource), [A2P Event Streams](https://www.twilio.com/docs/messaging/compliance/a2p-10dlc/event-streams-setup))
- **Fact:** Standard/Low-Volume Standard Brands require a tax ID; eligible US/Canadian businesses without one use the Sole Proprietor path. Campaign registration needs a precise description, documented opt-in flow, publicly accessible privacy policy and terms, representative samples, link/phone declarations, and opt-in/out/help details. ([A2P overview](https://www.twilio.com/docs/messaging/compliance/a2p-10dlc), [Required business information](https://www.twilio.com/docs/messaging/compliance/a2p-10dlc/collect-business-info))
- **Fact:** A phone number can belong to only one A2P Campaign at a time. `CUSTOMER_CARE` covers support/account interaction; `MIXED` covers multiple uses and can cost more with lower throughput; Low-Volume Standard Brands can use the lower-volume mixed option. The actual campaign must truthfully match the content. ([Campaign use cases](https://help.twilio.com/articles/1260801844470-List-of-Campaign-Types-and-Use-Case-Types-for-A2P-10DLC-registration), [Multiple use cases](https://help.twilio.com/articles/4403014741403-I-have-multiple-messaging-use-cases-How-should-I-register-my-use-cases-for-A2P-10DLC))
- **Fact:** Twilio's current Messaging Policy requires freely given, sender- and subject-specific informed consent, retained proof of consent, sender identification, an initial-message opt-out instruction, and immediate honoring of opt-out. Consent from one subject/sender is not a blanket grant. ([Twilio Messaging Policy](https://www.twilio.com/en-us/legal/messaging-policy))
- **Fact:** Advanced Opt-Out can process STOP/START/HELP keywords and sends `OptOutType` to the inbound webhook. After opt-out, further sends fail with error `21610`; the application should record the event and must not emit a duplicate automated confirmation. ([Advanced Opt-Out](https://www.twilio.com/docs/messaging/tutorials/advanced-opt-out))
- **Fact:** Inbound SMS arrives by signed webhook with a stable Message SID. Outbound status callbacks transition through accepted/queued/sent and delivered or failed/undelivered. Twilio recommends persisting the Message SID and states, polling anything without a terminal delivery update after 12 hours, and reconciling statuses daily. ([Incoming message webhook](https://www.twilio.com/docs/messaging/guides/webhook-request), [Outbound status callbacks](https://www.twilio.com/docs/messaging/guides/track-outbound-message-status), [Delivery logging](https://www.twilio.com/docs/messaging/guides/outbound-message-logging))
- **Fact:** Subaccount Usage Records include number rental, inbound/outbound SMS, carrier fees, and A2P registration fees, and usage triggers can signal thresholds. Messaging Insights supports filtering by subaccount, Messaging Service, number, carrier, status, and error, while Monitor Alarms can notify on error thresholds. ([Usage Records](https://www.twilio.com/docs/usage/api/usage-record), [Messaging Insights](https://www.twilio.com/docs/messaging/features/messaging-insights/dashboards), [Monitor Alarms](https://www.twilio.com/docs/usage/monitor-alarms))
- **Fact:** Twilio numbers can be provisioned, ported/hosted, transferred between subaccounts, and released. A release is a destructive provider action; port-in has its own tracked workflow and compliance still has to be completed after the port. ([IncomingPhoneNumber resource](https://www.twilio.com/docs/phone-numbers/api/incomingphonenumber-resource), [Port into Twilio](https://www.twilio.com/docs/phone-numbers/port-in), [Cancel or release a number](https://help.twilio.com/hc/en-us/articles/223183028-Cancel-or-release-a-Twilio-number))

## 3. Proposed UCRM delivery plan

This is the smallest end-to-end plan that reaches a trustworthy production outcome. It is a proposal, not implementation approval.

### Phase A — lock the commercial and sender contract

1. Confirm US-only local 10DLC for v1 and one stable number per contractor organization.
2. Confirm that UCRM is the Twilio ISV and each contractor is the registered Brand in its own Twilio subaccount.
3. Decide number acquisition choices: buy a new local number for v1; make port-in a supported onboarding path or a clearly scheduled follow-up.
4. Decide the customer promise for ownership and exit. Recommended: the contractor can request port-out; UCRM never silently releases an active number.
5. Decide billing packaging: included allowance plus overage, transparent pass-through, or wallet/prepay. Regardless of packaging, meter segments and every provider fee.

### Phase B — make each contractor registration-ready

1. Collect legal name, entity type, EIN/tax ID status, address, authorized contact, website, and expected volume.
2. Publish public SMS terms and privacy pages that match the contractor Brand.
3. Build the actual opt-in surfaces before registration: booking/request/client forms with optional, unbundled SMS consent and the required sender, subject, frequency, rates, and opt-out disclosure.
4. Persist consent evidence by recipient, sender/Brand, message category, disclosure version, source, and timestamp.
5. Choose the truthful campaign use case after the message catalog is final. Keep marketing separate from the initial operational campaign.

### Phase C — guided number and 10DLC onboarding

1. Create the contractor's Twilio subaccount and Messaging Service.
2. Let an authorized admin choose an available local number, or initiate port-in; show recurring cost and a clear permanence warning.
3. Create the Secondary Customer Profile and Brand, then submit the Campaign with real opt-in evidence and representative samples.
4. Normalize provider states into plain UI: `Not started`, `Needs information`, `Submitted`, `In review`, `Action required`, `Approved—activating number`, `Ready`, and `Suspended`.
5. Subscribe to registration events, show every required fix, and support correction/resubmission. Keep all sending disabled until Brand, Campaign, and number registration are ready.

### Phase D — production SMS transport and inbox

1. Send through the organization's Messaging Service, never a shared cross-tenant sender.
2. Receive inbound messages through signature-validated, idempotent webhooks and attach them to the correct organization, contact, and continuous SMS conversation.
3. Store the provider Message SID, source (human/automation/system), sender user, segment count, price components, and full status history.
4. Process status callbacks idempotently even when duplicated or out of order; reconcile nonterminal statuses after 12 hours and all message states daily.
5. Display useful states in the inbox: queued/sending, sent, delivered, failed/undelivered, and blocked by consent/DND. SMS has no handset read receipt.
6. Do not automatically resend a failed SMS. Explain the cause and offer an appropriate action: fix number, wait for registration, ask the client to START, retry manually after a transient failure, or switch to email.

### Phase E — first contractor workflows

Recommended operational v1:

1. manual two-way SMS from the unified client conversation;
2. assessment/visit booking confirmation;
3. reminder before the appointment;
4. reschedule and cancellation notification, with old reminders canceled;
5. fieldworker On My Way with selectable ETA and a client/appointment link; and
6. inbound reply notification and shared-inbox ownership.

Next operational slice: quote and invoice links/follow-ups, then review requests. Marketing/bulk SMS should be a later campaign with separate consent and controls. Missed-call text-back should follow voice routing and must include a duplicate-call guard.

### Phase F — controls, permissions, billing, and operations

1. Enforce STOP/START/HELP and contact-level SMS DND at the send boundary for humans and automations alike.
2. Require a distinct permission to view/send two-way SMS, plus permission for any linked request, quote, job, invoice, or protected pricing.
3. Keep admin-only controls for number acquisition/release, registration, templates/presets, billing, and compliance settings.
4. Meter message segments rather than UI message bubbles; show number rental, registration, monthly campaign, carrier, inbound, outbound, and media costs separately.
5. Add organization and platform dashboards for volume, delivery rate, failures by code/carrier, opt-outs, registration health, webhook health, queue age, and spend/allowance.
6. Alert on registration suspension, delivery-error spikes, opt-out spikes, failed inbound/status webhooks, queue backlog, unusual spend, and low wallet/allowance.

### Phase G — exit and recovery

1. Define what suspension does to outbound, inbound, automations, and number billing.
2. Preserve message history independently of whether the provider number is moved or released.
3. Support documented port-out before release; never release during a recoverable closure window.
4. Require explicit destructive confirmation for release, stop recurring provider costs, unregister routing safely, and retain an audit trail.

## 4. Completion gate

“SMS sending successful” should mean all of the following have been demonstrated in a staging organization and then in a production smoke test:

- the organization is isolated in its own subaccount and the selected number is visibly ready;
- the registered Brand/Campaign matches the messages actually sent;
- a permitted user can send and receive in the unified conversation;
- an appointment reminder and On My Way message arrive with correct identity and links;
- a reschedule cancels the stale reminder;
- STOP blocks both manual and automated sends, START restores them, and HELP behaves correctly;
- an invalid/non-mobile destination and a carrier/provider failure are visible and actionable;
- duplicate/out-of-order webhooks do not duplicate messages or corrupt state;
- delivery callbacks reach terminal state or are reconciled;
- segment counts and all provider charges reach the correct organization ledger;
- registration, error-rate, opt-out, webhook, queue, and spend alerts fire in tests; and
- port/release responsibilities and conversation-history retention are documented before customers adopt the number.

## 5. Decisions Jafar still needs to make

1. Is v1 exactly manual two-way + reminders/reschedules + On My Way, or should quote/invoice texting be in the same launch?
2. Will contractors receive a portable-number promise, and will port-in be launch scope or a follow-up?
3. Will SMS be bundled with an allowance, prepaid/wallet-based, or passed through at cost/markup?
4. Which low-volume contractor types without an EIN will be accepted at launch?
5. Is marketing explicitly excluded until a separate campaign/consent project? Recommended: yes.
6. Should inbound voice and missed-call text-back be the next slice after SMS? Recommended: yes.

## Research limits

- Public Jobber material deliberately abstracts its upstream provider architecture and exposes packaged plan pricing, so it cannot validate an ISV implementation model; Twilio's own ISV docs are authoritative for that layer.
- HighLevel documents purchasing, port-in, sub-account moves, and whole-account transfers, but the reviewed public pages did not establish a simple end-user “port this number out” UX or a complete released-number recovery contract.
- This is product and platform research, not legal advice. Applicable consent/recordkeeping law still needs qualified legal review for launch jurisdictions and message types.
