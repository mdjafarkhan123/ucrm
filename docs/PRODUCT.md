# UpliftContractor CRM — Complete Product Blueprint

## 1. Product definition

The product connects the full customer journey:

**Inquiry → Request → Assessment → Quote → Approval → Job → Visits → Invoice → Payment → Review → Repeat work**

The main journey should be obvious, but users may take practical shortcuts such as creating a direct quote, manual job, standalone invoice, or offline payment.
The product combines customer management, sales, field service, communications, payments, reputation, and visible marketing growth in one system.

## 2. Target customers

Serve small and medium residential, commercial, and specialty contractors, including builders, remodelers, electricians, plumbers, HVAC, roofing, landscaping, cleaning, restoration, property maintenance, painting, flooring, pools, solar, security, and similar field-service businesses.
Support owner-operators as well as companies with office staff, salespeople, estimators, dispatchers, bookkeepers, and multiple field crews.

## 3. Product principles

Follow the proven contractor workflow without forcing unnecessary steps. Keep the customer’s complete history connected while separating sales, operations, scheduling, billing, and payments. Make the next action obvious, automate repetition rather than judgment, preserve history, use plain language, provide useful defaults, and respect consent, financial accuracy, privacy, and permissions everywhere.

## 4. Core product language

**Customer** is the paying person or company and may begin as a lead. **Property** is the physical service location. **Request** captures what is wanted. **Opportunity** tracks the possible sale. **Assessment** is a scoping visit. **Quote** is the proposed scope, options, terms, price, deposit, and approval. **Job** is the agreed work. **Visit** is one occasion of performing it. **Event** is a non-work calendar block. **Invoice** requests payment. **Payment** records money received or a financial adjustment.

## 5. Super Admin or PO (platform Owner), Users and access

### Super Admin

Read the `Owner.md` file for whole details whenever you need. Here is the summary

The platform owner area is the control room for the whole app. Its a seperate area/dashboard to run the whole operating system not used by Contractors, it has seperate hidden path to login '/jafar'. By this the Platfrom Owner:

- Create a new contractor organization.
- Set up the first administrator for that organization.
- Prepare important business settings and integrations.
- Turn features on or off for an organization.
- Control plan limits and account status.
- See when something important has failed in the background.

Owners see the complete business. Office staff manage leads, communication, scheduling, documents, and collections. Salespeople manage opportunities, assessments, quotes, approvals, and handoffs. Field workers see assigned visits and field tools. Finance users manage invoices, payments, and reports. Customers use branded secure pages. Platform or agency staff provision and support contractor accounts.

Permissions decide whether people see all or assigned work and separately protect revenue, cost, payments, negative feedback, and team controls. Deactivation preserves historical assignments and authorship.

### Authentication and organization membership rules

- Contractor users authenticate through Supabase Auth.
- A contractor user belongs to exactly one contractor organization. Multiple organization membership
  is not supported.
- Contractor users are provisioned by the Platform Owner during organization setup; there is no
  contractor invitation workflow.
- The Platform Owner currently signs in through the separate `/jafar` area using the
  environment-configured owner credentials. Stronger owner identity, MFA, revocation, and audit
  controls are future hardening work.

## 6. Main navigation

Navigation groups **Overview** (Dashboard, Schedule), **Customers** (Inbox, Customers, Requests, Pipeline), **Work & Money** (Jobs, Quotes, Invoices), **Growth** (Reputation, Growth Feed), and **System** (Settings, Team, Notifications, Usage).

Global creation supports all major records. Global search finds names, phone numbers, messages, requests, jobs, quotes, and invoices.

## 7. Dashboard

Dashboard shows summary of important entity

## 8. Customers and properties

The approved detailed behavior is in `docs/client-property-behavior-contract.md`. Read it before changing
Client or Property lifecycle, relationships, deletion, duplicate handling, or user-facing fields.

The customer profile is the complete relationship record.

Include person or company details, multiple contacts, phone numbers, emails, tags, lead source, marketing attribution, owner, lead temperature, next follow-up, notes, files, referrals, balance, and communication preferences.

Support multiple properties with their own address, contacts, service history, access notes, tax behavior, pricing memory, route information, and custom details.

Show one chronological timeline containing messages, requests, appointments, opportunities, quotes, jobs, invoices, payments, files, and reviews.

Warn about likely duplicates using phone, email, and identity similarity. Let authorized users merge duplicates with a preview.

Keep separate permissions for appointment reminders, quote follow-ups, invoice reminders, job follow-ups, review requests, and marketing.

A legal SMS opt-out blocks texting throughout the product until the customer opts back in.

## 9. Requests and public lead capture

Requests capture what the customer wants before work is priced or accepted.

Store the customer, property, description, requested services, photos, questions, preferred time, source, referrer, salesperson, and related assessment, quote, or job.

Support staff-created requests and branded public forms with custom questions and photo upload.

Each form uses one intake pattern: request only, customer-booked assessment, or direct booking for a standard service.

Each form can control services, branding, approval, availability, blocked dates, minimum notice, buffers, service area, confirmation message, share link, and website embed.

Request outcomes include New, Needs Approval, Unscheduled, Upcoming, Today, Overdue, Action Required, Converted, Declined, and Archived.

Completing an assessment should offer Create Quote, Create Job, Leave Action Required, or Archive.

Converted requests remain historical and cannot create duplicate work.

## 10. Sales pipeline

The pipeline manages open commercial opportunities, not operational jobs.

The approved first-release behavior is in `docs/sales-pipeline-behavior-contract.md`. Read it before changing
Opportunity identity, protected stages, movement, outcomes, Request and Quote cards, or reopen rules.

Opportunities are generated from Requests and Quotes. Staff never create one by hand. A Request and the Quote
it converts into are separate cards: the Request card leaves the board on conversion and the Quote appears in
Draft.

The first release uses seven protected stages in two groups, Requests and Quotes. Custom stages come later,
only once real contractor evidence asks for them.

Won and Lost are explicit outcomes, not pipeline columns.

Each opportunity contains customer, property, title, value, owner, stage age, expected close date, next follow-up, related request, assessment, quotes, conversations, and activity.

The Pipeline is desktop web only. The mobile app is separate work, later.

Stages can carry a color, description, win probability, and aging limit.

Real activity may move a deal forward, but automation never moves it backward or overrides later human progress.

Marking Lost may include a structured reason. Won follows an approved Quote or Job creation; a Request is
never manually marked Won. A deliberate Mark Won and Create Job action performs the real Job creation rather
than changing Pipeline outcome by itself.

## 11. Unified inbox

Bring SMS, email, web chat, Facebook Messenger, missed calls, logged calls, attachments, and internal notes into one shared inbox.

Approved contractor operational-email behavior, tenant-domain rules, Brevo allowances, reply routing,
reputation controls, and campaign ownership live in `docs/contractor-email-contract.md`. Read that contract
whenever work touches contractor email, Conversations email replies, sender domains, or Platform Owner
email controls.

Support assignment, unread state, open/snoozed/closed status, tags, filters, search, quick replies, typing signals, delivery status, failures, bounce details, open tracking, and retry.

Show customer and work context beside the conversation.

Allow one connected thread across channels when appropriate and separate threads for different projects or issues.

A missed call creates visible activity, identifies or creates the customer, alerts staff, and may trigger immediate compliant text-back.

### Communications service and balance

UCRM initially provides phone and messaging service to organizations in the United States and Canada through one isolated Twilio subaccount per organization under the platform-owned master account. Contractors search available inventory, select and purchase numbers inside UCRM, complete the required business and messaging registration, and may port their number away when leaving after valid charges are settled.

The Platform Owner privately funds the provider balance. Each organization separately holds a prepaid Communication Balance where one communication credit represents one US dollar and the contractor interface presents the value in dollars. Contractors see their balance, published retail prices, usage, top-ups, adjustments, and refunds; only the Platform Owner sees provider cost and margin.

A contractor may submit an offsite Top-up Request with its payment details, and the Platform Owner may also create one for a payment arranged outside UCRM. A request creates no spendable value until the Platform Owner verifies receipt and confirms it. Confirmation appends Purchased Credit to an immutable ledger and sends a safe receipt; neither the Platform Owner nor a contractor directly edits a balance.

A Top-up Request remains in immutable history as Awaiting Confirmation, Confirmed, Rejected, or Cancelled. Confirmation records both the claimed amount and the amount actually received; a mismatch requires a private reason and never rewrites the claim. Database locking and idempotency allow only one confirmation and one Purchased Credit entry for the same payment.

Purchased Credit and Promotional Credit remain distinguishable. Promotional Credit is spent first, may expire under its grant terms, and is never refundable as cash. Purchased Credit does not silently expire. Normal outbound communication stops when spendable credit is insufficient, while inbound communication and mandatory consent handling continue. UCRM reserves estimated credit before queuing outbound work, settles the final versioned retail charge from provider results, and releases or corrects the reservation when appropriate.

Each published package version may define a dollar-valued Monthly Communication Allowance. The Platform Owner may apply a reasoned, effective-dated organization override without redefining the package. UCRM grants the allowance as Promotional Credit once for each confirmed subscription period, never once per calendar month, and retries cannot grant it twice. Unused monthly allowance expires at the end of that subscription period and does not consume or expire Purchased Credit.

A package change during an active subscription period does not recalculate or supplement the allowance already granted; the new package allowance begins with the next confirmed period. A separately promised immediate benefit is a reasoned Promotional Credit adjustment. No new allowance posts before renewal is confirmed, including during commercial grace. Allowance spending uses the soonest-expiring Promotional Credit first, then later-expiring Promotional Credit, then Purchased Credit.

Suspension preserves every balance and ledger entry but blocks normal outbound activity and new allowance grants while required inbound, consent, provider-callback, and reconciliation work continues. Organization closure preserves Purchased Credit during the recoverable window but blocks spending. Before permanent purge, the Platform Owner resolves unused Purchased Credit through an offsite refund or an explicitly approved non-refundable outcome; unresolved Purchased Credit blocks purge and creates an owner recovery task. Promotional Credit expires at permanent closure.

Retail rates are versioned by destination, channel, sender type, message segments, provider and carrier fees, and recurring registration or number charges. Historical usage retains the rate that applied when it occurred. Provider cost and contractor retail charge remain separate so pricing changes never rewrite history.

When the provider accepts and bills communication, later delivery failure does not automatically refund the contractor. UCRM releases a reservation when no provider cost occurred and otherwise requires a reasoned exceptional adjustment. Unavoidable provider-billed inbound usage continues at zero balance and becomes visible Outstanding Communication Usage; later Purchased Credit settles that amount before becoming spendable, while Promotional Credit never pays old debt.

UCRM warns when balance falls below the global low-balance threshold, is estimated to cover fewer than seven days of recent use, or cannot cover an upcoming number or registration renewal. An underfunded number is protected for 30 days with normal outbound activity paused and an urgent owner task; release or porting always requires impact preview and explicit confirmation.

Platform safety controls include a global outbound pause, per-organization outbound pause, per-organization daily spend caps, unusual-usage and SMS-pumping alerts, a protected provider-balance floor, and immutable owner history. Exhausting the protected provider reserve stops normal outbound work but never disables inbound callbacks or mandatory STOP and HELP processing.

Each package version defines the normal maximum Organization SMS Mode, and the Platform Owner may apply a reasoned organization override. Modes are Disabled, Notifications Only, and Two-way SMS. Contractors may choose a lower mode but cannot exceed the platform maximum. Disabled blocks normal outbound SMS and automations while preserving history and required inbound processing. Notifications Only permits approved transactional notices; ordinary replies are received, billed, stored, and surfaced read-only without enabling an SMS conversation. Two-way SMS enables permitted manual and automated conversations in the unified inbox. Every mode remains subject to consent, registration, balance, rate limits, and emergency controls.

Unused Purchased Credit may be refunded offsite only for a duplicate payment, mistake, organization closure, or another approved exception. The Platform Owner records the offsite refund and confirms a matching immutable credit debit with a reason; Promotional Credit is never refunded as cash.

## 12. Quotes and proposals

Support a price catalog, templates, products, services, headings, quantities, customer price, internal cost, markup, margin, taxes, discounts, photos, notes, terms, warranty language, expiry, attachments, and customer preview.

Keep optional add-ons distinct from good/better/best packages where the customer chooses one complete option.

Support fixed or percentage deposits and milestone payment schedules.

Customers can view, compare options, request changes, sign, approve, decline, and pay a deposit through a secure branded page.

Staff can record verbal, offline, or in-person decisions and signatures.

Track sending, first meaningful view, changes, versions, approval, decline, expiry, extension, resend, deposit, and conversion history.

Resending replaces outdated customer links. Material changes after approval invalidate the prior signature.

Approval stops follow-ups but does not silently create a job. Staff confirms readiness with Create Job or Mark Won and Create Job.

Converted quote scope is copied into the job so later operational edits do not rewrite the historical proposal.

## 13. Jobs and field operations

Jobs may come from won work, an approved quote, direct booking, repeat work, warranty, callback, or manual entry.

Include customer, property, originating records, agreed scope, line items, job type, planned period, crew, instructions, visits, tasks, forms, custom fields, time, expenses, photos, sign-off, billing, invoices, review status, and profitability.

Support one-off, recurring, and as-needed work.

Recurring schedules include weekly, biweekly, monthly, annual, multiple weekdays, first/third weekday patterns, end date, duration, or no current schedule.

Editing recurring work always asks: This Visit Only or This and Future Incomplete Visits.

Completed visits never change when future schedules are rebuilt.

Field workers see today’s route, next stop, customer, property, access notes, scope, instructions, on-my-way action, forms, tasks, time clock, photos, expenses, sign-off, and completion action.

Job costing compares revenue with labor, materials, and expenses, then shows profit, margin, and warnings below the business target.

## 14. Visits, schedule, and dispatch

The job is the agreement; the visit is one calendar occurrence of doing the work.

The schedule combines visits, assessments, events, tasks, quote reminders, and invoice reminders without pretending they are the same thing.

Support month, week, and day views; timed grid; anytime lane; unscheduled backlog; drag-to-reschedule; duration resize; crew filters; conflict warnings; map; route order; and route optimization.

Visits can be Scheduled, Anytime, or Unscheduled and can become Upcoming, Today, Late, or Completed.

Use arrival windows, customer confirmations, team reminders, and on-my-way updates.

Visit completion offers Invoice Now or Later and, for the final visit, Close Job or Leave Open.

Creating an invoice does not automatically close the job. Open work with no future visit becomes Action Required.

## 15. Invoices and payments

Create invoices from quotes, jobs, selected visits, payment milestones, batches, or directly for a customer.

Include service dates, line items, discounts, taxes, deposits applied, issue and due dates, payment terms, customer message, terms, signature, PDF, secure link, text/email delivery, view history, tips, late fees, and reminder schedule.

Invoice outcomes include Draft, Sent Not Due, Awaiting Payment, Partially Paid, Past Due, Paid, Cancelled, and Bad Debt.

Ready work enters a Requires Invoicing queue for review, batch creation, exception handling, and batch delivery.

Support online card and bank payment plus manual cash, check, transfer, wallet, payment-app, financing, and other methods.

Distinguish a platform-processed card from a card payment merely recorded by staff.

Show one financial history containing invoices, payments, deposits, partial payments, refunds, corrections, failed-payment reversals, disputes, voids, and write-offs.

Never hide or rewrite original financial activity. Tips stay outside the taxable invoice total.

Automatic payment suppresses unnecessary reminders. Receipts may be sent by text or email.

## 16. Files and proof of work

Attach files to customers, messages, requests, quotes, invoices, jobs, visits, forms, and marketing activity.

Support job photos, before/after labels, line-item images, PDFs, customer signatures, form photos, logos, avatars, and marketing assets.

Provide fast everyday previews, preserve originals, compare before/after photos, and create shareable proof-of-work presentations.

## 17. Reputation and service recovery

After eligible completion, send a branded rating request after a configurable delay.

Four- and five-star customers continue to the public review page. One- to three-star customers enter a private feedback and complaint-resolution journey.

Support reminders for customers who do not engage, nudges for positive customers who do not finish, expiry, resending, manual requests, eligible-job selection, and review history.

Track sent, opened, rated, redirected, likely reviewed, private feedback, resolution, conversion rate, public count, and rating trend.

Any match between a recent customer and a new public review is shown as likely or confidence-based, never certain.

## 19. Automations

Ready-made automations include speed to lead, missed-call text-back, booking confirmation, assessment reminders, appointment reminders, no-show follow-up, no-quote staff reminder, quote follow-up, deposit receipt, job confirmation, on-my-way, invoice reminders, payment receipt, review requests, and repeat-service reminders.

Each preset lets the contractor enable it, choose timing and channel, edit messages, preview content, see active enrollments, and stop an enrollment.

Advanced automation follows: **When this happens → if these conditions are true → perform these actions.**

Actions may notify customers or staff, create tasks, assign work, change tags, schedule follow-up, move open deals forward, or create draft quotes.

Automations respect consent, do not run retroactively, stop when the business outcome is reached, rebuild reminders after rescheduling, separate customer follow-up from staff reminders, explain skips and failures, and avoid recurring-series message floods.

## 20. Customer portal

Provide a mobile-friendly, branded portal through secure links without password friction.

Customers can request or book work, manage allowed appointments, view past and upcoming visits, approve quotes, select packages and add-ons, request changes, pay deposits, view invoices, pay balances, add tips, download receipts, and see business contact details.

Contractors choose whether customers see all sent documents or only documents reached through direct links.

Business logo, colors, contact details, forms, documents, receipts, emails, and portal share one brand setup.

## 21. Notifications and activity

Action notifications include new leads, missed calls, assignments, follow-ups, quote views, change requests, approvals, deposits, visit changes, payment success/failure, and private feedback.

Important unassigned work falls back to the appropriate manager.

Routine status changes belong in Recent Activity rather than interrupting users.

Users control in-app and push preferences by notification type.

Contractor notifications are a separate system from the platform owner notifications built for
`/jafar`, and deliberately so. They share the front end only: the header bell, the recent panel, the
history page, read/unread behavior, and the rule that opening a linked record marks it read. Those
pieces move into shared components when the contractor side is built. Everything underneath is its
own: rows belong to an organization and to one member, so they need tenant isolation and RLS; read
state is per person; volume needs paging and the Recent Activity split above; delivery spans in-app,
email, and SMS with per-user, per-type preferences; and live updates matter far more than they do for
a single owner. No shared notification layer is built ahead of that work.

## 22. Business settings and platform administration

Contractor settings cover profile, branding, timezone, hours, team, permissions, stages, catalog, quote templates, job fields, job forms, quick replies, booking, availability, email identity, forwarding, phone number, messaging registration, SMS usage, payments, Messenger, notifications, and automations.

A separate platform-owner workspace provisions organizations, applies plans, controls features and limits, manages messaging credits and integrations, completes onboarding, suspends accounts, publishes growth work, reconciles review counts, and investigates failed processes.

Contractors see only their own company. Platform administration remains completely separate from contractor accounts.

## 23. Reporting

Report leads by source, response time, missed-call recovery, request conversion, pipeline conversion, stage aging, forecast, lost reasons, quote outcomes, scheduled and late visits, utilization, jobs requiring action or invoicing, recurring agreements nearing expiry, revenue, balances, overdue money, payment speed, deposits, job costs and margin, review results, complaints, referrals, repeat customers, published growth work, and source-influenced revenue.

Reports always respect each user’s financial and operational access.

## 24. Market position

Match Jobber’s proven customer-property-request-quote-job-visit-invoice-payment workflow, recurring work, scheduling, deposits, batch billing, automations, and client portal.

Beat it with Contractor OS strengths: a real sales pipeline, unified multichannel inbox, missed-call recovery, advanced quote packaging, deeper field records, smart reputation recovery, public experiences without account creation, and a Growth Feed showing visible marketing value.

Position the product as:

> The contractor CRM that runs the work and grows the business.

That complete journey is the product.
