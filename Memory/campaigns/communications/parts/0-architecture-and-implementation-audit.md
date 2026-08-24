# Part 0: Architecture and Implementation Audit

## Outcome

Establish an evidence-backed technical starting point for the approved unified inbox across Messenger,
Instagram, web chat, operational email, and SMS without changing application behavior, authentication, schema,
RLS, permissions, packages, provider state, or secrets.

## Approved behavior

`docs/unified-inbox-behavior-contract.md` is authoritative for shared Conversations behavior.
`docs/contractor-email-contract.md` owns operational email. Existing SMS/Twilio behavior remains authoritative
in `docs/PRODUCT.md`, `CONTEXT.md`, and `docs/jafar-organization-management-mission.md`. Every channel shares
the Conversations surface while retaining its provider, identity, consent, allowance or balance, capability,
failure, and onboarding rules.

## Dependencies

- Completed Jafar commercial control, durable operations, closure, and strict purge foundations.
- Current package, permission, tenant-isolation, queue, storage, and API conventions.
- Contractor domain campaigns remain separate and may be absent during the foundation audit.

## Checklist

- [x] Inspect repository instructions and relevant skills before analysis.
- [x] Map existing message, conversation, notification, outbox, operation-attempt, storage, provider, channel
      identity, integration-secret, and web-chat code.
- [x] Map database tables, functions, RLS, constraints, indexes, migrations, generated types, and tests that
      could be reused or conflict.
- [x] Map package entitlements, limit overrides, commercial periods, Communication Balance, and Jafar
      controls. Preserve the approved separation between email allowances and SMS-funded balance.
- [x] Map organization suspension, recoverable closure, purge, and provider-cleanup extension points.
- [x] Map contractor roles and permissions relevant to Conversations, work records, pricing, and payments.
- [x] Identify browser/server boundaries and confirm secrets stay server-side.
- [x] Compare implemented truth with every section of `docs/unified-inbox-behavior-contract.md` and the narrow
      channel contracts it points to.
- [x] Map the ContractorOs patterns approved for selective reuse and prove where UCRM needs a redesign.
- [x] Map channel-native thread identity for email, SMS, Messenger, Instagram, and web-chat sessions without a
      one-open-conversation-per-contact constraint.
- [x] Map shared needs-attention state, personal last-seen position, assignment, followers, mentions, archive,
      permanent delete audit, star/priority, saved views, filters, search, and SLA.
- [x] Map multiple channel connections, organization defaults, package-configurable limits, organization
      overrides, connection readiness, token rotation, revocation, and provider emergency stops.
- [x] Separate shared Communications foundations from rules owned by Clients, Requests/Assessments, Quotes,
      Jobs, Scheduling, Invoices/Payments, Reputation, Settings, and Client Portal.
- [x] Propose the smallest shared-foundation implementation slice, verification plan, and rollback boundary.
- [x] List every schema, RLS, authentication, permission, package, or dependency decision requiring Jafar's
      explicit approval.
- [x] Update this packet and `NOW.md` with the exact next action; stop before implementation.

## Audit result

| Concern | Current seam | Part 1 decision |
| --- | --- | --- |
| Client identity and consent | `clients`, contact methods, and communication preferences are tenant-safe and reusable. | Link messages to a Client and specific contact method; do not copy or extend the SMS preference row for email allowance. |
| Roles and protected work context | Effective access, RLS helpers, and role/feature overrides are reusable. | Add separate Conversations permissions and enforce underlying client/work/financial permissions when context is read. |
| Files | R2 keys, private downloads, and attachment validation are reusable. | Keep Conversations attachments separate: channel capability limits, malware scan state, and provider media identifiers do not fit generic record attachments. |
| Delivery and failures | Platform-only Brevo outbox, operations queue, and owner alerts prove a durable idempotent pattern. | Reuse the pattern, not its tables: contractor sends require organization, channel, sender, recipient, billing, provider, and message-thread identity. |
| Closure and recovery | Closure cron, strict SQL purge, operations retry, and owner controls are reusable extension points. | Every Communications provider resource and R2 object needs an impact-preview, retryable cleanup, and purge component before provider work ships. |
| Inbox and threading | No Conversations, messages, channel identities, provider secrets, web-chat, Meta, or SMS transport exists. The client Communication tab is only a placeholder. | Build a dedicated channel-native model; do not adapt notes, activity, tags, or a one-thread-per-client relation. |
| Packages and limits | Feature/override resolution is reusable, but limits are currently employee seats only. | Add channel capabilities and their limits generically; email allowance is a distinct ledger/counter, never Communication Balance. |

## Confirmed boundaries and open approvals

- ContractorOs patterns to adapt: transactional outbox, stable idempotency, callbacks, provider IDs, delivery-state history, cursor design, and web-chat restoration. Do not adopt its shared read state, single owner, free-form tags, secret storage, or one-open-thread rule.
- First slice remains operational-email transport only. Meta, web chat, and Twilio provider facts are verified immediately before their own slices; no connection or provider work is implied here.
- Jafar approval is needed before Part 1 for: the new Communications schema/RLS model; the exact four-or-more Conversations permissions; package capability and quantity keys; email allowance event/counter model; secret-storage and callback-auth boundary; and whether Part 1 creates only foundation records or also a non-visible test sender path.

## Acceptance checks

- Every relevant existing implementation seam has a file or migration pointer.
- Every approved shared or channel capability is classified as existing, reusable, missing, conflicting, or
  owned by a separate campaign.
- Security, tenant isolation, indexing, concurrency, idempotency, retries, partial failures, quota accounting,
  attachment handling, callback authentication, and closure cleanup have explicit design treatment.
- No schema, RLS, auth, permission, provider, package, or UI change is made during the audit.
- The proposed Part 1 is independently verifiable and does not prematurely build domain-owned behavior.

## Required sources

- `docs/contractor-email-contract.md`
- `docs/unified-inbox-behavior-contract.md`
- `docs/research/ghl-unified-inbox-reference.md`
- `docs/research/contractoros-unified-inbox-audit.md`
- `docs/research/unified-inbox-gap-review.md`
- `docs/PRODUCT.md` sections 11, 19, 21, and 22
- `CONTEXT.md`
- `docs/jafar-organization-management-mission.md`
- `Memory/campaigns/jafar-panel/NOW.md`
- Current code, migrations, generated types, and tests discovered with narrow searches

## Non-discoverable risks

- A shared Brevo account has a platform-wide credential, quota, webhook, and reputation blast radius even
  when contractor domains are unique.
- Existing Communication Balance language is phone/SMS-oriented. Reusing it for package-included email would
  violate the approved model.
- A generic conversation permission can accidentally expose quote, invoice, payment, or property information
  that the staff member cannot otherwise access.
- Closure currently knows provider resources are not built. New email resources must extend its impact
  preview, retryable cleanup, and strict purge rather than form a separate deletion path.
- Domain-specific default recipients and secure portal behavior belong to their individual campaigns.
- A universal thread or delivery state machine can erase channel-native email, Meta, SMS, and web-chat rules.
- Multiple provider connections and package-configurable quantities require schema and index decisions before
  any UI design.
