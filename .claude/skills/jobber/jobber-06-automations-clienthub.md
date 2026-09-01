# Jobber Reference — Automations & Client Hub

> Source: Jobber Help Center (behavior, cited) + `JobberJson.md` (schema, where it exists). Part of the Jobber
> competitor reference set — see `jobber-00-overview-lifecycle.md` for the index/lifecycle. Plain English;
> **(unverified)** marks anything not confirmed by schema or help center.
>
> **Schema-coverage caveat (important):** Jobber's **Automations** feature is **not represented in the public
> GraphQL schema** — there are _no_ `Automation`, `Trigger`, `Action`, `Workflow`, or `Campaign` object/enum
> types in `JobberJson.md` (grep confirms only `ICalendarRule`, unrelated). Automations are a **web-app-only**
> feature; everything in §1–§2 is from the help center. **Client Hub** is likewise a client-facing web surface,
> not a first-class API object — but the schema _does_ expose the plumbing it runs on: `clientHubUri` /
> `clientHubViewedAt` / `dateViewedInClientHub` on Quote/Invoice, `OnlineBookingConfiguration`,
> `SelfServeBooking`, `BookingType` (covered in `jobber-01`/`jobber-02`), and the `SelfServeBooking` enum here.

Two customer-facing growth systems sit on top of the core lifecycle:

1. **Automations** — Jobber does repetitive admin for you: chasing quotes/invoices, sending visit reminders,
   drafting quotes from requests, and flagging high-value opportunities — "so you can focus on running your
   business" (help center). Split into **built-in automations** (toggle on/off) and the newer **Custom
   Automation Builder** (trigger → condition → action).
2. **Client Hub** — a self-serve, mobile-friendly portal where a client can approve quotes, pay invoices,
   view appointments, print receipts, and request more work — "all in one place."

---

## 1. Automations

### 1.1 Built-in automations (help center)

These ship as named features you toggle/configure; each sends **email or text**, matching the channel the
original document was sent on where applicable.

| Automation                       | What it does                                                                                                                | Key rule                                                                                                                   |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| **Quote follow-ups**             | Auto-remind a client who hasn't responded to a quote in **awaiting-response** status.                                       | Up to **two** follow-ups; gated per-client by `receivesQuoteFollowUps` (see `jobber-01`). [[quote approvals]]              |
| **Invoice follow-ups**           | Dunning: remind a client whose invoice is **past due** to pay.                                                              | Up to **two**; you set **days-after-due**, **max 90 days**. Suppressed if automatic payments are on. [[invoice reminders]] |
| **Job follow-ups**               | Email sent (auto or manual) **on job completion** — feedback, referral survey, future-work discount, etc.                   | Content is up to the SP. [[job follow-ups]]                                                                                |
| **Visit / assessment reminders** | Remind the client of an upcoming **visit or assessment**, on a schedule or sent manually.                                   | Separate email + text templates. [[assessment and visit reminders]]                                                        |
| **"On My Way" messages**         | From the Jobber app, tech sends a client an _"on my way, ~N minutes"_ text for the day's appointment.                       | Manual, per-visit, tech picks the ETA. [[assessment and visit reminders]]                                                  |
| **Draft quote from request**     | Auto-create a **draft quote** when a client submits a request.                                                              | Named in the Automations overview. [[automations]]                                                                         |
| **High-value opportunity alert** | Alerts _you_ about high-value opportunities.                                                                                | Named in the Automations overview (internal alert). [[automations]]                                                        |
| **Review requests**              | Post-payment SMS asking for a **Google review** (gated by `allowReviewRequest` / `nextDateToSendReviewSms` on the invoice). | Reputation domain — later file.                                                                                            |

### 1.2 Custom Automation Builder (help center) — [[custom automation builder]]

A rules engine on **select plans** (Gear → **Settings → Automations → New Automation**). Three parts:

1. **Trigger — "When this happens."** The event that starts it. Day-offset triggers (e.g. _X days after a
   quote is sent or approved_) allow a **maximum of 90 days**. The documented catalog is date-passed/date-
   arrives around quotes being sent/approved and invoices being paid/due. Time-of-day: **"in the morning" =
   8 AM local**, **"in the evening" = 7 PM local**.
2. **Condition(s) — "And only if."** Criteria that must be true for it to run. **Max 6 conditions** per
   automation. Documented conditions are quote/invoice status, client tag, and line item.
3. **Action — "Then do this."** What happens. Documented actions:
   - **Notify** the client via **email or text** (sent in the **same method** the original quote/invoice was
     sent).
   - **Add tag** to the client.
   - **Update status** — archive a quote; **only available on quotes.**

**Lifecycle rules:**

- Save → the automation goes **live**. Deactivate via the automation's **More → Deactivate**.
- **Not retroactive** — an automation only fires on items that meet the trigger **after** it's created; it
  never back-applies to past items.

#### Current official verification — 2026-08-31

Jobber's current official
[Custom Automation Builder](https://help.getjobber.com/en/articles/custom-automation-builder/) article
(updated 2025-08-01) explicitly lists this builder catalog:

- **Confirmed triggers:** date-passed (`X days after` a quote is **sent or approved**, or an invoice is
  **paid or due**) and date-arrives (the **morning or evening when** those same milestones occur). These
  are scheduled milestone triggers, not a documented catalog of arbitrary lifecycle events. Day offsets
  have a **90-day maximum**; morning is **8 AM local** and evening is **7 PM local**.
- **Confirmed conditions:** quote status (`Awaiting response`, `Changes requested`, `Approved`,
  `Converted`, `Archived`), invoice status (`Due`, `Paid`), client tag inclusion/exclusion, and line-item
  inclusion/exclusion. An automation has at most **six conditions**.
- **Confirmed actions:** notify the client, add a client tag, or change a quote's status to **Archived**.
  Status update is quote-only. A notification uses the same method as the original quote/invoice: email
  stays email and text stays text.
- **Activation/lifecycle:** Save sets the automation live; More → Deactivate stops it. Rules are **not
  retroactive**: Jobber describes an `X days` rule as acting when an item reaches that exact age, not on
  already-older items when the rule is created.

Quote-event parity must be stated carefully:

| Proposed event             | Current official evidence                                                                                                                                                                                                                  | Builder-trigger verdict                                                                                                                              |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Customer viewed quote      | Jobber records the **first client view** in its [Activity Feed](https://help.getjobber.com/en/articles/activity-feed/).                                                                                                                    | **Unverified as a Custom Automation Builder trigger**; it is absent from the official trigger list.                                                  |
| Customer approved quote    | Approval changes the quote to Approved and produces admin activity/push notifications; `sent or approved` is also a supported scheduled trigger milestone. See [Quote Approvals](https://help.getjobber.com/en/articles/quote-approvals/). | **Confirmed only as the approved milestone for the documented date-based triggers**; an immediate `Customer approved` builder trigger is unverified. |
| Customer requested changes | Jobber changes the status to Changes Requested, emails the designated quote-reply team member, and creates an admin activity-feed notification. See [Quote Approvals](https://help.getjobber.com/en/articles/quote-approvals/).            | **Confirmed as a condition/status, not as a trigger**; it is absent from the official trigger list.                                                  |

Built-in quote follow-ups are separately confirmed in Jobber's current
[Automations](https://help.getjobber.com/en/articles/automations/) documentation (updated 2026-08-06):

- Connect Plan and above receive **two** built-in follow-up automations, allowing up to **two reminders**
  while a quote remains in **Awaiting Response**.
- Each follow-up configures a title, editable message, and delay after the original send (maximum
  **90 days**). It sends at the same local time of day and by the same method as the original quote.
- Original recipients receive follow-ups only when `outstanding quote follow-ups` is enabled in that
  client/contact's communication settings.
- Built-in cards can be deactivated and later activated. This article does not document quote-view,
  approval, or changes-requested as built-in follow-up triggers; the built-in schedule is based on days
  since the quote was sent and the Awaiting Response state.

### 1.3 Related, but _not_ the Custom Automation Builder

- **Campaigns (Marketing Tools)** — bulk email marketing to client segments; separate from automations.
- **Zapier integration** — connect Jobber events to 1000s of external apps ("Task Automation Powered by
  Zapier") when a rule needs to leave Jobber. [[jobber and zapier]]
- **Social/marketing items** — the schema _does_ model marketing posts (`SocialMediaPost`,
  `SocialMarketingItem*`, Google Business Profile / Facebook channels), i.e. the Marketing Suite — distinct
  from lifecycle automations.

---

## 2. Client Hub

### 2.1 What clients can do (help center) — [[what clients see in client hub]]

Client Hub is _"a self-serve, online experience that allows clients to approve quotes, check appointment
details, pay invoices, print receipts, or request more work — all in one place."_ Mobile-friendly (works on
computer or phone).

| Capability                           | Detail                                                                                                                                                        |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Approve quotes**                   | View a quote, **approve** (sign — draw/type), or **request changes**; **pay the deposit** if one is required ("Approve and Pay Deposit"). See `jobber-03` §5. |
| **Pay invoices**                     | With **Jobber Payments** (or a 3rd-party payment integration), pay invoices online; **add a tip**. See `jobber-05` §5.6.                                      |
| **View appointments**                | See **all past** appointments and the **next five upcoming**.                                                                                                 |
| **Book / request more work**         | **New Request** tab → fill the request form → creates a request (and, with **Online Booking**, can create a **job** or **assessment** directly — see §2.3).   |
| **Print receipts / billing history** | Print receipts and see their billing history.                                                                                                                 |
| **Contact us**                       | The nav's _Contact Us_ shows the SP's full address + contact info (from the branding page).                                                                   |

### 2.2 Client Hub settings & branding (help center) — [[client hub settings]]

- Access: **Gear → Settings → Client hub.**
- **Quotes & Invoices toggle:** ON = a logged-in client sees **all** quotes/invoices you've sent (nav items).
  OFF = they can only open a quote/invoice from the **direct link** in the email/text you sent (no list in the
  side nav).
- **Branding:** the side nav shows your **logo + business name** (top-left); logos/brand colors come from your
  **Business Profile** and auto-apply to Client Hub _and_ request/booking forms so everything matches.

### 2.3 Online Booking / self-serve (schema + help center)

Client Hub's "request/book work" is powered by **Online Booking** (detailed in `jobber-02`). The schema's
**`SelfServeBooking`** enum defines what a self-serve booking creates:

| `SelfServeBooking` value | Creates                                                   |
| ------------------------ | --------------------------------------------------------- |
| `WORK_ORDER`             | A **job** (books work directly).                          |
| `WORK_REQUEST`           | An **assessment** (books a scoping/estimate visit first). |

Config lives in **`OnlineBookingConfiguration`** + `RequestSettings` (see `jobber-02`); `BookingType` /
`EfficientSchedulingType` control how slots are offered. Branding is shared with Client Hub (§2.2).

---

## 3. How WE compare (build notes)

- **Two-layer automation model to match:** (1) a handful of **built-in, one-toggle** automations covering the
  90% cases — quote follow-up ×2, invoice dunning ×2 (days-after-due, max 90), visit reminders, on-my-way, job
  follow-up on completion, review request, draft-quote-from-request — _plus_ (2) a **custom builder**
  (trigger → conditions → action) for everything else. Don't ship only the builder; contractors want the
  presets on by default. This aligns with our automation-engine roadmap and the outbox pattern (Rule 12).
- **Builder guardrails worth copying verbatim:** day-offset triggers capped at **90 days**, **max 6
  conditions**, morning=8AM / evening=7PM local, **not retroactive**, notify sends on the **same channel** as
  the original doc. These are sensible defaults + they double as our rate/spam guardrails
  ([[automation-rate-limit-deferred]]).
- **"Update status" action is quote-only** in Jobber — a deliberate constraint. When we build actions, scope
  status-changing actions carefully rather than allowing arbitrary status writes on every entity.
- **Automatic payments suppress dunning** — the automation engine must know about billing state so it doesn't
  chase an invoice that will auto-charge. Keep automations _aware of_ payment state, not blind senders.
- **Client Hub is the conversion surface.** The highest-value pieces to reach parity: **approve + sign + pay
  deposit** on quotes, **pay + tip** on invoices, **request more work** (self-serve upsell), and **view
  upcoming/past appointments**. Our public booking + document-send links already cover parts; the gap is a
  **logged-in, branded, all-in-one portal** with the Quotes/Invoices visibility toggle.
- **Self-serve booking = job _or_ assessment.** Match Jobber's `WORK_ORDER` vs `WORK_REQUEST` choice: some
  trades want instant job booking, others want an estimate visit first. Config, not hardcode.
- **Branding once, applied everywhere:** logo/colors set in one Business Profile flow into Client Hub _and_
  booking/request forms. Single source of truth for branding — worth matching so contractors set it once.

---

### Help-center sources

- Automations — https://help.getjobber.com/hc/en-us/articles/24244124296471-Automations
- Custom Automation Builder — https://help.getjobber.com/hc/en-us/articles/26980855822231-Custom-Automation-Builder
- Quote Approvals — https://help.getjobber.com/hc/en-us/articles/115012715008-Quote-Approvals
- Invoice Reminders — https://help.getjobber.com/hc/en-us/articles/115009517847-Invoice-Reminders
- Job Follow-ups — https://help.getjobber.com/hc/en-us/articles/115009739988-Job-Follow-ups
- Assessment and Visit Reminders — https://help.getjobber.com/hc/en-us/articles/360033608974-Assessment-and-Visit-Reminders
- Automatic Payments — https://help.getjobber.com/hc/en-us/articles/360036931633-Automatic-Payments
- Jobber and Zapier Integration — https://help.getjobber.com/hc/en-us/articles/360026513994-Jobber-and-Zapier-Integration
- Campaigns | Marketing Tools — https://help.getjobber.com/hc/en-us/articles/19885016029207-Campaigns-Marketing-Tools
- Client Hub Settings — https://help.getjobber.com/hc/en-us/articles/115009571307-Client-Hub-Settings
- What Do Your Clients See in Client Hub? — https://help.getjobber.com/hc/en-us/articles/1500011237822-What-Do-Your-Clients-See-in-Client-Hub
- A Guide for Your Clients: How to Navigate Client Hub — https://help.getjobber.com/hc/en-us/articles/360046586294-A-Guide-for-Your-Clients-How-to-Navigate-Client-Hub
- Online Booking — https://help.getjobber.com/hc/en-us/articles/13808363916951-Online-Booking
