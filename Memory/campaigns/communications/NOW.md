# Communications: Current Checkpoint

## Goal

Build secure contractor Communications with one shared Conversations model and independently gated
email and Twilio channel tracks. Preserve the approved differences between package-included operational
email and balance-funded phone/SMS.

## Active part

None. The operational-email contract and Communications roadmap are approved, but implementation is
paused until Clients and Properties establishes real contact, ownership, preference, and authorization
behavior.

## Exact next action

Prepare the Clients and Properties campaign proposal described by `docs/build-sequence.md`. Inspect its
approved behavior, Jobber comparison, existing schema/RLS/API/UI/tests, and Git state. Present its goal,
ordered parts, dependencies, risks, meaningful edge cases, and completion gates. Wait for Jafar's
approval before registering that campaign or changing implementation.

## Current truth

- Email product decisions Q26 through Q86 are approved in `docs/contractor-email-contract.md`.
- Email launches through one shared Brevo account with UCRM tenant isolation, verified contractor
  domains, package-included allowances, inbound replies, and configurable Jafar safety controls.
- Twilio/SMS decisions remain approved and authoritative in `docs/PRODUCT.md`, `CONTEXT.md`, and
  `docs/jafar-organization-management-mission.md`. They were not reopened by the email grill.
- Email and Twilio are separate channel contracts and implementation tracks inside this one major
  campaign. Email allowance never deducts Communication Balance.
- Marketing email, general inbound email, and Gmail/Outlook sync remain later independently gated work.
- Other contractor features are individual campaigns: Clients and Properties; Requests and
  Assessments; Quotes; Jobs; Scheduling; Invoices and Payments; Reputation; Contractor Settings; and
  Client Portal. Communications integrates with them without absorbing their domain ownership.

## Blockers

Communications implementation intentionally waits for Clients and Properties. Campaign planning for
Clients and Properties is not blocked.

## Protected work

Preserve unrelated dirty work. Do not rewrite completed SMS decisions while auditing email. Do not
create future feature campaign folders until that feature's goal and ordered roadmap are approved.

## Required pointers

- `docs/build-sequence.md`
- `docs/PRODUCT.md` section 8
- `.codex/skills/jobber/jobber-01-clients-properties.md`
- `Memory/campaigns/communications/ROADMAP.md`
- `docs/contractor-email-contract.md`

## Active-part completion gate

A Clients and Properties campaign proposal is evidence-backed and presented for approval. No campaign is
registered and no implementation, schema, RLS, authentication, or permission change has started.
