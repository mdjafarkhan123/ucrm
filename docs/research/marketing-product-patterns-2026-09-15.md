# Integrated Marketing product patterns

Research date: 2026-09-15  
Scope: First-party product and help material from Jobber, HighLevel, HubSpot, Mailchimp, and Twilio. This is evidence for product-planning discussions, not an approved behavior contract or coding plan.

## Executive finding

The mature pattern is **Marketing as a growth layer over the existing CRM**, not a second customer database. The same client/contact, lead source, work history, tags, consent state, conversations, requests, quotes, jobs, invoices, and payments should determine who is eligible, what is sent, when it stops, and whether the outreach led to booked work.

For UCRM, the smallest useful first release is:

1. saved audiences built from existing customer and work facts;
2. reusable email content;
3. a safe one-off email campaign flow with exact recipient preview, test, schedule, cancellation of unclaimed work, and per-recipient results;
4. a few contractor-specific automated presets, using the existing Automation product rather than a second workflow engine;
5. channel-scoped consent, unsubscribe, suppression, frequency, and sender-readiness controls;
6. reporting that connects delivery and engagement to requests, jobs, and revenue without claiming that correlation proves causation; and
7. a post-work review flow, followed later by referrals and SMS marketing when their dependencies are ready.

## 1. The shared product model

### One customer record, many marketing uses

HubSpot segments group existing CRM records and can be active, meaning membership updates automatically as facts change, or static, meaning membership is a fixed/manual group. Those segments can drive email and workflow enrollment. HighLevel Smart Lists and Mailchimp prebuilt segments follow the same general pattern: they derive audiences from contact fields, engagement, and business activity rather than copying people into a separate marketing-only address book. ([HubSpot segments](https://knowledge.hubspot.com/segments/create-active-or-static-lists), [HighLevel Smart Lists](https://help.gohighlevel.com/support/solutions/articles/48001062094), [Mailchimp prebuilt segments](https://mailchimp.com/help/about-pre-built-segments/))

**Recommendation for UCRM:** the existing client/contact remains canonical. A saved audience stores reusable criteria. A one-off campaign resolves those criteria into a reviewable recipient snapshot at launch, while an always-on automation evaluates current eligibility when a person reaches the send step. Neither creates duplicate contacts.

### Use unambiguous names

“Campaign” means different things in mature products:

- In Jobber it can mean one one-off send or one always-on automated outreach.
- In HubSpot it is a broader planning container that can group emails, forms, landing pages, social posts, budgets, goals, and reporting. ([HubSpot campaigns](https://knowledge.hubspot.com/campaigns/create-campaigns))
- In Twilio A2P registration, a Campaign is a registered telecom use case, not a marketer's send. ([Twilio A2P 10DLC](https://www.twilio.com/docs/messaging/compliance/a2p-10dlc))

Product planning and UI copy should therefore distinguish **Marketing campaign**, **send**, **automation**, **audience**, and **SMS registration**.

## 2. Audiences and segments

Jobber's contractor-specific filters are the best starting point. It supports lead/client state, tags, city, never-booked clients, last completed job and lack of upcoming work, services/line items, recurring versus one-off work, and explicit include/exclude choices. It previews both the matching count and the actual clients before send. ([Jobber Campaigns](https://help.getjobber.com/en/articles/campaigns-marketing-tools/))

### First-release audiences

Provide named presets that explain their intent:

- past customers with no upcoming work;
- lost leads who never booked;
- customers of a selected service who may need a seasonal or complementary service;
- customers in a selected city/service area;
- tagged customers; and
- all eligible active customers, used cautiously.

Filters should initially cover client/lead state, tags, city/property area, lead source, service used, one-off/recurring work, last completed job, and upcoming work. The preview must show:

- total matching customers;
- eligible recipients by channel;
- excluded recipients and plain reasons such as no address, opted out, suppressed, duplicate destination, or sender/channel not ready; and
- the exact people who will receive the campaign.

HubSpot's active/static distinction supports keeping **dynamic saved audiences** for reuse and **fixed snapshots** for one-off execution history. ([HubSpot segments](https://knowledge.hubspot.com/segments/create-active-or-static-lists))

## 3. Campaign behavior and content

Across Jobber, HighLevel, HubSpot, and Mailchimp, the core flow is consistent: select recipients, choose or edit content, preview/test, review sender and exclusions, then send now or schedule. Jobber reduces this to three understandable steps—recipients, content, review—and supports templates or starting from scratch. ([Jobber Campaigns](https://help.getjobber.com/en/articles/campaigns-marketing-tools/), [HighLevel email campaigns](https://help.gohighlevel.com/support/solutions/articles/48001215263), [HubSpot marketing email](https://knowledge.hubspot.com/marketing-email/create-and-send-marketing-emails), [Mailchimp campaigns](https://mailchimp.com/help/getting-started-with-campaigns/))

### Recommended first-release workflow

1. **Goal/template:** choose Seasonal reminder, Win back past customers, Win back lost leads, Upsell another service, Announcement, or Start from scratch.
2. **Audience:** choose or edit a saved audience and inspect the exact eligible/excluded recipients.
3. **Content:** sender, reply-to, subject, preview text, heading/image/body, approved variables, and one clear call to action.
4. **Delivery:** send now or schedule in the business timezone; show the applicable volume, reputation, and allowance limits.
5. **Review:** test send, desktop/mobile preview, final content, actual eligible count, exclusions, send time, and an explicit confirmation.

The primary call to action should normally return customers to an existing request form, booking form, or relevant website page so the result re-enters the Lead → Request → Quote → Job workflow. Jobber supports request/booking CTAs in campaigns and tracked request/booking links. ([Jobber Campaigns](https://help.getjobber.com/en/articles/campaigns-marketing-tools/), [Jobber tracked forms](https://help.getjobber.com/en/articles/add-your-request-and-booking-forms-to-your-website-and-social-media/))

### Content reuse

Templates should be editable starting points, not centrally linked content that silently rewrites sent or active campaigns. The first template set should stay small and contractor-specific. Brand logo, colors, verified sender, business identity, physical address, and unsubscribe content come from their owning settings.

Campaign states should be understandable: Draft, Scheduled, Sending, Sent/Completed, Cancelled, and Stopped/Needs attention. Once sending starts, sent messages cannot be recalled; cancellation stops only recipients not yet claimed. Jobber exposes draft, scheduled, in-progress, sent, and deliverability-stopped states and sends larger audiences gradually. ([Jobber Campaigns](https://help.getjobber.com/en/articles/campaigns-marketing-tools/))

## 4. One-off campaigns and automations are related, but different

Jobber supports one-off campaigns and always-on contractor presets such as re-engaging past clients, winning back lost leads, and following up pending quotes. Its automated campaigns apply only from activation onward rather than sending retroactively. ([Jobber Campaigns](https://help.getjobber.com/en/articles/campaigns-marketing-tools/))

HighLevel, HubSpot, and Mailchimp demonstrate the larger automation pattern: enrollment trigger, ordered actions, waits, conditions/branches, exits, and result history. ([HighLevel workflow triggers](https://help.gohighlevel.com/support/solutions/articles/155000002292), [HubSpot workflows](https://knowledge.hubspot.com/workflows/create-workflows), [Mailchimp customer journeys](https://mailchimp.com/help/about-customer-journeys/))

**Recommendation for UCRM:** Marketing owns campaign intent, audiences, content, and reports. The existing Automation product owns always-on trigger/wait/action execution. The first marketing release adds only narrow dependency-ready presets and marketing-safe actions; it does not build a parallel visual journey engine.

Quote follow-ups, visit reminders, invoice reminders, receipts, and direct replies remain operational Communications/Automation behavior. Marketing should not duplicate them merely because Jobber offers a “close pending quotes” campaign. Promotional, cross-sell, referral-reward, discount, and unrelated sales content belongs to the marketing lane.

## 5. Lead capture and CRM workflow connection

Jobber request/booking forms can create a request or scheduled work, capture “How did you hear about us?”, accept communication consent, share/embed tracked links, and record UTM parameters. HubSpot forms create or update CRM records and can start follow-up or add people to segments. ([Jobber request and booking settings](https://help.getjobber.com/en/articles/requests-and-bookings-settings/), [Jobber lead management](https://help.getjobber.com/en/articles/lead-management/), [HubSpot forms](https://knowledge.hubspot.com/forms/create-and-edit-forms))

**Recommendation for UCRM:** Marketing should link to existing lead-capture surfaces rather than own a disconnected form database. Every capture source should:

- create or safely match the CRM contact and request;
- preserve explicit source, referrer, landing page, and bounded UTM fields;
- preserve the originating campaign/send where the link is UCRM-generated;
- treat service-request submission separately from optional marketing consent; and
- allow immediate operational acknowledgement even when marketing consent was not given.

Forms, website chat, referrals, imports, and integrations must use the same lead-source vocabulary and retain original source evidence rather than overwriting it with the latest campaign.

## 6. Consent, compliance, and customer trust

The safe industry pattern is channel- and purpose-specific eligibility, evaluated again at send time.

- Twilio requires prior consent tied to the recipient, sender, and message subject/purpose; the sender must be identified, and after opt-out only a final confirmation is allowed. ([Twilio Messaging Policy](https://www.twilio.com/en-us/legal/messaging-policy))
- Twilio Messaging Services can enforce and report opt-in, opt-out, and help keywords, including STOP/START/HELP behavior. ([Twilio Messaging Services](https://www.twilio.com/docs/messaging/services))
- HubSpot forms can capture processing consent separately from consent to a particular communication subscription, and a form can still accept a submission when optional communication consent is not selected. ([HubSpot form consent](https://knowledge.hubspot.com/forms/add-notice-and-consent-information-to-your-hubspot-form))
- Mailchimp requires a marketing-email unsubscribe path and physical address in campaign footers. ([Mailchimp footer requirements](https://mailchimp.com/help/about-campaign-footers/))
- Jobber keeps campaign unsubscribe separate from quotes, invoices, reminders, and other operational messages. ([Jobber Campaigns](https://help.getjobber.com/en/articles/campaigns-marketing-tools/))

### Required product behavior before any marketing send

- Store evidence of consent or another approved legal basis with channel, purpose/subscription, source, disclosure version, and time; do not use a tag as the legal record.
- Keep marketing eligibility separate from essential operational communications.
- Process unsubscribe/STOP immediately and recheck current consent, suppression, destination, sender readiness, organization state, allowance, and frequency at dispatch.
- Deduplicate shared email addresses/phone numbers within one launch and show which customer records were affected.
- Include mandatory identity, address, unsubscribe, and SMS wording automatically; users must not be able to delete required content.
- Keep email and SMS marketing in a separate queue/rate/reputation budget so a campaign cannot delay quotes, invoices, receipts, or direct replies.
- SMS marketing remains disabled until the contractor's sender/use case is registered where required, explicit SMS consent exists, STOP/HELP works, quiet hours and country rules are approved, delivery callbacks work, and segment/cost controls are live.

## 7. Reporting and attribution

Mailchimp reports delivery, opens, clicks, bounces, unsubscribes, complaints, and where connected, orders/revenue; it also warns that bot activity can inflate engagement. Jobber connects campaigns to jobs and revenue within a disclosed 30-day window and exposes per-recipient delivery, open, click, unsubscribe, jobs, and revenue. ([Mailchimp email reports](https://mailchimp.com/help/about-email-campaign-reports/), [Jobber Campaigns](https://help.getjobber.com/en/articles/campaigns-marketing-tools/))

Jobber also reports lead sources, conversion, reviews, referrals, website requests, and job revenue by channel. HubSpot shows the later-stage model: one campaign may contain multiple assets and multi-touch attribution can assign credit across contact, deal, and revenue interactions. ([Jobber Marketing Performance](https://help.getjobber.com/en/articles/marketing-performance-marketing-tools/), [Jobber lead management](https://help.getjobber.com/en/articles/lead-management/), [HubSpot campaign attribution](https://knowledge.hubspot.com/campaigns/use-campaign-attribution-reports))

### First-release reporting

The Marketing overview should answer four plain questions:

1. How many people did we try to reach, and how many were eligible?
2. What was delivered, failed, bounced, complained, unsubscribed, opened, or clicked?
3. How many requests and jobs followed, and what value/revenue do those records hold?
4. Which campaign, audience, source, or service appears to perform best?

Each campaign detail should include recipient totals, delivery/engagement, unsubscribes/complaints, per-recipient status/reason, request/job links, and attributed value/revenue. UCRM should state its attribution rule in the UI—for example, a direct tracked CTA association plus a clearly labelled time-window fallback—and call the result **attributed**, not “caused by.” Opens are directional because privacy features and bots make them unreliable.

First release should retain original lead source plus UTM/campaign evidence and offer simple first-touch/direct-campaign/defined-window views. Multi-touch models, paid-media cost/ROI, cross-channel journey analytics, and custom attribution models belong later.

## 8. Reviews and referrals

### Reviews: first reputation release

Jobber triggers review requests after a completed visit, closed job, or fully paid invoice; supports email, text, or both; provides follow-ups; limits repeated asks; permits per-client suppression; and reports contacted, clicked, and reviewed outcomes. ([Jobber Reviews](https://help.getjobber.com/en/articles/reviews-marketing-tools/))

The first UCRM reputation release should include:

- Google Business Profile/review destination setup;
- manual request plus one recommended post-work preset;
- job/visit/payment-based eligibility owned by the underlying lifecycle record;
- email first, SMS only when its marketing/optional-message safeguards are ready;
- a cooldown, reminders, and stop rules for reply, opt-out, invalid work state, private feedback, or confidently matched review;
- history on the customer and work timeline; and
- basic sent/clicked/feedback/review reporting.

A plain post-job review request can remain optional operational communication under UCRM's approved email contract. Adding promotions, incentives, referral rewards, or cross-sells changes it into marketing. Detailed routing and third-party review-platform policy must be rechecked during the Reputation campaign; the existing `docs/research/reputation-feature-research.md` records that unresolved policy boundary.

### Referrals: later, after review/campaign foundations

Jobber gives each referring client a unique referral path, tracks resulting leads, jobs, and revenue, and supports fixed or percentage credits that can be applied to invoices. It offers both one-off and post-job automated referral campaigns. ([Jobber Referrals](https://help.getjobber.com/en/articles/referrals-marketing-tools/))

UCRM should add referrals after campaigns, lead-source capture, and credit/invoice behavior are stable. The product needs a configured offer, unique recipient-bound link, referral relationship on the new lead, success rule, earned-credit state, invoice application, anti-abuse/cancellation behavior, and performance report. Referral incentives must not be mixed into the review request because that changes both customer expectations and compliance risk.

## 9. Recommended information architecture and UX

### Marketing navigation

- **Overview:** onboarding/recommended actions plus results across campaigns, reviews, referrals, lead sources, and booked work.
- **Campaigns:** one-off and automated marketing campaigns with search, status/type filters, and results.
- **Audiences:** saved dynamic criteria, current count, channel eligibility, last used, and duplicate/edit actions.
- **Templates:** small branded email/SMS library; SMS appears only when ready.
- **Reviews:** setup, requests, outcomes, and connected destination.
- **Referrals:** later program, sharing, credits, and performance.

Lead-capture forms stay with their owning Requests/Bookings or Website settings but are selectable as campaign CTAs. Broad communication delivery health and sender registration stay in Communications settings. Automation continues to own workflow execution. Marketing links to these surfaces when setup is incomplete.

### Key screen behavior

- The overview should lead with useful actions—create a seasonal campaign, reconnect with past clients, or finish sender/consent setup—not an empty analytics dashboard.
- Campaign list rows show name, one-off/automated type, channel, status, audience, scheduled/sent time, delivered/clicked, attributed jobs/revenue, and last update.
- Campaign detail separates Overview, Recipients, Content, and Activity/Results so a failed recipient is diagnosable without exposing provider jargon.
- The audience editor continuously updates the count and opens a recipient drawer before save/use.
- The final review step shows the rendered message, sender, CTA destination, eligible/excluded counts, schedule/timezone, estimated usage/cost where relevant, and a destructive “send cannot be recalled” warning.
- Contact and work timelines identify message origin as human, operational automation, or marketing campaign and link back to the exact campaign result.

Jobber's guided first-run Campaigns layout, preset templates, exact recipient preview, simple builder, list filters, and campaign dashboards support this contractor-friendly structure. ([Jobber Campaigns](https://help.getjobber.com/en/articles/campaigns-marketing-tools/))

## 10. Release boundary

| Phase | Include | Defer |
| --- | --- | --- |
| Foundation | Marketing permission; sender/readiness checks; consent and unsubscribe truth; audience eligibility; separate marketing lane/budget; audit/history | Broad new provider/infrastructure work without approval |
| First useful release | Marketing overview; saved audiences; one-off email; branded templates; test/preview/schedule/cancel; exact recipients and exclusions; per-recipient results; simple request/job/revenue attribution; request/booking CTA | SMS until registered and proven; free-form journey canvas; paid ads/social publishing |
| Next | Narrow win-back and lapsed-customer presets through Automation; Google review request funnel | General branching/looping campaign builder; multi-location review aggregation |
| Later | Referral program and credits; SMS campaigns; broader template library | Multi-touch/custom attribution, CDP identity graph, predictive audiences, AI optimization, ad audience sync, A/B/holdout testing, social calendar, job showcase |

The deferrals are deliberate. General journey builders, multi-asset campaign planning, CDP identity stitching, predictive audiences, and multi-touch attribution are mature features, but they add substantial scope and often depend on data volume. HubSpot's multi-asset campaign model and attribution, Mailchimp's journey branching, and HighLevel's broad trigger library are useful expansion references after UCRM proves safe targeted outreach. ([HubSpot campaigns](https://knowledge.hubspot.com/campaigns/create-campaigns), [HubSpot attribution](https://knowledge.hubspot.com/reports/create-attribution-reports), [Mailchimp customer journeys](https://mailchimp.com/help/about-customer-journeys/), [HighLevel workflow triggers](https://help.gohighlevel.com/support/solutions/articles/155000002292))

## Planning questions that still need Jafar's decision

1. Should the first release contain only one-off email plus Reviews, or also the two automated marketing presets (lost lead and lapsed customer)?
2. Which countries may use marketing email at launch, and which later qualify for SMS?
3. What exact evidence qualifies an imported/existing customer for marketing email when explicit form consent is absent?
4. What attribution window should UCRM display for a campaign when there is no direct tracked request link?
5. Which roles beyond owner/admin may create drafts, view results, schedule, or perform the final send?
6. Does the first Review release require public review ingestion/matching, or only request, click, and private-feedback tracking?
7. When Referrals arrives, what event earns the credit: request, booked job, completed job, fully paid invoice, or another approved milestone?

These are user-facing product choices. They should be resolved before dependent behavior/UI planning, not guessed during implementation.
