# CRM production feature-gap audit — 2026-09-10

## Verdict

UpliftContractor has a substantial core contractor workflow, but it is not yet a complete sell-ready CRM. The
strongest implemented path is Request/Quote through Job, Schedule, Invoice and recorded Payment. The largest
product gaps are business onboarding/import, data export and portability, public intake, a unified customer
portal, reputation, contractor notifications, broad reporting/accounting handoff, online payments and the
remaining communication channels.

This is a product-completeness audit, not authorization to build every competitor feature. The launch promise
must choose what a contractor can rely on from day one; segment-specific machinery stays out until a real target
customer needs it.

## Evidence boundary

- Current implementation truth was checked through the contractor/public route and API inventory.
- Approved versus shipped behavior was checked against `docs/PRODUCT.md`, `docs/build-sequence.md`, the domain
  behavior contracts, `Memory/INDEX.md` and the deferred-work register.
- Competitor behavior comes from the existing Jobber reference and
  `docs/research/contractor-crm-production-feature-baseline-2026-09-10.md`.
- Route presence proves that a surface exists, not that every journey is complete. Closed campaign evidence and
  explicit implementation-status sections are stronger than a route name.
- A fresh live Jobber interaction tour was unavailable because no connected Chrome/Jobber tab was present. Any
  interaction-specific comparison that is not already recorded needs a live pass before implementation.

## Launch classification

| Gate | Meaning |
| --- | --- |
| Paid launch | A contractor cannot safely adopt, operate, bill, recover or leave without it. |
| Product promise | Needed before marketing the complete Inquiry-to-Repeat-work product described in `docs/PRODUCT.md`. |
| Wider rollout | A controlled pilot can use a documented manual path, but growing customer count cannot. |
| Later/segment | Useful only for a chosen trade, company size, integration or competitive tier. |

## Capability matrix

| Capability | What is evidenced today | Confirmed gap | Gate |
| --- | --- | --- | --- |
| Guided onboarding | `/get-started` collects package, business, contact and first-administrator application details | No signed-in completion checklist proves branding, tax, team access, import, documents, enabled delivery channels and payment choices together | Paid launch for ordinary self-serve onboarding; a controlled pilot may use a tested assisted runbook |
| Import and migration | Client behavior permits imports; Price Book design names CSV import | No import UI/API exists. Client/Property and Price Book imports are unbuilt. Historical work migration has no approved promise | Paid launch for established contractors; exact historical scope is a Jafar decision |
| Export and portability | Individual documents and receipts have narrow view/download paths | No business-data export UI/API exists. There is no complete portable export of clients, work, financial records and file manifests | Paid launch for trust/offboarding; large file bundle can follow a background export pattern |
| Bulk workflows | Quote bulk archive, Visit bulk move and Invoice batch create/deliver exist | Client bulk actions are visibly disabled; Client tag/settings updates and Price Book mass updates are absent; there is no shared per-item result/error history | Paid launch for repetitive workflows sold in the first package; generic bulk machinery is not required |
| Clients and Properties | Identity, contacts, properties, tags, notes, files, timeline, permissions, search and create-time duplicate warnings are shipped | Merge, archive/restore, historical-address safety, billing-address completion and guarded deletion remain open | Paid launch: historical/billing safety and a documented duplicate path; wider rollout: self-serve merge/archive |
| Requests and intake | Staff request pages, assessment and conversion APIs exist | No public request/booking-form surface; Field users can read every Request title/description; requested-service/form configuration is absent | Paid launch: permission leak; product promise: public intake/booking |
| Sales Pipeline | Parts 1–5 are closed and browser-verified | Final desktop, accessibility, performance, security and contractor-manual audit is unscoped | Paid launch audit |
| Quotes and proposals | Draft, pricing, versions, secure customer view, approval/signature, deposits and Job conversion are evidenced | Published branding is not fully frozen; internal cost can ride the Request pricing payload; Good/Better/Best is not built | Paid launch: privacy and immutable customer document; later/segment: packages |
| Jobs and field records | Jobs campaign closed after integrated browser and proportional performance verification | Offline field records, maximum 520-Visit detail measurement and two small Visit-card backend fields are deferred | Controlled online launch supported; offline is segment/network dependent |
| Schedule and dispatch | Unified Schedule, Visits, Assessments, Events, assignment, completion, map context and route ordering exist | General Tasks/reminders, route optimization, bulk reassignment/reschedule and dedicated mobile app remain incomplete or deferred | Product promise depends on advertised scope; route optimization/mobile are segment decisions |
| Invoices and recorded payments | Invoice lifecycle, batch billing, deposits, manual payment records, receipts, void/bad-debt truth and secure customer pages are evidenced | Issued-invoice correction UI, payment edit/delete/split, void notification, online card/ACH processing, saved methods, disputes and payouts are absent | Paid launch: correction/reversal path; product promise: online payment if advertised |
| Communications | Operational email and website chat are implemented; email delivery was live-verified | SMS/phone is paused; Messenger/Instagram, missed-call recovery and several inbox operations are absent | Choose launch channels explicitly; do not market an omnichannel inbox yet |
| Customer portal | Narrow secure Quote, Invoice, receipt and Work Report links exist | No unified customer portal for appointments, documents, balances and requesting more work | Product promise |
| Reputation | Product blueprint defines review requests and private recovery | No contractor Reputation route or evidenced campaign delivery | Product promise for the stated Review/Repeat-work journey |
| Automations | Durable engine, builder and Quote follow-up parity exist | Most promised presets and owning-domain actions are not complete; scale evidence remains VPS-gated | Wider rollout; only advertise proven recipes |
| Contractor notifications | Platform Owner notifications exist | Contractor notification store, preferences, bell/history and push delivery are explicitly unbuilt | Product promise; assignment/payment failures need an interim operational path for pilot |
| Reporting and accounting handoff | Pipeline Outcomes plus domain summaries/costing exist | No general Reports area, broad permission-aware operational/financial reports, CSV accounting export, QuickBooks/Xero integration or approved general-ledger boundary | Paid launch: basic financial/operational exports; wider rollout: dashboards and integrations |
| Settings, team and access | Business profile, branding, hours, taxes, Price Book, Quote settings, Team, Checklists, email, website chat, Pipeline and Automation settings have surfaces | Team/access Part 3E, booking, payments, integrations, contractor notifications and several feature-owned settings remain | Paid launch: final access model and settings needed by sold features |
| Platform administration | Provisioning, packages, organization control, closure/recovery, operations and email controls are substantial | Provider-specific control slices and final A-to-Z owner audit wait on contractor subsystems | Paid launch for every provider actually enabled |
| Production operations | A bounded VPS topology and staged migration design exist | No approved/implemented immutable app/worker images, production-like staging cutover rehearsal, clean-machine restore proof, concurrent load result or final monitoring gate | Paid launch blocker |

## Minimum import/export contract to approve

### Import

The smallest useful first release should import Clients, their Contacts, billing details, Properties, phones,
emails, tags, notes, lead source, opening balances and Price Book items from CSV. Price Book input includes name,
description, price, protected cost, taxable/active state and product/service classification. Import needs a
downloadable template, column mapping, normalization, preview, row-level errors, duplicate handling, an explicit
create/update/skip policy, an idempotent retry key, progress, cancellation before commit, a downloadable result
and a time-limited rollback where relationships allow it. It must not silently create partial customers, guess a
merge, overwrite protected cost or cross an organization boundary.

Whether to import historical Requests, Quotes, Jobs, Invoices and Payments is a launch-positioning decision:

- **Assisted migration:** UCRM staff transform and load history for early customers. Faster product delivery,
  but operationally expensive and not self-serve.
- **Self-serve history import:** better for broad acquisition, but each financial/work object needs lineage,
  validation, immutable-history and error-recovery rules. This is a separate campaign, not an extra CSV tab.
- **Opening-state only:** import customers, open work and opening balances while keeping old history in the prior
  system. Smallest product, but the sales promise must say so clearly.

### Export

Contractors need tenant-scoped export of Clients/Contacts/Properties, Price Book, Requests, Quotes, Jobs/Visits,
Invoices, deposits, Payments/refunds, expenses and time records. Financial and internal-cost columns follow the
caller's permissions. A full account export should include structured CSV/JSON plus a manifest for downloadable
documents and attachments, run as a bounded background job, expire securely and leave an audit event. A tested
support-assisted complete offboarding package is acceptable for a controlled pilot, but it must exist before a
contractor's paid access ends.

## Decisions required before a final implementation roadmap

1. Is the first customer a new business, or an established contractor migrating years of data?
2. Which history promise applies: assisted migration, self-serve history import, or opening-state only?
3. Are online card/ACH payments required at launch, or are recorded offline payments acceptable for the pilot?
4. Which communication channels may sales advertise at launch: email, website chat, SMS/phone, or all channels?
5. Does “complete CRM” at launch include public booking, unified portal, reputation and contractor notifications?
6. Which accounting handoff is required first: portable CSV, QuickBooks, Xero, or no direct integration?
7. Is offline field work required for the initial trades and service areas?

## Proposed delivery order

1. Approve the launch promise and migration model using the decisions above.
2. Close access/privacy/data-integrity P1 findings, beginning with Request permissions.
3. Deliver Client/Property/Price Book import and complete business-data export.
4. Close Invoice/Payment correction and customer-document immutability gaps.
5. Finish the sold customer-facing promise: public intake, portal, notifications, reputation and chosen channels.
6. Deliver basic permission-aware reporting and the chosen accounting handoff.
7. Complete the Sales Pipeline and cross-domain accessibility/security/manual audits.
8. Package immutable containers, rehearse the self-hosted Supabase cutover and clean restore, then run
   production-like failure and concurrent-load tests.
9. Pilot with a small group, close observed blockers, and widen traffic only against measured evidence.

## Audit completion gate

The audit closes when Jafar approves the seven product decisions, every promised launch capability has an owner
and completion test, intentionally excluded features are named plainly, and the production cutover/load/restore
gates are part of the same release roadmap. It does not close merely because every planned page exists.
