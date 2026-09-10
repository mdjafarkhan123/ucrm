# Contractor CRM production feature baseline

**Date:** 2026-09-10  
**Scope:** Import/export, onboarding and migration, data portability, bulk operations, reporting and accounting handoff, customer self-service, and adjacent launch-readiness capabilities. This is a market baseline, not an audit of UCRM's current implementation.

## Bottom line

A contractor CRM is not launch-complete merely because Lead → Request → Quote → Job → Invoice → Payment works one record at a time. A credible first release also needs a safe way to bring in existing customers and prices, get usable business and financial data back out, perform the most repetitive operations in batches, hand records to accounting, and let customers complete the commercial steps without staff re-entering them.

The evidence does **not** make every mature-product feature a universal launch requirement. Jobber and Housecall Pro vary by plan and still have documented limits. The baseline below therefore separates:

- **Launch gate:** needed before taking ordinary paying contractors whose existing business data and daily work are placed in UCRM.
- **Wider-rollout gate:** may be support-assisted or narrowly scoped during a controlled pilot, but should be productized before onboarding many established contractors.
- **Later / segment-specific:** valuable only after demand, industry, region, or business size justifies it.

## Launch gate

### 1. Guided account setup with a visible completion state

The owner needs one guided checklist for company identity and branding, tax settings, document/payment settings, initial administrator and team access, customer import, Price Book setup, and a first end-to-end test record. Payment-provider onboarding is required only when the contractor enables online payments; communications registration is required only for the enabled channel and country.

This grouping is not speculative. Jobber's own first steps cover company details, branded client documents, tax rates, team setup, its field app, and payment setup. Housecall Pro similarly puts company profile, employees, customer import, Price Book, bank account, SMS registration, and estimate/invoice/payment settings into its getting-started checklist. ([Jobber: First Steps](https://help.getjobber.com/en/articles/first-steps-basic-account-set-up/), [Housecall Pro: Getting Started](https://help.housecallpro.com/en/articles/11115983-getting-started-with-housecall-pro/))

**Acceptance baseline:** progress is saved; skipped optional steps remain clearly incomplete; only authorized owners/admins can perform sensitive setup; the final check proves that the configured branding, tax, permissions, delivery, and payment choices actually work together.

### 2. Safe customer/property and Price Book import

At minimum, an established contractor must be able to import:

- clients/contacts, billing details, service properties, phones/emails, tags, notes, lead source, opening balance, and supported custom fields;
- products/services with name, description, price, cost where authorized, taxable state, active state, and product/service category.

Jobber supports mapped client CSV/TSV/PSV imports, property rows, custom fields, validation, and a roughly 5,000-row/2.5 MB batch; it also imports and mass-updates Products & Services from CSV. Housecall Pro supports customer and job files through an in-product mapper and offers assisted imports for customer history, equipment, and Price Book data. ([Jobber: Import Clients](https://help.getjobber.com/en/articles/import-clients/), [Jobber: Products & Services](https://help.getjobber.com/en/articles/products-services-list/), [Housecall Pro: Import & Export Jobs and Customers](https://help.housecallpro.com/en/articles/6797101-how-to-import-export-jobs-and-customers/))

An import is launch-safe only if it includes:

1. a downloadable sample/template and encoding/size limits;
2. automatic field mapping with manual correction;
3. a row preview before writing;
4. row-level validation with an invalid-row filter and plain-language errors;
5. explicit matching precedence using stable source/UCRM IDs first, then carefully defined fallback keys;
6. an explicit create/update/skip policy—never silent overwrites or guessed merges;
7. a background import job with progress, created/updated/skipped/failed counts, and a downloadable error file;
8. safe retry without duplicating already accepted rows; and
9. cancellation or a time-limited whole-import rollback where relationships allow it.

Jobber's current client importer previews mapped values and lets users correct invalid rows. Its Quote and Invoice imports preview before confirmation and can cancel/revert already imported data; its Jobs import highlights invalid rows and offers a ten-minute revert that removes records created by the import. Jobber's quote/invoice matching prioritizes its client/property IDs before exact email/name/address fallbacks. Housecall Pro also maps, previews, validates, emails an error report for its QuickBooks import, and warns customers to use support-assisted reversal rather than delete/re-import. ([Jobber: Import Clients](https://help.getjobber.com/en/articles/import-clients/), [Jobber: Import Quotes](https://help.getjobber.com/en/articles/import-quotes/), [Jobber: Import Invoices](https://help.getjobber.com/en/articles/import-invoices/), [Jobber: Import Jobs](https://help.getjobber.com/en/articles/import-jobs/), [Housecall Pro: QuickBooks Onboarding](https://help.housecallpro.com/en/articles/3006688-quickbooks-online-integration-onboarding-guide/))

### 3. Core exports and document downloads

The contractor must be able to retrieve usable copies of the data needed to run, reconcile, or leave the service:

- clients/contacts/properties, including stable IDs, tags, addresses, custom fields, and communication preferences;
- Price Book items;
- requests, quotes, jobs/visits, invoices, deposits, payments/refunds, expenses, and time entries, with relationship IDs;
- quote, job/work-order, invoice, receipt, and completed-checklist PDFs;
- uploaded documents and media, either individually or as a support-assisted archive during the pilot.

Exports should respect role/financial permissions, allow useful filters/date ranges and selected/all columns, use explicit timezone and currency fields, and run asynchronously for large accounts. A generated archive needs a manifest of included and omitted record types plus failures; “export complete” must not silently mean “clients only.”

Jobber exports client data (including tags, property/contact/custom-field information), Products & Services, and configurable CSV reports across financial, work, and client domains. It provides PDF downloads for quotes, jobs, and invoices and ZIP export for multiple attachments on a note. Housecall Pro exports customer/job lists and detailed payment, time, job, and estimate reports. Intuit likewise treats export of reports, lists, posting transactions, and non-posting records as a normal data-access workflow. ([Jobber: Export Client Information](https://help.getjobber.com/en/articles/export-client-information/), [Jobber: Reports Basics](https://help.getjobber.com/en/articles/reports-basics/), [Jobber: Client Document Settings](https://help.getjobber.com/en/articles/client-document-settings/), [Jobber: Notes and Attachments](https://help.getjobber.com/en/articles/notes-and-attachments/), [Housecall Pro: Import & Export Jobs and Customers](https://help.housecallpro.com/en/articles/6797101-how-to-import-export-jobs-and-customers/), [Housecall Pro: Payments Export](https://help.housecallpro.com/en/articles/8028448-payments-export/), [Intuit: Export QuickBooks Online Data](https://quickbooks.intuit.com/learn-support/en-us/help-article/list-management/export-reports-lists-data-quickbooks-online/L1xleDrLp_US_en_US))

**Boundary:** a one-click, every-table backup is not demonstrated as universal competitor behavior. UCRM should still guarantee a complete support-assisted offboarding package before cancellation during the controlled pilot. Jobber explicitly says account access, including clients, jobs, and invoices, ends when the paid term expires; UCRM should surface export before that deadline rather than make customers discover data loss afterward. ([Jobber: Cancel Subscription](https://help.getjobber.com/en/articles/cancel-your-jobber-subscription/))

### 4. The highest-value bulk workflows

Bulk action is not a generic checkbox requirement. It is required where normal contractor work produces repetitive batches:

- add/remove client tags and update supported client communication/status settings;
- import/update Price Book prices and states;
- reassign/reschedule selected visits;
- create draft invoices from jobs ready to invoice; and
- review, then deliver selected invoices together.

Jobber documents bulk client tags and CSV-based mass client/Price Book updates, multi-appointment reassignment/rescheduling, batch invoice creation, and batch delivery. Its invoice workflow deliberately creates drafts before delivery, and it splits invoices when properties have different tax rates. These are useful safeguards to copy conceptually. ([Jobber: Tags](https://help.getjobber.com/en/articles/tags/), [Jobber: Mass Updates to Clients](https://help.getjobber.com/en/articles/how-to-make-mass-updates-to-clients/), [Jobber: Products & Services](https://help.getjobber.com/en/articles/products-services-list/), [Jobber: Route Optimization](https://help.getjobber.com/en/articles/route-optimization-new-schedule/), [Jobber: Batch Create Invoices](https://help.getjobber.com/en/articles/batch-create-invoices/), [Jobber: Batch Deliver Invoices](https://help.getjobber.com/en/articles/batch-deliver-invoices/))

**Acceptance baseline:** the UI shows the exact selection/filter scope and affected count; previews financial/client-facing changes; rechecks authorization and current state at execution; preserves per-item results; supports idempotent retry of failures; and never turns a partial failure into an all-success toast. Destructive or customer-visible bulk actions require stronger confirmation than reversible internal edits.

### 5. Operational and financial reports with a workable accounting handoff

The first release needs filterable, permission-aware, exportable reports for:

- invoices/amount due/aging and client balances;
- payments, deposits, refunds, tips/fees where applicable, and payout reconciliation;
- tax collected by date/jurisdiction;
- jobs and visits by status/date/assignee, including uninvoiced work;
- quotes/requests and basic won/lost or conversion outcomes; and
- time entries needed for payroll/accounting handoff.

Jobber groups more than 20 reports into financial, work, and client categories and supports date filters, configurable columns, and emailed CSV. Housecall Pro documents up to 40 out-of-the-box reports plus filtered, saved, scheduled, and exported views. This supports a baseline of curated operational reports; it does not prove that an unrestricted report builder is required on day one. ([Jobber: Reports Basics](https://help.getjobber.com/en/articles/reports-basics/), [Housecall Pro: Managing Reports](https://help.housecallpro.com/en/articles/7336458-managing-reports/))

For a controlled pilot, correct CSV/Excel handoff to an accountant can satisfy the accounting boundary if direct sync is not promised. Before broader adoption by QuickBooks-using contractors, UCRM should provide a real integration or an equally low-friction supported process. Jobber's new QuickBooks flow imports clients and products/services once, then lets admins choose sync timing for clients, items, invoices, payments/refunds/tips/payout reconciliation, and approved timesheets; it also supports older-item sync and an error/warning activity view. Housecall Pro imports customers, tax rates, invoices, products/services, accounts, and business units from QuickBooks and emails import errors. Intuit itself supports ordered import of customers, products/services, and invoices and export of accounting reports/lists. ([Jobber: Connect QuickBooks Online](https://help.getjobber.com/en/articles/how-to-connect-jobber-and-quickbooks-online-new-quickbooks-integration/), [Housecall Pro: QuickBooks Onboarding](https://help.housecallpro.com/en/articles/3006688-quickbooks-online-integration-onboarding-guide/), [Intuit: Import Data](https://quickbooks.intuit.com/learn-support/en-global/help-article/import-export-files/import-data-software-quickbooks-online/L6LbxyKFZ_ROW_en))

Any direct integration must declare the source of truth per object/field, sync direction and trigger, historical cutoff, mapping rules, dependencies, disconnect/reconnect behavior, and how users resolve errors. “Connected” is not enough if invoices or payments silently diverge.

### 6. Minimum customer self-service

Before ordinary paid use, the customer-facing flow must at least provide secure mobile-friendly links to:

- view/download a quote, approve/sign it or request changes, and pay a required deposit when enabled;
- view/download an invoice/receipt and pay online when enabled;
- view appointment date/window, property, and contractor identity; and
- submit a new work request or booking without calling the office.

A consolidated passwordless portal is the expected mature-product shape, but it can follow immediately after a pilot if the same capabilities already work safely through expiring per-document links. Jobber's Client Hub combines quote approval/change requests, deposits, appointments, invoices/payments/receipts, and new work requests with company branding and secure email/text access. Housecall Pro's portal similarly exposes invoice payment, past/upcoming appointments, estimate approval, messaging, booking, and wallet management. ([Jobber: Client Hub Settings](https://help.getjobber.com/en/articles/client-hub-settings/), [Jobber: What Clients See](https://help.getjobber.com/en/articles/what-do-your-clients-see-in-client-hub/), [Housecall Pro: Customer Portal](https://help.housecallpro.com/en/articles/8474580-customer-guide-to-the-portal))

**Security baseline:** portal/link access must be tenant- and customer-scoped, revocable, expiry-aware, and safe when a recipient forwards a message. Jobber warns that anyone given its Client Hub link can access the same client information; UCRM should avoid treating possession of one document link as permanent access to every client record.

## Wider-rollout gate

These can be temporarily support-assisted or limited during a small pilot, but should be productized before many established contractors are onboarded:

1. **Historical work import:** quotes, one-off and recurring jobs/visits, invoices and opening payment state, with explicit limits and unsupported-field reports. Jobber now imports all three historical work types; its Jobs import is still labeled beta, demonstrating that breadth does not remove the need for warnings and rollback. ([Jobber: Import Quotes](https://help.getjobber.com/en/articles/import-quotes/), [Jobber: Import Jobs](https://help.getjobber.com/en/articles/import-jobs/), [Jobber: Import Invoices](https://help.getjobber.com/en/articles/import-invoices/))
2. **Self-serve complete account export:** one request that assembles relational CSV/JSON, all customer documents, attachments, activity/audit history, a manifest, checksums, and a secure expiring download. Pilot fallback: a tested support runbook with a delivery time commitment.
3. **Primary-market accounting sync:** QuickBooks Online for US/Canada if those are UCRM's first markets, including reconciliation and sync-error recovery. Xero or regional systems follow the actual market.
4. **Saved and scheduled reports:** saved filters/columns, scheduled delivery, and larger-account asynchronous generation. Housecall Pro documents saved/scheduled/exported reports; this is operational leverage, not evidence that a full custom analytics engine is a first-day requirement. ([Housecall Pro: Managing Reports](https://help.housecallpro.com/en/articles/7336458-managing-reports/))
5. **Unified branded client portal:** quote/invoice history, appointments, request/booking, payment methods, downloads, communications, and safe delegated contacts.
6. **Bulk-operation history:** who ran it, its selection definition, before/after counts, per-record outcome, downloadable errors, and undo/compensating action where safe.

## Later or segment-specific

Do not block the first launch on these unless the chosen pilot segment requires them:

- equipment/asset history, service plans/memberships, inventory, purchase orders, warehouse replenishment, or technician commissions;
- payroll, fleet/GPS, route optimization beyond basic dispatch, or complex multi-day project planning;
- marketing campaigns, referrals, review automation, and advanced attribution;
- unrestricted custom-report builders, forecasting, benchmarks, or BI/data-warehouse connectors;
- accounting integrations beyond the primary market's system;
- commercial account hierarchies, multi-location approvals, consolidated statements, purchase-order controls, and customer-side roles;
- public API/webhooks and bulk data APIs for enterprise integrations; and
- industry-specific forms, regulatory records, chemical tracking, or warranty/equipment workflows.

These are real mature-product capabilities, but their value depends on contractor size, trade, country, and operating model. They should be promoted only when a target segment and acceptance evidence justify them—not because a competitor has them.

## Recommended delivery order

1. Build the shared import-job framework, then ship clients/properties and Price Book import.
2. Ship matching core exports and a tested support-assisted complete offboarding package.
3. Close the operational batch workflows: client tags/settings, visit reassignment/rescheduling, draft invoice creation, and invoice delivery.
4. Complete the curated operational/financial report set and accountant-ready CSV package.
5. Verify the minimum secure customer-facing approve/pay/appointment/request journeys; then consolidate them into the portal.
6. Add historical quote/job/invoice imports and the primary-market accounting integration before wider rollout.

## Evidence limits

- Vendor help centers describe current product behavior, not independent proof that each feature is necessary or well implemented.
- Plan restrictions and regional availability change. UCRM packaging should follow its own customer promise.
- “Launch gate” here means the smallest credible capability for the target product and ordinary established contractors. A deliberately constrained pilot can use support-assisted migration/export where the limitation is disclosed and operationally tested.
- Data portability is used here as a product/data-ownership promise. This report makes no universal legal claim; privacy, tax, accounting-record retention, and jurisdiction-specific export duties require separate legal review.
