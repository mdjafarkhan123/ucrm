# ADR 0003: Package editions, customer agreements, and an offsite billing ledger

## Status

Accepted 2026-09-29. Jafar approved replacing the whole package system while keeping each feature's
existing access check, and clearing the test organizations' old package and payment history. Jafar chose
automatic suspension at the end of grace, with an overdue banner during it.
Supersedes ADR 0001's fixed monthly price and the “package version” wording; the rest of ADR 0001 stands.

## Context

The first release fixed three package keys (Starter, Growth, Elite), one monthly USD price, saves split
across several database calls, and receipt-only payment history. The approved
[package plan](../package-builder-behavior-contract.md) needs any number of packages, monthly and yearly
prices, introductory offers, whole-draft saves, and money tracked per service period. The fixed keys run
through database checks, validation, the access resolver, and the owner screens
([audit](../research/package-flexibility-audit-2026-09-29.md)), so patching them would not deliver it. All
organizations are test data.

## Decision

1. **Replace the package system; keep the entitlement seam.** The new storage for packages, editions,
   agreements, and money replaces `platform_packages`, `platform_package_versions` and their feature and
   limit rows, `package_features`, `package_limits`, the `organizations.package_key` columns,
   `organization_package_assignments`, `organization_payment_confirmations`,
   `organization_billing_accounts`, and the old package, payment, legacy-review, and free-access commands
   and screens. Features keep asking the same questions. `resolveOrganizationAccess` returns the same
   `features`, `permissions`, and `limits` shape, and the permission-to-feature prefix map stays. The limit
   functions (`effective_employee_seat_limit`, `effective_website_chat_widgets_limit`,
   `effective_marketing_email_limit`, `private.effective_website_chat_conversation_limit`,
   `private.resolve_communication_email_allowance`, `effective_automation_limits`,
   `private.organization_has_automations_feature`) keep their names and signatures and read the new
   storage. About 300 permission checks in about 250 server files stay unchanged. This is the Stripe
   Entitlements seam: a feature checks an entitlement, and the catalog behind it can change.
2. **A package has editions.** A package is a stable identity with a public slug, visibility, display order,
   and archived state, all changeable without touching customer terms. An edition holds the customer-facing
   terms: name, promise, highlights, included services, capabilities, allowances, monthly and yearly USD
   prices, and exclusions. A package has at most one draft and one published edition. Publishing freezes the
   draft as the next edition and supersedes the previous one, which stays readable for customers still on
   it. A trigger keeps published editions unchangeable. Highlights and services are ordered JSON frozen with
   the edition. Capabilities and allowances are rows, because access checks read them.
3. **Whole-draft saves with a revision check.** One command saves the whole draft in one transaction and
   names the revision the editor loaded. A mismatch returns the newer draft so the editor can compare the
   two. Publishing names the draft and revision it reviewed and fails if either changed. Create and copy
   commands carry idempotency keys.
4. **Capability readiness is reference data.** Each capability records whether it is core, an extra, or
   planned, what it requires, which allowances belong to it, and whether it is sellable. Only a verified
   build changes `sellable`, by migration, never a screen toggle. Publishing refuses unsellable
   capabilities, unmet requirements, and allowances that contradict the chosen capabilities. Automation
   safety controls (conditions, steps, messages per enrollment, spacing, delays, enrollment length) become
   platform-wide values, not package allowances.
5. **Agreements freeze what a customer agreed.** An agreement ties an organization to one edition, with its
   billing interval, agreed price, frozen offer terms, service anchor, and effective date. Access reads the
   latest agreement already in effect, and a move at the next renewal is an agreement dated in the future.
   Prices are never read live from the catalog for an existing customer. Temporary feature and limit
   exceptions sit on top, each with a reason, start date, and end date.
6. **Money is an append-only ledger with explicit applications.** A charge is the amount due for one service
   period, or for the rest of a period after an immediate change. A receipt is money Jafar confirms was
   received offsite. An application moves part of a receipt or credit onto a charge. Money received but not
   applied is credit, and the unused paid time returned by an immediate change is non-cash credit.
   Corrections, reversed applications, and refunds are new records with reasons; nothing is edited or
   deleted. Paid-through moves only through an explicit coverage confirmation. Charges are created at
   activation, for the next period when coverage is confirmed, and by change commands; no background job
   bills anyone. Every money command locks the organization's commercial-state row first, so commands for
   one organization run one at a time, and each carries an idempotency key. This follows Chargebee's offline
   payments: a recorded payment reduces the invoice's amount due, extra money becomes excess payment, and a
   removed payment returns to excess instead of being refunded. Here, application is always explicit, as
   the plan requires. Contractor invoices and payments are a separate domain and share no tables.
7. **Monthly allowances follow the service start.** Email and website chat windows restart monthly from
   the first confirmed coverage start in the commercial time zone, for monthly and yearly agreements alike.
   They no longer start from the organization's creation date.
8. **Public details come from the CRM.** The static marketing site links “View details” to a public
   read-only page built from the published edition, and passes the slug and billing choice to
   `/get-started`. Publishing, revising, or archiving leaves a reminder until Jafar confirms the site copy
   matches.
9. **Grace end suspends automatically.** A scheduled SQL job suspends
   organizations whose grace has ended, using the existing lifecycle suspension (category `nonpayment`,
   system actor). Confirming coverage lifts only that suspension; security and manual suspensions stay.

## Considered options

- Altering the old tables: the fixed keys and partial saves would survive in constraints, functions, and
  screens, and the legacy fallback would stay.
- Rewriting every feature's checks: this touches finished features for no customer benefit.
- A single signed balance per customer: it cannot show which period a payment covered.
- Automatic credit application or scheduled billing: the plan requires Jafar's explicit choice, and manual
  billing needs no background charge generation.

## Consequences

- The Jafar panel contract's immediate package changes, optional exception expiry, and receipt-only
  payments are superseded by the package plan. The Jafar panel's final audit should check the new rules.
- Resetting the test organizations keeps lifecycle events (suspension, closure, time zone) and removes
  package, payment, exception, and free-access events. Onboarding applications keep their snapshots and
  point to the new test edition.
- Performance design: the access snapshot runs once per gated request and the limit functions run per
  send, invite, or activation. The catalog is tiny, and each organization has a few agreements, at most
  twelve charges a year, and a handful of exceptions. Indexed single-row lookups by
  `(organization_id, effective_from desc)` and by primary key are enough, with no cache. The snapshot drops
  the legacy all-packages read. Verification collects `EXPLAIN` for the snapshot and every limit function on
  an organization with 20 agreements and 20 exceptions, confirms one database call per gated request, and
  checks the directory and public catalog plans. No capacity claim follows from this design.
