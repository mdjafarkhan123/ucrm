# Reputation and review-request feature research

Updated: 2026-09-12

## Purpose and evidence standard

This document describes the complete reputation-management capability for a contractor CRM before choosing a smaller first release. Product facts below are verified from official vendor documentation or first-party policy sources. Items labelled **Recommendation** are product proposals for UpliftContractor, not claims about competitors.

## Executive conclusion

A complete product is not merely an SMS containing a Google link. It is a reputation workflow connected to completed work: determine eligibility, ask through one or more channels, give the customer a low-friction destination, stop intelligently, capture replies and private feedback, alert the business when recovery is needed, reconcile public reviews, and report the result. Mature products automate the ask but retain manual sending, templates, per-customer suppression, multi-location routing, review response, and reporting.

The strongest contractor-specific pattern is Jobber's: trigger on a completed visit, closed job, or fully paid invoice; send email, text, or both; suppress repeat requests; allow per-client opt-out; and record messages in the client communication report. Jobber limits a client to one request every six months and avoids late-night review texts ([Jobber Reviews](https://help.getjobber.com/en/articles/reviews-marketing-tools/)). NiceJob adds a sequenced campaign that stops when a review is detected ([NiceJob campaigns](https://help.nicejob.com/en/articles/3133773-what-is-a-nicejob-campaign)). Birdeye demonstrates manual, bulk, mobile, scheduled, integration, SFTP, API, and condition-based automation entry points ([Birdeye review requests](https://support.birdeye.com/en/articles/12653437-how-can-i-get-new-reviews-from-my-customers-using-birdeye)). Podium demonstrates single-recipient/location-specific invitation links, invite delivery/click tracking, automated reminders, review aggregation, attribution, customer-profile linkage, and a consolidated inbox ([Podium Reviews](https://www.podium.com/product/reviews), [Podium invite API](https://docs.podium.com/reference/review_invitecreate-1), [Podium invite webhooks](https://docs.podium.com/changelog/new-webhooks-review-invites)).

HighLevel confirms the broader CRM pattern: requests can be sent manually, in bulk, from a contact, or through a workflow; SMS and email have editable initial/retry templates and cadence; retries stop per channel after the recipient clicks; and the general workflow builder supports ordered communication, wait, condition, goal, and internal actions ([HighLevel request settings](https://help.gohighlevel.com/support/solutions/articles/48000980328-reputation-management-how-to-customize-the-review-request-messages-sms-email-), [HighLevel workflow builder](https://help.gohighlevel.com/support/solutions/articles/155000001254)).

## Verified competitor patterns

| Area | Verified facts |
| --- | --- |
| Jobber | Automated ask after visit completion, job close, or full invoice payment; configurable email/text/both and message; optional follow-up; six-month per-client frequency guard; late-night completed-work triggers send email rather than text; per-client “Ask for review” control; likely-review matching can turn the job/invoice ask off; dashboard supports viewing and replying to Google reviews, AI reply drafts, competitor comparison, and communication reporting. Admin or Marketing Suite permission is required ([official guide](https://help.getjobber.com/en/articles/reviews-marketing-tools/)). |
| HighLevel | Manual, bulk, contact-record, and workflow request entry points; SMS, email, and separately configured WhatsApp channels; editable initial and retry templates; configurable delay, cadence, retry count, sender, and destination; per-channel retries stop after a link click. Its general workflows add waits, conditions, goals, draft/publish control, and mixed actions around a dedicated Review Request action ([request settings](https://help.gohighlevel.com/support/solutions/articles/48000980328-reputation-management-how-to-customize-the-review-request-messages-sms-email-), [sending guide](https://help.gohighlevel.com/support/solutions/articles/48001222668-how-to-send-review-requests), [workflow builder](https://help.gohighlevel.com/support/solutions/articles/155000001254)). |
| Podium | Automated textable invites and reminders; review sites are consolidated into one inbox; reporting includes totals and attribution; reviews sync to contact profiles; mobile management is supported ([official product page](https://www.podium.com/product/reviews)). The API creates an invite for one location and recipient and warns not to reuse a link across contacts because that damages reporting and may invalidate it ([official API](https://docs.podium.com/reference/review_invitecreate-1)). Webhooks expose created, delivered, clicked, and failed invite states ([official changelog](https://docs.podium.com/changelog/new-webhooks-review-invites)). |
| Birdeye | Quick Send by email/text, contact-level sending, manual check-in link, mobile sending, bulk campaigns, scheduled date ranges, and automation through CRM integration, SFTP, REST API, or conditions ([official guide](https://support.birdeye.com/en/articles/12653437-how-can-i-get-new-reviews-from-my-customers-using-birdeye)). Birdeye also advertises surveys/private feedback, alerts, responses/rules, 150+ review sites, and a central dashboard ([official integration description](https://birdeye.com/integration/birdeyedirect/)). |
| NiceJob | A review invite enrolls the customer in a campaign: initial SMS, up to three email follow-ups over 14 days, and automatic exit after a detected review or the final message. NiceJob explicitly tells businesses to send only where they have applicable email/SMS consent ([official campaign guide](https://help.nicejob.com/en/articles/3133773-what-is-a-nicejob-campaign)). Its official Jobber integration starts a campaign when a Jobber job closes; responses remain in NiceJob rather than syncing back to Jobber ([Jobber integration guide](https://help.getjobber.com/en/articles/jobber-and-nicejob-reviews-and-referrals/)). |

## Complete recommended feature set

### 1. Campaigns and triggers

**Recommendation**

- Allow multiple named review campaigns, each tied to a location/brand and service category.
- Native triggers: visit completed, job completed/closed, invoice paid in full, and manual enrollment. Later add external/API and import triggers.
- Configurable delay after the event, business timezone, sending window, allowed weekdays, and channel order.
- Make “job completed” the recommended contractor default. Payment completion can be an alternative, not a mandatory dependency.
- Store the exact event and record that caused enrollment. Use idempotency so retries cannot create duplicate sequences.
- For recurring work, support “after N visits” and a global customer cooldown.

Jobber verifies the three principal contractor triggers and an “after N visits” option; HighLevel verifies using a Review Request action inside a general workflow, including after an appointment-status change; Birdeye and NiceJob verify that external integrations and completed transactions are common automation sources ([Jobber](https://help.getjobber.com/en/articles/reviews-marketing-tools/), [HighLevel](https://help.gohighlevel.com/support/solutions/articles/48000980328-reputation-management-how-to-customize-the-review-request-messages-sms-email-), [Birdeye](https://support.birdeye.com/en/articles/12653437-how-can-i-get-new-reviews-from-my-customers-using-birdeye), [NiceJob](https://get.nicejob.com/resources/how-automation-ai-replies-get-repeats-broadcasts-and-referral-campaigns-work-together-to-grow-your-business)).

### 2. Eligibility and suppression

**Recommendation**

A request is eligible only when all configured rules pass:

- the work event is valid and not reversed;
- the customer has a usable destination and consent for the selected channel;
- the customer, contact, job, or campaign is not suppressed;
- no prior request/review falls within the cooldown;
- no open complaint, refund, dispute, chargeback, or recovery case exists, if the contractor enables that operational exclusion;
- the contact is not an employee/test/internal record;
- the location and connected review profile are active.

Show a human-readable reason whenever a customer is skipped. Permit an authorized user to cancel a queued request or manually include an otherwise eligible customer, but never override channel opt-out or platform-level abuse controls.

Jobber verifies per-client suppression, review matching, and a six-month cooldown ([official guide](https://help.getjobber.com/en/articles/reviews-marketing-tools/)).

### 3. Customer journey and destinations

**Recommendation**

- Use a unique, expiring, recipient-bound request link, following Podium's attribution pattern.
- Landing page shows contractor branding, completed job context, a neutral request for honest feedback, and accessible buttons.
- Contractor configures the primary public destination per location (initially Google); later support Facebook and industry sites.
- Include a separate “Send private feedback” route available with equal visibility to every recipient.
- Private feedback captures rating, comment, optional callback request, and attachments only if needed later.
- Thank the customer after either action; never claim a public review was posted until confirmed by the destination.
- Let customers reply directly to SMS/email and place the reply in the existing communications inbox.

### 4. Rating funnel configuration

**Approved product direction:** contractors may configure a landing-page rating question and route outcomes differently—for example, direct high ratings toward a public review and low ratings toward private recovery.

**Policy fact/risk:** Google prohibits discouraging negative reviews and “selectively solicit[ing] positive reviews”; it permits asking for genuine-experience reviews without incentives ([Google fake-engagement policy](https://support.google.com/business/answer/7400114)). FTC staff likewise says not to ask only people expected to be positive or prevent/discourage negative reviews ([FTC platform guidance](https://www.ftc.gov/business-guidance/resources/featuring-online-customer-reviews-guide-platforms)). A selective funnel can therefore put the contractor's Google profile and the platform at risk even if the contractor chooses it.

**Terminology correction:** HighLevel's current “Review Balancing” is not a rating funnel. It distributes request traffic by configured percentage across connected public destinations such as Google and Facebook. HighLevel can also branch a workflow by star rating after a Google or Facebook review has already been received; neither feature validates pre-review selective routing ([HighLevel balancing](https://help.gohighlevel.com/support/solutions/articles/155000004137-review-request-balancing-across-platforms), [HighLevel review-received trigger](https://help.gohighlevel.com/support/solutions/articles/155000003873-how-to-setup-workflow-triggers-for-google-and-facebook-reviews)).

**Recommendation:** support two modes with a clear owner-facing disclosure:

1. **Equal-choice mode (recommended/default):** every recipient sees the same public-review and private-feedback choices regardless of rating. Rating can still prioritize recovery internally.
2. **Selective-routing mode (contractor-configurable):** configurable threshold and destinations, visibly labelled as carrying third-party policy risk. Platform owner can disable this mode globally, by country, destination, tenant, or enforcement event.

Do not describe selective routing as “Google compliant,” do not prefill review text, and do not use language that pressures a particular rating. Keep an immutable audit of the mode, threshold, copy, recipient, and routing decision in effect for every request.

### 5. Messages, channels, reminders, and stop rules

**Recommendation**

- SMS and email templates with preview, test-send, locale, contractor identity, merge fields, and safe fallback for missing data.
- Every preset is an editable starting template. Activating it creates a contractor-owned version that future platform-template changes do not overwrite.
- Support up to 50 ordered steps per automation. Contractors can add, remove, duplicate, reorder, and edit steps.
- Each step independently selects SMS, email, internal notification, delay, message/template, conditions, and stop behavior. A single journey may mix channels and operational actions.
- SMS-first, email-follow-up is a strong default, but the contractor selects SMS, email, both in sequence, or both together.
- Default sequence: initial request 1–2 hours after completion, email reminder after 2–3 days, final reminder after 7 days. This is a recommended template, not a product limit.
- Long sequences need a readable timeline, per-step recipient/channel preview, test mode, message-segment and cost estimate, and warnings for excessive contact frequency.
- Stop immediately after a matched public review, submitted private feedback, direct reply, opt-out, hard bounce/undeliverable, manual cancellation, reopened/cancelled job, open recovery case, or sequence expiry.
- Do not send non-essential review requests during quiet hours; defer to the next permitted local window.
- Keep SMS concise and calculate segment count/cost before activation.

NiceJob verifies multi-step SMS/email sequences and stopping after a review. Jobber verifies an editable initial request plus up to two follow-ups, configurable follow-up delay/channel, click-based suppression, and late-night protection. HighLevel verifies editable initial/retry templates, retry cadence and count, click-based stop behavior, mixed-action workflows, reply/link/event waits, and workflow time windows ([NiceJob](https://help.nicejob.com/en/articles/3133773-what-is-a-nicejob-campaign), [Jobber](https://help.getjobber.com/en/articles/reviews-marketing-tools/), [HighLevel request settings](https://help.gohighlevel.com/support/solutions/articles/48000980328-reputation-management-how-to-customize-the-review-request-messages-sms-email-), [HighLevel wait action](https://help.gohighlevel.com/support/solutions/articles/155000002470/), [HighLevel workflow settings](https://help.gohighlevel.com/support/solutions/articles/48001239875)).

### 6. Manual, one-off, and bulk sending

**Recommendation**

- “Request review” action on client, job, invoice, communication thread, and mobile job-completion screen.
- Quick-send drawer selects contact, eligible channel, location, destination, template, and send time, while showing suppression/consent status.
- Bulk flow supports filter/CSV selection, dry-run eligibility counts, duplicate removal, estimated message cost, sample preview, schedule, explicit confirmation, throttling, and result report.
- Bulk sending must use one unique tracked link per recipient and cannot bypass consent, cooldown, or opt-out.

Birdeye verifies quick send, contact-level, mobile, bulk, scheduled, and uploaded-contact flows; HighLevel verifies individual and bulk sending from Reputation, contact-level sending, and automated workflow sending; Podium verifies recipient-specific invitation links ([Birdeye](https://support.birdeye.com/en/articles/12653437-how-can-i-get-new-reviews-from-my-customers-using-birdeye), [HighLevel](https://help.gohighlevel.com/support/solutions/articles/48000980328-reputation-management-how-to-customize-the-review-request-messages-sms-email-), [Podium API](https://docs.podium.com/reference/review_invitecreate-1)).

### 7. Review ingestion and response workspace

**Recommendation**

- Connect review profiles per location and ingest public reviews, rating, text, author, date, source, response, and permalink.
- Match a review to the request/customer conservatively; show “likely match” separately from confirmed match.
- Unified review inbox with source/location/rating/responded filters, assignment, internal note, follow-up task, and customer timeline link.
- Reply from the CRM where the destination API permits; AI may draft or rewrite, but a human approves publishing by default.
- Flag suspicious reviews and deep-link to the review network's reporting process rather than promising removal.
- Optional widgets for website/quote use must disclose their selection rule and must not misleadingly present selected reviews as all reviews.

Jobber verifies review matching, replies, AI drafts, and using Google reviews in quotes; Podium verifies aggregation and profile linkage ([Jobber Reviews](https://help.getjobber.com/en/articles/reviews-marketing-tools/), [Jobber quotes](https://help.getjobber.com/en/articles/quotes-in-the-jobber-app/), [Podium](https://www.podium.com/product/reviews)). FTC guidance says platforms should publish genuine feedback fairly, disclose collection/display methods, avoid more scrutiny for negative reviews, and investigate suspicious reviews ([FTC](https://www.ftc.gov/business-guidance/resources/featuring-online-customer-reviews-guide-platforms)).

### 8. Private feedback and service recovery

**Recommendation**

- Private feedback belongs in the same campaign but is not a substitute that hides the public-review option in equal-choice mode.
- Configurable recovery threshold, urgent keyword detection, callback request, assignee/team, due date/SLA, and alerts.
- Create a recovery case linked to customer, job, request, invoice, communication, and campaign.
- Recovery states: new, acknowledged, contacting customer, resolved, closed; capture outcome and resolution notes.
- Stop reminders while recovery is open. After resolution, never pressure the customer to change/remove a truthful review or offer compensation for doing so.
- Report recovery speed and resolution independently of public-review conversion.

The FTC rule prohibits unfounded threats or intimidation used to suppress negative reviews and bars misleading claims that displayed reviews represent all/most submissions when negative reviews were suppressed ([FTC final-rule summary](https://www.ftc.gov/news-events/news/press-releases/2024/08/federal-trade-commission-announces-final-rule-banning-fake-reviews-testimonials)).

### 9. Reporting

**Recommendation**

Provide a funnel by date, campaign, channel, template, location, service, technician/team, and trigger:

- eligible, suppressed, queued, sent, delivered, failed/bounced;
- link opened/clicked;
- private feedback submitted;
- public review matched/confirmed;
- conversion rate and median time to review;
- rating/review volume trend and response rate/time;
- recovery cases, acknowledgement time, resolution time/outcome;
- opt-outs, complaints, failure codes, message segments, and estimated/provider cost.

Attribution must distinguish observed facts from inference: “clicked” is not “reviewed,” and name-based review matching is not confirmation. Podium verifies delivery/click/failure events and attributed reporting; Jobber verifies review messages in communication reporting ([Podium webhooks](https://docs.podium.com/changelog/new-webhooks-review-invites), [Podium Reviews](https://www.podium.com/product/reviews), [Jobber](https://help.getjobber.com/en/articles/reviews-marketing-tools/)).

### 10. Permissions and audit

**Recommendation**

- Owner/admin: connect profiles, select mode, activate campaigns, edit compliance settings, bulk send, export, and publish responses.
- Manager/marketer: manage campaigns/templates and responses for assigned locations if granted.
- Dispatcher/office: one-off send/cancel and manage recovery if granted.
- Fieldworker: request a review for their completed job only, if enabled; no campaign or aggregate reputation settings.
- Read-only/reporting role.
- Audit activation/deactivation, configuration/template changes, manual overrides, sends, suppression, review matching, published replies, exports, consent changes, and platform intervention.

Jobber restricts its Reviews dashboard/settings to admins or users with Marketing Suite permission ([official guide](https://help.getjobber.com/en/articles/reviews-marketing-tools/)).

### 11. Multi-location and integrations

**Recommendation**

- Each location has business name, timezone, sender, email identity, Google profile, public destinations, templates, campaign defaults, and report scope.
- Jobs inherit a location; requests must never fall back silently to another location's profile.
- Organization owners can publish locked defaults with location overrides and compare locations.
- Integrations: native CRM lifecycle events first; Google Business Profile for reviews/replies where API access permits; Twilio delivery/inbound/consent; email delivery/events; later webhooks/API and CSV import/export.
- External enrollment API requires idempotency key, tenant/location, customer, triggering record, occurred-at timestamp, consent evidence reference, and campaign; provide status webhooks.

Podium's invite API requires a location identifier and recipient; Birdeye supports integrations, SFTP, and REST API automation ([Podium](https://docs.podium.com/reference/review_invitecreate-1), [Birdeye](https://support.birdeye.com/en/articles/12653437-how-can-i-get-new-reviews-from-my-customers-using-birdeye)).

### 12. Platform-owner controls and abuse prevention

**Recommendation**

Because UpliftContractor is multi-tenant, add controls competitors' tenant-facing pages do not fully describe:

- global/country/destination feature flags, including selective-routing kill switch;
- per-tenant send caps, velocity limits, cooldown minimums, complaint/opt-out thresholds, and spend ceilings;
- campaign/template review state; block deceptive/incentivized or prohibited content;
- verified sender and connected-location ownership requirements;
- quarantine anomalous spikes and repeated failed destinations;
- immutable delivery, consent, content-version, and routing audit evidence;
- platform suppression list plus tenant suppression list;
- suspend campaign, channel, sender, tenant, or destination without deleting evidence;
- compliance dashboard and abuse escalation queue;
- data retention/deletion/export controls and least-privilege support access.

Google may restrict a Business Profile from receiving reviews, unpublish reviews, or display a warning after fake-engagement violations ([Google restrictions](https://support.google.com/business/answer/14114287)).

## Messaging and review compliance facts

These are product requirements, not optional polish:

- Twilio classifies messages sent through its services as application-to-person traffic. Before messaging, the sender must obtain recipient consent appropriate to the message subject; consent must be informed, unambiguous, specific to the sender/subject, provable, and revocable. The initial message must identify the sender and include a standard opt-out instruction; after opt-out, further messages are prohibited except one confirmation unless the recipient later re-consents ([Twilio Messaging Policy](https://www.twilio.com/en-us/legal/messaging-policy)).
- An inbound customer message permits a response in that conversation but does not create consent for ongoing recurring messages ([Twilio Messaging Policy](https://www.twilio.com/en-us/legal/messaging-policy)).
- Twilio's Consent Management API can store/synchronize opt-in, opt-out, and re-opt-in status and records STOP replies for Messaging Services ([Twilio Consent API](https://www.twilio.com/docs/messaging/features/consent-api)). UpliftContractor should still retain its own tenant-scoped consent evidence and event history.
- Twilio's US Compliance Toolkit documents quiet-hours protection for 9:00 PM–8:00 AM in the recipient's local time for non-essential traffic ([Twilio Compliance Toolkit](https://www.twilio.com/docs/messaging/features/compliance-toolkit)). Review solicitations should always be deferred during that window.
- Google allows soliciting genuine reviews without incentives, but prohibits incentives, discouraging negative reviews, and selectively soliciting positive reviews ([Google policy](https://support.google.com/business/answer/7400114)).
- The FTC's Consumer Review Rule prohibits fake reviews, sentiment-conditioned incentives, undisclosed insider practices in specified circumstances, deceptive company-controlled “independent” review sites, and review suppression. Review-management companies can themselves be liable ([FTC Q&A](https://www.ftc.gov/business-guidance/resources/consumer-reviews-testimonials-rule-questions-answers)).
- The FTC rule does not categorically ban a sentiment-neutral incentive, but disclosure may still be required and a destination may ban all incentives. Therefore **Recommendation:** do not support incentives in the product ([FTC Q&A](https://www.ftc.gov/business-guidance/resources/consumer-reviews-testimonials-rule-questions-answers), [Google policy](https://support.google.com/business/answer/7400114)).

SMS consent classification for a review request can depend on jurisdiction, copy, context, and carrier interpretation. **Recommendation:** treat review-request SMS as its own disclosed messaging subject in the opt-in language, retain evidence, and obtain legal review before launch rather than assuming ordinary job-notification consent covers it.

## Suggested product surfaces

**Recommendation**

1. **Reputation overview:** rating/review trend, request funnel, recent reviews, unresolved feedback, location comparison.
2. **Reviews inbox:** public reviews and response workflow.
3. **Private feedback/recovery:** cases, assignment, SLA, outcome.
4. **Campaigns:** trigger, audience/eligibility, journey, messages, destination, schedule, mode, activation checklist.
5. **Requests log:** every enrollment/message/link/review with reason and status.
6. **Profiles and destinations:** connected sites and per-location routing.
7. **Templates:** SMS/email with versions and test-send.
8. **Compliance and consent:** opt-in evidence, suppressions, quiet hours, sender registration/health.
9. **Organization controls:** permissions, defaults, location overrides, audit log.
10. **Platform console:** caps, enforcement, complaints, anomalies, suspensions, and selective-routing policy switch.

## Sensible release slicing (for the later scoping discussion)

This is not the final v1 decision; it shows dependency order.

- **Foundation:** consent/suppression, sender/delivery events, unique tracked links, queue/idempotency, audit.
- **First useful release:** one location, Google destination, job-completed trigger, one automatic sequence plus manual send, SMS/email, neutral equal-choice page with private feedback, stop rules, basic request log and recovery alert.
- **Operational expansion:** paid-invoice/visit triggers, campaign builder, bulk, review ingestion/matching/replies, role permissions, deeper reporting.
- **Growth/enterprise:** multiple locations, organization defaults, external API/webhooks/imports, additional review sites, advanced recovery, website/quote widgets, benchmarking/AI assistance, and platform abuse console.
- **Selective funnel:** can be introduced behind contractor and platform controls once the owner accepts the documented destination-policy risk and the audit/enforcement foundation exists.

Current mature-product evidence supports the first useful release above without requiring the complete reputation suite: Jobber and HighLevel both make a trigger, editable SMS/email request and reminders, stop behavior, manual sending, destination connection, and request visibility useful before advanced ingestion, AI responses, benchmarking, multi-location controls, or a dedicated reputation-only automation builder. The approved 50-step mixed-channel ceiling remains an UpliftContractor product requirement, not a reputation-industry norm established by these sources.

## Decisions required before v1 scope

1. Default funnel mode and whether selective routing ships at all in the first release.
2. Trigger default: job completed versus paid in full.
3. Consent capture experience and countries supported at launch.
4. One shared platform sending model versus tenant-owned sender configuration.
5. Whether public-review ingestion/replies are required for v1 or the first release only tracks requests/clicks/private feedback.
6. Whether one-off manual requests are available to fieldworkers or office roles only.
7. Initial cooldown and reminder defaults.
8. Whether the 50-step limit is organization-wide for every automation type or may be lowered for specific high-risk channels while preserving the editable workflow model.
