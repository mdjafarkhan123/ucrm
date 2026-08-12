# Jafar onboarding and package implementation contract

## Status

Approved. This document describes the approved behavior to build. It is not a
database migration, API, or production-screen change.

## Purpose and scope

Build the paid-prospect path for UpliftContractor:

1. A contractor submits a public onboarding application.
2. The Platform Owner reviews it, records an offsite payment, and can correct the activated
   package with a private reason.
3. One confirmed owner action creates the organization and its first contractor administrator.
4. The administrator receives a one-time password-setup email.
5. The owner can manage packages, paid-through dates, renewals, suspension, and the retained
   private history for this path.

The existing direct “Create organization” form, temporary-password field, fixed package names,
default-package assignment, and scheduled package changes are replaced by this path. They must
not coexist as alternative ways to create contractor organizations.

This release does not include annual billing, trials, coupons, discounts, automatic payment
collection, payment-provider credentials, automatic overdue messages, named owner accounts, MFA,
impersonation, deletion of organizations, or contractor access to the platform-owner workspace.

## Terms and states

- An **onboarding application** belongs to the platform, not to a contractor organization.
- Its stage is exactly one of: `new`, `awaiting_payment`, `payment_confirmed`,
  `needs_attention`, `account_created`, or `not_proceeding`.
- A possible duplicate is a review warning only; it never changes the stage or merges records.
- An organization remains either `active` or `suspended`. `pending_setup` is not used by this
  flow. A successfully provisioned organization is active, even when the administrator has not
  yet set a password.
- Only published package versions may be selected publicly or activated. A retired version remains
  visible in history and on affected organizations but cannot be newly selected.

## Public onboarding

The public form collects only:

- business name;
- main contact name, email, and phone;
- optional different initial administrator name and email;
- trade, city/country, and IANA time zone;
- “Package you’re interested in”;
- optional note; and
- privacy-policy agreement version, agreement confirmation, and acceptance time.

The page shows every published package with its exact USD monthly platform price, currency,
billing period, public description, inclusions, and the statement that provider fees, if any, are
separate. UpliftContractor does not add, calculate, collect, or show tax in this release. It does
not call the package a subscription or promise account access.

Submission creates a new application and an immutable package snapshot. It creates no Supabase
Auth user, organization, membership, contractor data, or session. Repeated submissions are kept
for review. The confirmation only says that details were received and payment is handled
separately.

The server validates every field, applies a server-side rate limit, verifies Cloudflare Turnstile,
and records a failed private owner-email alert without hiding a successfully saved application.
The public route has no service-role credentials in browser code.

## Packages and access

- A package has a permanent internal identity, editable customer-facing name, public description,
  fixed USD monthly price, monthly billing period, status (`draft`, `published`, `retired`), and
  ordered display position.
- A package version is immutable and contains the price, public text, controlled feature catalog,
  and controlled limits exactly as published. Publishing an edit creates a new version; it never
  rewrites a prior version.
- The initial controlled catalog is the existing enforceable feature and limit catalog. Package
  editing cannot create arbitrary feature or limit names. Each limit is explicitly unlimited, not
  included, or a positive numeric value; numeric zero has no ambiguous meaning.
- A package can be published only with a name, public description, monthly USD price, and either an
  included CRM capability or a clear value explanation.
- An organization stores its activated package version, never merely a mutable package key.
  Existing package/feature/limit reads resolve from that activated version plus valid explicit
  exceptions. The existing fixed `starter`/`growth`/`elite` assumptions and live joins are removed.
- An owner changes an organization’s package only through a separate confirmation that records the
  old and new version, effective date (immediate in this release), and required reason. Package
  exceptions include a reason, start date, optional expiry, and clear indication that the package
  remains the default.

## Owner review, payment, and provisioning

The owner can correct submitted prospect details before provisioning, retaining the original
submission and a required private correction note. The owner may change the package that will be
activated before payment confirmation, retaining the original snapshot, activated version, and a
required private reason.

Payment confirmation requires an explicit confirmation screen showing the amount and private
reference. It records only the paid date, amount, USD currency, private reference/note, selected
package version, and a required mismatch reason when the amount differs from its published price.
It never records card, bank-account, or provider-login data.

Provisioning requires the `payment_confirmed` stage and an explicit confirmation showing business,
administrator email, and activated package. It must:

1. recheck that the selected package version is published or valid retained history;
2. recheck that the administrator email is not linked to any organization;
3. create the organization, package assignment, local time zone, first membership, and required
   records as one database operation;
4. create the initial administrator through server-side Supabase Auth with trusted tenant/role
   claims only in `app_metadata`;
5. mark the application `account_created` only after all creation work succeeds; and
6. create a single-use, 24-hour password-setup link and send it without exposing a password to the
   owner or browser.

The workflow needs an idempotency key tied to the application and a durable operation record. A
retry may resume safe work but must never create a second organization, membership, or Auth user.
If a check or creation fails, no usable partial contractor account may remain. If safe completion is
impossible, the application moves to `needs_attention` with a private explanation; payment state is
not reversed automatically.

If setup-email delivery fails after successful account creation, retain the account, show a clear
owner warning, and allow a safe resend. Resend replaces any earlier unused setup link. The email
link must be verified against the intended recipient and must not grant a session before password
setup is completed.

The owner may mark an unpaid application `not_proceeding` with a confirmation. It retains personal
contact details for 12 months, then permanently removes them unless the owner records a documented
business reason to retain them. The privacy policy must state this rule.

## Renewals and lifecycle

- Each organization has a paid-through date and an organization time zone. Paid access and its
  seven-calendar-day grace period end at the end of the organization’s local day.
- The owner view flags renewals due in seven days and one day, and overdue organizations after the
  paid-through date. This release sends no automatic overdue-payment messages to contractors.
- Each manual renewal creates an immutable confirmation: amount, USD currency, private reference,
  confirmation date, paid-through date, and any required mismatch reason. Corrections append a
  correction record; they never overwrite the original.
- An overdue or disputed organization may be suspended with a required private reason. Suspension
  blocks contractor access while preserving records. A late renewal is recorded and reactivation is
  completed in one confirmed owner action.
- Legacy organizations may receive a current package version and paid-through date. Their missing
  application and payment history is never fabricated.

## Private history and security

Every package publish/edit/retire, prospect correction, payment confirmation, provisioning attempt,
setup-email resend/failure, renewal, suspension/reactivation, and organization package change
creates private history with timestamp, affected record, old/new summary, configured Platform
Owner actor, and required reason where specified. It never contains a password, password token,
payment account detail, provider credential, or other secret.

All owner and public writes use server routes and Zod validation. Owner routes check the separate
owner session before creating a service-role client. Platform-owned tables have RLS enabled and no
anonymous or contractor write policy. Contractor tenant RLS remains unchanged. Every new table and
policy receives a focused database test, including cross-tenant and unauthenticated access checks.

## Required records

The approved schema work will introduce platform-owned records for:

- packages and immutable package versions;
- versioned feature and limit assignments;
- onboarding applications, original submissions, corrections, and package snapshots;
- offsite payment confirmations and renewal/correction records;
- organization activated-package assignments and paid-through dates;
- provision attempts/idempotency and password-setup delivery state; and
- private owner history.

It will migrate existing organizations as legacy accounts, assign a chosen current package version
and paid-through date through an owner operation, and remove the old fixed package/default/scheduled
package model only after all existing organization access can resolve from the new versioned model.

## Routes and screen boundary

The approved product surface is:

- a public onboarding page and confirmation page;
- `/jafar` overview with application, renewal, and organization attention counts;
- an onboarding application list and read-only history/detail view with permitted owner actions;
- package management and package-version history;
- an organization directory and detail view with package, paid-through, renewal, lifecycle, and
  private-history sections.

The next part is a demo-only Svelte/SCSS design for these screens. It must use the project design
system, BEM naming, and Tabler icons, and it must receive user approval before the production
routes, migrations, or APIs are changed.

## Acceptance checks for later implementation

1. A public submission creates only an onboarding application and package snapshot.
2. An unpublished or retired package cannot be newly selected or activated.
3. Editing a package never changes an existing organization’s access or commercial history.
4. Payment confirmation and provisioning require their separate confirmation screens and required
   private reasons where this contract says so.
5. An administrator email tied to another organization cannot be provisioned again.
6. Failed or retried provisioning cannot leave a usable partial account or duplicate tenant.
7. No owner can see, enter, copy, log, or resend an administrator password.
8. A setup link is single-use, expires after 24 hours, and is safely replaced by a resend.
9. Suspension blocks contractor access; reactivation restores it after a recorded late renewal.
10. Public and contractor callers cannot read or alter platform-owned records.
