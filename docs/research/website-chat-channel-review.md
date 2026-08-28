# Website Chat Channel Review

Research date: 2026-08-26  
Status: Product-decision input; not approved behavior or implementation scope  
Scope: Current first-party HighLevel, Intercom, and Zendesk behavior relevant to UCRM's proposed
website-chat channel. This note reviews product behavior and staged scope only. It does not define UI or
implementation architecture.

## Executive recommendation

Jafar's direction is sound, but the product should be framed as a **persistent website messenger with live
human help and later AI**, not simply a “live chat widget.” That distinction matters for contractor teams:
many conversations will begin while a technician or owner is busy, continue after the visitor leaves the
site, and sometimes switch between AI and a person.

The polished product promise should be:

> A visitor identifies themselves once, starts a durable conversation with the contractor, gets an immediate
> AI answer when AI is enabled, and can ask for a person at any time. If a person is available, the same thread
> becomes live; otherwise the visitor gets an honest reply expectation and can return later or receive an
> approved follow-up. Photos and documents remain part of the conversation.

This combines HighLevel's CRM lead-capture model with Intercom/Zendesk's persistent-messaging model. It avoids
the main weakness of traditional live chat: pretending the business is instantly available and losing the
visitor when it is not.

## What the leading products establish

### 1. Identity can be required before the composer unlocks

HighLevel now supports an optional pre-chat contact form for Live Chat. When enabled, visitors must submit it
before the message box unlocks. Its minimum identity rule is name plus at least one of phone or email. An active
returning visitor skips the form and resumes; refresh auto-reconnects without losing messages; an ended or
expired chat shows the form again. ([HighLevel: Collect Visitor Details Before Live Chat Starts](https://help.gohighlevel.com/support/solutions/articles/155000005415-collect-visitor-details-before-live-chat-starts))

HighLevel also allows up to five standard/custom fields, with required-field validation. This proves that a
configurable intake is common, but not that asking five questions is a good default. ([HighLevel: Add Custom
Fields to Chat Widget Contact Form](https://help.gohighlevel.com/support/solutions/articles/155000004356-adding-custom-fields-in-the-chat-widget-contact-form))

**UCRM adaptation:** Require **first name plus one reply method** before the first message. Default to phone or
email rather than requiring both. Do not put service type, full property address, budget, job details, and
marketing questions in the opening gate; AI or a human can collect them conversationally when relevant. Show a
privacy link beside the form. If SMS follow-up is offered, make its consent separate and explicit rather than
treating phone entry as marketing consent.

### 2. Modern messaging is continuous and asynchronous, even when a live exchange is possible

Zendesk describes its current messaging widget as supporting persistent and continuous conversations, past
interaction history, live-agent involvement, and email notifications when an agent replies. Its “Remember
history” setting restores full conversation text when the visitor returns unless browser storage was cleared.
([Zendesk: Comparing the Web Widgets](https://support.zendesk.com/hc/en-us/articles/4429429087002-Comparing-the-Zendesk-Web-Widgets),
[Zendesk: Viewing and configuring Web Widget settings](https://support.zendesk.com/hc/en-us/articles/7178617945498-Viewing-and-configuring-Web-Widget-settings))

Intercom uses a first-party anonymous visitor identifier and a session identifier that gives the visitor access
to previous conversations. It also distinguishes visitors, leads, and identified users; conversations remain
with a lead when that lead later becomes a user. ([Intercom: Messenger Cookies](https://www.intercom.com/help/en/articles/2361922-intercom-messenger-cookies),
[Intercom: How visitors, leads and users work](https://www.intercom.com/help/en/articles/310-how-do-visitors-leads-and-users-work-in-intercom))

**UCRM adaptation:** Make the visible experience Messenger/WhatsApp-like, but retain explicit sessions beneath
it. A visitor has at most one active website-chat session per widget/business. Refreshing, navigating the site,
or returning on the same recognized browser restores it. Ending a resolved session preserves it as history; a
later new need starts a new session linked to the same contact instead of extending one endless operational
thread. An identified visitor should be able to recover continuity across devices through a secure link or
verification flow later; a browser cookie alone must not grant access to sensitive history indefinitely.

### 3. Availability must set expectations; it must not make a false “online” promise

HighLevel supports business hours, outside-hours wording, assignment, inactivity messages, and manual or
automatic chat ending. Its outside-hours behavior collects contact details and then automatically closes the
chat. ([HighLevel: Business Office Hours in Live Chat](https://help.gohighlevel.com/support/solutions/articles/155000004104-chat-widget-business-office-hours-in-live-chat),
[HighLevel: Web Chat inside Conversations](https://help.gohighlevel.com/support/solutions/articles/155000007355-web-chat-inside-conversations))

Intercom goes further by showing office hours and a configured or dynamically calculated expected reply time;
its current Messenger can also show who is handling the conversation and visibly mark a Fin-to-teammate
handover. ([Intercom: Set your default office hours](https://www.intercom.com/help/en/articles/732390-set-your-default-office-hours),
[Intercom: Share your expected response time](https://www.intercom.com/help/en/articles/732436-share-your-expected-response-time),
[Intercom: Updates to the Messenger](https://www.intercom.com/help/en/articles/9319961-updates-to-the-messenger))

**UCRM adaptation:** Separate three states:

1. **Available now** — at least one eligible teammate is actually accepting website chat; show a truthful short
   expectation such as “Usually replies in a few minutes.”
2. **Business hours, nobody free** — keep messaging open, queue/assign the conversation, and show an honest
   delayed expectation.
3. **Outside hours** — keep the same persistent conversation open, state when the business returns, and offer
   follow-up by the visitor's approved reply method.

Do not copy HighLevel's automatic close immediately after an outside-hours form. That contradicts the durable
messenger promise. Also do not show an “online” dot based only on office hours; office hours do not prove a human
is watching the inbox.

### 4. AI-to-human transfer must be explicit and preserve context

HighLevel's Human Handover can trigger when the visitor requests a person, the AI lacks information, or repeated
attempts fail; the handover can assign a user, create a task, notify staff, send a final AI message, and pause the
bot. ([HighLevel: Conversation AI Human Handover](https://help.gohighlevel.com/support/solutions/articles/155000005615-conversation-ai-human-handover-action))

Intercom clearly labels whether Fin, a workflow bot, or a teammate is responding and announces when a teammate
joins. Its deployment settings let teams define escalation guidance and collect more context before handover.
([Intercom: Updates to the Messenger](https://www.intercom.com/help/en/articles/9319961-updates-to-the-messenger),
[Intercom: Deploy Fin AI Agent over chat](https://www.intercom.com/help/en/articles/8286630-deploy-fin-ai-agent-over-chat))

Zendesk recommends designing the transfer deliberately, including additional intake, estimated waits, and a
notification method; the agent receives the conversation history and collected fields. ([Zendesk: Designing
your conversational messaging workflow](https://support.zendesk.com/hc/en-us/articles/5746068733338-Designing-your-conversational-messaging-workflow),
[Zendesk: AI agent answer step types](https://support.zendesk.com/hc/en-us/articles/4408836323738-Understanding-the-step-types-for-AI-agent-answers-Legacy))

**UCRM adaptation:** AI must introduce itself as AI, and “Talk to a person” must remain available throughout the
conversation. Handoff should occur on explicit request, low confidence/no approved answer, repeated failure,
frustration, safety or emergency language, complaints, unusual estimate conditions, or any action requiring
human judgment. The thread must show a visible handoff event. Once handed over, the AI stops replying until the
human returns control or a defined fallback occurs. The teammate receives an AI summary plus the original
transcript and captured facts; the summary never replaces the transcript.

### 5. AI knowledge and estimates need different trust boundaries

HighLevel positions Conversation AI for Q&A, lead capture, appointment handling, and human handoff, with both
Suggestive mode (a human reviews drafts) and Auto-Pilot. It explicitly recommends testing FAQs, lead capture,
booking, unknown questions, and workflows before Auto-Pilot. ([HighLevel: Set Up a Conversation AI Bot](https://help.gohighlevel.com/support/solutions/articles/155000004401-setting-up-conversation-ai))

Intercom supports grounding by approved content, guidance, audience, and external data connectors, and provides
previews for validating answers before launch. ([Intercom: Deploy Fin AI Agent over chat](https://www.intercom.com/help/en/articles/8286630-deploy-fin-ai-agent-over-chat),
[Intercom: Use Fin previews](https://www.intercom.com/help/en/articles/12599471-use-fin-previews))

**UCRM adaptation:** Treat business facts and estimate calculations as separate capabilities.

- AI may answer from contractor-approved knowledge: services, service areas, hours, process, warranties,
  financing availability, common preparation questions, and non-sensitive policy.
- AI may collect estimate inputs conversationally: service, property location, measurements, urgency, photos,
  and constraints.
- AI may present a **non-binding range** only when it comes from a contractor-configured deterministic pricing
  rule or approved range. It should show the assumptions and say what could change the price.
- AI must not invent a price from general knowledge, present a generated number as a quote, promise a schedule,
  waive terms, approve credit, or make a binding commitment. When no safe rule applies, it should say that a
  person must review the details and create an estimate/request.

The safe progression is internal suggested replies first, then customer-facing AI for approved Q&A and lead
qualification, and only later controlled estimate/booking actions. “AI that knows the website owner's business”
should mean curated, versioned business knowledge—not unrestricted website scraping at answer time.

### 6. Attachments are core for contractor conversations, but the first scope should stay narrow

HighLevel's current Live Chat supports attachment-only messages, up to five files at 25 MB each, with JPG/JPEG,
PNG, HEIC, and PDF among its documented image/document types; it also supports audio and voice notes.
([HighLevel: Voice Notes and Attachments in Live Chat](https://help.gohighlevel.com/support/solutions/articles/155000006664-chat-widget-using-file-attachments-in-live-chat))

Intercom supports multiple files, captions, previews, and attachment controls. It virus-scans uploads,
quarantines detected malware, and uses short-lived signed access URLs for Messenger/chat uploads.
([Intercom: Sharing files and images in the Messenger](https://www.intercom.com/help/en/articles/12130647-sharing-files-and-images-in-the-messenger),
[Intercom: Control how attachments are uploaded and used](https://www.intercom.com/help/en/articles/2339426-control-how-attachments-are-uploaded-and-used))

Zendesk now malware-scans end-user and agent messaging attachments before delivery/download and blocks
suspicious files pending authorized review. ([Zendesk: Malware scanning for messaging channels](https://support.zendesk.com/hc/en-us/articles/10561175103514-Announcing-malware-scanning-for-messaging-channels))

**UCRM adaptation:** Photos and PDFs are launch-level requirements because contractors need damage photos,
site conditions, plans, and documents. Support inbound and outbound JPG/JPEG, PNG, HEIC, WEBP, and PDF with
preview/progress/failure states and attachment-only messages. Every file must be type/size checked, malware
scanned, private, and served through expiring access. Defer video, archives, arbitrary office formats, and voice
notes until storage cost, moderation, mobile behavior, accessibility, and AI-processing rules are settled.

### 7. Platform entitlement and contractor operation are different controls

Intercom separates feature access and usage from day-to-day channel configuration. Its current pricing states
that some messaging and AI usage is usage-based; its conversation add-on supports usage reporting, threshold
alerts, and a hard cap. Fin separately supports stopping customer-facing AI answers when a defined usage limit is
reached. ([Intercom: Pricing FAQs](https://www.intercom.com/help/en/articles/8344190-pricing-faqs),
[Intercom: Pro add-on usage and hard caps](https://www.intercom.com/help/en/articles/13868265-pro-add-on),
[Intercom: Fin AI Agent explained](https://www.intercom.com/help/en/articles/7120684-fin-ai-agent-explained))

**Industry implication:** UCRM needs two control planes, with platform entitlement acting as the ceiling:

| Control owner | Controls | Must not control |
| --- | --- | --- |
| `/jafar` platform admin | Whether Website Chat is entitled for an organization; monthly allowance and reset; temporary platform suspension; plan/override; usage visibility; later, a separate AI entitlement/allowance | The contractor's welcome copy, hours, staffing, routing, knowledge, estimate rules, or choice to publish a widget |
| Contractor organization | Enable/disable Website Chat within its entitlement; publish/unpublish each widget; allowed domains; branding; intake fields; hours; teammate availability/routing; attachments; later AI on/off and approved knowledge | Raising its platform allowance, bypassing suspension, or enabling a feature the organization is not entitled to use |

The effective public state is therefore **platform entitled and not suspended AND organization enabled AND
widget published on an allowed domain**. The settings UI should explain which layer is preventing use instead of
showing a generic failure.

For a predictable initial allowance, count **new visitor-initiated website-chat conversations accepted in the
billing period**, not individual messages. Count once when the identified visitor sends the first message;
abandoned identity forms, blocked spam, internal notes, retries, and additional messages in the same active
session do not consume another unit. This follows Intercom's broad conversation-based usage pattern and avoids
punishing a visitor for supplying the photos or detail needed to solve a contractor request. Exact pricing and
allowance quantities remain a platform decision.

At the warning threshold, notify the organization owner/admin in-product. At the hard cap, preserve transcripts
and allow staff to finish already accepted conversations, but do not accept a new Website Chat conversation
until reset or a `/jafar` override. The visitor should see an honest branded fallback contact path, not an error
or an apparently working composer. A platform suspension may be stricter for abuse/security, but it must retain
history and show staff the reason.

Keep later **AI usage separate** from the human Website Chat allowance. Industry AI products meter AI outcomes
or conversations independently, and their limits can stop AI while leaving human support available. Combining
the two would make the channel disappear when only the variable-cost AI capability is exhausted. When an AI
allowance is reached, AI should stop accepting new turns and offer human/async continuation in the same thread.

## Copy, adapt, defer, or reject

### Copy

- HighLevel's optional per-widget pre-chat identity gate and active-session resume behavior.
- Intercom's visible AI/bot/human identities and explicit handoff marker.
- Intercom's honest office-hours/reply-expectation language.
- Zendesk's persistent messaging/history model and “leave now, hear back later” behavior.
- HighLevel's single inbox routing and assignment for website messages.
- The shared industry rule that handoff includes transcript and collected context.
- Malware scanning, private attachments, upload progress, previews, and visible failures.

### Adapt for contractor CRM

- Create or match a **Lead/contact** after the identity form, preserving source widget, landing page, referral
  data, current page, and service intent. Do not create duplicate people on every session.
- Add contractor context during conversation rather than at the front door: property, service address,
  request, photos, desired timing, and quote/estimate state.
- Show human availability only from real channel availability/capacity, with office hours as a fallback signal.
- Keep one active session but preserve resolved sessions separately under the same contact and work context.
- Let AI qualify and collect estimate inputs, but calculate only from approved pricing rules and make the
  difference between a rough range, an estimate, and an accepted quote unmistakable.
- Offer reply notifications by email or SMS only with the correct address/number and applicable consent.
- Give `/jafar` platform-level entitlement, allowance, suspension, and override controls while leaving widget
  operation and customer-experience configuration with the contractor organization.
- Meter accepted new conversations rather than raw messages; treat later AI allowance as a separate meter.

### Defer

- Customer-facing AI Auto-Pilot until human-only chat produces a stable conversation model and knowledge set.
- AI-created estimate ranges until deterministic pricing sources, assumptions, approval, and audit behavior are
  defined.
- Appointment booking, request/estimate creation, payments, and other AI actions.
- Cross-device history recovery, WhatsApp/Messenger channel continuation, and multiple simultaneous topics.
- Embedded/inline placement; launch the ordinary corner launcher first unless the approved UI blueprint says
  otherwise.
- Proactive popups, behavior-triggered outreach, multilingual AI, voice notes, video, screen sharing, co-browse,
  queue-position numbers, CSAT, and team SLAs.

### Reject for the initial product

- A mandatory long lead form before the visitor can ask anything.
- Requiring both phone and email.
- Calling the business “online” merely because it is within office hours.
- Closing and discarding the visitor experience when a teammate is unavailable.
- An AI persona that hides that it is AI or makes human presence ambiguous.
- AI-generated prices without an approved deterministic source, or language that makes a range look like a
  contractual quote.
- Letting AI continue to answer after a human handoff.
- Public/permanent attachment URLs, unscanned uploads, or unrestricted file types.
- A single never-ending database thread that mixes unrelated future service requests even if the widget feels
  continuous to the visitor.
- HighLevel's broad all-in-one launcher at launch; UCRM should first make its owned Website Chat excellent.
- Letting a contractor-side toggle bypass `/jafar` entitlement/suspension, or letting platform staff silently
  rewrite contractor messaging and operating choices.
- Cutting off an already accepted customer conversation merely because the organization reaches its allowance
  mid-thread.

## Recommended staged product scope

### Stage 1 — Human website messenger

This is the foundation and should ship before customer-facing AI:

- Floating, branded website widget with per-widget install script and allowed-domain control.
- `/jafar` organization entitlement, monthly accepted-conversation allowance, warnings, hard-cap/override, and
  platform suspension; contractor organization and per-widget enable/publish controls.
- Pre-chat form: first name plus phone or email; privacy notice; separate optional follow-up consent where
  required.
- Contact matching/lead creation, source/page attribution, and duplicate-safe re-entry.
- One active session, durable transcript, refresh/navigation recovery, ended-session history, and clear “new
  conversation” behavior.
- Real-time messages when both sides are present plus async continuation when they are not.
- Honest available/busy/outside-hours states and reply expectation.
- Conversations inbox routing, assignment, unread/notification behavior, manual end/reopen rules, and visible
  delivery/failure states.
- Visitor and teammate photo/PDF attachments with secure processing.
- Abuse controls, rate limiting, file scanning, data retention, and a tested uninstall/disable state.

### Stage 2A — AI assist for staff

- Approved business knowledge set with ownership, freshness, and preview/testing.
- Suggested replies and conversation summaries visible only to teammates.
- Feedback/correction loop and answer-gap reporting.
- No autonomous customer replies or CRM actions.

### Stage 2B — Customer-facing AI concierge

- Clearly disclosed AI identity and persistent “Talk to a person” action.
- Approved Q&A, service-area checks, lead qualification, and photo/context collection.
- Explicit handoff triggers, transcript/summary transfer, and AI pause after handoff.
- Availability-aware fallback when no human can accept immediately.
- Conservative unknown-answer behavior: admit the limit and hand off rather than improvise.

### Stage 3 — Controlled contractor actions

- Deterministic, non-binding estimate ranges with visible assumptions and contractor configuration.
- Appointment/assessment booking against real availability.
- Draft Request/Estimate creation from collected facts, with human review before anything binding or customer-
  facing is finalized.
- Later expansion to approved channel continuation (for example SMS or WhatsApp) without losing the unified
  UCRM transcript.

## Product questions that remain for approval

1. Is the required reply method visitor choice between phone and email, or should phone be the default while
   email remains available?
2. Should a submitted identity form immediately create a Lead, or only after the visitor sends the first
   message? Recommendation: create/match only when the first message is sent, so abandoned forms do not pollute
   the CRM.
3. What exact signal makes a human “available now”: manual availability, open app presence, assigned shift, or
   a combination? Recommendation: explicit channel availability plus capacity, not passive login presence.
4. How should an identified visitor recover conversation history on another device? This can be deferred, but
   the launch copy must not promise cross-device continuity without it.
5. Which estimate categories can ever be safely rule-based, and which always require site review? This must be
   contractor-configurable and settled before Stage 3.
6. Should closed website-chat sessions be visible to the visitor as a list, or should launch show only the
   current/most recent session while staff retain the full history? Recommendation: current/most recent at
   launch; add a history list only when multiple-session behavior is proven.
7. What are the launch allowance quantities and warning thresholds? Recommendation: define the unit now as one
   accepted new visitor conversation, then set quantities with packaging rather than embedding them in the
   Website Chat behavior contract.

## Bottom line

Keep the ambition, but sequence it. The durable human messenger is the product; AI is a later participant in
that same channel. Identity-first fits the CRM goal when the form stays small. Live human support is a mode of
the conversation, not a promise that every message is synchronous. Contractor-specific strength comes from
preserving property/work context and handling estimate boundaries safely—not from copying every Intercom or
HighLevel option.
