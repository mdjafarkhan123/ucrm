# Part 0: Architecture and Implementation Audit

## Outcome

Establish an evidence-backed technical starting point for operational email without changing application
behavior, authentication, schema, RLS, or permissions.

## Approved behavior

`docs/contractor-email-contract.md` is authoritative for operational email. Existing SMS/Twilio behavior
remains authoritative in `docs/PRODUCT.md`, `CONTEXT.md`, and
`docs/jafar-organization-management-mission.md`. Email and Twilio share a future Conversations surface but
retain separate provider, allowance, consent, failure, and billing rules.

## Dependencies

- Completed Jafar commercial control, durable operations, closure, and strict purge foundations.
- Current package, permission, tenant-isolation, queue, storage, and API conventions.
- Contractor domain campaigns remain separate and may be absent during the foundation audit.

## Checklist

- [ ] Inspect repository instructions and relevant skills before analysis.
- [ ] Map existing message, conversation, notification, outbox, operation-attempt, storage, and provider code.
- [ ] Map database tables, functions, RLS, constraints, indexes, migrations, generated types, and tests that
      could be reused or conflict.
- [ ] Map package entitlements, limit overrides, commercial periods, Communication Balance, and Jafar
      controls. Preserve the approved separation between email allowances and SMS-funded balance.
- [ ] Map organization suspension, recoverable closure, purge, and provider-cleanup extension points.
- [ ] Map contractor roles and permissions relevant to Conversations, work records, pricing, and payments.
- [ ] Identify browser/server boundaries and confirm secrets stay server-side.
- [ ] Compare implemented truth with every section of `docs/contractor-email-contract.md`.
- [ ] Separate shared Communications foundations from rules owned by Clients, Requests/Assessments, Quotes,
      Jobs, Scheduling, Invoices/Payments, Reputation, Settings, and Client Portal.
- [ ] Propose the smallest Part 1 implementation slice, verification plan, and rollback boundary.
- [ ] List every schema, RLS, authentication, permission, package, or dependency decision requiring Jafar's
      explicit approval.
- [ ] Update this packet and `NOW.md` with the exact next action; stop before implementation.

## Acceptance checks

- Every relevant existing implementation seam has a file or migration pointer.
- Every approved email capability is classified as existing, reusable, missing, conflicting, or owned by a
  separate campaign.
- Security, tenant isolation, indexing, concurrency, idempotency, retries, partial failures, quota accounting,
  attachment handling, callback authentication, and closure cleanup have explicit design treatment.
- No schema, RLS, auth, permission, provider, package, or UI change is made during the audit.
- The proposed Part 1 is independently verifiable and does not prematurely build domain-owned behavior.

## Required sources

- `docs/contractor-email-contract.md`
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
