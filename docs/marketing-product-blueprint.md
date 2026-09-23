# Marketing Product Blueprint

**Status:** Product behavior approved — implementation planning not started  
**Approved:** 2026-09-15  
**Purpose:** Define the complete Marketing destination while delivering only the most-needed contractor features
first. This document describes customer behavior, workflows, screens, states, permissions, safety, and outcomes.
It is not a coding plan.

Research evidence:

- `docs/research/marketing-product-patterns-2026-09-15.md`
- `docs/research/marketing-bulk-email-safety-2026-09-15.md`
- `docs/research/reputation-feature-research.md`
- `.claude/skills/jobber/jobber-06-automations-clienthub.md`

Existing authoritative boundaries remain in:

- `docs/contractor-email-contract.md` for email identity, consent, reputation, provider safety, and service-email priority;
- `docs/unified-inbox-behavior-contract.md` for replies and message history;
- `docs/automation-behavior-contract.md` for always-on journeys; and
- `docs/crm-launch-implementation-roadmap.md` for delivery order.

## 1. Product outcome

Marketing helps a contractor turn existing relationships into repeat work without needing marketing expertise.
The first version answers five plain questions:

1. What do I want customers to do?
2. Which customers should receive this?
3. What will they see?
4. When will it be sent?
5. Did it produce requests, jobs, and revenue?

Marketing is a growth layer over the existing CRM. It uses the same Customers, properties, tags, lead sources,
services, Requests, Jobs, communication preferences, Conversations, Forms, and business identity. It never creates
a separate marketing-only customer database.

## 2. Product principles

1. **Simple front door:** present contractor goals, following Jobber and Autopilot, rather than a toolbox of
   marketing jargon.
2. **One deliberate launch:** a contractor confirms one campaign once; UCRM safely handles the gradual delivery.
3. **Exact audience:** show the actual recipients and every exclusion before launch.
4. **Current permission:** scheduling is not permanent permission. Recheck consent, address, suppression, sender,
   limits, and campaign state immediately before each recipient is handed off.
5. **Service messages win:** Quotes, Invoices, receipts, security mail, and direct replies cannot be delayed by a
   marketing burst.
6. **Truthful results:** delivery, clicks, Requests, Jobs, and revenue remain separate facts. UCRM may say
   “attributed to,” never “caused by,” when attribution is inferred.
7. **Safe defaults:** required identity, address, unsubscribe, deduplication, pacing, and reputation protection are
   platform behavior, not optional checkboxes.
8. **Progressive power:** advanced capability may grow behind the simple journeys without turning the opening
   screen into HighLevel's large tool catalogue.

## 3. Scope and release boundary

### First useful release

- Marketing home
- One-off email campaigns
- Three campaign goals: Bring past customers back, Promote a seasonal/additional service, and Announcement
- Saved, automatically updating customer groups
- Contractor-specific targeting from Customer and work history
- Exact eligible and excluded recipient preview
- A small branded email-template library
- One visual email editor
- Test email, desktop/mobile preview, send now, schedule, and cancel scheduled/unclaimed delivery
- Gradual background delivery with service-email priority
- Per-recipient outcomes and plain failure reasons
- Basic delivery, engagement, Request, Job, and attributed-revenue reporting
- Customer and work timeline links back to the campaign
- Owner/admin launch controls and a separate staff drafting permission
- A separate Marketing recipient allowance that cannot consume protected operational-email capacity

### Next approved product parts

1. Automatic Past Customer Win-back preset through the existing Automation product
2. Automatic Lost Lead Follow-up preset through the existing Automation product
3. Reputation/Reviews with Google destination, manual request, a recommended post-work preset, private feedback,
   recovery alerts, cooldown, stop rules, and basic reporting
4. SMS campaigns only after SMS registration, consent, STOP/HELP, cost, quiet-hour, callback, and live-delivery
   safeguards pass

### Deliberately preserved Later Marketing

These are named future product parts. Finishing the first release does not close or erase them.

- Referral program, tracked referral links, rewards, credits, invoice application, and anti-abuse rules
- Social posting and content calendar
- Google Business Profile optimization
- Completed-job showcase posts
- Website and landing-page builder
- Paid advertising and prospecting
- Advertising-audience synchronization
- General branching/looping marketing journeys
- A/B and holdout testing
- Predictive customer groups and AI optimization
- Multi-touch attribution and paid-media ROI
- Multi-location marketing and review aggregation
- Broader email/SMS template library
- Advanced campaign planning across multiple assets

Each later part needs fresh primary-source, provider, policy, and demand research before its detailed behavior is
approved. It will reuse the same Customers, consent, Campaign, Communications, Automation, and attribution truth.

## 4. Language and concepts

- **Marketing campaign:** one named outreach initiative with a goal, audience, content, delivery choice, and results.
- **One-off campaign:** one deliberate launch that resolves a customer group and delivers once.
- **Automatic campaign:** an always-on marketing journey executed by Automation after a qualifying future event.
- **Customer group:** saved rules that find matching CRM Customers or leads. The visible label is “Customer group”;
  technical or advanced views may call it an audience.
- **Recipient snapshot:** the exact people considered when a campaign launches. It preserves history even when the
  saved customer group changes later.
- **Eligible recipient:** a person who passes current channel, consent, suppression, address, sender, frequency,
  and platform checks.
- **Excluded recipient:** a matching person who will not receive the campaign, with a plain reason.
- **Campaign result:** one recipient's waiting, delivery, engagement, exclusion, or attributed work outcome.
- **SMS registration:** telecom/provider readiness. It is never labelled simply “Campaign” in the Marketing UI.

## 5. Navigation and information structure

The contractor sidebar contains a **Growth** group:

- **Marketing** — available with the first release
- **Reputation** — appears when the Reviews product part is available

Marketing uses one destination with these views:

- **Overview** — useful actions, setup/readiness, recent work, and a small result summary
- **Campaigns** — all one-off and later automatic campaigns
- **Customer groups** — saved recipient rules and current counts
- **Templates** — approved organization-owned branded starting points

Campaign detail uses URL-addressable tabs:

- Overview
- Recipients
- Content
- Results

Communications continues to own sender setup, delivery health, suppressions, and channel readiness. Automation
continues to own always-on workflow execution. Requests/Bookings continues to own forms. Marketing links to the
exact owning screen when setup is incomplete instead of duplicating those settings.

## 6. Marketing overview

The opening screen leads with useful actions rather than an empty analytics dashboard.

### Ready state

Primary actions:

- Bring past customers back
- Promote a seasonal service
- Send an announcement

Supporting areas:

- Continue draft campaigns
- Upcoming scheduled campaigns
- Recent campaign results
- Saved customer groups
- Email readiness and a direct fix link when attention is required

The top summary stays small: recipients reached, delivered, Requests attributed, and Jobs/revenue attributed for
the selected period. Open rate is supporting information because privacy tools and bots make it unreliable.

### First-use state

Explain in one short paragraph that Marketing uses existing Customers and Job history. Offer the three campaign
goals immediately. Do not require a general setup wizard when the sender and consent foundation are already ready.

### Blocked or incomplete setup

Keep history and drafts visible. Disable only the action that is unsafe and state one exact fix, for example:

- Verify your sending domain
- Add a business address
- No eligible customers have marketing consent
- Marketing email is temporarily paused to protect delivery

## 7. Campaign list and lifecycle

Each row shows:

- name and goal;
- One-time or Automatic;
- channel;
- Draft, Scheduled, Sending, Completed, Cancelled, or Needs attention;
- customer group and recipient count;
- scheduled or last-sent time in the business timezone;
- delivered, clicked, and attributed Jobs/revenue when applicable; and
- last update.

Search finds a campaign by name. Filters cover status, type, channel, goal, and date. Results use bounded pages and
do not load every campaign into the browser.

### Campaign states

- **Draft:** editable and never deliverable.
- **Scheduled:** frozen launch instructions; may be cancelled before delivery starts.
- **Sending:** at least one recipient is being processed. Sent email cannot be recalled; Cancel stops only
  recipients not yet claimed.
- **Completed:** every recipient has a terminal delivery or exclusion result.
- **Cancelled:** no new recipients will be claimed; already accepted messages retain their real outcomes.
- **Needs attention:** delivery stopped because sender/reputation/platform safety requires intervention. It never
  silently resumes stale marketing.

Duplicating creates a new Draft using copied content and customer-group rules. It does not copy recipients or
send history. A launched campaign is historical and cannot be edited into a different message; “Duplicate” is the
safe correction path.

## 8. Create campaign journey

One full-page five-step journey owns the draft. Back and Continue move between steps in the current editor. An
explicit **Save draft** action preserves it for later; merely opening or changing the form never writes. Leaving
with unsaved changes requires Save draft, Discard, or Stay.

### Step 1 — Goal

Choose:

1. Bring past customers back
2. Promote a seasonal or additional service
3. Send an announcement
4. Start from a blank campaign

Each option explains the expected audience and suggests a small branded template. The campaign receives an
editable internal name.

### Step 2 — Customers

Choose a saved customer group or start from a recommended group:

- Past customers with no upcoming work
- Customers who purchased a selected service
- Customers in a selected city or service area
- Customers with selected tags
- Lost leads who never booked
- All eligible active customers

Available filters in the first release:

- lead or customer state;
- tags;
- city/service area;
- original lead source;
- service or line item used;
- one-off or recurring work;
- last completed Job date;
- whether upcoming work exists; and
- include or exclude selected Customers.

The count updates as rules change. “View customers” opens the exact matching list. The page separates:

- matches;
- eligible recipients;
- excluded recipients; and
- duplicate email destinations.

Exclusions show plain reasons: missing email, no recorded consent, No marketing, Do not disturb, unsubscribed,
hard bounce, complaint suppression, duplicate destination, inactive Customer, sender not ready, or platform hold.

A saved customer group stores rules and updates with CRM truth. The campaign launch preserves a separate exact
snapshot so later Customer/Job changes never rewrite history.

### Step 3 — Email

Choose a template or Start blank. The first template library stays small:

- We miss you / book again
- Seasonal service reminder
- Complementary service offer
- Business announcement

One visual editor provides these blocks:

- image;
- heading;
- text;
- button;
- divider; and
- service summary.

The editor also provides subject, preview text, approved customer/business variables, and a desktop/mobile
preview. Variables with no safe value show a blocking correction rather than leaking a placeholder.

UCRM owns and locks the required footer: contractor identity, physical business address, preference/unsubscribe
link, and any required provider/legal content. Branding comes from Business Profile. A copied template belongs to
the contractor and later platform-template changes never silently rewrite the draft.

### Step 4 — Delivery

Choose:

- Send now; or
- Schedule for a date and time in the business timezone.

The page shows the selected verified Marketing sender, reply destination, estimated eligible recipients, remaining
Marketing allowance, current warm-up/reputation state, and the expected gradual-delivery explanation. The default
is a stable Marketing address on the contractor's verified domain, separate from receipt, Quote, and Invoice
identity. Changing the sender requires choosing another eligible organization sender; a marketing campaign never
silently falls back to a platform identity.

The primary campaign action normally links to an existing UCRM Request or Booking form. Also allow a verified
website link or a phone-call button. UCRM checks that an internal destination still exists and offers a test open.

### Step 5 — Review

Show one final, readable summary:

- rendered desktop/mobile message;
- sender and reply destination;
- campaign goal and customer-group rules;
- exact eligible count;
- excluded count with reasons and list access;
- duplicate destination handling;
- call-to-action destination;
- send time and timezone;
- applicable allowance/reputation/warm-up notices; and
- the statement that sent email cannot be recalled and cancellation affects only waiting recipients.

Send a test email is available to the logged-in authorized user's verified staff address. A test is clearly
labelled and cannot use a Customer address.

The final Send/Schedule button is owner/admin-only. It uses the latest review revision, so a material audience,
content, sender, or schedule change forces a fresh review rather than launching something the owner did not see.

## 9. Safe delivery: one click for the contractor, gradual work for UCRM

The contractor sends the campaign once. UCRM must not attempt to deliver every recipient in one second.

### Product behavior

1. Final confirmation freezes the campaign version and creates the recipient snapshot once.
2. UCRM removes duplicate destinations and records every exclusion.
3. UCRM queues one Marketing campaign and its durable recipient work; the browser never sends customer email
   directly.
4. The UCRM Marketing worker releases recipients progressively through Amazon SES v2 in bounded batches. A large
   campaign from one contractor cannot occupy all platform/provider capacity.
5. Immediately before a waiting batch is released, UCRM rechecks current consent, unsubscribe, suppression,
   address, sender, campaign cancellation, organization state, reputation, allowance, and frequency for its
   recipients.
6. Valid recipients are released at the currently safe pace. Stable campaign/recipient identity makes repeated
   launch or reconciliation harmless rather than double-sending.
7. Provider callbacks update delivery, bounce, complaint, unsubscribe, and engagement outcomes. Provider
   acceptance is “Submitted,” not “Delivered.” Uncertain outcomes are reconciled before any retry.
8. Cancellation stops unreleased UCRM work. Messages already accepted by SES continue to their real outcome and
   cannot be recalled.

### Pacing and priority

- Marketing has a separate queue and rate budget from operational email.
- Marketing uses a dedicated UCRM worker and the SES v2 send API; operational email keeps its own queue, rate
  budget, configuration set, and protected capacity.
- Requested Quotes, Invoices, receipts, security messages, and direct replies receive priority and protected
  capacity.
- A new or unhealthy domain may deliver a small campaign over hours or days. The UI shows progress and the reason;
  it never promises instant completion.
- Existing email-contract warm-up defaults remain the outer starting guard: 100 accepted recipients/day on days
  1–3, 250/day on days 4–7, and 500/day on days 8–14. Marketing additionally requires its own readiness and may be
  slower. These are configurable safety defaults, not a proven capacity claim.
- The existing 100-recipient/10-minute organization ceiling is also an outer guard. The campaign dispatcher may
  pace below it based on recent bounces/complaints, provider response, platform capacity, domain age, or fair use.
- A domain that has only sent small service-email volume does not automatically earn permission for a sudden large
  marketing burst.

### Failure and pause behavior

- One invalid recipient is excluded without failing the whole campaign.
- Temporary provider or platform pressure leaves safe work waiting with a visible progress state.
- A complaint, hard-bounce spike, unsafe unsubscribe rate, suspicious volume, sender-authentication failure, or
  platform hold stops new optional delivery according to the approved email contract.
- Only the authorized recovery path resumes a reputation pause. Resuming reruns current eligibility and never
  releases stale marketing automatically.
- The campaign detail explains whether a result is Waiting, Submitted, Delivered, Bounced, Complained,
  Unsubscribed, Cancelled, Excluded, or Checking status.

### Capacity statement

No campaign-size or completion-time promise is approved yet. The future implementation must measure at least:

- recipients per campaign and per organization;
- concurrent campaigns and tenant skew;
- claim and provider-submission throughput;
- queue age for marketing and protected service mail;
- duplicate/idempotency outcomes;
- provider rejections, callbacks, and retry backlog;
- database/API latency for recipient preview and result pages; and
- cancellation while delivery is active.

Only those measured workloads may support a capacity claim.

## 10. Consent, trust, and destination rules

- Marketing eligibility requires recorded evidence appropriate to the channel and enabled country. Store purpose,
  source, disclosure/version, and time. A tag is not consent evidence.
- Imported Customers without reliable marketing-consent evidence start ineligible. Authorized staff may record a
  real verbal or written preference with source and date; they cannot bulk-assert consent merely because someone
  was a Customer.
- A Marketing unsubscribe takes effect immediately for Marketing and never blocks valid essential operational
  messages.
- A legal SMS opt-out remains product-wide for SMS and cannot be overridden by a campaign.
- Shared email destinations receive one copy per campaign. The review shows every affected Customer record and the
  selected primary recipient identity.
- UCRM rechecks eligibility at delivery time because a Customer may unsubscribe after scheduling.
- Every email automatically identifies the contractor and provides the required preference/unsubscribe action.
- Frequency protection warns about recent marketing to the same recipient and blocks platform-defined abusive
  contact patterns. The recommended first-release default is at most one Marketing email from an organization to
  the same destination in seven days. Jafar may tighten the platform rule; a contractor cannot bypass it. This
  default remains subject to pilot review rather than a capacity or legal claim.

### Marketing allowance

- Marketing access and its billing-period recipient allowance are separate from operational email.
- Count each unique recipient accepted by the provider once. Excluded/invalid recipients and idempotent retries do
  not consume another unit; a later bounce still counts because provider work was accepted.
- Final review shows the estimated use and remaining allowance. Launch reserves enough allowance for the eligible
  snapshot so concurrent campaigns cannot overspend it.
- No package numbers are approved in this blueprint. Jafar will set package defaults and reasoned organization
  overrides only after provider cost and pilot usage are measured.
- Reaching the Marketing allowance pauses optional Marketing only. It never consumes the operational reserve or
  blocks valid Quotes, Invoices, receipts, security messages, and direct replies.

Country enablement is controlled and evidence-led. Marketing email is enabled only where the launch behavior has
received a current compliance review. SMS country enablement remains separately gated by provider and telecom
requirements. “Global-ready” architecture does not mean every country is enabled on day one.

## 11. Sender and replies

Marketing uses the organization's selected eligible verified sender and defaults its display name to the business
name. The final review always shows it. A missing or unhealthy sender blocks launch with a direct setup link.

The contractor chooses one eligible reply destination during delivery setup. Replies enter the existing shared
Conversations workspace and preserve Campaign as the message origin. Assignment, staff visibility, and unknown
sender handling continue to follow the unified-inbox contract.

Disabling a staff account cannot strand a campaign reply. Organization-owned campaign identity and a shared
fallback destination remain available; changing the fallback is visible and audited.

## 12. Campaign detail and results

### Overview tab

- campaign goal, state, owner, created/launched times, customer group, sender, and call to action;
- progress for Waiting, Submitted, Delivered, Failed/Excluded, and Cancelled;
- a clear Cancel remaining delivery action while work is still claimable; and
- Duplicate for any historical campaign.

### Recipients tab

A searchable, bounded list with Customer, email, eligibility/result, reason, sent time, delivery time, engagement,
and attributed Request/Job. Filters cover waiting, delivered, failed, excluded, unsubscribed, and engaged.
Opening a recipient links to the authorized Customer and Conversation history.

### Content tab

Shows the immutable launched message and destination. A Draft remains editable through the create journey. A
launched campaign offers Duplicate, not Edit.

### Results tab

Answer four questions:

1. How many matched, were eligible, and were actually submitted?
2. What was delivered, bounced, complained, unsubscribed, opened, or clicked?
3. What Requests and Jobs followed, and what value/revenue do they hold?
4. Which campaign, group, or service appears strongest?

Display open activity as directional, not exact. Link every aggregate to the underlying authorized results. Do
not hide zeroes or partial failures behind a single success rate.

## 13. Attribution

Preserve the Customer's original lead source. A Marketing touch never overwrites it.

First-release attribution order:

1. **Direct tracked action:** the Customer used this campaign's recipient-bound UCRM Request/Booking link.
2. **Direct declared relationship:** authorized staff connect a resulting Request/Job after reviewing the
   Customer and timing.
3. **Defined-window association:** the same Customer created a Request, or a Job with no Request (a phone
   booking), after a delivered campaign within the displayed attribution window and no stronger source exists.
   Only the most recent delivered campaign before that work is credited (amended 2026-09-23, Jafar-approved).

The UI names which method was used. Direct tracked results are stronger than window-based association. Campaign
revenue follows real linked Jobs/Invoices/Payments and never invents a payment from quoted value.

Recommended first-release window: **30 days**, matching Jobber's understandable contractor reporting pattern.
The UI displays the rule beside attributed results. Multi-touch credit models remain Later Marketing.

## 14. Permissions and audit

### Owner and administrator

- view Marketing and results;
- create/edit customer groups, templates, and drafts;
- send tests;
- schedule, send, and cancel remaining delivery; and
- manage eligible sender/reply selections through their owning settings.

### Marketing-enabled staff

- view Marketing and permitted results;
- create/edit customer groups, templates, and drafts; and
- send a test to their own verified staff address.

They cannot perform the final Send/Schedule or change channel safety settings in the first release.

### Default role behavior

Sales, field, finance, and ordinary office roles have no Marketing access by default. A future explicit Marketing
permission may grant the drafting capability without granting final launch. Underlying Customer, revenue, and
Conversation permissions still filter what a person may see.

Audit history records draft ownership changes, sender/customer-group/content revision at launch, test delivery,
schedule/change/cancel, launching actor, recipient counts, safety pause/resume, and material platform-owner action.
It excludes provider secrets and unnecessary message content.

## 15. Loading, empty, error, and recovery states

All page content renders without blocking the app shell.

- **Loading:** show the page structure and matching skeletons; never replace the whole page with a spinner.
- **Empty:** lead with the next useful campaign goal.
- **No matching Customers:** explain which rule removed everyone and offer Edit customer group.
- **No eligible recipients:** preserve matches, list exclusion reasons, and disable launch.
- **Forbidden:** explain that Marketing access is required; expose no counts or Customer names.
- **Not included:** explain plan availability without pretending there are no campaigns.
- **Sender unavailable:** retain the draft and link to the exact Communications fix.
- **Stale draft:** show that another person changed it, reload the latest version, and never overwrite blindly.
- **Partial failure:** keep successful recipient results and make failed/excluded recipients filterable.
- **Connection loss during final confirmation:** show an unknown/pending result and reconcile the stable launch
  command before allowing another attempt.
- **Paused campaign:** show who/what paused it, what remains unsent, and the authorized recovery path.

Every important action has visible hover, keyboard focus, disabled, running, success, and error behavior.

## 16. Responsive behavior

Desktop uses the full dashboard and multi-column review where useful. Narrow screens stack content into the same
step order and keep one primary action visible without hiding exclusions or safety notices.

- Marketing home cards become one column.
- Campaign list becomes compact rows/cards with status and the most important result.
- Create steps remain full-page; the step indicator scrolls horizontally if needed.
- Email preview switches between desktop and mobile rather than squeezing the desktop canvas.
- Large recipient lists remain server-bounded and filterable; the browser never renders every recipient at once.
- Final review stacks message preview after the audience/delivery summary so the irreversible action follows all
  important facts.

Desktop browser completion is required for the first release. Responsive web must remain usable, but a dedicated
mobile-app campaign builder is Later Marketing unless customer evidence changes the priority.

## 17. Automation boundary

Marketing owns goals, customer groups, marketing content, campaign identity, and marketing reporting. Automation
owns future-event enrollment, waits, ordered actions, stop rules, and execution history.

The automatic Past Customer and Lost Lead presets appear from Marketing in plain language but open the existing
Automation authoring/review experience when customized. They are future-event only and never silently enroll the
whole historical database on activation. An authorized manual one-off campaign remains the safe tool for existing
Customers.

Operational Quote follow-ups, appointment reminders, Invoice reminders, receipts, and plain review requests keep
their existing operational category unless promotional content changes their purpose to Marketing.

## 18. Platform-owner boundary

The contractor controls campaigns, customer groups, content, schedule, and permitted sender/reply choice. Jafar
controls platform/provider readiness, configurable safety ceilings, reputation enforcement, package/organization
availability, emergency pauses, and sanitized recovery.

Platform controls extend existing Communications and organization surfaces. Marketing does not introduce a
second owner dashboard family. Jafar can identify organizations needing attention without reading unnecessary
Customer lists or message content.

## 19. First-release completion checks

The product behavior is complete only when a reviewer can prove:

1. A contractor can create each of the three goals through one five-step journey.
2. Saved customer-group rules update, while a launched recipient snapshot never changes.
3. Exact eligible, excluded, and duplicate recipients are visible before launch.
4. Missing consent, unsubscribe, suppression, sender failure, and platform hold block the right recipients/actions.
5. Owner/admin can send or schedule; drafting staff cannot launch.
6. The contractor confirms once and UCRM gradually delivers without requiring manual batches.
7. A current opt-out or safety change before dispatch prevents that recipient's delivery.
8. Duplicate launch/retry cannot double-send a recipient.
9. Cancellation stops unclaimed work and never claims to recall provider-accepted email.
10. A representative marketing burst does not break the tested service-email delivery target.
11. Partial failures and uncertain outcomes remain visible and recoverable.
12. Replies appear in the correct authorized Conversation with Campaign origin.
13. Results link to real Customer, Request, Job, Invoice, and Payment facts without overstating causation.
14. Loading, empty, forbidden, not-included, stale, paused, partial-failure, and narrow-screen states are usable.
15. The deliberately preserved Later Marketing list remains in the approved roadmap after first-release completion.

## 20. Performance design verdict

**Growth path:** recipient matching and preview, one result per recipient, provider fan-out, callbacks, and result
reporting grow with campaign size, organizations, and concurrent launches.

**Workload contract:** the first controlled release serves a few closely supported contractors, but no safe maximum
campaign size, concurrent-campaign count, or completion time is yet proven. Recipient lists and result pages must be
bounded. Delivery correctness requires tenant isolation, fair claims, stable send identity, idempotency, current
eligibility, and recoverable partial failure.

**Chosen shape:** one launch snapshot, durable per-recipient results, the provider's Marketing campaign/batching
primitive, bounded fair release, separate marketing admission/rate budget, protected service-email priority,
provider callbacks, and paged reads. This is the smallest proven shape that can stop remaining work, explain
partial results, and avoid an HTTP request or browser session owning the delivery.

**Complexity cost:** durable recipient/result history and a marketing-aware dispatcher are justified by external
fan-out, cancellation, retries, fairness, and audit. Predictive audiences, a CDP, materialized analytics, a new
workflow engine, and multi-touch attribution are not justified for the first release.

**Failure behavior:** overload waits rather than creating unbounded concurrency; one hot organization cannot own
all claims; service messages keep protected capacity; retries reconcile uncertain provider outcomes; a safety
pause stops new optional delivery; tenant-scoped reads and commands fail closed.

**Verification required later:** representative small/medium/large recipient snapshots; concurrent organizations;
preview query plans and payload sizes; claim fairness; cancellation race; duplicate launch/retry; provider timeout
and callback disorder; queue age for Marketing and service email; browser result-page size; bounce/complaint pause;
and clean recovery after worker restart.

**Verdict:** Ready as a product design. No numerical capacity or one-second completion claim is approved until the
named workloads are measured.

## 21. Campaign handoff

Implementation is routed through `Memory/campaigns/marketing-growth/NOW.md`. The campaign owns Marketing,
future Reputation, and every deliberately preserved later feature. Communications, Automation, Customers,
Jobs, Requests/Bookings, and billing remain dependencies rather than duplicate owners.

Resume with:

`continue the marketing-growth campaign`
