# HighLevel review-request behavior — official documentation check

**Researched:** 2026-09-25  
**Scope:** Current HighLevel help-centre documentation only. This note establishes what HighLevel documents; it does not approve, reject, or alter the owner's selected UCRM product direction.

## Short answer

HighLevel documents a configurable **direct-review-link** system: a request is sent by SMS, email, or (separately) WhatsApp; each channel can have an initial message plus a configured number of retries; that channel's repeat schedule stops when its review link is clicked. It records request activity and offers a dashboard/history.

HighLevel's published Review Requests material does **not** describe an intermediate customer page that asks for a star rating, routes 4–5 stars to Google, and collects 1–3 stars in a private form. Its similarly named **Review Balancing** feature is instead percentage-based distribution between connected public platforms such as Google and Facebook.

This distinction matters for planning accuracy: the owner's proposed rating page is a UCRM product decision inspired by the wider reputation-management category, not a confirmed copy of HighLevel's documented native review-request journey.

## Confirmed HighLevel behavior

### 1. Sending and retries

In **Reputation → Settings → SMS Requests** or **Email Requests**, a HighLevel user can:

- turn requests on;
- choose when the first message is sent after “check-in”;
- select the repeat interval, including a custom number of days;
- set maximum retries; and
- choose an initial (“Live”) template and a template for every retry slot.

HighLevel defines “after check-in” as the point where a request is triggered manually from a contact/Reputation → Requests, or automatically through a Workflow's Review Request action. The sender number/email is separately selected in the relevant settings. Its help article says most teams start with two or three retries, but does not make that a product-enforced maximum. [Customize Review Request Messages (SMS/Email)](https://help.gohighlevel.com/support/solutions/articles/48000980328-reputation-management-how-to-customize-the-review-request-messages-sms-email-)

**What stops by default:** the documented repeat schedule stops **for that channel** when HighLevel detects a click on its review link. The same article does not say that an SMS click ends an email sequence, or vice versa. [Customize Review Request Messages (SMS/Email)](https://help.gohighlevel.com/support/solutions/articles/48000980328-reputation-management-how-to-customize-the-review-request-messages-sms-email-)

**Not confirmed by this documentation:** an automatic stop after an email open, reply, delivery failure, submitted private feedback, or a Google review being posted. HighLevel workflows can separately use a `Review Request Clicked` goal event, filter it by channel or review link, and move/end a contact's workflow; that is workflow configuration, rather than evidence of a single built-in whole-campaign stop rule. [Goal Event Workflow Action](https://help.gohighlevel.com/support/solutions/articles/155000003328)

### 2. Manual and automated enrolment

HighLevel documents three ways to create a request:

1. **Quick Actions** — manual;
2. **Workflow Action** — automated, with the channel selected; and
3. **Reputation → Requests** — manual, individual request and request tracking.

The setup wizard also says a user can choose a contact *or enter recipient information manually* before sending SMS or email. [How to Send Review Requests](https://help.gohighlevel.com/support/solutions/articles/48001222668-how-to-send-review-requests), [Guided Review Setup Wizard](https://help.gohighlevel.com/support/solutions/articles/155000005201-guided-review-setup-wizard-reputation-management-)

HighLevel gives “Appointment Completed” as a workflow-trigger example, but its standard documentation does not define a contractor job-completion rule, recurring-visit frequency, client main-contact rule, or a UCRM-style job/client-page action placement. [Workflow Action — Review Request](https://help.gohighlevel.com/support/solutions/articles/155000003291)

### 3. What the recipient sees

The published standard is a **Review Link** inserted into the message. The contractor either:

- enables **Review Balancing** across connected platforms; or
- chooses **Custom Link** and pastes a single destination URL.

HighLevel says a custom link should open directly to the review form. Its SMS template uses the `{{reputation.review_link}}` token; its email builder has a Review Link element/CTA. [Customize Review Request Messages (SMS/Email)](https://help.gohighlevel.com/support/solutions/articles/48000980328-reputation-management-how-to-customize-the-review-request-messages-sms-email-)

No official HighLevel Review Requests article found in the current documentation describes:

- a HighLevel-hosted pre-review star screen;
- different public/private destinations selected from that rating;
- a private-feedback form tied to a review request;
- a customer thank-you screen after an external Google submission; or
- proof that a recipient posted a Google review after clicking.

The last point is especially important for activity language: the documented signal is a **review-link click**, not a verified Google review submission. HighLevel's own workflow example treats a click as an event that can begin a different path. [Goal Event Workflow Action](https://help.gohighlevel.com/support/solutions/articles/155000003328)

### 4. “Review Balancing” is not rating routing

HighLevel's **Review Request Balancing** distributes review-link traffic by a chosen percentage across public review platforms. With both connected, its documented starting ratio is 50% Google and 50% Facebook; the user can set another ratio such as 70/30. If only one platform is connected, requests redirect there. It requires the connected GBP/Facebook page and is configured at **Reputation → Settings → Review Link → Enable Review Balancing → Configure Balance**. [Review Request Balancing Across Platforms](https://help.gohighlevel.com/support/solutions/articles/155000004137-review-request-balancing-across-platforms)

HighLevel does classify *received* reviews in its reporting: 4–5 stars positive, 3 neutral, and 1–2 negative when there is no written text. The documentation describes this as analytics/sentiment, not the routing logic for outbound review requests. [Reputation Overview Dashboard](https://help.gohighlevel.com/support/solutions/articles/48001222767)

### 5. Tracking, status and notifications

HighLevel's multi-channel documentation says its tracking/reporting shows, per channel:

- sent requests;
- opened requests; and
- clicked review links.

It also says the channel can be selected from SMS, email, and WhatsApp, with a separate editable message for each. [Multi-Channel Review Requests](https://help.gohighlevel.com/support/solutions/articles/155000004803-multi-channel-review-requests)

Its established request-status documentation lists **Queued**, **Sent**, **Delivered**, and **Failed**. It specifically states that SMS delivery is Twilio-confirmed, while Mailgun does not provide the Delivered status there. [How to Send Review Requests](https://help.gohighlevel.com/support/solutions/articles/48001222668-how-to-send-review-requests)

The Reputation Overview documents outbound invite totals and a “Latest Review Requests” list with recipient, channel, and sent date. It only pulls public Google/Facebook reviews after those channels are integrated. [Reputation Overview Dashboard](https://help.gohighlevel.com/support/solutions/articles/48001222767)

**Gap:** the pages above establish activity tracking/history. They do not document an automatic contractor notification specifically when a recipient opens a message or clicks a review link, nor define exactly how “opened” is measured for every channel. A light UCRM “opened/clicked” activity event is comparable to HighLevel's reporting; an alert rule remains a UCRM planning choice.

### 6. Google Business Profile and no-connection setup

For an integrated Google review destination, HighLevel's current setup is:

1. **Settings → Integrations → Google Business Profile → Connect**;
2. sign in with a Google account that has **Owner or Manager** access;
3. select the verified GBP location; and
4. confirm the connection.

HighLevel says that connected reviews appear in Conversations in near real time and can be replied to there. A user can later disconnect the GBP. [Integrate Google Business Profile with HighLevel CRM](https://help.gohighlevel.com/support/solutions/articles/48001222899)

For review balancing, HighLevel says an unintegrated GBP/Facebook page cannot be configured as a distribution destination. Its general review-request page says Google review links require GMB integration, while it also refers to using a third-party review link as an alternative. [Review Request Balancing Across Platforms](https://help.gohighlevel.com/support/solutions/articles/155000004137-review-request-balancing-across-platforms), [How to Send Review Requests](https://help.gohighlevel.com/support/solutions/articles/48001222668-how-to-send-review-requests)

The owner brief's “paste a Google review link now; defer review import/replies until a later connection” is therefore **not HighLevel's documented connected-GBP route**, but it does match the documented concept of a custom, direct review-link destination. HighLevel's docs do not explain a no-API manual Google-link onboarding flow in enough detail to copy its exact UI.

## Direct comparison with the owner brief

| Owner brief behavior | What official HighLevel docs confirm | Planning status from this research |
| --- | --- | --- |
| SMS-first request with editable copy, timing and reminders | SMS has editable templates, first-send timing, cadence and retry count. | Directly supported as a mature-product pattern. |
| A small activity view showing who opened/clicked | Sent/opened/clicked tracking is documented; Queued/Sent/Delivered/Failed status is also documented. | Directly supported as a light tracking pattern. “Clicked” is not a verified Google review. |
| Stop reminders after the link is opened | Retry stops after a detected review-link click **for that channel**. | Supported for the same channel. Cross-channel/whole-campaign stopping needs an explicit UCRM rule. |
| Manual request in addition to automatic completed-job request | Manual sending and workflow automation are documented. | Directly supported at the capability level; exact UCRM job/client placement is our decision. |
| Contractor sets Google link before one-click connection exists | HighLevel supports custom direct links, but documents GBP integration for Google destinations/connected reviews. | The manual no-connection setup is a UCRM decision; no exact HighLevel onboarding behavior is documented. |
| 4–5 stars go to Google; 1–3 stars go to a private form | No HighLevel official documentation found for this rating screen, routing, or private-feedback form. HighLevel's “balancing” is public-platform percentage distribution, not rating routing. | Additional UCRM behavior, not confirmed HighLevel behavior. |
| After 4–5 stars, send customer straight to Google with no thank-you page | HighLevel documents a direct review-link destination. | Directionally similar; documentation does not show HighLevel's exact recipient screen sequence. |
| Private low-rating recovery alert/work item | HighLevel documents reacting to public negative reviews and sentiment analytics, but not a private-feedback submission path from Review Requests. | Additional UCRM behavior; detailed handling is still to be planned. |

## Source list

- [Customize Review Request Messages (SMS/Email)](https://help.gohighlevel.com/support/solutions/articles/48000980328-reputation-management-how-to-customize-the-review-request-messages-sms-email-)
- [How to Send Review Requests](https://help.gohighlevel.com/support/solutions/articles/48001222668-how-to-send-review-requests)
- [Workflow Action — Review Request](https://help.gohighlevel.com/support/solutions/articles/155000003291)
- [Goal Event Workflow Action](https://help.gohighlevel.com/support/solutions/articles/155000003328)
- [Multi-Channel Review Requests](https://help.gohighlevel.com/support/solutions/articles/155000004803-multi-channel-review-requests)
- [Review Request Balancing Across Platforms](https://help.gohighlevel.com/support/solutions/articles/155000004137-review-request-balancing-across-platforms)
- [Reputation Overview Dashboard](https://help.gohighlevel.com/support/solutions/articles/48001222767)
- [Guided Review Setup Wizard](https://help.gohighlevel.com/support/solutions/articles/155000005201-guided-review-setup-wizard-reputation-management-)
- [Integrate Google Business Profile with HighLevel CRM](https://help.gohighlevel.com/support/solutions/articles/48001222899)
