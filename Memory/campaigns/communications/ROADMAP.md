# Communications Roadmap

The permanent product behavior lives in `docs/contractor-email-contract.md`, the Communications
sections of `docs/PRODUCT.md`, and linked approved channel contracts. This file owns campaign ordering
and completion gates only.

Email and Twilio are separate channel tracks within the Communications campaign. The approved roadmap
below is the operational-email track. Before Twilio implementation begins, consolidate its existing
approved behavior into a channel contract and add an independently approved Twilio track here.

| Part | Outcome | Status | Dependencies | Packet | Completion gate |
| --- | --- | --- | --- | --- | --- |
| 0 | Architecture and implementation audit | Pending after Clients and Properties | Clients and Properties contact/authorization model | `parts/0-architecture-and-implementation-audit.md` | Current truth, reusable seams, risks, approval boundaries, and first implementation slice are established without implementation. |
| 1 | Email delivery foundation | Pending | 0 and required approvals | Created when Part 0 closes | Tenant-safe outbox, idempotency, Brevo adapter, callbacks, retries, and usage counting pass database and service checks. |
| 2 | Domains and sender identities | Pending | 1 | Created when dependency-ready | Jafar can provision, verify, warm, replace, restrict, and remove domains and eligible senders safely. |
| 3 | Operational outbound email | Pending | 1, 2 | Created when dependency-ready | Authorized manual and system sends use current work state, previews, secure links, allowances, and auditable resend behavior. |
| 4 | Inbound replies and attachments | Pending | 1, 2 | Created when dependency-ready | Opaque replies, authenticated callbacks, deduplication, guarded senders, private attachments, and loop protection work tenant-safely. |
| 5 | Conversations experience | Pending | 3, 4 | Created when dependency-ready | Shared and personal views, ownership, followers, mentions, permissions, forwarding, and work context pass desktop, mobile, and accessibility checks. The client page's Communication tab is filled here — its shell already exists. |
| 6 | Templates, snippets, and preferences | Pending | 3, 5 | Created when dependency-ready | Platform and organization content, automation copies, category preferences, and suppressions behave as approved. |
| 7 | Allowances, reputation, and Jafar controls | Pending | 1 through 6 | Created when dependency-ready | Package defaults, overrides, reserves, rates, provider capacity, reputation pauses, recovery, and immutable history are enforced. |
| 8 | Suspension, closure, and cleanup | Pending | 4, 7 and Jafar closure foundation | Created when dependency-ready | Suspension, reactivation, 30-day inbound recovery, impact preview, provider cleanup, and strict purge are recoverable and verified. |
| 9 | Cross-domain integration and completion | Pending | 1 through 8 and ready domain campaigns | Created when dependency-ready | Ready CRM domains integrate without ownership leakage; security and browser checks pass; only shipped behavior enters the product manual. |

## Settled before implementation

- **The client's Communication tab loads on demand, not with the page.** Approved by Jafar 2026-08-17. Its
  query stays off until the tab is hovered, prefetches on hover, shows a skeleton if the click wins, and
  caches so reopening is instant. Landing on `?tab=communication` fetches straight away. The general rule
  is now in `CLAUDE.md` rule 9 and applies to every revealed panel, not only this one.
- **Jobber's Communication tab is a read-only history, not a composer.** Sending starts from the header.
  Toured live and written up in `.claude/skills/jobber/jobber-01-clients-properties.md` §2.4 — read it
  before designing this list.

## Separate major feature campaigns

Clients and Properties, Requests and Assessments, Quotes, Jobs, Scheduling, Invoices and Payments,
Reputation, Contractor Settings, and Client Portal each receive their own campaign, roadmap, packets,
and completion gates when approved for work. Communications owns transport and Conversations, not those
features' business rules.
