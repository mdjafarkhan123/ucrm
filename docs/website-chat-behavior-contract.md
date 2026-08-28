# Website Chat Product Contract

Status: Approved product behavior; implementation not started  
Approved: 2026-08-26  
Scope: UCRM's organization-branded Contact Widget and owned Website Chat channel

Research evidence lives in `docs/research/website-chat-channel-review.md` and
`docs/research/ghl-unified-inbox-reference.md`. HighLevel is the default behavior and interaction baseline;
Intercom and Zendesk inform persistent messaging, truthful availability, and visitor continuity. Evidence is
not product instruction: this contract owns the approved UCRM behavior.

## Product promise and boundaries

The Contact Widget is an organization-branded website launcher. It opens Website Chat directly when that is
the only configured option; with multiple options it first presents a channel picker. Website Chat is UCRM's
owned persistent customer-messaging channel and enters the shared Conversations workspace. Configured
WhatsApp or Messenger links initially open those external applications and do not imply that their messages
enter UCRM. A future provider integration may turn an external destination into a Connected channel.

Website Chat supports live human exchange when a team member is genuinely available and asynchronous
continuation when nobody is. It never promises immediate help merely because the business is within office
hours. Customer-facing AI, AI knowledge ingestion, AI estimates, voice/video recording, and live video calls
are later independently approved tracks. The human channel preserves the message-origin and handoff seams
those tracks will need without designing them now.

Website Chat follows the shared threading, collaboration, permission, unread, assignment, follower, message-
origin, outbox, idempotency, and work-context rules in `docs/unified-inbox-behavior-contract.md`.

## Visitor identity, Client creation, and consent

The identity form asks for one whole name, as HighLevel's does, and unlocks the composer only after that name
and either phone or email are valid. The name is split at the first space when a Client is created: everything
before it is the first name, the whole remainder is the last name, and a single-word name leaves the last name
empty rather than guessing one (approved 2026-08-27). It uses a
searchable international country picker with flags, formats while typing, and stores phone numbers in E.164.
Country detection is a suggestion from a prior selection, an entered international prefix, or a privacy-safe
locale lookup; the visitor can always change it.

Submitting the form alone creates nothing. When the first message is successfully accepted, UCRM creates or
matches a Client in the Lead lifecycle state and records widget, landing-page, referral, and campaign
attribution. Website Chat does not automatically create a Request, Opportunity, or other work record. A human,
approved automation, or later qualified AI flow may do so when service intent is established.

Matching uses normalized organization-scoped phone or email. Public input never overwrites an existing
Client. When supplied identifiers point to different Clients, messaging remains usable through a guarded
Needs review identity; UCRM never guesses, merges Clients, or exposes either Client's private history.

The form links to the organization's privacy policy. The link is a per-widget contractor setting
(`website_chat_widgets.privacy_policy_url`, approved 2026-08-27), https only, and blank hides the link
entirely. It is per widget rather than per organization because one organization can run widgets on
several marketing sites, and the policy a visitor is pointed at belongs to the site they are on. The
platform's own privacy policy is never shown on a contractor's widget.

Transactional consent follows HighLevel literally (approved 2026-08-26, evidence in
`Design/Website Chat/highlevel-identity-form.jpg`). One consent line sits directly under the fields, not in a
separate step, and reads as a single channel-agnostic statement covering whichever reply method the visitor
supplied, with its rate disclosure attached: *"By submitting you agree to receive SMS or e-mails for the
provided channel. Rates may be applied."* It is always shown and, as HighLevel's is, checked by default — this
is service consent for the channel the visitor themselves just offered, not a marketing opt-in. It is never
hidden from a visitor who supplied only an email.

Marketing consent remains a separate thing: optional, unchecked, and outside the first release. Supplying a
phone number never silently grants marketing consent.

## Sessions and continuity

A recognized browser restores its active Website Chat session, transcript, and unsent draft across refreshes,
page navigation, and browser restarts. Clearing browser storage removes recognition. A browser session never
unlocks email, SMS, financial, or older Website Chat history merely because its visitor entered contact data.
Cross-device recovery requires a later secure verification flow and is not promised at launch.

A visitor or authorized team member may end a session. Thirty days of inactivity also closes it. Closing the
browser, staff unavailability, allowance exhaustion, or ordinary page navigation does not close an accepted
session. A later inquiry creates a new session linked to the same Client. Sessions from distinct widgets stay
separate so different sites, brands, and project intents are not collapsed; the Client workspace retains the
complete history and every message preserves source attribution.

## Human availability

Eligible team members explicitly switch Available for Website Chat on or off. Passive login, application
presence, and business hours are not availability. Business hours inform expectations and fallback wording.
Availability and capacity may drive assignment, routing, escalation, and delayed text-back even when the
public status is hidden.

Each widget chooses one public visibility mode:

- **Hidden** (default): neutral messaging with no public availability signal;
- **Show when available**: show an online signal only while real capacity exists, otherwise remain neutral;
- **Always show**: truthfully distinguish available, busy, and outside-hours expectations.

Hiding status never permits a false online claim. Staff unavailability never prevents a visitor from leaving
a persistent message.

## Widget configuration and installation

Organization-wide sources include business identity, logo, default brand color, operational timezone,
default business hours, and the Website Chat routing pool. A widget inherits those values and may configure
its name, allowed domains, published state, installation code, launcher position, animated teaser, channel
options/order, greeting, expected-response wording, availability visibility, identity fields, source label,
privacy-policy link, and approved branding/hours overrides. The privacy-policy destination moved from this
organization-wide list to the widget itself on 2026-08-27; see the identity section above for why.

The widget carries no UCRM branding (approved 2026-08-26, following HighLevel). Its footer attributes the
widget to the contractor — "Powered by *&lt;organization name&gt;*" — exactly as HighLevel's does, never to the
platform. A contractor's customers see only the contractor.

The initial installation is a lightweight script that renders a floating bottom-left or bottom-right launcher.
Inline placement is later scope. The teaser slides or fades in without opening the widget, is dismissible and
remembered, stays compact on mobile, and honors reduced-motion preferences. The channel picker validates
destinations and clearly indicates when WhatsApp or Messenger opens another application.

Contractor owners and administrators, or a future explicitly equivalent permission, manage Website Chat in
Settings > Communications. They receive desktop/mobile preview, copyable installation code, installation
testing, domain diagnostics, publish controls, and actionable entitlement/limit/suspension explanations.

## Entitlement and allowance

The Platform Owner controls organization entitlement, maximum active widgets, accepted Website Chat
conversations per confirmed subscription period, reasoned effective-dated overrides, ordinary channel disable,
security/abuse suspension, public-token lifecycle, usage visibility, health, and diagnostics. Contractors
control whether to use an entitled channel and how their widgets behave; they cannot exceed the platform
ceiling or bypass suspension.

One allowance unit is claimed when an identified visitor's first message starts a new accepted session. Forms,
blocked spam, retries, internal activity, staff replies, attachments, and later messages in that session do not
consume another unit. Existing accepted sessions remain usable at the hard cap. New Website Chat sessions show
an honest branded fallback; configured external contact options may remain available. A normal Website Chat
disable removes that channel while safe external options may remain. A platform security/abuse suspension may
disable the entire Contact Widget while preserving history and showing staff the reason.

AI usage, future provider-backed communication charges, and attachment storage are separate limits. Exhausting
a future AI allowance must fall back to human Website Chat rather than disabling the channel.

## Messages, attachments, and Conversations

Text messaging supports live delivery when both sides are present and asynchronous continuation otherwise,
with drafts, typing signals, reconnecting, queued/sent/failed states only where provable, retry without
duplication, and explicit session end/reopen behavior. Website Chat appears as a first-class channel in the
existing contact-grouped Conversations list and mixed-channel timeline. Assignment, followers, unread state,
permissions, origin labels, work context, and independent panel loading reuse existing seams.

Launch media includes inbound and outbound JPG/JPEG, PNG, HEIC, WEBP, PDF, and approved short-video formats,
including attachment-only messages. Files are private, type/size checked, malware scanned, quarantined when
unsafe or unresolved, served through authorized expiring access, and represented by progress, preview,
failure, retry, and accessible fallback states. Images use the shared lightbox behavior. Video uses a safe
player. Storage counts against the organization's storage limit. Exact size/count limits are chosen during
architecture review against storage, scanner, and browser constraints rather than copied blindly from a
competitor.

## Automation and SMS boundary

Website Chat emits durable, idempotent events with organization, widget, Client, session, attribution,
consent, availability, and message context. It can accept channel replies and human-handoff requests and
shows automation-originated activity truthfully in the timeline.

The Automation domain owns presets, sequences, delays, templates, enrollment/re-entry, cancellation,
execution history, and configuration UI. The SMS track owns numbers, registration, balance, opt-out,
quiet-hours, eligibility, delivery, and charges. A future Website Chat text-back preset sends at most once per
session after its configured no-response delay, cancels when a human or AI responds first, and never blocks
Website Chat when SMS is unavailable. Its SMS consumes Communication Balance, not Website Chat allowance.

## Required UI surfaces and states

Every implementation packet must name and complete its affected surfaces:

1. **Public Contact Widget:** launcher, teaser, channel picker, identity form, timeline, composer, media,
   availability, reconnecting, ended/expired, limit, disabled, invalid-domain, and accessible mobile states.
2. **Contractor Website Chat settings:** list, create/edit, preview, publishing, identity, branding, channels,
   availability visibility, routing, domains, install test, usage, and entitlement states.
3. **Conversations:** Website Chat list/filter/timeline/composer, attribution, identity review, assignment,
   availability, session, media, delivery, and failure states.
4. **Platform Owner:** package fields and organization entitlement, allowance, usage, overrides, suspension,
   token, abuse, health, storage, and reconciliation controls in existing `/jafar` surfaces.

No backend layer is complete while its required UI is absent unless this contract and the roadmap explicitly
assign that UI to a named dependency-ready later packet. Each UI packet still requires the short pre-design
plan from `docs/unified-inbox-behavior-contract.md`, UCRM tokens and components, desktop/mobile behavior,
permissions, loading/empty/error/retry states, keyboard/focus/reduced-motion coverage, and browser verification.

## Deferred scope

- customer-facing AI, knowledge upload/retrieval, AI estimates, and AI actions;
- Automation preset design or builder behavior;
- cross-device history recovery;
- inline widget placement;
- voice notes, recorded video messages, and live video calling;
- provider-connected WhatsApp or Messenger behavior;
- proactive targeting, co-browse, screen sharing, queue positions, CSAT, and complex SLA UI.
