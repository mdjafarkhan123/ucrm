# Jobber feature catalog (as of 2026-10-08)

Purpose: a sourced list of what Jobber sells today, by plan, so we can later compare it with our contractor
edition and find the gaps a paying contractor would notice. Research only — nothing here is a build decision.

## How this was gathered

- **Plan placement** comes from the per-plan comparison table on Jobber's pricing page
  (https://www.getjobber.com/pricing/), read from the page's own HTML labels ("Available with Plus",
  "Not Available with Core", "Add-on"). AI summaries of that page disagreed with the raw HTML, so the raw
  HTML is used.
- **Feature detail** comes from Jobber's features page (https://www.getjobber.com/features/), individual
  feature pages, the public changelog (https://productupdates.getjobber.com/, pages 1–19, newest
  2026-10-07), and help-centre articles.
- **Changelog citations** give the page URL plus the post date, because the posts have no stable per-post
  links. Page 1 covers 2026-08-19 to 2026-10-07; `/page/2` covers 2026-06-25 to 2026-08-19; `/page/3` covers
  2026-04-13 to 2026-06-17; `/page/4` covers 2025-12-22 to 2026-03-26; `/page/5` covers 2025-10-16 to
  2025-12-16; `/page/6` covers 2025-09-04 to 2025-10-14; `/page/7` covers 2025-05-14 to 2025-08-28;
  `/page/8` covers 2025-01-16 to 2025-05-01.
- **Review sites:** Capterra, G2, Software Advice and GetApp blocked direct reading (HTTP 403 and a bot check,
  which was not bypassed). The review themes therefore come from search-engine excerpts of those pages and
  from Jobber's own public community forum. See Uncertainties.
- No account was created and nothing was signed up for.

---

## 1. Summary

- **Five price levels.** Jobber sells four plans plus add-ons:
  - **Core:** $29/mo billed annually, $49 monthly, 1 user.
  - **Connect:** from $99/mo annually, 1–15 users.
  - **Grow:** from $149/mo annually, 1–15 users.
  - **Plus:** from $399/mo annually, 5–15 users.
  - **Extra users:** $29/mo each.
  - **Add-ons:** Marketing Suite $99/mo, AI Receptionist $29/mo, Pipeline $49/mo. All three are included in
    Plus. Jobber Bookkeeping is a newer US-only add-on with no published price.
  - Source: https://www.getjobber.com/pricing/
- **Core is the basic office system.** It covers clients, requests, online booking, quotes, scheduling,
  invoices, online card/ACH payments, tips, Tap to Pay, progress invoicing, the client portal, a free
  website, basic reports and the mobile app.
- **Connect adds automation and the field team.** It adds automated reminders and follow-ups, automatic card
  charging, checklists (formerly "job forms"), route optimisation, GPS, time and expense tracking,
  QuickBooks/Xero/Zapier/Gusto, and custom fields.
- **Grow adds selling and profit tools.** It adds rich quotes with optional line items and markups, two-way
  SMS, the custom automation builder, job costing, automatic (geofenced) time tracking, "Find a Time", and
  photos on invoices.
- **Plus is for larger crews.** It adds crew scheduling and crew clock-in, breaks and labelled time,
  @mentions, a files library, receipt and supplier-invoice scanning, job-profit alerts, revenue goals, an AI
  custom-report builder, AI Voice for field workers, premium support, and the three add-ons included.
- **2025–2026 investment has gone into four areas.** AI, sales, crew/costing, and offline/mobile work:
  - **AI:** Receptionist, Voice, Chat, auto-drafted quotes, AI reports, receipt scanning, and a ChatGPT
    connector.
  - **Sales:** a Pipeline board and auto-archiving of stale requests and quotes.
  - **Crew and costing:** crew clock-in, labelled time, and profit alerts.
  - **Offline and mobile:** offline mode, Apple CarPlay and Android Auto.
- **Plan placement has moved before.** Several features were re-tiered between 2025 and 2026, for example
  route optimisation and Receptionist. Treat placements as a snapshot from 2026-10-08.

---

## 2. Feature catalog

Plan column key: **Core+** means every plan from Core up; **Connect+**, **Grow+** and **Plus** read the same
way. **Add-on** means paid extra on Core, Connect and Grow and included in Plus.

- **P** = https://www.getjobber.com/pricing/ (comparison table, read 2026-10-08)
- **F** = https://www.getjobber.com/features/
- **CLn** = https://productupdates.getjobber.com/page/n (CL1 = https://productupdates.getjobber.com/)

### 2.1 Clients & properties

| Feature                                  | What it does                                                                                                                                                       | Plan                                          | Source                                                                                          |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Client manager (CRM)                     | One profile per client with contact info, properties, job history and all past emails and texts.                                                                    | Core+                                         | https://www.getjobber.com/pricing/ ; https://www.getjobber.com/features/                        |
| Multiple properties per client           | A client can have several service addresses, each holding its own jobs, quotes and invoices.                                                                       | Core+ (implied by merge-properties post)      | https://productupdates.getjobber.com/page/2 (2026-08-19)                                        |
| Multiple client contacts                 | Add landlords, tenants, accounts-payable contacts and so on under one client, and choose which messages each receives (quotes, reminders, invoices).                 | Core+ ("Available on all plans")              | https://productupdates.getjobber.com/page/7 (2025-05-15)                                        |
| Property contacts                        | Contacts attached to a specific property for easier communication.                                                                                                  | Core+ ("Available on all plans")              | https://productupdates.getjobber.com/page/7 (2025-05-30)                                        |
| Lead management                          | Tag clients as leads to manage them apart from active clients. Syncs with Mailchimp and QuickBooks Online.                                                          | Core+                                         | https://www.getjobber.com/pricing/                                                              |
| Lead source tracking                     | Automatically tags the lead source on new clients, with a customisable source list.                                                                                 | Unconfirmed (shipped 2024–2025)               | https://productupdates.getjobber.com/page/8 (2025-01-16) ; https://productupdates.getjobber.com/ |
| Tags and bulk tagging                    | Tag, email or archive clients from the client list, including in bulk.                                                                                               | Unconfirmed                                   | https://productupdates.getjobber.com/page/14 (2023-12-13)                                       |
| Custom fields                            | Extra fields on records, which reports can filter and sort by.                                                                                                       | Connect+                                      | https://www.getjobber.com/pricing/                                                              |
| Merge duplicate clients and properties   | Merges duplicate records and moves their jobs, quotes, invoices, notes and tags across. A saved card does not transfer.                                              | Unconfirmed (no plan note)                    | https://productupdates.getjobber.com/page/2 (2026-08-19)                                        |
| Payment terms by client type             | Sets default net terms for residential and commercial clients, with a per-client override.                                                                          | Unconfirmed (no plan note)                    | https://productupdates.getjobber.com/page/3 (2026-04-21)                                        |
| Files and media library                  | Filterable gallery of every photo, video and document for a client, pulled from notes, checklists and forms.                                                        | Plus                                          | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/page/3 (2026-05-27)   |
| History / audit log                      | Shows who changed what, and when, on timesheets, requests, quotes and invoices.                                                                                     | Unconfirmed                                   | https://productupdates.getjobber.com/page/2 (2026-07-28)                                        |
| Data import (assisted)                   | Jobber imports your existing data for you, listed as a $499 value.                                                                                                  | Plus                                          | https://www.getjobber.com/pricing/                                                              |

### 2.2 Requests & online booking

| Feature                                | What it does                                                                                                                                                           | Plan                                               | Source                                                                                                   |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| Requests                               | One inbox for incoming work requests, which can be shared on a website, social media or the client portal, or entered by hand from a phone call.                        | Core+                                              | https://www.getjobber.com/pricing/ ; https://www.getjobber.com/features/                                 |
| Custom request forms                   | Several forms per business with step-by-step pages, brand colours, extra question types, a drag-and-drop builder and Google address autocomplete.                       | Core+ (forms); multi-form plan not stated          | https://productupdates.getjobber.com/page/6 (2025-10-09)                                                 |
| Smarter duplicate detection on requests | Matches an incoming request to an existing client or property.                                                                                                          | Unconfirmed                                        | https://productupdates.getjobber.com/page/6 (2025-10-09)                                                 |
| On-site assessments                    | Schedule a site visit from a request and assign it to a team member. Checklists can be attached to assessments.                                                         | Core+ (requests); assessment checklists Connect+   | https://www.getjobber.com/features/ ; https://productupdates.getjobber.com/page/3 (2026-04-27)            |
| Online booking                         | Clients book bookable services online. Jobber auto-schedules and auto-assigns an available team member, and sends email confirmations.                                  | Core+                                              | https://www.getjobber.com/pricing/ ; https://www.getjobber.com/features/                                 |
| Booking controls                       | Earliest availability, buffer between appointments, slot rules, service area and drive-distance limit, bookable team members, and quantity selection.                   | Core+ (with booking)                               | https://www.getjobber.com/features/ ; https://productupdates.getjobber.com/page/16 (2023-07-11) ; https://productupdates.getjobber.com/page/15 (2023-08-09) |
| Unified booking and request forms      | Booking is a section inside a request form, so a business can run several booking flows (for example assessments and jobs) with intake questions.                       | Core+ (with booking)                               | https://productupdates.getjobber.com/page/4 (2026-03-20)                                                 |
| Card on file at request or booking     | Optional payment-method field that saves a credit card when a client submits a request or books. Cards only, client portal only.                                       | Unconfirmed                                        | https://productupdates.getjobber.com/page/3 (2026-05-11)                                                 |
| Embeddable forms                       | Embed booking and request forms in WordPress and Wix sites, and add a booking link to a Google Business Profile.                                                        | Unconfirmed                                        | https://productupdates.getjobber.com/page/6 (2025-09-04) ; https://productupdates.getjobber.com/page/4 (2026-03-11) |
| Auto-archive stale requests and quotes | Moves sent quotes and requests to "Archived" after 90 days by default. The period can be edited.                                                                        | Connect+                                           | https://productupdates.getjobber.com/page/4 (2026-03-17)                                                 |
| Pipeline (sales board)                 | Board of every open request and quote by stage, with custom stages, an owner per deal, flags for overdue or quiet deals, and captured lost-deal reasons.                 | Add-on ($49/mo); included in Plus                  | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/page/3 (2026-04-14)            |

### 2.3 Quotes

| Feature                                      | What it does                                                                                                                                                         | Plan                                                     | Source                                                                                                                   |
| -------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Quoting                                      | Professional quotes from templates, with signature approval and calendar reminders, sent by SMS or email.                                                            | Core+                                                    | https://www.getjobber.com/pricing/ ; https://www.getjobber.com/features/                                                 |
| Quote templates                              | Start a quote from a saved template, on web and on mobile.                                                                                                            | Unconfirmed (mobile post implies broad)                   | https://productupdates.getjobber.com/page/8 (2025-01-30) ; https://productupdates.getjobber.com/page/6 (2025-09-15)      |
| Online approval / request changes            | The client approves, or asks for changes, in the client portal. The business is notified.                                                                             | Core+                                                    | https://www.getjobber.com/features/client-hub/                                                                           |
| Deposits on quotes                           | Require a deposit. The client clicks "Approve & Pay Deposit", signs by drawing or typing, and pays by card. Offline payments can also be recorded.                     | Unconfirmed (all plans with Jobber Payments, per help)    | https://help.getjobber.com/en/articles/deposits-on-quotes/ ; https://www.getjobber.com/features/                         |
| Automated quote follow-ups                   | Sends email or text reminders when a client has not answered a quote.                                                                                                 | Connect+                                                 | https://www.getjobber.com/pricing/                                                                                       |
| Auto-drafted quotes (AI)                     | Jobber AI drafts a quote from a request using past quotes and templates, automatically or on demand with "Draft for me".                                              | Connect+                                                 | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/page/6 (2025-10-06)                            |
| High-value quote alerts                      | Notifies you when a high-value quote is in play.                                                                                                                      | Connect+                                                 | https://www.getjobber.com/pricing/                                                                                       |
| Advanced quote customisation                 | Adds an introduction, image gallery, Google reviews and attachments to a quote. Reviews require the Reviews/Marketing Suite add-on.                                    | Grow+                                                    | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/page/6 (2025-09-15)                            |
| Optional line items and markups              | Clients tick optional add-ons and see the total update. Markups can be set on costs.                                                                                  | Grow+                                                    | https://www.getjobber.com/pricing/ ; https://www.getjobber.com/features/                                                 |
| Consumer financing (Wisetack)                | Shows monthly-payment financing offers on quotes. The contractor is paid upfront. Fixed 3.9% fee. US only, with eligibility rules on industry, reviews and revenue.     | All plans "except Lite" per help (Lite is a legacy plan) | https://help.getjobber.com/en/articles/jobber-and-wisetack-consumer-financing-integration/ ; https://www.getjobber.com/features/ |
| Home Depot catalogue in quotes               | Search more than 3M Home Depot products with live prices and local stock while building a quote.                                                                      | Core+ (US)                                               | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/page/4 (2026-02-25)                            |
| EagleView roof measurements                  | Imports aerial roof measurements into quotes.                                                                                                                         | Connect+ (US/CA)                                         | https://productupdates.getjobber.com/page/6 (2025-10-14)                                                                 |
| Products & services list                     | A saved item list used for quote, job and invoice line items and for material costs.                                                                                 | Core+ (implied)                                          | https://www.getjobber.com/features/ ; https://productupdates.getjobber.com/page/14 (2023-10-30)                          |
| AI "Rewrite"                                 | One-click rewrite of any message into a polished tone.                                                                                                                | Unconfirmed                                              | https://www.getjobber.com/features/put-ai-to-work/ ; https://productupdates.getjobber.com/page/12 (2024-04-15)           |

### 2.4 Jobs, visits, scheduling & dispatch

| Feature                                  | What it does                                                                                                                                                                | Plan                                                                 | Source                                                                                                         |
| ---------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| Jobs (one-off and recurring)             | Work orders with one or many visits, assignees, instructions and an invoicing schedule.                                                                                     | Core+                                                                | https://www.getjobber.com/features/ ; https://help.getjobber.com/en/articles/create-a-recurring-job/           |
| Multi-visit one-off jobs                 | Create many visits at once from a date range or chosen dates. Moving one visit offers to shift the rest.                                                                     | Unconfirmed                                                          | https://productupdates.getjobber.com/ (2026-08-19)                                                             |
| Recurring jobs: per-visit or fixed price | Recurring work billed per visit or at a fixed amount per period (for example monthly), with invoice reminders on a schedule.                                                 | Core+ (jobs); auto-charge Connect+                                    | https://help.getjobber.com/en/articles/create-a-recurring-job/                                                 |
| Scheduling calendar ("New Schedule")     | Day, week and month views, a map beside the calendar, drag-and-drop, 72 colours, status filters (including Overdue), and quote and invoice reminders on the calendar.          | Core+                                                                | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/page/4 (2026-03-13)                  |
| Unscheduled work and bulk reschedule     | Sort unscheduled items, shift many appointments by X days, and notify the client by email or text on reschedule.                                                            | Unconfirmed                                                          | https://productupdates.getjobber.com/page/2 (2026-07-24)                                                       |
| Arrival windows                          | Shows clients a time window instead of an exact time.                                                                                                                        | Unconfirmed                                                          | https://productupdates.getjobber.com/page/17 (2023-03-23)                                                      |
| Day sheets                               | Printable daily work sheet.                                                                                                                                                  | Unconfirmed                                                          | https://productupdates.getjobber.com/page/4 (2025-12-22)                                                       |
| Route optimisation                       | Builds routes for one person or the whole team over a day, several days or a week, with set start and end points and instant re-optimising.                                  | Connect+ per pricing table (Oct 2025 post said Core+)                | https://www.getjobber.com/pricing/ ; https://www.getjobber.com/features/route-optimization/ ; https://productupdates.getjobber.com/page/5 (2025-10-24) |
| GPS tracking / waypoints                 | Team locations on a map, assigning work to the nearest person, and waypoint trails for the day.                                                                              | Connect+                                                             | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/page/4 (2025-12-22)                  |
| Find a Time                              | Suggests slots using team availability and travel time.                                                                                                                      | Grow+                                                                | https://www.getjobber.com/pricing/                                                                             |
| Crew scheduling                          | Groups teammates into crews, assigns work to a crew in one action, and filters the calendar by crew.                                                                         | Plus                                                                 | https://www.getjobber.com/pricing/                                                                             |
| Team push notifications                  | Staff get a phone notification when today's schedule changes.                                                                                                               | Unconfirmed                                                          | https://www.getjobber.com/features/                                                                            |
| Checklists (formerly job forms)          | Custom checklists on jobs and assessments: checkboxes, dropdowns, text, required fields, photos and signatures. Can attach automatically.                                     | Connect+                                                             | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/page/3 (2026-04-27)                  |
| Job details and attachments              | Notes, photos and files on jobs, with image markup and fast multi-photo capture.                                                                                            | Core+                                                                | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/page/5 (2025-11-21)                  |
| Snow-removal "New Visits" tool           | Quickly creates visits on existing recurring jobs.                                                                                                                          | Unconfirmed                                                          | https://productupdates.getjobber.com/page/4 (2025-12-22)                                                       |
| Activity feed                            | A feed of team actions and client-portal activity.                                                                                                                           | Unconfirmed                                                          | https://www.getjobber.com/features/                                                                            |

### 2.5 Time tracking, expenses, job costing

| Feature                         | What it does                                                                                                                                                       | Plan     | Source                                                                                         |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------- | ---------------------------------------------------------------------------------------------- |
| Time tracking                   | Clock in and out of jobs and assessments in the app, with a Timesheets page (week and day views, error hints) and manual time entries.                              | Connect+ | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/page/3 (2026-04-13)  |
| Automatic time tracking         | Geofenced "location timers" start and stop visit timers, or send reminders, near the client's property.                                                            | Grow+    | https://www.getjobber.com/pricing/                                                             |
| Breaks and labelled time        | Tracks breaks (with an end-of-break reminder), drive time, office time, supply runs and custom labels.                                                             | Plus     | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/page/2 (2026-08-18)  |
| Crew time tracking              | A crew lead clocks the whole crew in or out at once. Each person still gets their own timesheet entry.                                                              | Plus     | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/ (2026-10-01)        |
| Expense tracking                | Log expenses against jobs with receipt photos, and track reimbursements.                                                                                            | Connect+ | https://www.getjobber.com/pricing/                                                             |
| Receipt capture (AI)            | Photograph a receipt and Jobber fills in vendor, date, total and tax. An admin matches it to a job.                                                                 | Plus     | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/ (2026-10-06)        |
| Supplier invoice scanning (AI)  | Upload or email-forward supplier invoices to a unique Jobber address. Jobber reads them and auto-links them to a job by job or PO number.                           | Plus     | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/ (2026-10-06)        |
| Job costing                     | Live job profit from line-item costs, labour (hours × labour rate) and expenses, plus a profitability report.                                                       | Grow+    | https://www.getjobber.com/pricing/ ; https://www.getjobber.com/features/                       |
| Job profit alerts               | Set a target margin per job or job type. Jobber flags jobs that fall below it.                                                                                      | Plus     | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/page/2 (2026-07-07)  |

### 2.6 Invoicing & payments

| Feature                                | What it does                                                                                                                                                         | Plan                                     | Source                                                                                                    |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Invoicing                              | One-click invoice from job details, sent by text or email, with templates and "time to invoice" reminders (after each visit, at job completion, or monthly).          | Core+                                    | https://www.getjobber.com/pricing/ ; https://www.getjobber.com/features/                                  |
| Batch invoicing                        | Creates invoices for many clients at once (one per client, split where tax rates differ) as drafts, then sends them in a batch.                                         | Core+ (listed under Invoicing)           | https://www.getjobber.com/pricing/ ; https://help.getjobber.com/en/articles/batch-create-invoices/        |
| Progress invoicing / payment schedules | Deposit plus milestone schedule shown on the quote and each invoice. The remaining balance updates automatically.                                                     | Core+                                    | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/page/6 (2025-09-25)             |
| Credit card processing                 | Online card payments at 2.9% + 30¢ (US, Canada, UK).                                                                                                                  | Core+                                    | https://www.getjobber.com/pricing/                                                                        |
| ACH bank payments                      | Bank payments at 1% (US).                                                                                                                                             | Core+                                    | https://www.getjobber.com/pricing/                                                                        |
| Tap to Pay                             | The phone becomes a card reader at 2.7% + 30¢. Tips can be added.                                                                                                     | Core+                                    | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/page/5 (2025-10-16)             |
| Tip collection                         | Client adds a tip when paying online in the client portal.                                                                                                            | Core+                                    | https://www.getjobber.com/pricing/                                                                        |
| Instant payouts                        | Funds in seconds, weekends included, for a 1% fee. Standard payout takes about two days.                                                                              | Core+                                    | https://www.getjobber.com/pricing/ ; https://www.getjobber.com/features/                                  |
| Automatic payments (card on file)      | Charges a saved card or ACH automatically on the recurring-job invoice schedule (US/CA).                                                                              | Connect+                                 | https://www.getjobber.com/pricing/ ; https://help.getjobber.com/en/articles/automatic-payments/           |
| Automated invoice follow-ups           | Email or text reminders with a one-click pay link.                                                                                                                    | Connect+                                 | https://www.getjobber.com/pricing/                                                                        |
| Images and attachments on invoices     | Attach photos, videos, contracts, permits and warranties. Plus can pick from existing files.                                                                         | Grow+                                    | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/page/3 (2026-06-10)             |
| Refunds                                | Partial or full refunds.                                                                                                                                              | Unconfirmed                              | https://productupdates.getjobber.com/page/11 (2024-05-31)                                                 |
| Surcharging / card fees                | **Not offered.** Jobber has no automated surcharge. Users add a manual line item instead.                                                                             | n/a                                      | https://community.getjobber.com/discussions/invoicing-getting-paid/easily-add-processing-fees-to-jobs-/6706 (community, not official docs) |
| Jobber Capital                         | Pre-approved business financing offers.                                                                                                                               | Core+                                    | https://www.getjobber.com/pricing/                                                                        |
| Jobber Bookkeeping                     | A dedicated bookkeeper reconciles and closes the books monthly from synced bank and Jobber data. US only.                                                             | Add-on (price unconfirmed)               | https://productupdates.getjobber.com/ (2026-10-05)                                                        |

### 2.7 Client Hub (customer portal)

| Feature                       | What it does                                                                                                           | Plan                                | Source                                                                                     |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------- | ----------------------------------- | ------------------------------------------------------------------------------------------ |
| Client hub                    | Self-serve portal where a client can request work, approve quotes or ask for changes, see past and upcoming visits (with assigned team photos), pay invoices and deposits with a tip, and refer friends. | Core+                               | https://www.getjobber.com/pricing/ ; https://www.getjobber.com/features/client-hub/        |
| Save card in hub              | Save a card at request or booking time.                                                                                | Unconfirmed                         | https://productupdates.getjobber.com/page/3 (2026-05-11)                                   |

### 2.8 Communications

| Feature                              | What it does                                                                                                                                                        | Plan                                     | Source                                                                                                        |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| Automated client notifications       | Visit reminders, booking confirmations and job follow-ups (thank-you, feedback, review ask) by email or text.                                                        | Connect+                                 | https://www.getjobber.com/pricing/ ; https://www.getjobber.com/features/                                      |
| On-my-way texts                      | One-tap "on the way" or "running late" text, with a callback number. Live-tracking links come through Force Fleet.                                                  | Unconfirmed (bundled with notifications) | https://www.getjobber.com/features/ ; https://productupdates.getjobber.com/page/7 (2025-08-21)                |
| Email and text templates             | Editable templates per message type.                                                                                                                                | Unconfirmed                              | https://www.getjobber.com/features/                                                                           |
| Two-way text messaging               | Dedicated business number and a shared Message Center (choose who is notified). MMS up to 5 images per message. US, Canada and UK. Not available during the trial. | Grow+                                    | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/page/5 (2025-10-28) ; https://help.getjobber.com/hc/en-us/articles/14711336911383-Two-Way-Text-Messaging-FAQ |
| Communication history                | Every email and text, including automated ones, shown on the client.                                                                                                 | Core+                                    | https://www.getjobber.com/features/                                                                           |
| Team @mentions                       | Tag teammates in notes, with a mentions feed and read receipts.                                                                                                      | Plus                                     | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/ (2026-08-24)                       |
| Mobile push notifications            | Alerts for new requests, viewed quotes and inbound texts.                                                                                                            | Unconfirmed                              | https://www.getjobber.com/features/                                                                           |

### 2.9 Automations & follow-ups

| Feature                      | What it does                                                                                                                         | Plan     | Source                                                                                                   |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ | -------- | -------------------------------------------------------------------------------------------------------- |
| Built-in automations         | Quote follow-ups, invoice follow-ups, visit reminders, job follow-ups and auto-archive.                                               | Connect+ | https://www.getjobber.com/pricing/                                                                       |
| Custom automation builder    | If-this-then-that rules for client and internal communications, tagging and quote handling.                                           | Grow+    | https://www.getjobber.com/pricing/ ; https://www.getjobber.com/features/automate-repetitive-tasks/       |
| AI-suggested automations     | Jobber AI recommends when to switch automations on.                                                                                   | Unconfirmed | https://www.getjobber.com/features/put-ai-to-work/ ; https://productupdates.getjobber.com/page/6 (2025-10-06) |

### 2.10 Marketing

| Feature                         | What it does                                                                                                                                                  | Plan                                     | Source                                                                                                              |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| Website                         | AI-pre-filled, multi-page site with SEO, custom domain, gallery, request forms, Google reviews and a Receptionist chat widget. Free on all plans worldwide.    | Core+                                    | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/page/6 (2025-09-24) ; https://productupdates.getjobber.com/page/4 (2026-03-09) |
| Marketing Suite (bundle)        | AI marketing plan, a marketing dashboard, and the Reviews, Campaigns, Referrals, Job Showcase, Social Posting (Facebook and Instagram), Google Manager and Brand Central tools below. US, Canada and UK. | Add-on ($99/mo); included in Plus        | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/page/3 (2026-06-17) ; https://productupdates.getjobber.com/ (2026-10-01) |
| Reviews                         | Automatic Google review requests (job close, visit complete or invoice paid) with follow-ups, a reviews dashboard, AI replies and competitor comparison.      | Part of Marketing Suite                  | https://www.getjobber.com/features/ ; https://productupdates.getjobber.com/page/7 (2025-08-26)                      |
| Email campaigns                 | Branded templates, an AI campaign generator, segments (city, lead source, quote status and more), automated campaigns and revenue reporting.                  | Part of Marketing Suite                  | https://www.getjobber.com/features/ ; https://productupdates.getjobber.com/page/4 (2026-01-23)                      |
| Referrals                       | Referral links, automatic credit applied to the referrer's next invoice, a referral campaign, and tracking and reporting.                                     | Part of Marketing Suite                  | https://www.getjobber.com/features/                                                                                 |
| Google Business Profile connect | Optimises the profile from Jobber data and adds a booking link.                                                                                              | Unconfirmed                              | https://productupdates.getjobber.com/page/3 (2026-04-20)                                                            |
| Direct mail                     | Postcards through the PostcardMania integration (US).                                                                                                         | Integration                              | https://productupdates.getjobber.com/page/7 (2025-08-28)                                                            |
| Marketing attribution report    | Shows which marketing brings in revenue.                                                                                                                       | Unconfirmed                              | https://productupdates.getjobber.com/page/7 (2025-07-30)                                                            |

### 2.11 Reports & insights

| Feature                         | What it does                                                                                                     | Plan     | Source                                                                                         |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------- | -------- | ---------------------------------------------------------------------------------------------- |
| Insights dashboard              | Business health metrics, workflow stage counts and dollar values, appointment progress and payout tracking.     | Core+    | https://www.getjobber.com/pricing/ ; https://www.getjobber.com/features/                       |
| Financial reporting             | Projected income, taxation, payments, invoices and aged receivables.                                             | Core+    | https://www.getjobber.com/pricing/ ; https://www.getjobber.com/features/field-service-reporting/ |
| Client reporting                | Client metrics and behaviour.                                                                                    | Core+    | https://www.getjobber.com/pricing/                                                             |
| Work reporting                  | Job progress, visits and timesheets.                                                                             | Core+    | https://www.getjobber.com/pricing/                                                             |
| Expense reporting               | All tracked expenses.                                                                                            | Connect+ | https://www.getjobber.com/pricing/                                                             |
| Salesperson reporting           | Quote-to-job performance per salesperson.                                                                         | Connect+ | https://www.getjobber.com/pricing/                                                             |
| Team productivity reporting     | Output per employee.                                                                                             | Connect+ | https://www.getjobber.com/pricing/                                                             |
| Revenue goals                   | Annual target broken into weeks and months, with a pacing bar and a comparison to last year.                     | Plus     | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/page/4 (2026-03-26)  |
| Custom report builder (AI)      | Describe a report in words. AI builds it from live data with charts, and it can be saved and refreshed.          | Plus     | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/ (2026-10-01)        |

### 2.12 Team, permissions, GPS, timesheets, payroll

| Feature                  | What it does                                                                                                                                                 | Plan                           | Source                                                                                       |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------ | -------------------------------------------------------------------------------------------- |
| User permissions         | Preset levels (Limited Worker, Worker, Dispatcher, Manager), plus Admin and fully custom permissions.                                                         | Unconfirmed (multi-user plans) | https://help.getjobber.com/es/articles/user-permissions/ ; https://www.getjobber.com/features/ |
| Users per plan           | Core 1 user. Connect and Grow 1, 5, 10 or 15. Plus 5, 10 or 15. Extra users $29/mo each.                                                                     | per plan                       | https://www.getjobber.com/pricing/                                                           |
| Gusto payroll sync       | Timesheets and reimbursable expenses sync to Gusto.                                                                                                          | Connect+                       | https://www.getjobber.com/pricing/                                                           |
| SequiPay payroll sync    | Approved timesheets flow into SequiPay payroll (US).                                                                                                         | Connect+                       | https://productupdates.getjobber.com/page/2 (2026-06-30)                                     |
| Fleet GPS integrations   | Live vehicle location from Azuga and Force Fleet.                                                                                                            | Connect+                       | https://productupdates.getjobber.com/page/2 (2026-06-25) ; https://productupdates.getjobber.com/page/8 (2025-03-20) |
| Onboarding               | Connect: 2 sessions. Grow: 3 sessions. Plus: unlimited white-glove onboarding and Premium Support.                                                           | per plan                       | https://www.getjobber.com/pricing/                                                           |

### 2.13 Mobile app & offline

| Feature                       | What it does                                                                                                         | Plan        | Source                                                                                       |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------- | ----------- | -------------------------------------------------------------------------------------------- |
| iOS and Android app           | Runs daily operations from the phone. Available in Spanish for non-admin team members.                               | Core+       | https://www.getjobber.com/pricing/                                                           |
| Offline mode                  | Fill in checklists, view visits and notes, and track time without signal. Changes sync when back online.             | Unconfirmed | https://productupdates.getjobber.com/page/4 (2026-03-18)                                     |
| Apple CarPlay / Android Auto  | Next visit, directions, calling the client and on-my-way texts from the car display.                                  | Unconfirmed | https://productupdates.getjobber.com/page/2 (2026-08-17)                                     |
| Dark mode                     | Dark theme.                                                                                                          | Unconfirmed | https://productupdates.getjobber.com/page/10 (2024-08-26)                                     |

### 2.14 Integrations

| Feature                         | What it does                                                                                                                                                                                                                 | Plan                                   | Source                                                                                                    |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| App Marketplace                 | More than 100 apps.                                                                                                                                                                                                          | Core+                                  | https://www.getjobber.com/pricing/                                                                        |
| QuickBooks Online sync          | Syncs clients, products, timesheets, invoices, payments, refunds, tips and payouts. **No QuickBooks Desktop sync** (client-list import only).                                                                                 | Connect+                               | https://www.getjobber.com/pricing/ ; https://www.getjobber.com/features/field-service-reporting/ ; https://help.getjobber.com/es/articles/quickbooks-integration-faqs/ |
| Xero sync                       | Syncs clients, products and services, and invoices with payments.                                                                                                                                                           | Connect+                               | https://www.getjobber.com/pricing/ ; https://help.getjobber.com/en/articles/jobber-and-xero-integration/  |
| Zapier                          | Connects to more than 7,000 apps.                                                                                                                                                                                           | Connect+                               | https://www.getjobber.com/pricing/                                                                        |
| Public API                      | Open API, with an "API Tour" ($99 value) included in Plus. Whether lower plans get API access is not stated.                                                                                                                 | Plus (tour); API itself unconfirmed    | https://www.getjobber.com/pricing/                                                                        |
| ChatGPT connector               | Ask about or update Jobber data from ChatGPT.                                                                                                                                                                               | Unconfirmed                            | https://productupdates.getjobber.com/ (2026-10-07)                                                        |
| Notable marketplace apps        | Lead sources: Angi, Thumbtack, Oply. Website forms: HighLevel, WordPress, Wix. Phone and calls: CallRail, OpenPhone. Photos: CompanyCam. Inventory: Ply. Contracts: DocuSign. Reviews: Birdeye. Analytics: Google Analytics. Payroll: Gusto, SequiPay. Measurements: EagleView. Direct mail: PostcardMania. | varies (several Connect+)              | https://productupdates.getjobber.com/page/4 ; https://productupdates.getjobber.com/page/6 ; https://productupdates.getjobber.com/page/8 ; https://productupdates.getjobber.com/page/9 ; https://productupdates.getjobber.com/page/11 ; https://productupdates.getjobber.com/page/15 ; https://www.getjobber.com/features/ |

### 2.15 AI features

| Feature                              | What it does                                                                                                                                                                                                                                         | Plan                                                     | Source                                                                                                      |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| Jobber AI Chat (formerly Copilot)    | Assistant on web and mobile for business coaching, data questions, marketing content and product help.                                                                                                                                               | Core+                                                    | https://www.getjobber.com/pricing/ ; https://help.getjobber.com/en/articles/jobber-ai-voice-and-chat-beta/ ; https://productupdates.getjobber.com/page/10 (2024-10-01) |
| Jobber AI Voice                      | Hands-free control of more than 100 tasks in the app: create and send quotes, invoices, directions, client updates and timers.                                                                                                                       | Core+ (owner/admin)                                      | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/page/5 (2025-10-27)               |
| AI Voice for field workers           | The whole team can use Voice for notes in any language (with translation), job updates and timers.                                                                                                                                                  | Plus                                                     | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/page/2 (2026-06-26)               |
| AI Receptionist                      | 24/7 calls and texts. It answers questions from account data, creates requests, books visits within booking rules, and takes messages as tasks. It recognises existing clients and can reschedule or cancel. It texts back callers who hang up, transfers on chosen keywords, and keeps summaries, transcripts and recordings. Works through call forwarding. | Add-on ($29/mo); included in Plus; website chat free      | https://www.getjobber.com/pricing/ ; https://www.getjobber.com/features/ai-receptionist/ ; https://productupdates.getjobber.com/page/5 (2025-11-17, 2025-12-12) |
| Receptionist Companion               | Listens on calls you answer yourself and drafts the request or booking. Marked "coming soon".                                                                                                                                                        | Coming soon                                              | https://www.getjobber.com/features/ai-receptionist/                                                         |
| AI-powered tools elsewhere           | Auto-drafted quotes, Rewrite, campaign generator, AI review replies, receipt and invoice scanning, and the custom report builder (see their rows above).                                                                                             | see rows                                                 | see rows                                                                                                    |

### 2.16 Add-ons

| Add-on            | Price                    | Contents                                                                                       | Source                                                                    |
| ----------------- | ------------------------ | ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| Marketing Suite   | $99/mo (in Plus)         | Reviews, Campaigns, Referrals, Job Showcase, Social Posting, Google Manager, AI marketing plan | https://www.getjobber.com/pricing/ ; https://productupdates.getjobber.com/page/3 |
| AI Receptionist   | $29/mo (in Plus)         | See 2.15                                                                                       | https://www.getjobber.com/pricing/                                        |
| Pipeline          | $49/mo (in Plus)         | See 2.2                                                                                        | https://www.getjobber.com/pricing/                                        |
| Jobber Bookkeeping| Unconfirmed (US only)    | Managed monthly bookkeeping                                                                    | https://productupdates.getjobber.com/ (2026-10-05)                        |

---

## 3. Contractor review themes

Caveat: Capterra, G2, Software Advice and GetApp returned 403 or a bot check. The themes below come from
search-engine excerpts of those review pages and from Jobber's community forum. The quoted fragments are
search excerpts, not verbatim text read on the page.

**What contractors praise (must-haves)**

- **Ease of use and one place for everything.** Reviewers like having scheduling, invoicing and client
  communication together. Sources: https://www.g2.com/products/jobber/reviews ;
  https://www.capterra.com/p/127994/Jobber/reviews/
- **Client hub self-service.** Clients approve quotes and pay invoices themselves, and an approved quote
  "converts straight into a job with no re-entry". Source: https://www.g2.com/products/jobber/reviews
- **Automated follow-ups.** Repeated as a top value in reviews and in Jobber's own customer quotes. Sources:
  https://www.capterra.com/p/127994/Jobber/reviews/ ;
  https://www.getjobber.com/features/automate-repetitive-tasks/
- **Online payments and fast payouts; route optimisation.** Both praised, especially by lawn care
  businesses. Source: https://www.getjobber.com/features/route-optimization/ (customer quote on the
  vendor page)

**What contractors complain about or say is missing**

- **Price climbs with users, and features are gated to higher tiers or add-ons.** Sources:
  https://www.softwareadvice.com/field-service/jobber-profile/reviews/ ;
  https://www.capterra.com/p/127994/Jobber/reviews/
- **Card fees feel high, and there is no automated surcharge.** Sources:
  https://www.capterra.com/p/127994/Jobber/reviews/ ;
  https://community.getjobber.com/discussions/invoicing-getting-paid/easily-add-processing-fees-to-jobs-/6706
- **No proper flat-rate price book.** Users want categories and subcategories and mobile price-book access.
  Sources: https://community.getjobber.com/discussions/quoting/add-category--subcategory-structure-to-pricebook-items-for-faster-field-quoting/7231/replies/7235 ;
  https://community.getjobber.com/discussions/invoicing-getting-paid/get-products-and-services-in-separate-lines-on-the-invoice-and-get-a-price-book-/3773
- **Only basic inventory, and no native purchase orders.** Users rely on Ply or Arka. Source:
  https://community.getjobber.com/discussions/operations-forum/inventory-management/4964/replies/4981
- **No native membership or service-agreement tracking.** Users work around it with tags and custom
  fields. Source: https://community.getjobber.com/discussions/operations-forum/membership-tracking-and-pricing/16201
- **Limited quote and line-item formatting.** Reviewers say there is "no ability to customize how quotes
  look". Source: https://www.capterra.com/p/127994/Jobber/reviews/
- **Confirmation emails can't list the services for the visit.** Source:
  https://www.softwareadvice.com/field-service/jobber-profile/reviews/
- **The mobile app does less than desktop.** It is slow with photos, and historically did not work offline;
  offline mode shipped in March 2026. Sources: https://www.softwareadvice.com/field-service/jobber-profile/reviews/ ;
  https://productupdates.getjobber.com/page/4
- **QuickBooks sync problems.** Tax and payment mismatches; no QuickBooks Desktop. Sources:
  https://www.capterra.com/p/127994/Jobber/reviews/ ;
  https://help.getjobber.com/es/articles/quickbooks-integration-faqs/
- **Schedule and map confusion, and reporting depth and export limits.** Source:
  https://www.capterra.com/p/127994/Jobber/reviews/

---

## 4. Housecall Pro standard features that Jobber lacks or gates

Housecall Pro (HCP) plans: Basic $59/mo annual (1 user), Essentials $149 (5 users), MAX $299 (8 users, +$35
per user). Source: https://www.housecallpro.com/pricing/

| HCP feature                                   | HCP plan                         | Jobber position                                                                                                | Sources |
| --------------------------------------------- | -------------------------------- | -------------------------------------------------------------------------------------------------------------- | ------- |
| **Price book** and flat-rate pricing with margins | Price book on Basic; flat-rate on Essentials | Jobber has only a products & services list; users ask for a real price book                    | https://www.housecallpro.com/pricing/ ; community links in §3 |
| **Job costing on the entry plan**             | Basic                            | Jobber has it on Grow+ only                                                                                    | https://www.housecallpro.com/pricing/ ; https://www.getjobber.com/pricing/ |
| **Review management on the entry plan**       | Basic                            | Jobber: paid Marketing Suite add-on, or Plus                                                                   | same |
| **Consumer financing on all plans**           | All                              | Jobber also offers it (Wisetack); roughly parity                                                               | same + Wisetack help link |
| **Recurring service plans / maintenance agreements** | MAX                        | Jobber has recurring jobs but no membership or agreement object                                                | https://www.housecallpro.com/pricing/ ; https://community.getjobber.com/discussions/operations-forum/membership-tracking-and-pricing/16201 |
| **Sales proposal tool** (visual, side-by-side options) | MAX ($40 value)          | Jobber: advanced quote customisation and optional line items (Grow+); no side-by-side option comparison found  | https://www.housecallpro.com/pricing/ |
| **Technician commissions**                    | Essentials                       | No Jobber commission feature found (unconfirmed absence)                                                       | https://www.housecallpro.com/pricing/ |
| **Photo reports with annotations**            | Essentials                       | Jobber has image markup, but a client-facing photo report was not found                                        | https://www.housecallpro.com/pricing/ ; https://productupdates.getjobber.com/page/5 |
| **Native payroll**                            | Add-on                           | Jobber offers sync only (Gusto, SequiPay)                                                                      | same |
| **VoIP phone system ("Voice")** with call flows | Add-on                         | Jobber: integrations only (OpenPhone, CallRail); Receptionist is AI only                                       | https://www.housecallpro.com/pricing/ ; https://productupdates.getjobber.com/page/8 |
| **Vehicle GPS and dashcams**                  | Add-on                           | Jobber: phone GPS plus Azuga and Force Fleet integrations                                                      | same |
| **Multi-channel campaigns** (text, email, postcards) | Add-on                    | Jobber Campaigns are email only; postcards through the PostcardMania integration                               | https://www.housecallpro.com/pricing/ ; https://www.getjobber.com/features/ |
| **Expense cards and fee-free mobile check deposit** | Listed in HCP menu and FAQ | No Jobber equivalent found                                                                                    | https://www.housecallpro.com/pricing/ |
| **Card rate "as low as 2.59%"**               | All                              | Jobber 2.9% + 30¢                                                                                              | same |
| **Offline viewing**                           | All                              | Jobber now has offline mode (2026-03)                                                                          | same |

Things where Jobber is ahead of, or equal to, HCP on the cheaper tiers:

- Zapier is on Connect+ in Jobber but MAX only in HCP. Source: https://www.housecallpro.com/pricing/
- Jobber includes a free website on every plan, where HCP sells websites as an add-on.
- Route optimisation is MAX only in HCP. Jobber's pricing table shows it on Connect+.

---

## 5. Uncertainties

- **Plan placement for "Unconfirmed" rows.** Many changelog posts carry no plan note, for example merge
  duplicates, history log, offline mode, CarPlay, multi-visit jobs, payment terms and refunds. Do not assume
  they are on Core.
- **Route optimisation.** The October 2025 changelog says Core, Connect, Grow and Plus. The current pricing
  table marks Routing "Not Available with Core". The pricing table (2026-10-08) is the more recent source.
- **Receptionist.** A December 2025 post says "included in Plus, or add-on to Grow". The current pricing
  table shows it as an add-on on Core, Connect and Grow. The website chat version is described as free.
- **Earlier AI summary of the pricing page was wrong.** It claimed GPS, two-way SMS and job costing are on
  every plan. The raw HTML contradicts this, and the raw HTML is used here. Third-party pricing articles
  (getonecrew, costbench, toolradar) show older prices and were not used.
- **Two-way SMS limits** (message caps, extra charges) were not found in public docs.
- **Jobber Bookkeeping** price is not published.
- **Public API** access by plan is unclear. Only the Plus "API Tour" is listed.
- **Permissions** depth (custom permissions) is described only in one help-article search excerpt; the full
  article was not read.
- **Commissions, purchase orders and inventory** are judged absent from community threads and the lack of
  any feature page. That is evidence of absence, not an official statement.
- **Review sites** could not be read directly (403 and bot verification), so the quotes in §3 are
  search-engine excerpts and their exact wording and dates are unverified. Review counts and star ratings
  were not confirmed.
- **Country limits.** Payments are US, Canada and UK; ACH is US only; Marketing Suite is US, Canada and UK;
  Bookkeeping, Home Depot and PostcardMania are US only. Anything for other markets is unconfirmed.
- **Recency.** Prices and placements are a 2026-10-08 snapshot. Jobber re-tiers often (for example the
  route optimisation and Receptionist changes above, and Copilot being renamed Jobber AI). The free trial runs on Grow.
