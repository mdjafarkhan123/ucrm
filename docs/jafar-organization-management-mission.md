# Platform Owner organization-management mission

## Status and authority

**Approved supporting context.** This document records the product and security decisions resolved
after auditing Ucrm, ContractorOs, the accepted onboarding ADR, the approved onboarding contract,
and the initial Platform Owner decision rounds. The newer
`docs/jafar-completion-contract.md` owns the approved A-Z completion behavior and wins where the two
documents differ.

It works with:

- docs/jafar-completion-contract.md
- docs/jafar-onboarding-implementation-contract.md
- docs/adr/0001-paid-prospect-provisioning-and-versioned-packages.md
- CONTEXT.md

Approved documents win over older recommendations, current legacy code, and ContractorOs.
ContractorOs is behavior evidence only; its code and UI are not implementation standards.

This mission supersedes only the earlier demo-route and demo-approval clauses for this mission. The
user explicitly approved direct real-route placeholder UI. Every other onboarding-contract and ADR
clause remains authoritative.

In this document, “Jafar” means an authorized Platform Owner acting through the protected /jafar
workspace; the route itself is never treated as an actor.

## Mission

Build a secure Platform Owner control room that takes a contractor business from application to an
active organization, preserves commercial history, controls platform-provided access and
integrations, and gives the operator safe diagnostic and recovery tools without making the operator
part of the contractor tenant.

The Platform Owner never becomes a contractor team member, never impersonates a contractor
administrator, and never uses unrestricted tenant editing as a support shortcut.

## Current verified baseline — 2026-08-11

Implemented foundations verified in the current worktree:

- platform onboarding application, original-submission, and correction tables;
- read-only prospect list/detail APIs and the Jafar prospect screen;
- package definitions, immutable version foundations, publication APIs/UI, and package tests;
- organization package assignment, feature/seat exception, free-access, lifecycle, and effective
  access foundations; and
- separate owner authentication and server-only privileged Supabase access.

Key evidence: src/routes/api/jafar/prospects, src/routes/jafar/(protected)/prospects,
src/routes/api/jafar/packages, src/routes/jafar/(protected)/packages,
src/routes/api/jafar/organizations, src/lib/server/access, and the 20260809/20260810 Supabase
migrations.

Verified missing or incomplete behavior:

- public onboarding form, confirmation, submission API, rate limit, Turnstile, and saved-package
  snapshot workflow;
- prospect correction, payment-confirmation, not-proceeding, and provisioning actions;
- durable application-bound idempotent provisioning and no-partial-account recovery;
- password-setup delivery records, intended-recipient verification, resend, and replacement;
- complete renewal, paid-through, correction, and attention workflows;
- migration from legacy direct creation and owner-entered administrator passwords; and
- behavioral/RLS/browser tests covering the complete journey.

Local and remote Supabase migration histories are currently drifted and must be reconciled before
Phase 2 schema/API writes. File presence or generated types alone do not prove remote deployment.

## Ownership boundaries

### Platform Owner

The Platform Owner controls:

- prospect review, payment confirmation, and provisioning;
- packages, immutable versions, organization assignments, and exceptions;
- paid-through dates, renewals, corrections, and approved free access;
- organization lifecycle and commercial access;
- integration eligibility, provider infrastructure, readiness, credits, and emergency controls;
- administrator setup-email delivery and verified recovery;
- private platform history and operational recovery; and
- read-only team-access inspection for support.

### Contractor owner or administrator

The contractor controls:

- business profile after provisioning;
- team members, roles, and permissions;
- operational timezone, hours, branding, and ordinary settings;
- communication content, schedules, routing, and channel preferences;
- webchat content and allowed domains;
- review destinations and campaigns; and
- its payment-provider account and payout details.

### Layered integration control

Effective integration access resolves these separate gates:

1. Platform availability
2. Organization entitlement
3. Provider readiness
4. Contractor preference
5. Customer consent
6. Credits, quotas, and safety limits
7. Organization lifecycle

A platform denial overrides but preserves contractor preferences. Every integration surface
distinguishes configured state, provider-reported state, effective state, last checked time, and the
next required action with its responsible party.

## Onboarding and provisioning

The normal lifecycle journey is:

Public application -> Owner review -> Offsite payment confirmation -> Confirmed provisioning ->
Active organization

Password-setup email issuance is a post-provisioning side effect. Delivery failure does not reverse
the active organization.

Rules:

- Public submission creates only a platform onboarding application and immutable package snapshot.
- Payment confirmation is required before provisioning.
- Provisioning is durable, idempotent, and tied to the application.
- It creates the organization, settings, activated package version, billing state, initial
  membership, trusted Auth metadata, and history without leaving a usable partial account.
- The legacy direct-create path and owner-entered administrator password are retired when paid
  provisioning is usable. Both must not remain normal alternatives.
- The Platform Owner triggers a single-use 24-hour password-setup email but never sees or creates
  the administrator password.
- The setup link is verified for the intended recipient and does not grant an application session
  before password setup completes.
- Administrator setup readiness is separate from organization lifecycle.
- Delivery failure after successful provisioning preserves the organization, creates an owner
  warning, and supports a safe resend that replaces earlier unused links.

## Lifecycle

### Active

Successful provisioning creates an active organization even if administrator password setup is
pending. Active means commercial platform access is allowed; administrator readiness is separate.

### Suspended

Suspension:

- blocks contractor application access;
- pauses new outbound messages, automations, confirmations, and new customer-facing actions;
- preserves tenant data, preferences, configuration, and history;
- continues necessary inbound opt-outs, receipts, disputes, payment reconciliation, provider
  callbacks, and security events;
- classifies queued work by type as paused or cancelled-with-reason and requires a relevance review
  before anything stale resumes;
- requires confirmation, private reason, identity reconfirmation, and history; and
- keeps safe existing invoice, receipt, payment-history, and quote-history access while pausing new
  approvals, bookings, requests, chat initiation, and new obligations.

Existing valid invoice payments may continue. Existing quotes remain view-only. Public pages explain
clearly when an action is temporarily unavailable.

Reactivation is confirmed and recorded. Late renewal and reactivation may share one owner workflow,
but their immutable commercial and lifecycle records remain distinct.

Reactivation after nonpayment requires a renewal or correction that restores commercial
eligibility. A noncommercial suspension may reactivate without inventing payment or renewal history.

### Legacy pending setup

New paid organizations do not use pending_setup. Existing rows enter a one-time review queue showing
administrator readiness, package assignment, paid-through state, and relevant activity. Each is
deliberately converted to active or suspended with a reason. No bulk assumption is allowed.

### Later closure

Deletion is excluded from the first onboarding release. The later lifecycle is:

Active -> Suspended -> Pending closure -> Closed

Pending closure requires impact preview, confirmation, reason, and a recovery deadline. Restoration
is possible during recovery. Final retention, anonymization, or removal is category-specific and
policy-driven; immediate blanket deletion is forbidden.

Pending closure stops new customer-facing and provider activity. Only necessary cleanup,
reconciliation, opt-out, dispute, security, and restoration-related callbacks continue.

## Commercial rules

### Packages, capabilities, and limits

- Packages and immutable published versions are the commercial source of truth.
- Organizations remain on their activated version until a separate confirmed change.
- Package changes are immediate in the first release and record old/new version, time, and reason.
- Exceptions are time-bound or permanent, require reason and start date, may expire, and never
  redefine the package.
- Capabilities, contractor preferences, provider readiness, consent, and usage limits remain
  separate.
- Feature and limit keys come from a controlled expandable catalog.
- Limits explicitly mean not included, numeric, or unlimited. Zero never means unlimited.
- A feature or limit is not sold or shown until server enforcement and usage measurement exist.

The long-term limit catalog may include team seats, monthly SMS credits, bulk SMS per day, SMS
throughput, AI requests, storage, active automations, and later API/webhook usage. Each is added only
with its enforcing subsystem.

### Payments, renewals, and grace

- Subscription payments remain offsite and manually confirmed.
- Original confirmations are immutable; mistakes, refunds, and reversals append corrections.
- Before provisioning, an unresolved reversal moves the application to needs_attention.
- After provisioning, paid-through state changes through a confirmed action; suspension remains
  separate.
- Seven-calendar-day grace ends at the end of the commercial timezone day.
- The first release uses owner attention queues and confirmed manual suspension after grace. It
  does not automatically suspend based on manually recorded payments.
- Operational timezone is contractor-controlled. Commercial timezone is separately owner-controlled
  and changes only with reason and history.
- A commercial-timezone change does not silently recalculate existing deadlines unless the confirmed
  change explicitly includes that effect.
- Partial payments, price mismatches, and corrections remain visible with their required reasons;
  they are never normalized by rewriting the original confirmation.

### Free access

Free access is an exceptional owner-granted commercial arrangement, not a public trial. It requires
an activated package version, reason, start date, optional end date or explicit forever state,
immutable history, and expiry attention. Permanent free access requires identity reconfirmation.

## Team access and support recovery

- Jafar may inspect team roles, effective permissions, access warnings, and administrator readiness.
- Contractor owners/admins normally change team access in the contractor application.
- Jafar does not silently grant or deny team-member permissions.
- Exceptional profile corrections use a dedicated support action with before/after values,
  confirmation, reason, actor, time, and contractor-safe notice.
- Administrator email recovery uses independent verification and identity reconfirmation. It checks
  through a trusted channel, shows the old and proposed new email, stores a non-secret evidence
  summary, checks cross-organization uniqueness, revokes relevant sessions and unused links,
  notifies old/new addresses when appropriate, and never exposes a password.

## Provider and channel rules

### Emergency controls

Platform-wide and organization-specific controls exist separately for SMS, email, and other
channels. A pause records operator, reason, and time; stops new outbound work; preserves
configuration and queued records; continues necessary inbound/provider events; and requires review
before stale work resumes.

### Phone and carrier registration

- Jafar provisions, assigns, ports, replaces, suspends, and releases platform-managed phone numbers.
- Contractors control greetings, routing, hours, missed-call behavior, and messaging preferences.
- Contractors supply and attest legal carrier-registration information.
- Baseline information includes legal business name, registration or tax identifier, legal address,
  website, messaging purpose/use case, consent and opt-in details, and contractor attestation.
- Country- and provider-specific fields are verified from current provider requirements during
  implementation rather than guessed.
- Jafar reviews completeness, submits it, records provider responses, and requests resubmission.
- Formatting may be owner-assisted; changing legal meaning requires renewed contractor attestation.
- Customer opt-outs can never be overridden.
- Number replacement/release requires impact preview, reason, confirmation, history, and identity
  reconfirmation.
- Historical conversations and messages retain the phone-number identity used at the time.

### SMS credits

- Package versions may include monthly SMS allowance.
- Balances derive from an immutable ledger and are never directly overwritten.
- Allowance, top-up, correction, reservation, release, charge, and provider adjustment are distinct
  entries.
- Allowance posting and sending are idempotent.
- Top-ups and corrections require a reason, actor, and immutable history.
- Every retry has a distinct idempotent attempt identity, and one provider request cannot finalize
  credit more than once.
- Sending reserves estimated credit, releases it when no provider cost occurred, and finalizes the
  charge when the provider accepts the request.
- Later delivery failure is not automatically refunded when the provider charged the platform.
- Balance, allowance, usage, and reserved credit are displayed separately.
- Zero allowance means no included messages.

### Email

- New organizations may use a verified platform-domain fallback for essential transactional email.
- The sender clearly identifies the contractor.
- Organizations may authenticate their own domain for branding and deliverability.
- Jafar manages eligibility, DNS/provider verification, last check, and failure diagnosis.
- Contractors control sender display name and permitted reply address.
- Marketing email does not automatically use the fallback without consent and policy checks.

### Payments

- Contractors own and connect payment-provider accounts.
- Jafar controls package eligibility and sees safe readiness information only: connection state,
  live/test mode, requirements due, sanitized errors, and last checked.
- Jafar never exposes bank credentials, secrets, or full payment details.
- Disconnecting or changing a provider account requires contractor confirmation. The Platform Owner
  may impose only a narrow emergency eligibility block and never changes payout/account credentials.

### Webchat

- Jafar controls entitlement, public widget identity/token lifecycle, provider health, abuse
  controls, and diagnostics.
- Contractors control enabled preference, greeting, offline message, mode, branding, notifications,
  and allowed website domains.
- Public embed configuration never exposes signing secrets.

### Reviews

- Contractors control review destinations and campaigns.
- Jafar diagnoses readiness, count discrepancies, reconciliation history, and sanitized failures.
- Reconciliation never invents reviews or rewrites customer history.
- Customer-to-public-review matches remain confidence-based, never certain.
- Manual reconciliation corrections require a reason and preserve the original observation.

Provider-specific requirements and retry contracts are verified against current primary provider
documentation during their implementation phase.

## History, transparency, and recovery

### Owner-private history

Jafar retains sanitized history for provisioning, packages and exceptions, payments and corrections,
setup-email delivery, lifecycle, credits, provider actions, support corrections, emergency controls,
retries, and recovery.

History excludes passwords, setup links, credentials, secrets, full payment details, and unnecessary
message content.

### Contractor-visible history

Contractors see safe outcomes relevant to their organization, including access, lifecycle, credit,
and integration-availability changes. Private payment references, investigations, raw provider
errors, credentials, and operator evidence remain private.

High-impact organization changes create an in-app notice and, where appropriate, a customer-safe
email without exposing private owner notes.

### Retention

Retention is category-specific:

- not-proceeding prospect personal data follows the approved 12-month rule unless documented
  retention is required;
- commercial records follow applicable accounting and contractual periods;
- privileged and security history remains for organization lifetime plus an approved post-closure
  period;
- provider diagnostics use a shorter sensitive-data-aware period; and
- exact legal durations are confirmed before closure implementation rather than guessed.

### Operational recovery

One failure record appears in both a global Operations queue and an organization-filtered recovery
view. Retry is idempotent. Acknowledge records review without deleting history. Manual resolution
requires a note. Recurring failures remain visible as health issues. Records show organization,
type, attempts, sanitized error, next retry, correlation identifier, current disposition
(pending, retrying, acknowledged, or manually resolved), and history.

## High-impact action security

Routine actions use confirmation and a reason but do not require step-up identity reconfirmation:

- package change;
- time-bound capability or limit exception;
- renewal recording;
- SMS credit top-up; and
- carrier submission or resubmission.

These high-impact actions additionally require recent Platform Owner identity reconfirmation:

- administrator email recovery;
- suspension/reactivation;
- permanent free access;
- phone-number replacement/release;
- platform-wide emergency controls;
- closure/restoration; and
- future account-ownership changes.

The first release may reconfirm the configured owner password for a short-lived authorization
window. Named operators and MFA remain a later hardening phase already excluded from the first
onboarding release.

## Organization-detail structure

The dedicated route is /jafar/organizations/[organizationId].

1. **Overview** — identity, lifecycle, administrator setup, warnings, and next actions.
2. **Commercial access** — package, paid-through date, grace, renewals, free access, capabilities,
   limits, and exceptions.
3. **Integrations** — phone/SMS, carrier registration, email, webchat, payments, readiness, and
   emergency state.
4. **Team access** — read-only roles/effective permissions, administrator recovery, and warnings.
5. **History and recovery** — provisioning, payments, package/lifecycle changes, setup delivery,
   provider failures, and audited support actions.

The organization directory remains a searchable inventory. Expensive provider panels load
independently and never block the page shell.

## UI-first delivery decision

The user explicitly approved skipping a separate demo route for this mission.

1. Build the polished desktop UI directly in the real Jafar routes.
2. Use realistic, typed, development-only placeholder scenarios.
3. Simulate or disable actions whose secure backend is incomplete.
4. Prevent placeholder data from appearing in production; production fails honestly when live data
   is unavailable.
5. Implement backend behavior one vertical section at a time.
6. Replace each placeholder adapter with live queries and mutations.
7. Remove the placeholder source before release.

Required scenarios include active, overdue, setup-email pending, suspended, feature exception,
carrier rejection, provider outage, and failed background work.

## Phased roadmap

### Phase 0 — Reconcile foundations

- Reconcile local and remote Supabase migration history.
- Inventory legacy organizations, assignments, and pending_setup rows.
- Confirm authoritative generated database types.
- Freeze expansion of legacy direct-create behavior.

**Gate:** schema history is trustworthy before further database work.

Phase 0 may run before or in parallel with Phase 1 placeholder UI. It must finish before Phase 2
schema or API writes begin.

### Phase 1 — Build real-route UI with safe placeholders

- Build directory navigation and dedicated organization detail shell.
- Build all five sections and critical scenarios.
- Build confirmations, identity reconfirmation, loading, empty, error, partial-failure, and stale
  states.
- Verify wide desktop behavior and accessibility.

**Gate:** user approves the real-route UI and fixtures cannot appear in production.

### Phase 2 — Complete paid onboarding vertically

- Public application and confirmation
- Rate limiting, Turnstile, package eligibility, and immutable snapshot
- Owner corrections and payment confirmation
- Idempotent provisioning and durable attempt history
- Setup-email delivery, expiry, replacement, and recovery
- Retirement of legacy direct-create UI/API in the same usable release

**Gate:** every approved onboarding acceptance check passes.

### Phase 3 — Commercial access and legacy reconciliation

- Live overview, assignment, paid-through, renewals, corrections, grace, and manual suspension
- Capability/limit resolution and audited exceptions
- Free-access arrangements and commercial timezone
- Individual review of legacy pending_setup organizations

**Gate:** effective commercial access is explainable from immutable records.

### Phase 4 — Team access and support recovery

- Read-only team/effective-permission inspection
- Administrator readiness and setup-email resend
- Verified administrator email recovery
- Narrow audited profile correction
- Contractor-visible safe change history

**Gate:** support recovery needs no impersonation, password handling, or casual permission editing.

### Phase 5 — Communications and integrations

- Phone lifecycle and carrier registration
- SMS eligibility, credits, ledger, reservations, and emergency controls
- Platform fallback and tenant email-domain verification
- Webchat eligibility/token diagnostics with contractor-owned configuration
- Payment-provider eligibility/readiness
- Review readiness and reconciliation

Each provider is delivered as its own vertical slice and verified against current provider docs.

### Phase 6 — Operations and recovery

- Global failure queue and organization-filtered recovery history
- Idempotent retry, acknowledge, and manual resolution
- Correlation identifiers and sanitized diagnostics
- Platform health and recurring-failure visibility

**Gate:** retry cannot duplicate users, messages, credits, payments, or provider work.

### Phase 7 — Owner-security hardening

- Named Platform Owner accounts
- MFA
- Revocable server-side sessions
- Stronger step-up authentication
- Login rate limiting and monitoring
- Individual operator accountability

This is excluded from the first onboarding release but remains a production-hardening mission item.

### Phase 8 — Controlled closure and retention

- Pending-closure impact preview and recovery period
- Restoration
- Category-specific retention, anonymization, and removal
- Backup and provider-cleanup policy
- Legally reviewed durations

**Gate:** closure cannot erase required history or orphan provider resources.

## Global release gates

No phase is complete without:

- independent authorization on every Jafar API;
- server-only secrets;
- Zod validation for every write;
- RLS and privilege tests;
- related database writes are transactional;
- external writes use idempotency and explicit compensation;
- complete affected-cache invalidation;
- loading, partial-error, and retry states;
- owner-private and contractor-safe history;
- risk-proportionate automated checks;
- browser verification of the real route; and
- removal of development placeholder data before production.

## Excluded from the first onboarding release

- annual billing;
- public trials;
- discounts and coupons;
- automatic subscription payment collection;
- automatic overdue messages or suspension;
- named Platform Owner accounts and MFA;
- impersonation;
- organization closure; and
- general contractor invitation workflows.

## ContractorOs comparison traceability

| Concern | ContractorOs evidence | Approved Ucrm direction |
| --- | --- | --- |
| Organization navigation | General, Details, Entitlements, Integrations | Task-oriented Overview, Commercial access, Integrations, Team access, History and recovery |
| Entitlements | About 32 mixed booleans and context-dependent zero limits | Separate capability, preference, provider readiness, consent, and explicit limit states |
| Integration ownership | Many contractor-facing settings editable from Jafar | Platform controls eligibility/infrastructure; contractor controls ordinary content and preferences |
| Provider state | Some saved integration JSON and dedicated provider columns can disagree | Configured, provider-reported, and effective state shown separately with last check |
| SMS credits | Balance, allowances, top-ups, and ledger | Immutable reservation/finalization ledger with idempotency and explicit adjustments |
| Dead letters | Dashboard retry and dismiss actions | One global plus organization-filtered recovery record; retry is idempotent and acknowledge never deletes |
| Organization details | Broad single route with overlapping General/Details sections | Dedicated Ucrm route with independently loaded task panels and partial-failure states |

Detailed source traceability remains in docs/Owner.md under Legacy source map.
