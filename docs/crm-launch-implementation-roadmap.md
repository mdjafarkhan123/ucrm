# CRM launch implementation roadmap

**Approved:** 2026-09-10  
**Owner:** Jafar  
**Purpose:** Turn UpliftContractor into a safe paid CRM, then deliver the lead-conversion services contractors
most demand.

## Approved controlled-first-launch position

The controlled first launch serves a few closely supported, paying small established contractors through assisted onboarding. It supports the
office-led Request → Quote → Job → Invoice → recorded Payment workflow, works online, launches with email and
Website Chat, migrates opening-state data, and hands accounting records off through CSV.

The commercial priority after the safety foundation is one connected speed-to-lead loop:

1. A website visitor submits a hero Quote form or Website Chat.
2. UCRM creates or matches the lead and records the source and consent evidence.
3. Staff see the conversation and Request immediately.
4. A configurable automation replies only when a human has not replied within the chosen window.
5. A missed call creates visible activity and can send a compliant text-back.
6. Contractors can run simple permission-aware campaigns and send completed customers through a Google review
   funnel with private recovery for poor feedback.

The existing Automation engine remains the shared execution foundation. Each owning domain must publish a
durable event and a guarded action; the engine must not invent customer, phone, consent, Job, payment, or review
truth.

## Ordered delivery

### 1. Close paid-launch trust blockers

**Owner:** focused security/data-integrity campaign, with the affected domain campaign owning each correction.  
**Depends on:** current implementation.  
**Deliver:** Request access isolation; removal of internal cost from customer reads; frozen issued-Quote branding;
rate limits on exposed write/read paths; authenticated public functions; historical/billing address safety;
guarded Client/Property deletion; Invoice correction and Payment reversal/correction; void communication; final
Team/access rules; removal of launch-blocking hydration failure.

**Main risk:** fixing a screen without fixing its API/database authority leaves the exposure in place.  
**Complete when:** role and tenant tests prove isolation; issued documents retain their original truth; financial
corrections append history; the approved owner/office/sales/field/finance journeys pass.

### 2. Make assisted adoption and exit safe

**Owner:** new onboarding-and-data-portability campaign.  
**Depends on:** Part 1 access rules.  
**Deliver:** assisted onboarding runbook and visible checklist; Client/Contact/Property/Price Book/opening-balance
import with mapping, preview, row errors, duplicate policy, idempotent retry and result file; support-assisted full
offboarding export with structured records, relationship IDs, document/file manifest, permission filtering,
secure expiry and audit event; client tags/settings and Price Book mass updates needed by the pilot.

**Main risk:** guessed matches or partial retries can silently corrupt customer and financial data.  
**Complete when:** a representative established contractor can be imported twice without duplicates, rejected
rows are explainable, rollback/recovery is exercised, and an independent operator can restore useful records from
the offboarding package.

### 3. Finish the paid CRM operating core

**Owner:** Sales Pipeline, Reporting/Accounting, and affected lifecycle campaigns.  
**Depends on:** Parts 1–2.  
**Deliver:** final Pipeline desktop/accessibility/security/performance/manual audit; permission-aware aging,
balances, payments/deposits/refunds, tax, Job/Visit, uninvoiced-work, sales-outcome and time-entry exports; one
accountant-ready CSV package; verify batch Invoice creation/delivery with per-item failures; close the complete
Request → recorded Payment pilot journey.

**Main risk:** totals that differ across screens and exports destroy trust even when each page appears complete.  
**Complete when:** seeded financial and operational scenarios reconcile from source record through CSV, and every
failed bulk item remains visible and safely retryable.

### 4. Ship website speed-to-lead

**Owner:** Requests/Public Forms + Website Chat + Communications + Automation.  
**Depends on:** Parts 1–3; existing Website Chat, email delivery and Automation engine.  
**Deliver:** embeddable branded hero Quote/Request form; configurable questions and channel-specific consent
capture; deterministic lead/customer matching without guessed merges; Request and source attribution; Jobber-
style inbox/activity visibility and configured-recipient alerts; one HighLevel-style editable speed-to-lead preset
whose five-minute Wait is only the starting value; supported Wait, condition, assignment, task, internal-
notification and customer-message steps; stop/pause rules for staff and customer replies; delivery, enrollment
and failure history.

**Main risk:** duplicates, double replies, replying after a person has answered, and treating a chat open/read
signal as a human response.  
**Complete when:** form and Chat submissions each create or match exactly one lead, appear live to permitted staff,
send at most one timed reply only when eligible, stop on real human activity, and recover safely after worker or
provider failure.

### 5. Ship missed-call text-back

**Owner:** Communications Activation A2 + Phone/SMS settings + Automation missed-call pack + Platform Owner phone
controls.  
**Depends on:** Part 4 automation rules; Twilio number setup; approved messaging registration/compliance.  
**Deliver:** phone number provisioning/assignment; durable missed-call event; known-lead match or safe lead creation;
inbox activity; staff alert; editable delay/message; consent and opt-out enforcement; quiet-hour/timezone policy;
one compliant text-back; suppression after qualifying human response; delivery and failure history.

**Main risk:** carrier rejection, unlawful texting, SMS pumping, duplicate provider callbacks and runaway cost.  
**Complete when:** registered-number live tests cover known/unknown callers, STOP/HELP, quiet hours, duplicates,
staff reply races, provider outage, credit/rate limits and owner recovery controls.

### 6. Ship one-click campaigns without harming service messages

**Owner:** `marketing-growth`, with Customers, Automation, Communications, Requests/Bookings, and billing as
dependencies.
**Depends on:** Part 5 SMS truth for SMS campaigns; email campaigns may be enabled first after the same safeguards.  
**Deliver:** owner/admin-only seasonal reminder and win-back campaigns; saved recipient segment from customer/job
history; exact recipient preview; channel consent and global opt-out; editable template/test send; schedule/send;
separate marketing queue/rate budget; per-recipient result, retry boundary and campaign report.

**Main risk:** one bulk send can damage sender reputation, delay Quotes/Invoices, overspend provider credit or
contact an opted-out customer.  
**Complete when:** transactional delivery stays within its service target during a representative campaign burst,
every recipient is permission/consent eligible at send time, partial failures are visible, cancellation stops
unclaimed work, and duplicate execution cannot double-send.

### 7. Ship the Google review funnel

**Owner:** `marketing-growth` Reputation part + Jobs/Payments completion truth + Automation review pack + Platform
Owner review-link controls.
**Depends on:** trustworthy completed-work eligibility; email, with SMS optional after Part 5.  
**Deliver:** contractor Google review link; eligible completed-customer selection; manual request and preset;
customer rating landing page; 4–5 ratings continue to Google; 1–3 ratings create private feedback and a protected
staff alert; reminders, stop rules, history and basic conversion reporting. Public-review matching remains
confidence-based, never claimed as certain.

**Main risk:** review gating and platform-policy compliance require a current policy/legal check before the final
interaction is approved; negative feedback must not be exposed to unauthorized staff.  
**Complete when:** all rating paths, permissions, consent, reminders, repeated requests, link expiry, private
recovery and reporting pass; the final flow has a recorded compliance approval.

### 8. Productize for wider rollout

**Owner:** owning domain campaigns coordinated by launch readiness.  
**Depends on:** Parts 1–7 and pilot evidence.  
**Deliver:** self-serve onboarding and opening-state import/export; Client merge/archive/restore; unified customer
portal; contractor notification center; online card/ACH payments when sold; Visit reassignment/rescheduling;
remaining advertised automation presets; productized reports; the accounting integration selected from real
customer demand; accessibility/security/browser/mobile-web audits.

**Main risk:** widening acquisition before support-heavy operations are productized creates an unscalable service
business rather than a software product.  
**Complete when:** a new contractor can configure, migrate, operate, reconcile and export without database access
or routine staff intervention, and support/pilot evidence shows no unresolved launch blocker.

### 9. Prove production and launch gradually

**Owner:** Production Operations + Platform Owner.  
**Depends on:** every capability sold in the controlled first launch; Jafar's separate infrastructure topology/cutover approval. Preparation may proceed alongside Part 3, but infrastructure implementation remains behind that approval.
**Deliver:** immutable app/worker images; production-like staging; pinned official self-hosted Supabase stack;
secure networking/secrets; off-host base backups and continuous WAL archive; clean-machine point-in-time restore;
managed-to-self-hosted cutover and rollback rehearsal; monitoring/alerts; restart, dependency-failure and
representative load tests; pilot support and incident runbooks.

**Main risk:** one VPS is one failure domain and cannot be described as highly available. Registered-user count is
not a capacity measurement.  
**Complete when:** tested evidence records achieved recovery point/time, latency, errors, connections, queue age,
provider limits and tenant skew; the pilot ramps in bounded stages with rollback gates. The working targets are no
more than 15 minutes of lost data and restoration within four hours, subject to proof.

## Explicitly outside this launch

Full historical self-serve migration, QuickBooks/Xero sync, WhatsApp/Messenger/Instagram, offline field work,
native mobile apps, route optimization, Good/Better/Best proposals, saved cards/auto-charge/disputes/payouts,
arbitrary report building, and multi-host high availability require a later customer, trade, region, payment or
uptime decision. UCRM will make no 40,000-user capacity claim until a named workload is exercised.

## Final launch gate

Jafar may open the controlled first launch only after Parts 1–4 and 9 pass. Begin with a few closely supported
paying contractors. Parts 5–7 follow after that first launch and must not be sold before their own gates pass.
Wider rollout waits for the necessary Part 8 work plus evidence from the first customer group. A page existing is
never completion evidence by itself.
