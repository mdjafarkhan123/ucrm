# Part 5B1: Secure access foundation and one customer renderer

Approved as part of Jafar's useful Quote-actions scope on 2026-08-21. This is the first independently
verifiable half of 5B. It creates safe recipient/version access and the customer document surface without
customer mutations. 5B2 owns view tracking, decisions, expiry behavior, rotation, and rate limiting.

## Outcome

An authorized staff member can issue a version-bound recipient link, open **Preview as client**, and print
or save the same document as PDF. A valid raw token can read only its frozen customer document. Invalid,
revoked, stale, or malformed tokens reveal no organization, client, Quote, or version facts.

## Approved behavior

- Quotes owns recipient/contact snapshots and access links; Communications owns message delivery.
- The first release creates one primary recipient from the Quote client's current email when staff issues
  access. Recipient rows remain version-bound snapshots and do not create general portal membership.
- Each access link uses a cryptographically random 256-bit token. Store only its SHA-256 hash; return the raw
  token only in the newly generated URL. Never put raw tokens in logs, database rows, activity payloads, or
  staff read endpoints.
- Link scope binds organization, Quote, published version, recipient, allowed actions, and an optional expiry.
- `anon` receives no direct Quote table, view, or function access. A server-only resolver hashes the supplied
  token, validates the active link and current published version, and returns a deliberately shaped customer
  document.
- An unavailable token returns one generic page and response shape with no tenant or document hints.
- The customer document uses only the frozen published snapshot: organization identity, client/property,
  Quote number/status/dates, introduction, customer-visible lines/packages/add-ons, visibility switches,
  customer-visible attachments, message, disclaimer, currency, and totals.
- Never return internal cost, markup, margin, catalog source ids, private attachments, notes, staff-only
  activity, other recipients, mutable source records, or service credentials.
- **Preview as client** opens the same renderer in a new tab under authenticated staff authorization. Its
  customer decision controls are inert and explain that only the customer can act.
- **Print or Save PDF** uses a print stylesheet on this renderer. Navigation and decision furniture disappear;
  document identity, content, totals, and disclaimer remain. No separate PDF data mapper may drift from it.
- Public GET does not record a view. HEAD, token lookup, scanners, and link previews remain read-only. 5B2 adds
  the explicit meaningful-view command after the rendered document becomes visible.
- No email, signature, customer decision, deposit, Pipeline outcome, or Job conversion occurs in this slice.

## Database and performance decisions before SQL

- Add tenant-owned `quote_recipients` and `quote_access_links` with UUID primary keys, duplicated
  `organization_id`, and composite tenant-safe foreign keys to Quote/version/recipient parents.
- Store token hashes in a fixed-width binary representation or constrained text chosen during schema review;
  enforce global uniqueness. Never index or store raw tokens.
- Required access path is one equality lookup by token hash followed by exact parent joins. Index every FK and
  use the smallest unique token-hash index; add an active-link partial index only if the final query benefits.
- Staff recipient/link reads are bounded by one Quote/version; no pagination is needed in this slice.
- No aggregate or materialized view is needed. Link issuance and resolution must use a bounded number of
  database round trips, with no per-line or per-attachment N+1.
- New exposed tables use RLS for authenticated staff. Server-only public resolution must not broaden `anon`.
- Narrow database commands own link issuance/revocation and verify organization membership, permission,
  publication state, and current version before writing.

## Implementation checklist

- [x] Confirm schema types, indexes, constraints, RLS, grants, and token-generation boundary before SQL.
- [x] Implement declarative/imperative migration according to the repository's current Supabase workflow.
- [x] Add pgTAP coverage for tenant-safe FKs, RLS roles, forbidden direct writes, hash uniqueness, stale/current
      version scope, and absence of `anon` grants.
- [x] Run the migration performance/security gate before any API route work.
- [x] Add protected staff issuance/read routes and a server-only public resolver with deliberate response fields.
- [x] Add route tests for random/malformed/revoked/stale tokens, cross-tenant/version crossing, no-store headers,
      raw-token/log exclusion, and forbidden private/cost fields.
- [x] Run the API performance/security gate before UI work.
- [x] Build one Svelte customer renderer and thin public/staff-preview page shells around it.
- [x] Add Preview as client and Print or Save PDF to the status/permission-aware Quote menu.
- [x] Add print CSS, desktop and phone layouts, keyboard/focus checks, unavailable state, and attachment handling.
- [x] Run Svelte autofixer, targeted tests, check, formatting, production build/chunk review, and browser passes.

## Acceptance checks

- A newly issued raw URL works once exposed to the browser, while the database contains only its hash.
- Random, malformed, revoked, or wrong-version tokens return the same safe unavailable result.
- A token cannot cross organization, Quote, version, or recipient boundaries.
- Public payload and rendered HTML contain no cost, margin, notes, private files, source ids, or other recipients.
- Preview and public access render the same document component and visibility switches.
- Preview cannot submit customer decisions; the public page has no decision mutation in 5B1.
- Print preview removes app/navigation/action furniture and preserves the complete customer document.
- Resolution is one bounded access path with supporting indexes and no N+1.

## Non-discoverable risks

- URLs leak through referrers and logs unless token-bearing pages use a strict referrer policy and redact server
  logging. Do not load third-party assets from the token page.
- Client-visible attachments require token-scoped streaming or safe derived access; never expose reusable storage
  URLs or the authenticated attachment endpoint blindly.
- Organization branding snapshots may not yet contain every desired field. Render honest available data and do
  not pull live branding into an immutable historical version.
- A staff preview route is not a public token and must not mint or rotate a customer link merely to display it.
- Print-to-PDF is browser output in this slice, not a stored PDF artifact or emailed attachment.

## Source pointers

- `docs/quote-behavior-contract.md` §§ Recipients, API routes, public security verification.
- `.claude/skills/jobber/jobber-03-quotes.md` §8.3.
- `supabase/migrations/20260820161041_quote_professional_proposals_foundation.sql` - version snapshots.
- `src/routes/api/quotes/[id]/+server.ts` - current document read shape to narrow, never reuse wholesale.
