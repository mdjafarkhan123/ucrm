# Client onboarding and delivery — behavior contract

**Status:** Approved by Jafar on 2026-10-01

## Summary

UpliftContractor wins clients through outbound outreach, then sends them to a three-to-five-minute
presentation video. A contractor may book a call or buy a package directly. Buying asks for only the
details needed to identify the business, contact the buyer, choose the package, and arrange payment.
The first release uses an offsite Payoneer business payment; Jafar confirms received funds before an
account is created. Stripe may later replace that payment step without changing the surrounding journey.

After payment, the contractor signs in to a complete CRM and uses a separate, protected setup wizard to
provide the facts and access Uplift needs to configure their purchased services. The wizard never hides or
locks the CRM. It asks each fact once, reuses accepted answers across the CRM, website, Google Business
Profile, communications, and marketing, and lets the contractor ask Uplift for help. Jafar reviews the
submission before marking it **Ready for Uplift**; only then does the promised 7–10 business-day build window
begin. The client later reviews the result, approves launch, receives training and a handover pack, and can
contact Uplift from a persistent support messenger throughout.

This contract is the source of truth for the client setup and delivery journey. The commercial application,
payment ledger, package agreement, provisioning safety, and renewal rules remain owned by
`docs/package-builder-behavior-contract.md`, ADR 0001, and ADR 0003. Where the older
`docs/jafar-onboarding-implementation-contract.md` describes a small post-provisioning checklist or an earlier
package/payment model, this contract and the newer package contract win.

## Language and boundaries

- **Purchase start** is the short public `/get-started` journey. It is not client onboarding.
- **Client setup** is the protected, multi-session wizard completed after confirmed payment.
- **Ready for Uplift** means Uplift accepted the essential brief and the build window can begin.
- **External wait** means Google, a telecom carrier, a registrar, or another provider is reviewing or waiting
  for something outside Uplift's control. It is shown separately from Uplift's build time.
- **Project delivered** means the approved system is live, training is completed or scheduled, and the
  handover pack is available.
- **Uplift Support Messenger** is contractor-to-Uplift support. It is separate from Website Chat, which is
  contractor-to-customer messaging.

“Building the system” means configuring the contractor's website, brand, Google presence, communications,
imports, automations, and CRM defaults. The CRM product itself is complete before launch; client setup never
means finishing the CRM for that customer.

## 1. Sales, purchase, and payment

The intended path is:

1. Uplift contacts a potential client through outbound outreach.
2. The client watches a three-to-five-minute, outcome-led presentation video.
3. The client books a call or buys directly.
4. `/get-started` collects the selected package and billing interval, business name, main contact name/email/
   phone, initial administrator identity when different, trade, general location/time zone, privacy agreement,
   and an optional note.
5. Submission creates a platform-owned application and no contractor organization or login.
6. Jafar sends an offsite Payoneer Payment Link or Request a Payment.
7. The client sees an honest payment state while Jafar verifies that funds reached Uplift.
8. One confirmed owner action provisions the organization and sends the administrator a secure password-setup
   link. Jafar never handles the password.

Commercial states are separate from setup and delivery states: awaiting payment, payment under verification,
paid, unsuccessful/cancelled, reversed/refunded. “Paid” means Jafar verified received funds; a client return
page, screenshot, or claim is not proof.

Payoneer is the only active payment method at first. Payment concepts and records stay provider-neutral so a
future Stripe-hosted checkout can become the active mode. No inactive Stripe control or simulated checkout is
shown before that work is approved and built.

## 2. First login and continuing access

The administrator's first authenticated visit shows **Set up your Uplift system** and explains:

- what Uplift will configure;
- what is useful to have nearby;
- that answers save automatically and can be resumed;
- that plain facts are enough because Uplift writes polished copy;
- that the complete CRM is already available; and
- how to ask Uplift for help.

The welcome may recommend starting setup, but it never traps the user. On later visits, a prominent dashboard
card shows progress, the next useful action, and the current delivery status. The normal CRM navigation remains
available at all times for an active account.

The wizard is a task list, not one long form. It is mobile-friendly and usable across several sessions. Each
suitable item offers **I have this**, **I don't have this yet**, and **I need Uplift's help**. Help is a valid
answer that creates an Uplift task. Only genuinely essential facts prevent Ready for Uplift.

The package edition decides which tasks appear. A contractor is never questioned about a feature they did not
buy. Common identity facts are collected once and reused in every purchased branch.

## 3. Setup tasks and exact information

### 3.1 Your business — required once

Collect:

- public business name exactly as used with customers, plus legal name when different;
- trade and business type;
- registration country and registration/tax/company number only where a provider requires it;
- main contact and final approver; a different final approver may be named;
- public phone and email;
- private operating address, whether customers visit it, and whether it may be public;
- country, preferred language, time zone, and currency;
- normal weekly hours plus appointment-only, 24-hour, seasonal, and holiday exceptions; and
- opening date, licences, or other identity facts only when relevant.

Accepted values populate the matching CRM business profile, formatting, hours, branding, and notification
defaults. The contractor confirms time zone and currency before either becomes a business default.

### 3.2 Services and service area — required

Collect the main service, additional services, work not offered, residential/commercial/both, emergency or
after-hours availability, minimum or starting price only when the contractor wants it public, applicable
licences/certifications/warranties, and the three-to-five services they most want to promote.

Collect the base city, real cities/postcodes/regions served, maximum travel radius or time, excluded areas, and
separate staffed locations only when they actually exist. Ask which locations deserve priority pages. Uplift
turns these facts into service and location copy; the contractor is not asked for SEO keywords or finished
marketing writing.

### 3.3 Brand, proof, and assets

Ask for a logo, preferred colors/fonts, real project/team/vehicle/storefront photos, project captions, awards,
accreditations, social links, testimonials and their sources, years operating, guarantees, financing/payment
methods, and factual reasons customers choose the business.

Logo and media branches are **upload it**, **I do not have it**, or **I need Uplift's help**. Missing branding
does not block a build when the package includes Uplift-created starter branding or approved imagery. The
contractor confirms they own or may publish every supplied asset and identifies any customer or photographer
restriction.

### 3.4 Website and domain — when included

The domain branch is **I own one**, **someone else controls it**, **I need a new one**, or **not sure**. For an
existing domain, collect the name, registrar/provider, owner email, current website, and whether business email
depends on it. For a new domain, collect two or three preferences; Uplift checks availability and obtains client
approval rather than promising a name.

Collect the primary call to action, public contact details, form-notification recipients, business origin,
service process, evidence-backed differentiators, guarantees, licences/insurance statements, existing content
that must be kept, social links, and legal disclaimers. Preference examples or admired websites are optional.

The contractor owns the domain. Uplift uses delegated access, exact DNS instructions, or supervised setup. The
wizard never requests a registrar, email, hosting, Google, or social password. Publishing requires a separately
recorded approval.

### 3.5 Google Business Profile — when included

Start with **already have one**, **someone else controls it**, **need a new one**, or **not sure**. Collect the
profile/Maps link when known, storefront/service-area/hybrid choice, exact public name, primary and secondary
categories, private verification address, address visibility, service areas, phone, hours, website, opening
date, profile history, previous suspension or duplicate concerns, and suitable photos.

The contractor remains primary owner and invites Uplift as manager. Google passwords are never collected and
Uplift is not made owner by default. Ownership requests, postcard/phone/email/video verification, reinstatement,
and Google's review time are external waits. The product promises accurate setup and management, not ranking or
approval.

### 3.6 Calls, missed-call text-back, and SMS — when included

Present only choices available in the contractor's country: new Uplift number, forward an existing number,
host messaging on an eligible existing number, or port a number. Collect phones to ring, order or simultaneous
ringing, no-answer delay, busy/after-hours behavior, business hours and quiet hours, voicemail choice, reply
recipients, backup person, languages, missed-call acknowledgement, and test-call approval.

Before messaging activation, collect the provider's required business facts in everyday language: legal name,
entity type, registration number when applicable, full address, working website, operating region, authorized
representative details, authority confirmation, texting purpose, recipient type, opt-in method and wording,
evidence location, two-to-five realistic samples, estimated volume, URLs/numbers used in messages, privacy and
messaging-terms URLs, and STOP/HELP acknowledgement.

Porting or hosting additionally requests the current number/carrier, account identity, recent proof, any required
PIN/OTP, and authorized signer/letter. Sensitive provider documents use protected uploads. Approval, porting,
and carrier timing are external waits. SMS remains off until registration, sender, consent, and routing are
ready; no delivery guarantee is made.

### 3.7 Reviews and private feedback — when included

Collect or retrieve the Google review link, display name/logo, private-feedback recipients, message tone,
email/SMS channel, send timing after completed work, reminder limit, quiet hours, and eligible historical
customers when requested.

The system neutrally asks genuine customers for an honest review. It may offer every customer a separate private
feedback route, but it never hides the Google option based on sentiment, asks only happy customers, buys reviews,
or offers review incentives. Historical contacts require the contractor to confirm a real customer relationship
and lawful messaging basis.

### 3.8 CRM defaults and imports

Reuse business identity, hours, time zone, currency, logo, and brand color. Ask in scenarios rather than CRM
jargon about the normal path from enquiry to quote/job, whether requests usually need an assessment, inquiry
recipients and initial owner, quote terms/signature preference, invoice terms, tax approach, accepted payment
methods/instructions, and optional team members.

Optional assisted imports include customers/properties, services and price-book items, and opening balances.
Standard clean spreadsheets are included. Uplift maps columns, shows validation results and counts, asks how to
handle likely duplicates, and obtains approval before commit. Very large, handwritten, damaged, or cleanup-heavy
data receives a separate review. A new business can skip imports without being trapped.

### 3.9 Marketing — when included

Collect the campaign goal, target service/area, audience and exclusions, offer and precise terms/expiry/capacity,
channel, timing, frequency/reminder limit, quiet hours, sender identity, reply owner, tone, and call to action.
For every audience source, collect the country/region, lawful consent basis and evidence, and existing opt-outs or
suppression list.

Setup may prepare draft campaigns. Nothing is sent merely because onboarding was submitted. Each campaign needs
its own preview/test and explicit **Approve and schedule/send** action. Regional rules are applied from recipient
location rather than one assumed global rule.

### 3.10 Check and send to Uplift — required

Show one plain-language summary with section edit links, skipped/help-needed labels, outstanding access tasks,
and separate confirmations that:

- information is accurate;
- supplied content, photos, testimonials, and data may be used;
- Uplift may build and publish after final approval and make approved DNS changes;
- the contractor stays Google owner while Uplift manages the profile;
- Uplift may submit truthful phone/SMS registration and configure approved routing;
- Uplift may import the separately previewed data; and
- campaigns still require a later send approval.

Record approver, time, wording/version, and answer snapshot. **Send to Uplift** freezes the submitted brief;
later material changes are tracked rather than silently rewriting history.

## 4. Uplift review and Ready for Uplift

After submission, Jafar reviews by section. He may accept it, ask a contextual question, return only that section,
mark an access/provider task pending, or accept the project as Ready for Uplift. The contractor answers in the
returned section and never repeats the whole wizard. **Ask Uplift** from any section starts a new support
chat about that section, with the section attached as context.

Keep the client's original answer, any later answer, and the final accepted value. Accepted facts may then seed or
update matching CRM settings. Repeating a safe provisioning/configuration operation must not duplicate records or
messages. Material owner changes are visible in history.

Ready for Uplift requires the essential business/service facts, required approvals, and enough access or an agreed
alternative to perform Uplift's work. Optional assets, optional imports, deferred features, and provider decisions
that can progress independently do not block it. The review screen states every actual blocker.

## 5. Delivery promise, statuses, and reminders

The 7–10 business-day window starts at the recorded Ready for Uplift time, not application, payment, first login,
or partial submission. The client sees the start date and target range. A later major client-directed scope change
may revise the target; Uplift records and shows the reason instead of silently moving it.

Client-facing project states are:

1. Payment required
2. Payment being verified
3. Complete your setup
4. Uplift is reviewing
5. Waiting for your information
6. Ready for Uplift
7. Building your system
8. Ready for your review
9. Approved — preparing launch
10. Live — training next
11. Project delivered

External provider state is an independent badge/timeline such as waiting for client access, submitted, under
provider review, action needed, approved, or unavailable. A provider wait never makes the whole project look as if
Uplift is working or late.

Incomplete-setup email reminders are sent around 24 hours, 3 days, and 7 days after inactivity and link to the
exact unfinished task. They stop after submission, opt-out where applicable, or a human deferral. SMS onboarding
reminders remain off until lawful consent and sender readiness exist.

## 6. Preview, approval, launch, and training

The client receives an organized preview of business facts, services/areas, website pages, forms and lead routing,
phone/text behavior, Google facts, CRM defaults, and import counts relevant to the package. The package includes one
organized factual-correction round; Uplift errors are always corrected. A new direction or expanded scope is
reviewed separately.

Before requesting launch approval, Uplift checks domain/DNS/TLS, mobile presentation, form-to-CRM delivery, email
delivery, call/no-answer/text/reply behavior, STOP/HELP, import counts, access ownership, and every purchased
feature. Provider items still pending are named and never presented as complete.

The final approver explicitly approves the website/system to go live. Record the approved version, approver, and
time. Launch cannot rely on a support-chat message that is unclear about what was approved.

Training asks for attendees/roles, time zone, preferred meeting times, language/accessibility needs, top tasks to
demonstrate, recording consent, and recording/guide recipients. Training must be scheduled before delivery is
closed, but it does not block starting the build. The handover pack contains the recording when allowed, guides,
ownership/access summary, open external actions, support route, and launch approvals.

## 7. Uplift Support Messenger

A bottom-right **Chat with Uplift** control is visible throughout authenticated setup and CRM screens, including
commercial-warning or suspended-access screens where support is needed. It is real-time when an Uplift responder
is available and asynchronous otherwise; office hours and expected reply time are honest. The interface does not
promise “Live chat.”

Each new question is its own chat (Intercom's messenger model; Jafar, 2026-10-02). The messenger lists the
member's past chats, newest first, with a **New message** button; someone with no chats yet goes straight to
writing one. Each chat has one topic — Setup, Website, Google Profile, CRM, Billing, or Other. Picking a topic is
optional and it starts as Other; the chat's starter, an owner/admin, or Uplift may change it, and each change leaves
a visible line in the chat. Jafar's Support Inbox filters by topic. The messenger supports unread badges,
attachments (photos and documents, up to 5 files and 20 MB per message; program files refused; photos show in the
chat, other files download), screen/section context, email fallback after a delayed unread message, resolve, and
reopen. Jafar may start a conversation. Messages use **Uplift Support** plus the actual responder's name.

Every active team member may contact support. Owners/admins may see organization-wide threads; another member sees
their own threads and ones they were explicitly added to (Zendesk's "My / CC'd / Organization requests"). Owners/admins
may also write in a teammate's thread under their own name. The thread's starter, an owner/admin, or Uplift may add or
remove teammates, and each change leaves a visible line in the thread. The unread badge counts only a member's own and
added threads; other team threads show a "new" dot in a Team chats list reached from the member's own thread (Jafar,
2026-10-01). The `/jafar` Support Inbox is separate from the tenant's
customer Conversations inbox. Support Messenger is a core package service and does not consume Website Chat
allowances.

Future messages support human, system, and AI sender identities, but no AI support agent is part of this campaign.
A future AI identifies itself, records its actions, and hands off to a human without losing context.

## 8. Jafar's client-delivery workspace

The private owner workspace lists each paid client with package, commercial state, setup progress, current project
state, next action, blockers, provider waits, build target, and unread support count. An organization view provides:

- payment/provisioning history and package agreement;
- submitted sections, completeness, help requests, and returned questions;
- original answers beside final accepted values;
- access tasks and protected provider-document status;
- explicit readiness blockers and Ready for Uplift action;
- delivery timeline and target dates;
- preview, correction, launch, training, and handover records;
- approvals, consents, actor/time/version history; and
- linked Support Messenger threads.

Jafar can confirm payment, provision/resend setup access safely, review a section, ask a question, return a section,
record access, mark a provider wait, accept Ready for Uplift, release a preview, record launch approval, and complete
training/handover. These are privileged platform operations with independent server authorization and durable audit
history. Jafar never becomes a contractor team member or impersonates one.

## 9. Data, security, and permission guarantees

- Public submission creates no tenant, member, or CRM data.
- Every write uses a validated server route and enforces the correct platform-owner or tenant permission.
- Tenant data stays organization-isolated. Platform onboarding records are not readable by another contractor.
- Passwords and provider credentials are neither requested nor stored in onboarding answers or support messages.
- Sensitive documents have narrow access, malware/file validation, retention rules, and audit history.
- Autosave preserves valid draft work without treating it as an attested final answer.
- Final attestations and approvals preserve wording/version, actor, and time.
- Imported contacts, assets, and claims retain their stated permission/provenance where needed.
- The client can see what Uplift is waiting for and what Uplift has changed.
- Organization closure/export rules eventually cover onboarding, approval, support, and handover records according to
  their legal and operational retention needs; closure never fabricates or silently erases financial history.

## 10. Acceptance behavior

The feature is not complete until these journeys work end to end:

1. A direct buyer submits minimal details, pays offsite, and receives exactly one account after Jafar verifies funds.
2. A client can enter the full CRM before finishing setup and can resume setup on another session/device.
3. Package choice hides irrelevant tasks while shared answers appear only once.
4. Help-needed creates an actionable Uplift item without falsely marking the requested fact complete.
5. Returning one section preserves accepted sections and links the client directly to the returned work.
6. Accepted business facts populate matching settings without duplicate records or overwriting unrelated later edits.
7. Ready for Uplift cannot be recorded while a named essential blocker remains, and its timestamp starts the visible
   delivery range.
8. Google/carrier review remains visibly external and does not mislabel the Uplift build as late or complete.
9. No password or provider secret appears in an answer, log, support thread, notification, or owner screen.
10. Preview approval is tied to a known version; one correction round and Uplift-error fixes remain distinguishable
    from expanded scope.
11. A marketing draft cannot send from onboarding; a separate authorized preview approval is required.
12. Honest-review behavior never suppresses the public review option based on sentiment.
13. Support conversations are available across setup and CRM, respect member visibility, and never mix with the
    contractor's customer inbox.
14. Launch, training, and handover leave a readable delivery record for both contractor and Uplift.

## Still unclear

None. Implementation sequencing and internal architecture are the next planning part; they may not change this
approved behavior without Jafar's approval.

## Not doing

- Inbound SEO discovery as the initial sales engine — the approved first sales motion is outbound outreach.
- Account creation before verified payment — unpaid prospects remain applications.
- An onboarding gate over the CRM — the shipped CRM is complete and available after account activation.
- Password collection or routine Uplift ownership of client assets — delegated access keeps the client in control.
- Guaranteed Google ranking, provider approval date, SMS delivery, or domain availability — those outcomes belong to
  external systems.
- Review gating, incentives, or “5-star reviews only” behavior — requests must be neutral and policy-safe.
- Automatic campaign sending during setup — each campaign has a separate approval.
- AI support in this campaign — only the sender/handoff seam is preserved for later work.
- Stripe implementation in the Payoneer-first release — it receives its own approved payment part later.
- Building infrastructure or changing production deployment — this contract authorizes product planning only.

## Research and supporting decisions

- [Existing paid-prospect contract](jafar-onboarding-implementation-contract.md)
- [Package builder behavior contract](package-builder-behavior-contract.md)
- [Onboarding imports and exports research](research/onboarding-import-export-research.md)
- [SMS onboarding reference](research/ghl-jobber-sms-onboarding-plan.md)
- [Google review policy research](research/google-review-campaign-policy-and-fallback-2026-09-25.md)
- [GOV.UK: Complete multiple tasks](https://design-system.service.gov.uk/patterns/complete-multiple-tasks/)
- [GOV.UK: Check answers](https://design-system.service.gov.uk/patterns/check-answers/)
- [Google: Business Profile ownership and third parties](https://support.google.com/business/answer/13763036?hl=en)
- [Google: Guidelines for representing a business](https://support.google.com/business/answer/3038177?hl=en)
- [Google: Prohibited and restricted review content](https://support.google.com/business/answer/7400114?hl=en)
- [Payoneer: Request a Payment](https://payoneer.custhelp.com/app/answers/detail/a_id/12280/)
- [Twilio: Information required for A2P registration](https://www.twilio.com/docs/messaging/compliance/a2p-10dlc/collect-business-info)
