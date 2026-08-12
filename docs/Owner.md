# Platform Owner (`/jafar`)

## Purpose of this document

This is the permanent product and implementation context for UpliftContractor's Platform Owner
workspace. Read it before designing or changing `/jafar`, organization provisioning, platform-level
entitlements, organization lifecycle controls, or privileged operational tools.

The approved current mission and phased roadmap are recorded in
docs/jafar-organization-management-mission.md. The paid onboarding rules remain in
docs/jafar-onboarding-implementation-contract.md and ADR 0001. Where this older audit contains an
open decision or recommendation resolved by those approved documents, the approved documents win.

The document uses four evidence labels:

- **Current UCRM** — behavior or architecture that exists in this repository now.
- **Legacy observation** — behavior found in `D:\Projects\ContractorOs`; it is reference evidence,
  not approved UCRM scope and must not be copied as code or UI.
- **Recommendation** — the preferred direction for UCRM, subject to the project's normal planning
  and approval process before implementation.
- **Open decision** — an ambiguity that must be resolved before the affected feature is built.

## Product boundary

`/jafar` is the private back office for the person or team operating the UpliftContractor platform.
It provisions and supports the separate contractor organizations that use the CRM. It is not a
contractor workspace and must never become a shortcut for day-to-day CRM work.

Platform operators may provision organizations, create the initial contractor administrator,
configure platform-managed capabilities, inspect integration readiness, control account lifecycle,
and recover failed platform work. Contractors use the normal application to manage their customers,
requests, quotes, jobs, visits, invoices, payments, team, and business settings.

The Platform Owner must remain outside every contractor tenant:

- The operator has no `organization_id` and no `organization_members` row.
- The operator does not appear as a contractor team member or inherit contractor permissions.
- The operator does not impersonate a contractor administrator for convenience.
- Tenant-scoped reads and writes remain protected by organization isolation and RLS.
- Privileged support actions require an explicit platform-owner operation and an audit trail.

The route is intentionally absent from contractor navigation. Hidden routing is not a security
control; server-side authentication and authorization protect every page and API operation.

## Current UCRM foundation

The current implementation is deliberately small. It proves the owner boundary and basic
organization creation; it does not implement the full target workspace described later.

### Authentication and routes

**Current UCRM:**

- `/jafar/login` is outside the protected route group. An authenticated operator is redirected to
  `/jafar`.
- Protected owner pages live under `src/routes/jafar/(protected)` and validate the owner session in
  a server layout load.
- Credentials come from `SUPER_ADMIN_EMAIL` and `SUPER_ADMIN_PASSWORD_HASH`. Password comparison
  uses bcrypt.
- `jafar_session` is an HttpOnly, SameSite Strict cookie containing an HMAC-signed payload with the
  configured email and expiry. Its lifetime is eight hours.
- The login fails closed if the email, password hash, or `SESSION_SECRET` is missing.
- `POST /api/jafar/session` creates the session and `DELETE /api/jafar/session` clears it.

This owner session is separate from Supabase Auth. The current operator is a single shared
environment-configured identity, not a Supabase user or named operator record.

### Authentication decisions

The current approved authentication model is intentionally narrow:

- Contractor users belong to exactly one organization. UCRM must reject a second organization
  membership for the same Auth user and does not need an organization-switching flow.
- Contractor users are provisioned by the Platform Owner as part of organization setup. There is no
  contractor invitation method or invite lifecycle to implement.
- The Platform Owner continues to authenticate with the environment-configured email and password
  through `/jafar/login`. Named owner operators, MFA, session revocation, and owner-action audit
  history are deferred until a later approved owner-security task.

### Organization access and lifecycle

**Current UCRM:**

- `GET /api/jafar/organizations` returns organizations ordered by newest first.
- `POST /api/jafar/organizations` validates the organization and initial administrator with Zod,
  derives a URL-safe slug, adds a numeric suffix when necessary, and provisions both records.
- New organizations are created as `active` with one confirmed, password-authenticated owner
  administrator. The owner may suspend an active organization or reactivate a suspended one.
- Tenant RLS membership checks require the organization to be `active`; pending and suspended
  organizations preserve their data while blocking contractor access.
- The owner provides the first administrator's name, email, and password directly. The password is
  sent only to Supabase Auth over the server-side Admin API and is never returned, logged, or
  persisted by UCRM. Trusted tenant and owner-role claims are stored in `app_metadata`, and an
  `owner` membership is created only after the Auth user exists. Failed provisioning attempts
  compensate by deleting the new Auth user and organization records.
- The protected `/jafar` page uses TanStack Query for the organization list and invalidates that
  query after creation.
- Owner database access uses a server-only Supabase client configured with
  `SUPABASE_SERVICE_ROLE_KEY`. The key is not exposed to browser code.
- The API checks the owner session before constructing or using the privileged client and fails
  closed when privileged access is not configured.

### Current data model

**Current UCRM:**

- `organizations` contains identity, slug, lifecycle status, and timestamps.
- `organization_members` connects Supabase Auth users to organizations and supports the roles
  `owner`, `admin`, `office`, `sales`, `field`, and `finance`.
- `organizations`, `organization_members`, `contacts`, `properties`, and `requests` have RLS enabled.
- Contractor access is membership-scoped through `private.is_organization_member(...)`.
- The initial migration intentionally leaves provisioning unseeded and assigns creation of the
  first organization and member to the Platform Owner workflow.

### Not implemented yet

The current UCRM owner slice does not yet store plans or feature flags, configure integrations,
manage messaging credits, operate dead letters, or maintain an owner-action audit history. The
navigation contains future Operations and Settings destinations, but their presence must not be
treated as completed behavior.

## Target workspace

The following capability map combines product intent from `docs/PRODUCT.md`, useful legacy evidence,
and recommendations for UCRM. Each area should be implemented only when it becomes an approved task.

### 1. Operator authentication and accountability

**Legacy observation:** ContractorOs used one environment email/password and a separate eight-hour
HS256 JWT cookie. It had no observed MFA, login throttling, named operator identities, revocation
store, or durable owner-action audit log.

**Recommendation:** Preserve the isolated owner session, but do not ship the shared-credential model
as the final production security posture. Before production use, add:

- Rate limiting and monitoring for failed logins.
- A second authentication factor appropriate for a platform-wide privileged account.
- Named operators with individual accountability rather than shared credentials.
- Server-side session revocation and rotation for sensitive credential changes.
- Re-authentication or step-up confirmation for destructive or high-impact actions.
- A durable audit event containing operator, action, target, before/after summary, result, timestamp,
  and request correlation identifier. Secrets and temporary passwords must never enter the log.

All `/api/jafar/*` handlers must authorize independently. Page protection alone is insufficient.

### 2. Organization inventory

The owner home should show all organizations with enough information to find accounts that need
attention without loading every integration in a sequence.

**Legacy observation:** The dashboard summarized organization status, setup progress, review links
and counts, SMS balances and allowances, dead letters, the platform SMS master state, and the
platform email domain.

**Recommendation:** Keep the default inventory focused on organization identity, lifecycle state,
setup state, plan, primary administrator, integration readiness, and important warnings. Load
expensive integration or operational details in parallel, on demand, or through purpose-built
summary endpoints. Support search and stable server pagination before the organization count makes
an unbounded list expensive.

### 3. Organization provisioning

Provisioning creates a tenant and its first real contractor administrator. It is a privileged,
multi-system workflow rather than a simple organization insert.

**Legacy observation:** The creation form collected business identity, trade, city/state/timezone,
an optional Twilio number, plan, feature overrides, limits, initial administrator identity and
temporary password, and a permission matrix. The server then:

1. Created and confirmed a Supabase Auth user.
2. Wrote trusted tenant and role metadata.
3. Transactionally created the pending organization, counters, SMS credit account, pipeline stages,
   automation settings and sequences, and active administrator membership.
4. Attempted to delete the Auth user if metadata or database provisioning failed.

**Recommendation:** Preserve the outcome and compensation principle, not the legacy implementation.
Use UCRM's plain SQL migration and Supabase architecture:

1. Validate the complete request with Zod before external or database work.
2. Reserve or validate the organization slug and identifiers without race-prone client logic.
3. Create the initial Supabase Auth user through a server-only Admin Auth client.
4. Put authorization claims only in trusted `app_metadata`; never authorize from user-editable
   metadata.
5. Create the organization, initial membership, required counters, and approved defaults in one
   database transaction or one narrowly scoped database function.
6. Compensate for partial external success, record cleanup failures for operator recovery, and make
   retries safe against duplicate users or organizations.
7. The platform owner manually delivers the administrator's initial password through an approved
   secure channel. UCRM never returns, logs, or persists that plaintext password.

The operator creates the contractor administrator but never becomes a member of the new tenant.

### 4. Organization lifecycle and onboarding

The product vocabulary currently anticipates `pending_setup`, `active`, `suspended`,
`pending_deletion`, and `deleted` account states.

Recommended meanings:

- `pending_setup` — provisioned but not released for normal contractor use.
- `active` — allowed to use enabled product capabilities.
- `suspended` — access is temporarily blocked while data and history are preserved.
- `pending_deletion` — scheduled for controlled removal and still recoverable under the retention
  policy.
- `deleted` — terminal business state; physical deletion and retention behavior require a separate
  data-governance decision.

Lifecycle controls are platform account controls, not CRM document statuses. Suspension must block
contractor access and new automated/customer communication without erasing history or making
financial records inconsistent.

**Open decision:** ContractorOs exposed one action that only set `is_setup_complete` and a separate
onboarding transition that set both setup complete and `pending_setup → active`. Before UCRM adds
these fields, decide whether setup completion and activation are independent concepts. Until then,
do not encode both booleans/statuses or expose a misleading “Complete setup” action.

Deletion, retention periods, restoration, billing effects, automation cancellation, and integration
shutdown remain separate decisions. Do not infer them from the legacy status names.

### 5. Plans, capabilities, and limits

A plan is a default entitlement template. A capability controls whether an organization may use a
feature. A limit constrains measurable usage. Contractor preferences inside an enabled capability
remain separate—for example, the platform may allow invoice reminders while the contractor chooses
whether to enable them.

**Legacy observation:** ContractorOs defined Starter, Growth, and Elite templates. They are useful
inventory, not approved UCRM packaging or pricing.

The 32 observed capability/channel keys were grouped as:

- **Workspace:** team management, appointments, online booking, media uploads.
- **Messaging:** one-way SMS, two-way SMS, bulk SMS, conversations, missed-call text-back, webchat,
  Messenger.
- **Automation:** automation engine, review funnel, appointment reminders, invoice reminders,
  payment receipts, quote follow-up, speed to lead.
- **SMS channel allowances:** SMS variants of payment receipts, quote follow-up, appointment
  reminders, invoice reminders, and review funnel.
- **Financial:** quotes/invoices, Stripe payments, client portal.
- **AI:** AI assistant.
- **Reporting:** Growth Feed and advanced reporting.
- **Integrations/API:** custom branding, API access, and webhooks.

The eight observed limits were team seats, monthly SMS, bulk SMS per day, SMS per minute, SMS per
day, AI requests per month, storage GB, and automation workflows. ContractorOs assigned different
meanings to zero depending on the limit (`disabled` or `unlimited`), which is error-prone.

**Recommendation:** Approve UCRM's plans, keys, defaults, and zero/null semantics before adding
columns. Prefer explicit unlimited/disabled representation over context-dependent numeric zero.
Enforce capabilities and limits in server/domain logic, not only by hiding UI. Record overrides and
who changed them. Disabling a capability should preserve recoverable configuration unless deletion
is explicitly required.

Online Booking and Messenger were disabled in every legacy preset, so their presence is evidence of
planned surfaces rather than proven production behavior.

### 6. Organization detail

**Legacy observation:** ContractorOs grouped organization management into General, Entitlements,
Integrations, and Details. It supported activation/suspension, setup completion, plan/features/limits,
SMS activation and carrier approval, credit configuration and top-ups, webchat, tenant email-domain
provisioning, branding/profile inspection, and read-only Stripe/Twilio connection state.

**Recommendation:** Retain these conceptual groups but design a new UCRM interface from its own
design system. Clearly distinguish:

- Platform-managed fields from contractor-editable business settings.
- Current saved state from provider-reported state.
- Safe configuration changes from actions with customer or billing impact.
- Editable controls from diagnostic/read-only integration facts.

Never copy `OrgEditorPanels.svelte`, the legacy page composition, or legacy Jafar SCSS. The legacy
component appears unused and duplicates route logic.

### 7. SMS and phone operations

**Legacy observation:** The owner could control a platform SMS master floor/pause state, activate SMS
per organization, record carrier approval or rejection, inspect balances and allowances, and apply
manual credit top-ups. Credit changes used a ledger. Some stored feature values were preserved while
a master SMS gate disabled their runtime effect.

**Recommendation:** Model platform availability, tenant eligibility, contractor preference, consent,
and credit/rate enforcement as separate gates. An interface toggle is never the enforcement layer.
Manual balance adjustments require an immutable ledger entry with reason, operator, amount, and
idempotency protection. Pausing SMS must stop sends predictably without losing queued work or stored
tenant configuration; the precise queue-resume policy must be designed with the worker.

Carrier registration and provider connection states must display timestamps and provider errors so
operators can distinguish pending, rejected, active, and stale information.

### 8. Email domains, reviews, and webchat

**Legacy observation:** ContractorOs managed platform and tenant email-domain provisioning and
verification, organization review links and count reconciliation, and webchat enablement, greeting,
offline behavior, and embed data. Email-change request backend/schema work existed, but no complete
owner management panel was found.

**Recommendation:** Treat provider verification as asynchronous state with last-checked timestamps,
actionable errors, and safe retries. DNS verification should never be represented as instantly
successful because an API request returned successfully. Review count reconciliation must preserve
source and confidence; it must not present customer-to-public-review attribution as certain when the
match is inferred. Webchat credentials or signing secrets must never be returned in public embed
configuration.

Email-change request management remains unverified scope and must not be implied by the legacy
schema alone.

### 9. Operational recovery

**Legacy observation:** Repeatedly failed outbox work appeared as dead letters with retry and dismiss
actions. Runtime/provider behavior was not executed during the audit, so conclusions come from code.

**Recommendation:** Show event type, organization, correlation identifier, attempt count, timestamps,
sanitized error details, and current disposition. Retry must be idempotent and must not duplicate
messages, payments, or downstream records. Dismiss means an operator has acknowledged that specific
failure; it must not delete history or hide recurring system health problems. Every retry/dismiss
action belongs in the owner audit trail.

Operational tools should help recover platform work, not provide arbitrary tenant database editing.

## Implementation guardrails

Future `/jafar` work must follow these boundaries:

- Keep owner auth separate from contractor Supabase sessions and organization membership.
- Put service-role and provider secrets only in server modules and server routes.
- Authenticate and authorize every privileged endpoint before performing work.
- Send all writes through `/api/jafar/*` routes and validate every POST/PATCH body with Zod.
- Use the standard `{ error, field_errors }` validation shape where field errors apply.
- Keep tenant-facing tables protected by RLS even when owner server operations use privileged access.
- Grant only the database/API access required for each path; a service-role client is not permission
  to build generic unrestricted endpoints.
- Use transactions for related database writes and explicit compensation for external operations
  that cannot participate in the transaction.
- Make privileged and provider-facing mutations safe to retry.
- Use TanStack Query for owner server state; invalidate all affected query keys after mutations or
  external events.
- Render the owner shell immediately and load independent panels concurrently with useful
  loading/error states.
- Use Svelte 5 runes, component-scoped SCSS with BEM, RemixIcon, and existing shared components.
- Reuse native controls for simple input and Bits UI wrappers only for complex interactive
  primitives.
- Do not copy ContractorOs code, Drizzle schema, stores, global SCSS, or UI composition.
- Do not add legacy fields or tables until their UCRM behavior, security, and ownership are approved.

## Failure and safety checklist

Before shipping an owner mutation, answer all of the following:

1. Who is allowed to invoke it, and is that checked on the server?
2. Which tenant or platform resource is affected, and can an identifier be confused across tenants?
3. What database and external-provider writes occur?
4. What happens if each step fails after earlier steps succeeded?
5. Can the request be retried without duplicating users, credits, messages, or records?
6. Does the action require a reason, confirmation, or step-up authentication?
7. What audit event is recorded without leaking credentials or customer-sensitive data?
8. Which TanStack Query caches or worker state must be invalidated/reconciled?
9. Can the contractor still see or change the same setting, and which source wins?
10. How will an operator distinguish saved state, effective state, and provider state?

## Legacy source map

The source paths below provide traceability for the observations in this document. They are outside
the UCRM repository and must remain read-only reference material.

### Routes and UI behavior

- `D:\Projects\ContractorOs\src\routes\jafar\+page.svelte`
- `D:\Projects\ContractorOs\src\routes\jafar\dashboard\+page.svelte`
- `D:\Projects\ContractorOs\src\routes\jafar\orgs\new\+page.svelte`
- `D:\Projects\ContractorOs\src\routes\jafar\orgs\[id]\+page.svelte`
- `D:\Projects\ContractorOs\src\lib\components\jafar\`

### Authentication and provisioning

- `D:\Projects\ContractorOs\src\lib\server\auth\jafarSession.ts`
- `D:\Projects\ContractorOs\src\lib\server\admin\orgProvisioning.ts`
- `D:\Projects\ContractorOs\src\lib\admin\planTemplates.ts`
- `D:\Projects\ContractorOs\src\lib\admin\featureGroups.ts`

### Privileged API surface

- `D:\Projects\ContractorOs\src\routes\api\admin\orgs\`
- `D:\Projects\ContractorOs\src\routes\api\admin\outbox-events\`
- `D:\Projects\ContractorOs\src\routes\api\admin\platform\email-domain\`
- `D:\Projects\ContractorOs\src\routes\api\admin\sms-master\+server.ts`

### Data and provider dependencies

Key observed dependencies included `organizations`, `org_members`, `automation_settings`,
`org_counters`, `org_sms_credit`, `sms_credit_ledger`, `outbox_events`, `platform_settings`,
`email_domains`, and `webchat_widgets`, plus pipeline and automation seed tables. Provider/runtime
dependencies included Supabase Admin Auth, Postgres, Twilio, BullMQ/Redis, Brevo, DNS/MX checks,
review attribution, provider webhooks, and the outbox worker.

These names describe the legacy implementation. They do not prescribe UCRM table names, schemas,
workers, or vendor contracts.

## Current UCRM source map

Use these repository paths to revalidate the “Current UCRM” section as the implementation evolves:

- `src/lib/server/auth/owner.ts` — owner credential verification, signed session, and cookie policy.
- `src/routes/api/jafar/session/+server.ts` — login/logout API behavior and validation.
- `src/routes/jafar/(protected)/+layout.server.ts` — protected owner-route boundary.
- `src/routes/jafar/(protected)/+page.svelte` — current organization inventory and creation UI.
- `src/routes/api/jafar/organizations/+server.ts` — current organization list/create API.
- `src/lib/server/db/owner-supabase.ts` — server-only privileged Supabase client.
- `supabase/migrations/20260808000100_initial_crm_foundation.sql` — current organization schema,
  membership roles, RLS, and the intentionally unseeded provisioning boundary.

## Superseded open-decision inventory

The decisions below were open when this audit was written. They have since been resolved by
docs/jafar-organization-management-mission.md and must not be asked again or treated as open.

- Whether setup completion and account activation are independent states.
- The production owner identity, MFA, recovery, and session-revocation model.
- UCRM plan names, capability keys, defaults, limits, and override semantics.
- Lifecycle transition permissions, suspension effects, deletion retention, and restoration policy.
- The first-admin password delivery and recovery process.
- Which profile/integration settings are platform-owned versus contractor-owned.
- Provider-specific retry, reconciliation, and idempotency behavior.
- Audit-log retention, visibility, and sensitive-data redaction policy.
- Whether email-change request operations belong in `/jafar`.

The approved resolution of these items is in docs/jafar-organization-management-mission.md. Legacy
behavior remains context, not a specification.
