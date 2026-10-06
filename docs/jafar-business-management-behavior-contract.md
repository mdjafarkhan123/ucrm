# Jafar Business Management

**Status:** Product planning — the lead-to-client journey and first useful release direction were approved by Jafar on 2026-10-06. Sending, team defaults, handoff details, and final release scope remain under review. This plan describes what people can do and how the business workflow behaves; it is not a coding plan and authorizes no build.

## The vision

Jafar and the Uplift team can run the business journey in `/jafar`: find suitable trade businesses, decide whom to approach, contact them personally or through a reviewed scheduled sequence, handle replies, sell the right offer, bring paid clients into the product, and look after them. The app shows what needs attention today, who owns it, and what happened before. Jafar can decide what each teammate may see and do across the whole panel.

This is one UCRM application. Business Management and Platform Operations are two clear entrances to the same `/jafar` panel, with navigation between them. A teammate sees only permitted areas. Existing Applications, Organizations, Packages, Onboarding, and Support remain the underlying records; a business-facing view may link to them without making a second copy. The two entrances organize the work. They are not a promise of faster loading by themselves.

The market is trade businesses in countries outside Asia. A business's country and contact method matter when deciding whether an outreach channel can be used. Finding a possible client does not by itself make that person eligible to receive a message.

## The work, from first discovery to client

### 1. Find and prepare a lead

**Leads** are businesses Uplift found before they applied or became a client. Jafar or a permitted teammate adds one business with its country, trade, source, website, independently verified contact details, useful fit notes, responsible teammate, and next action. A lead may be new, under research, ready for Jafar's review, approved for a specific outreach method, unsuitable, or saved for later. People with no usable contact details can still be researched; they do not enter a sending list. Possible duplicates are shown for review instead of silently merged. A business that contacts Uplift first enters the same history without pretending it received cold outreach.

The existing `/jafar/prospects` records are **Applications** submitted through the public form. The product should label them clearly as Applications in the Business Management journey; the current route need not change. Lead, Application, Deal, and Client are different stages of one relationship, not four disconnected address books. When one business moves forward, notes, contact history, owner, source, and next action stay visible.

### 2. Decide who may be contacted

Jafar chooses the people to approve for outreach. A teammate can research and prepare them, but that preparation never starts sending. Before approval, the panel shows why each person is proposed, where the contact detail came from, their country, the proposed channel, previous contact, any opt-out, and missing information. It shows excluded people with plain reasons. Jafar can approve selected people and a reviewed first message or sequence, or send them back for correction.

Approval of a person is separate from the channel's current permission and provider readiness. Sending checks both again when each message is due. Opt-out, a reply, a bounce, a bad address, an already active client, a paused sequence, or a channel rule can stop the next step. A manual message sent outside UCRM can be logged, so the system does not later treat that person as never contacted. No automatic scrape or imported Google Maps listing database is promised; Maps can help Jafar discover a business, then its contact details must be verified from its own site or another permitted source.

### 3. Reach out and handle the conversation

For example, if 29 approved leads have never been contacted, they remain idle in an approved list. Selecting or approving them never starts contact. Jafar may choose to send one message himself or separately start a reviewed scheduled sequence. When a permitted channel is ready, he writes a starting message, personalizes each person's version, previews the exact recipients and exclusions, and deliberately launches **29 individual conversations**. Each person has separate timing, delivery result, reply, and stop state. A complete, relevant first message should explain why Uplift contacted that business and give a simple way to respond; the next message should add useful context rather than send a fragment of the first message.

Each sequence step may be an email, a permitted connected message, or a task for a person to complete in the original channel. Jafar controls the time of each step. The editor prefills **five minutes** for the next step, as requested, and Jafar may change it. A channel or provider rule can require a longer wait or prevent the send, with a visible reason. The system never silently bypasses that rule. Sending is paced, safe to retry without creating a second copy, and checked again immediately before delivery. A reply or opt-out stops remaining automatic steps; Jafar can also pause or cancel a person or an entire batch. Failed, pending, skipped, and delivered outcomes are visible per person. An open or view count is never treated as proof of interest.

Email automation is considered only where the sender, recipient, country, opt-out handling, and provider policy are ready. A sending address being verified, a provider account being active, a free daily allowance, Jafar approving recipients, or Jafar pressing Start does not by itself approve first-contact email to people who never requested it. Neither the existing Brevo platform sender nor the current SES account is a verified route for that outreach. Until a provider approves the exact use and recipient checks pass, UCRM holds those sends and offers a human task with a logged outcome where that contact method is permitted. Brevo remains the provider for expected platform messages; the Uplift mailboxes use the chosen SES direction once ready. WhatsApp needs the recipient's permission; Instagram and Messenger cannot be promised as cold-message automation. For those channels, the first useful workflow is also a personal task and a logged result. Connected two-way messaging can be added only after its official channel rules and provider access are checked. A shared sales conversation view should show connected replies; other-channel activity can be logged manually until connected. Existing client Support remains identifiable as a different purpose, even when staff can see both conversations.

Jafar can create multiple Uplift email addresses on `upliftcontractor.com` inside `/jafar`, starting with `info@upliftcontractor.com`, without buying a Hostinger email plan. Each address has its own inbox for ordinary incoming and outgoing email, including a new inquiry that is not a reply to a CRM message. A Unified Inbox shows conversations across the addresses and other connected channels the viewer may access; a message delivered to two Uplift addresses appears once in that combined view while remaining visible in each relevant address inbox. The team can read, compose, reply, search, handle attachments, and see delivery or failure where the channel provides it. Replies use the address that received the conversation unless a permitted teammate deliberately changes the sender.

Jafar controls which teammates may see or send from each address. Shared addresses can be assigned to a team; a personal address starts private to its owner and Jafar until access is granted. Disabling an address stops new sending and makes its receiving behavior clear before the change; it does not silently erase existing mail. Unknown addresses on the domain are rejected instead of becoming hidden catch-all inboxes. Incoming spam or unsafe attachments are kept out of ordinary conversations, with a review path for legitimate mail caught by mistake. Email remains available for ordinary correspondence even when no lead or deal matches the sender; the team may link a conversation to the right business after review.

This is a real in-app mailbox service, not merely a new sender name. The existing contractor Unified Inbox supplies suitable interface and conversation patterns, and its SES receiving and sending work supplies reusable transport and safety pieces. The contractor Inbox itself is scoped to contractor customers and replies to CRM-sent email, so Uplift mailbox records, general inbound storage and routing, platform-team access, and lead/deal context require separate work. The domain may stay registered at Hostinger, but its mail delivery would move from the current Hostinger mail route to SES only after the existing mailbox and contents are checked and a safe cutover is ready. Incoming messages must survive a temporary app outage and reappear when service recovers; backups, failed-mail review, spam review, and a way to restore mail are part of the mailbox promise. Provider setup, operating costs, and recovery need a separate readiness check before any live mailbox or DNS change.

### 4. Turn interest into a deal

A reply showing real interest, or a booked discovery call, can create a **Uplift sales Deal** linked to the business. The proposed pipeline is **Interested → Call booked → Needs understood → Pricing shared → Awaiting decision/payment → Won or Lost**. **Later** holds people who asked to revisit at a particular date; it requires a next action. The active board contains buying conversations, while the Leads list continues to hold early research and outreach. A stage records a real event, not a guessed chance of winning.

The deal keeps the contact, source, notes, messages, call outcome, next action, responsible teammate, pricing-page link sent, the package and price shown or discussed at that time, and any agreed exception. The website carries the public offers; the first release does not need a separate offer-document maker. A later website price change does not rewrite what was previously shared. A missed or cancelled call returns to a rescheduling task. Pricing shared without an answer has a follow-up due date. A declined offer has a reason and remains in history. A business may submit an Application at any point; the team links it to the existing relationship instead of creating a second lead or client. A deal is **Won** when the agreed sale and payment are confirmed under Uplift's current commercial process; agreement alone can remain awaiting payment. Sales may mark it Won only after payment is confirmed; marking a Deal Won neither confirms payment nor creates an account. The existing Application, payment confirmation, account creation, and onboarding controls handle the actual client handoff. The first onboarding action belongs to the teammate Jafar assigns, or to Jafar if nobody is assigned; Won never means setup is finished.

### 5. Deliver, support, and keep the relationship

After the handoff, the same business appears as a Client. The Business Management view points to its organization, onboarding stage, support conversations, package, payments, renewal attention, and opportunities for later work. Team members see only the details their role permits. Existing Platform Operations controls remain the source for provisioning, provider failures, access recovery, and other sensitive corrections.

### 6. Know what to do today

The opening view should lead with **next actions**, not a wall of charts: leads waiting for Jafar's approval, approved people awaiting first contact, replies to answer, overdue follow-ups, calls, shared pricing awaiting a decision, onboarding handoffs, and client renewal attention. A Business Management calendar in `/jafar` shows sales calls and dated follow-ups, with their owner, time, linked business or Deal, outcome, and reminder. Jafar sees his own upcoming and overdue work; an assigned teammate sees theirs. It may reuse the contractor Schedule's calendar presentation, but contractor jobs and visits do not become Uplift sales events. A booked, missed, cancelled, or moved call updates the next action; the reminder reaches the assigned person, or Jafar when nobody is assigned. Every active lead or deal has one responsible teammate and either a dated next action or a visible reason it is waiting. A small report then shows researched, approved, contacted, replied, calls, pricing shared, won, and lost by source and time period. Counts distinguish people reached from messages sent, and a channel's delivery from an actual reply. Reports describe association with a source; they do not claim that a message caused a sale.

## Team access across `/jafar`

Jafar controls team invitations, access, and removal for the entire panel. The starting roles are Sales, Delivery, Support, and Platform Operations, but Jafar can turn specific areas and sensitive actions on or off for each teammate. These team features are built even though Jafar is the only user at first; unassigned work defaults to him. In particular, researching a lead, approving recipients, launching a batch, changing commercial terms, confirming payment, provisioning an account, managing teammates, and operating providers are separate abilities. Jafar initially keeps outreach approval, payment confirmation, provisioning, package changes, and teammate access unless he explicitly grants them. Sales can mark a Deal Won only after the payment confirmation already exists. Jafar retains the final owner powers. Screens and server actions enforce the same permissions; hiding a menu is insufficient. Important approvals, sends, commercial changes, and access changes retain an actor and time.

Contractor team permissions are a useful pattern, but they are scoped to each contractor organization. `/jafar` currently has a configured single-owner login. Platform-team accounts and permissions therefore need their own secure scope and cannot inherit contractor access to customer organizations.

## Reuse and simplicity

Reuse the existing automation editor, minute-based waits and background execution, marketing recipient preview and paced delivery, Unified Inbox interface and components, message handling, task and pipeline presentation, package data, onboarding, and permission design **where their behavior proves suitable**. Do not build a second conversation experience from scratch or copy contractor organization permissions into `/jafar`. This plan does not assume that current contractor automation can already send a five-minute cold follow-up: its existing safety rule separates two outgoing customer messages by 60 minutes. Uplift's outreach needs its own reviewed policy without weakening contractor protection. The contractor pipeline follows Requests and Quotes, so Uplift sales Deals need distinct business records while sharing suitable interface patterns. Contractor customer marketing is designed for existing customer relationships and cannot be copied as a cold-prospect permission rule.

The simple first useful journey is manual lead capture, clear approval, individually reviewed and scheduled outreach through ready channels, replies and tasks, a small deal pipeline, and a handoff to existing client operations. All trade businesses outside Asia can be recorded; automated outreach is available only for recipient/channel combinations whose rules and sender are verified. Build no extra message channel merely to make every icon look connected. Where a lawful contact method has no integration, show a human task and allow its outcome to be recorded; where permission is missing, hold contact until it is resolved.

## Still unclear

- Which provider, if any, will explicitly permit the proposed first-contact email workflow? SES is the chosen Uplift mailbox transport, but technical sender setup and provider permission for prospecting are separate checks. Live domain cutover and recovery need proof before activation.
- What country and channel checks must be proved before a particular automated send is enabled? The market remains all trade businesses outside Asia; there is no narrower lead-list geography.
- What reminder timing and delivery choices should the Business Management calendar provide, and should a prospect-facing self-booking link be in the first release?
- What exact access should each starting team role have by default? Jafar will be able to change it.

## Not doing

- Building features, changing production providers, or sending messages during this planning campaign — Jafar asked for product planning first.
- Scraping Google Maps or bulk cold DMs through WhatsApp, Instagram, or Messenger — source and channel rules do not support that promise.
- Copying contractor customer data or permissions into the platform team area — those belong to separate security scopes.
- A separate application for Business Management — Jafar wants one organized panel, and existing business records must remain connected.
- Predictive scores, AI-written outreach, elaborate branching, or a second general automation engine in the first useful release — they add complexity before the core journey works.
- A separate offer-document maker in the first release — Uplift shares its website pricing page and records the terms discussed in the Deal.

## Research

- [Mature sales workflow patterns](research/founder-sales-system-patterns-2026-10-06.md)
- [Outreach channel and source rules](research/founder-outreach-channel-rules-2026-10-06.md)
- [Current sender, country, and reuse check](research/jafar-outreach-sending-reuse-2026-10-06.md)
- [Uplift mailbox options and chosen direction](research/jafar-full-mailbox-options-2026-10-06.md)
- [Live mail readiness and provider permission check](research/jafar-mail-readiness-2026-10-07.md)
- [Existing Jafar controls](jafar-completion-contract.md)
- [Contractor marketing blueprint](marketing-product-blueprint.md)
- [Contractor pipeline behavior](sales-pipeline-behavior-contract.md)
